
/* =====================================================================================
   22. FINANCE, PAYROLL, ASSETS, LEASES & TAX LOGIC
   -------------------------------------------------------------------------------------
   22.1  Helpers ............ fn_fx_rate, fn_post_journal (JSON lines -> posted journal)
   22.2  Payroll ............ fn_calc_paye, fn_run_payroll, fn_approve_payroll, fn_pay_payroll
   22.3  Payables ........... fn_approve_vendor_bill, fn_pay_vendor_bill (WHT + IMTT)
   22.4  Fixed assets ....... fn_asset_nbv, fn_run_depreciation, fn_revalue_asset, fn_dispose_asset
   22.5  Leases & loans ..... fn_generate_lease_schedule, fn_recognise_lease, fn_post_lease_month,
                              fn_generate_loan_schedule, fn_post_loan_month
   22.6  Tax ................ fn_prepare_vat_return, fn_prepare_payroll_returns, fn_create_qpds,
                              fn_file_tax_return, fn_pay_tax_return, fn_accrue_income_tax,
                              fn_deferred_tax_schedule
   22.7  Other .............. fn_update_ecl_provision, fn_bank_transfer
   Keep cash journals "pure" (cash lines + their direct counterparts) so the direct-method
   cash-flow statement can classify every cash movement from the counter-accounts.
   ===================================================================================== */

/* ---------- 22.1 Helpers ---------- */

-- Units of USD per 1 unit of p_currency on (or before) p_date
CREATE OR REPLACE FUNCTION fn_fx_rate(p_currency CHAR(3), p_date DATE) RETURNS NUMERIC
LANGUAGE plpgsql STABLE AS $$
DECLARE v NUMERIC;
BEGIN
    IF p_currency = 'USD' THEN RETURN 1; END IF;
    SELECT rate INTO v FROM exchange_rates
     WHERE from_currency = p_currency AND to_currency = 'USD' AND rate_date <= p_date
     ORDER BY rate_date DESC LIMIT 1;
    IF v IS NULL THEN
        SELECT rate INTO v FROM exchange_rates
         WHERE from_currency = p_currency AND to_currency = 'USD' ORDER BY rate_date LIMIT 1;
    END IF;
    IF v IS NULL THEN RAISE EXCEPTION 'No exchange rate %->USD on or before %', p_currency, p_date; END IF;
    RETURN v;
END $$;

/* Create and post a journal in one call.
   p_lines = JSON array of objects: {"acc":"5100","dr":100.00,"cr":0,"desc":"...",
             "office":1,"dept":2,"project":3,"employee":4,"vendor":5,"client":6}
   Zero lines are skipped; a rounding difference of up to 0.05 is put on the last line. */
CREATE OR REPLACE FUNCTION fn_post_journal(p_date DATE, p_description TEXT, p_source TEXT, p_source_id BIGINT,
                                           p_lines JSONB, p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_je BIGINT; v_no SMALLINT := 0; l JSONB; v_dr NUMERIC; v_cr NUMERIC; v_diff NUMERIC;
BEGIN
    INSERT INTO journal_entries (entry_date, description, source_type, source_id, created_by)
    VALUES (p_date, left(p_description, 300), p_source, p_source_id, p_user)
    RETURNING journal_entry_id INTO v_je;

    FOR l IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
        v_dr := round(COALESCE((l->>'dr')::NUMERIC, 0), 2);
        v_cr := round(COALESCE((l->>'cr')::NUMERIC, 0), 2);
        IF v_dr < 0 THEN v_cr := v_cr - v_dr; v_dr := 0; END IF;     -- negative debit = credit
        IF v_cr < 0 THEN v_dr := v_dr - v_cr; v_cr := 0; END IF;
        IF v_dr > 0 AND v_cr > 0 THEN                                 -- net a two-sided line
            IF v_dr >= v_cr THEN v_dr := v_dr - v_cr; v_cr := 0; ELSE v_cr := v_cr - v_dr; v_dr := 0; END IF;
        END IF;
        CONTINUE WHEN v_dr = 0 AND v_cr = 0;
        v_no := v_no + 1;
        INSERT INTO journal_lines (journal_entry_id, line_no, account_id, debit, credit, description,
                                   office_id, department_id, project_id, employee_id, vendor_id, client_id)
        VALUES (v_je, v_no, fn_account_id(l->>'acc'), v_dr, v_cr, left(COALESCE(l->>'desc', p_description), 300),
                (l->>'office')::BIGINT, (l->>'dept')::BIGINT, (l->>'project')::BIGINT,
                (l->>'employee')::BIGINT, (l->>'vendor')::BIGINT, (l->>'client')::BIGINT);
    END LOOP;

    IF v_no = 0 THEN
        DELETE FROM journal_entries WHERE journal_entry_id = v_je;
        RETURN NULL;
    END IF;

    SELECT SUM(debit) - SUM(credit) INTO v_diff FROM journal_lines WHERE journal_entry_id = v_je;
    IF v_diff <> 0 THEN
        IF abs(v_diff) > 0.05 THEN
            RAISE EXCEPTION 'Journal "%" does not balance: difference %', p_description, v_diff;
        END IF;
        UPDATE journal_lines
           SET debit  = CASE WHEN debit  > 0 THEN debit  - v_diff ELSE debit END,
               credit = CASE WHEN credit > 0 THEN credit + v_diff ELSE credit END
         WHERE journal_entry_id = v_je AND line_no = v_no;
    END IF;

    UPDATE journal_entries SET status = 'posted' WHERE journal_entry_id = v_je;
    RETURN v_je;
END $$;

-- Current statutory rate / amount for a country (effective on p_date)
CREATE OR REPLACE FUNCTION fn_stat_rate(p_country CHAR(2), p_code TEXT, p_date DATE) RETURNS NUMERIC
LANGUAGE sql STABLE AS $$
    SELECT COALESCE((SELECT rate_pct FROM statutory_rates
                      WHERE country_code = p_country AND rate_code = p_code AND effective_from <= p_date
                        AND (effective_to IS NULL OR effective_to >= p_date)
                      ORDER BY effective_from DESC LIMIT 1), 0);
$$;

CREATE OR REPLACE FUNCTION fn_stat_amount(p_country CHAR(2), p_code TEXT, p_date DATE) RETURNS NUMERIC
LANGUAGE sql STABLE AS $$
    SELECT (SELECT amount FROM statutory_rates
             WHERE country_code = p_country AND rate_code = p_code AND effective_from <= p_date
               AND (effective_to IS NULL OR effective_to >= p_date)
             ORDER BY effective_from DESC LIMIT 1);
$$;


/* ---------- 22.2 Payroll ---------- */

-- Monthly PAYE from the progressive table: taxable x rate - "less" amount of the band
CREATE OR REPLACE FUNCTION fn_calc_paye(p_taxable NUMERIC, p_date DATE, p_country CHAR(2) DEFAULT 'ZW',
                                        p_currency CHAR(3) DEFAULT 'USD') RETURNS NUMERIC
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(round(GREATEST(p_taxable * b.rate_pct / 100 - b.deduct_amount, 0), 2), 0)
      FROM paye_tax_bands b
     WHERE b.country_code = p_country AND b.currency_code = p_currency
       AND b.effective_from = (SELECT max(effective_from) FROM paye_tax_bands
                                WHERE country_code = p_country AND currency_code = p_currency AND effective_from <= p_date)
       AND p_taxable >= b.lower_limit AND (b.upper_limit IS NULL OR p_taxable <= b.upper_limit)
     LIMIT 1;
$$;

/* Create a payroll run with payslips for every active employee based in p_country.
   Zimbabwe: NSSA 4.5% EE/ER on insurable earnings (USD 700 ceiling), WCIF, ZIMDEF 1%,
             pension (approved fund, deductible up to the cap), PAYE bands, 50% medical-aid
             credit, AIDS levy 3% of PAYE.
   Branches: simplified local rates from statutory_rates (effective income-tax rate,
             social security EE/ER, other employer levies). */
CREATE OR REPLACE FUNCTION fn_run_payroll(p_country CHAR(2), p_period_start DATE, p_pay_date DATE DEFAULT NULL,
                                          p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    v_end   DATE := (date_trunc('month', p_period_start) + INTERVAL '1 month - 1 day')::DATE;
    v_cur   CHAR(3);
    v_run   BIGINT;
    r       RECORD;
    v_gross NUMERIC; v_ins NUMERIC; v_nssa NUMERIC; v_pen NUMERIC; v_pen_er NUMERIC; v_med NUMERIC; v_med_er NUMERIC;
    v_taxable NUMERIC; v_tax NUMERIC; v_credit NUMERIC; v_aids NUMERIC; v_er_ss NUMERIC; v_er_other NUMERIC; v_zimdef NUMERIC;
    v_ceiling NUMERIC;
BEGIN
    SELECT default_currency INTO v_cur FROM countries WHERE country_code = p_country;
    INSERT INTO payroll_runs (run_number, country_code, period_start, period_end, pay_date, currency_code, exchange_rate, notes)
    VALUES ('PAY-' || p_country || '-' || to_char(p_period_start, 'YYYY-MM'), p_country, date_trunc('month', p_period_start)::DATE,
            v_end, COALESCE(p_pay_date, v_end - 2), v_cur, fn_fx_rate(v_cur, v_end),
            'Monthly payroll ' || to_char(p_period_start, 'FMMonth YYYY'))
    RETURNING payroll_run_id INTO v_run;

    FOR r IN
        SELECT e.employee_id, e.pension_member, e.medical_aid_member, c.base_salary_annual, c.monthly_allowances
          FROM employees e
          JOIN offices o ON o.office_id = e.office_id AND o.country_code = p_country
          JOIN LATERAL (SELECT * FROM employee_compensation ec
                         WHERE ec.employee_id = e.employee_id AND ec.effective_date <= v_end
                         ORDER BY ec.effective_date DESC LIMIT 1) c ON TRUE
         WHERE e.hire_date <= v_end
           AND (e.termination_date IS NULL OR e.termination_date >= p_period_start)
           AND e.employment_type IN ('full_time','part_time','intern')
    LOOP
        v_gross := round(r.base_salary_annual / 12, 2) + r.monthly_allowances;
        v_pen    := CASE WHEN r.pension_member THEN round(r.base_salary_annual / 12 * fn_stat_rate(p_country,'PENSION_EE',v_end) / 100, 2) ELSE 0 END;
        v_pen_er := CASE WHEN r.pension_member THEN round(r.base_salary_annual / 12 * fn_stat_rate(p_country,'PENSION_ER',v_end) / 100, 2) ELSE 0 END;

        IF p_country = 'ZW' THEN
            v_ceiling := COALESCE(fn_stat_amount('ZW','NSSA_CEILING',v_end), 700);
            v_ins    := LEAST(v_gross, v_ceiling);
            v_nssa   := round(v_ins * fn_stat_rate('ZW','NSSA_EE',v_end) / 100, 2);
            v_er_ss  := round(v_ins * fn_stat_rate('ZW','NSSA_ER',v_end) / 100, 2);
            v_er_other := round(v_ins * fn_stat_rate('ZW','NSSA_WCIF',v_end) / 100, 2);
            v_zimdef := round(v_gross * fn_stat_rate('ZW','ZIMDEF',v_end) / 100, 2);
            v_med    := CASE WHEN r.medical_aid_member THEN LEAST(round(v_gross * 0.04, 2), 180) ELSE 0 END;
            v_med_er := CASE WHEN r.medical_aid_member THEN round(v_med * 1.5, 2) ELSE 0 END;
            v_taxable := GREATEST(v_gross - v_nssa - LEAST(v_pen, COALESCE(fn_stat_amount('ZW','PENSION_CAP',v_end), 450)), 0);
            v_tax    := fn_calc_paye(v_taxable, v_end, 'ZW', 'USD');
            v_credit := LEAST(round(v_med * fn_stat_rate('ZW','MEDICAL_CREDIT',v_end) / 100, 2), v_tax);
            v_tax    := v_tax - v_credit;
            v_aids   := round(v_tax * fn_stat_rate('ZW','AIDS_LEVY',v_end) / 100, 2);
        ELSE
            v_ceiling := fn_stat_amount(p_country,'SOCIAL_CEILING',v_end);
            v_ins    := CASE WHEN v_ceiling IS NULL THEN v_gross ELSE LEAST(v_gross, v_ceiling) END;
            v_nssa   := round(v_ins * fn_stat_rate(p_country,'SOCIAL_EE',v_end) / 100, 2);
            v_er_ss  := round(v_ins * fn_stat_rate(p_country,'SOCIAL_ER',v_end) / 100, 2);
            v_er_other := round(v_gross * fn_stat_rate(p_country,'OTHER_ER',v_end) / 100, 2);
            v_zimdef := 0; v_med := 0; v_med_er := 0; v_credit := 0; v_aids := 0;
            v_taxable := GREATEST(v_gross - v_nssa - v_pen, 0);
            v_tax    := round(v_taxable * fn_stat_rate(p_country,'INCOME_TAX_EFFECTIVE',v_end) / 100, 2);
        END IF;

        INSERT INTO payslips (payroll_run_id, employee_id, currency_code, basic_pay, allowances,
                              nssa_employee, pension, taxable_income, paye_tax, medical_aid_credit, aids_levy, medical_aid,
                              employer_nssa, employer_wcif, employer_zimdef, employer_pension, employer_medical)
        VALUES (v_run, r.employee_id, v_cur, round(r.base_salary_annual / 12, 2), r.monthly_allowances,
                v_nssa, v_pen, v_taxable, v_tax, v_credit, v_aids, v_med,
                v_er_ss, v_er_other, v_zimdef, v_pen_er, v_med_er);
    END LOOP;

    UPDATE payroll_runs pr SET employee_count = s.n, total_gross = s.g, total_net = s.net, total_employer_cost = s.ec
      FROM (SELECT count(*) n, COALESCE(SUM(gross_pay),0) g, COALESCE(SUM(net_pay),0) net, COALESCE(SUM(employer_cost),0) ec
              FROM payslips WHERE payroll_run_id = v_run) s
     WHERE pr.payroll_run_id = v_run;
    RETURN v_run;
END $$;

-- Approve & post the payroll accrual (USD) - salaries by department/office, statutory liabilities
CREATE OR REPLACE FUNCTION fn_approve_payroll(p_run_id BIGINT, p_approver BIGINT, p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_run payroll_runs%ROWTYPE; v_lines JSONB := '[]'::JSONB; v_je BIGINT; x NUMERIC; r RECORD; t RECORD;
BEGIN
    SELECT * INTO v_run FROM payroll_runs WHERE payroll_run_id = p_run_id FOR UPDATE;
    IF v_run.status <> 'draft' THEN RAISE EXCEPTION 'Payroll run % is %', v_run.run_number, v_run.status; END IF;
    x := v_run.exchange_rate;

    -- gross pay and employer costs by department & office
    FOR r IN SELECT e.department_id, e.office_id, d.is_revenue_generating AS fee,
                    SUM(p.gross_pay) g, SUM(p.employer_nssa + p.employer_wcif) ss, SUM(p.employer_zimdef) zd,
                    SUM(p.employer_pension) pe, SUM(p.employer_medical) me
               FROM payslips p JOIN employees e USING (employee_id) JOIN departments d ON d.department_id = e.department_id
              WHERE p.payroll_run_id = p_run_id GROUP BY 1, 2, 3
    LOOP
        v_lines := v_lines
          || jsonb_build_object('acc', CASE WHEN r.fee THEN '5100' ELSE '5110' END, 'dr', r.g * x, 'dept', r.department_id, 'office', r.office_id, 'desc','Gross salaries')
          || jsonb_build_object('acc','5120','dr', r.ss * x, 'dept', r.department_id, 'office', r.office_id, 'desc','Employer social security & workers compensation')
          || jsonb_build_object('acc','5125','dr', r.zd * x, 'dept', r.department_id, 'office', r.office_id, 'desc','ZIMDEF levy')
          || jsonb_build_object('acc','5130','dr', r.pe * x, 'dept', r.department_id, 'office', r.office_id, 'desc','Employer pension')
          || jsonb_build_object('acc','5140','dr', r.me * x, 'dept', r.department_id, 'office', r.office_id, 'desc','Employer medical aid');
    END LOOP;

    SELECT SUM(paye_tax) paye, SUM(aids_levy) aids, SUM(nssa_employee) ss_ee, SUM(employer_nssa) ss_er, SUM(employer_wcif) oth,
           SUM(employer_zimdef) zd, SUM(pension + employer_pension) pen, SUM(medical_aid + employer_medical) med,
           SUM(other_deductions) oth_ded, SUM(net_pay) net
      INTO t FROM payslips WHERE payroll_run_id = p_run_id;

    IF v_run.country_code = 'ZW' THEN
        v_lines := v_lines
          || jsonb_build_object('acc','2400','cr', t.paye * x, 'desc','PAYE payable (ZIMRA)')
          || jsonb_build_object('acc','2405','cr', t.aids * x, 'desc','AIDS levy payable (ZIMRA)')
          || jsonb_build_object('acc','2410','cr', (t.ss_ee + t.ss_er + t.oth) * x, 'desc','NSSA POBS & WCIF payable')
          || jsonb_build_object('acc','2415','cr', t.zd * x, 'desc','ZIMDEF payable');
    ELSE
        v_lines := v_lines
          || jsonb_build_object('acc','2450','cr', (t.paye + t.ss_ee + t.ss_er + t.oth) * x,
                                'desc','Branch payroll taxes & social security payable - ' || v_run.country_code);
    END IF;
    v_lines := v_lines
      || jsonb_build_object('acc','2420','cr', t.pen * x, 'desc','Pension fund contributions payable')
      || jsonb_build_object('acc','2425','cr', t.med * x, 'desc','Medical aid contributions payable')
      || jsonb_build_object('acc','2500','cr', t.oth_ded * x, 'desc','Other payroll deductions payable')
      || jsonb_build_object('acc','2150','cr', t.net * x, 'desc','Net salaries payable');

    v_je := fn_post_journal(v_run.period_end, 'Payroll ' || v_run.run_number, 'payroll', p_run_id, v_lines, p_user);
    UPDATE payroll_runs SET status = 'approved', approved_by = p_approver, approved_at = now(), journal_entry_id = v_je
     WHERE payroll_run_id = p_run_id;
    RETURN v_je;
END $$;

CREATE OR REPLACE FUNCTION fn_pay_payroll(p_run_id BIGINT, p_bank_account_id BIGINT, p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_run payroll_runs%ROWTYPE; v_je BIGINT; v_amt NUMERIC; v_gl TEXT;
BEGIN
    SELECT * INTO v_run FROM payroll_runs WHERE payroll_run_id = p_run_id FOR UPDATE;
    IF v_run.status <> 'approved' THEN RAISE EXCEPTION 'Payroll run % must be approved before paying (current: %)', v_run.run_number, v_run.status; END IF;
    SELECT credit INTO v_amt FROM journal_lines
     WHERE journal_entry_id = v_run.journal_entry_id AND account_id = fn_account_id('2150');
    SELECT a.account_code INTO v_gl FROM bank_accounts b JOIN chart_of_accounts a ON a.account_id = b.gl_account_id
     WHERE b.bank_account_id = p_bank_account_id;
    v_je := fn_post_journal(v_run.pay_date, 'Net salaries paid ' || v_run.run_number, 'payroll_payment', p_run_id,
            jsonb_build_array(jsonb_build_object('acc','2150','dr', v_amt, 'desc','Net salaries'),
                              jsonb_build_object('acc', v_gl, 'cr', v_amt, 'desc','Salary transfer (IMTT exempt)')), p_user);
    UPDATE payroll_runs SET status = 'paid', payment_journal_id = v_je WHERE payroll_run_id = p_run_id;
    RETURN v_je;
END $$;


/* ---------- 22.3 Payables ---------- */

-- Approve a supplier bill: Dr expense / asset (+ recoverable ZIMRA input VAT) / Cr Accounts payable
CREATE OR REPLACE FUNCTION fn_approve_vendor_bill(p_bill_id BIGINT, p_approver BIGINT, p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE b vendor_bills%ROWTYPE; v vendors%ROWTYPE; v_je BIGINT; v_acc TEXT; v_ap TEXT; v_rate NUMERIC; v_vat_ok BOOLEAN;
BEGIN
    SELECT * INTO b FROM vendor_bills WHERE vendor_bill_id = p_bill_id FOR UPDATE;
    IF b.status <> 'draft' THEN RAISE EXCEPTION 'Bill % is already %', b.bill_number, b.status; END IF;
    SELECT * INTO v FROM vendors WHERE vendor_id = b.vendor_id;
    SELECT account_code INTO v_acc FROM chart_of_accounts
     WHERE account_id = COALESCE(b.expense_account_id, v.default_expense_account_id);
    IF v_acc IS NULL THEN RAISE EXCEPTION 'Bill % has no expense account', b.bill_number; END IF;
    -- capital purchases go to a separate payables account so their payment shows as INVESTING cash flow
    SELECT CASE WHEN ifrs_line_code IN ('SFP_PPE','SFP_INT','SFP_IP') THEN '2110' ELSE '2100' END INTO v_ap
      FROM chart_of_accounts WHERE account_code = v_acc;
    v_rate := CASE WHEN b.currency_code = 'USD' THEN 1 ELSE fn_fx_rate(b.currency_code, b.bill_date) END;
    -- input VAT is only claimable on Zimbabwean tax invoices from VAT-registered suppliers
    v_vat_ok := COALESCE(v.country_code, 'ZW') = 'ZW' AND v.vat_number IS NOT NULL;

    v_je := fn_post_journal(b.bill_date, format('Supplier bill %s - %s', b.bill_number, v.name), 'vendor_bill', p_bill_id,
        jsonb_build_array(
            jsonb_build_object('acc', v_acc, 'dr', (b.subtotal + CASE WHEN v_vat_ok THEN 0 ELSE b.tax_amount END) * v_rate,
                               'office', b.office_id, 'dept', b.department_id, 'project', b.project_id, 'vendor', b.vendor_id,
                               'desc', COALESCE(b.description, 'Supplier bill ' || b.bill_number)),
            jsonb_build_object('acc','2210','dr', CASE WHEN v_vat_ok THEN b.tax_amount * v_rate ELSE 0 END, 'vendor', b.vendor_id, 'desc','Input VAT'),
            jsonb_build_object('acc', v_ap, 'cr', (b.subtotal + b.tax_amount) * v_rate, 'vendor', b.vendor_id, 'desc','Accounts payable')),
        p_user);
    UPDATE vendor_bills SET status = 'approved', approved_by = p_approver, exchange_rate = v_rate, journal_entry_id = v_je
     WHERE vendor_bill_id = p_bill_id;
    RETURN v_je;
END $$;

/* Pay a supplier bill.
   * 30% withholding tax if a Zimbabwean supplier has no valid ITF263 tax clearance and the
     bill is at or above the threshold; 15% non-residents' tax on fees for foreign
     subcontractors/professionals.  WHT is paid over to ZIMRA later.
   * 2% IMTT charged by the bank on electronic transfers from Zimbabwean accounts.
   * AP is cleared at the bill's rate; the difference to today's rate is an FX gain/loss. */
CREATE OR REPLACE FUNCTION fn_pay_vendor_bill(p_bill_id BIGINT, p_amount NUMERIC, p_bank_account_id BIGINT,
                                              p_date DATE DEFAULT CURRENT_DATE, p_reference TEXT DEFAULT NULL,
                                              p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    b vendor_bills%ROWTYPE; v vendors%ROWTYPE; k bank_accounts%ROWTYPE;
    v_bank_gl TEXT; v_zw_bank BOOLEAN; v_rate NUMERIC; v_wht NUMERIC := 0; v_wht_rate NUMERIC := 0; v_wht_type TEXT;
    v_cash NUMERIC; v_imtt NUMERIC := 0; v_ap_usd NUMERIC; v_cash_usd NUMERIC; v_wht_usd NUMERIC; v_fx NUMERIC;
    v_pay BIGINT; v_je BIGINT; v_ap TEXT;
BEGIN
    SELECT * INTO b FROM vendor_bills WHERE vendor_bill_id = p_bill_id FOR UPDATE;
    IF b.status NOT IN ('approved','partially_paid') THEN
        RAISE EXCEPTION 'Bill % must be approved before payment (current: %)', b.bill_number, b.status;
    END IF;
    IF p_amount <= 0 OR p_amount > b.total_amount - b.amount_paid THEN
        RAISE EXCEPTION 'Payment % must be between 0 and the balance %', p_amount, b.total_amount - b.amount_paid;
    END IF;
    SELECT * INTO v FROM vendors WHERE vendor_id = b.vendor_id;
    SELECT * INTO k FROM bank_accounts WHERE bank_account_id = p_bank_account_id;
    IF k.currency_code <> b.currency_code THEN
        RAISE EXCEPTION 'Pay a % bill from a % account (selected account is %)', b.currency_code, b.currency_code, k.currency_code;
    END IF;
    SELECT a.account_code INTO v_bank_gl FROM chart_of_accounts a WHERE a.account_id = k.gl_account_id;
    SELECT o.country_code = 'ZW' INTO v_zw_bank FROM offices o WHERE o.office_id = k.office_id;
    SELECT CASE WHEN EXISTS (SELECT 1 FROM journal_lines jl WHERE jl.journal_entry_id = b.journal_entry_id
                              AND jl.account_id = fn_account_id('2110')) THEN '2110' ELSE '2100' END INTO v_ap;

    IF v.is_resident AND COALESCE(v.country_code,'ZW') = 'ZW' AND v.vendor_type NOT IN ('government','utility')
       AND (v.tax_clearance_expiry IS NULL OR v.tax_clearance_expiry < p_date)
       AND b.total_amount >= COALESCE(fn_stat_amount('ZW','WHT_TENDER_THRESHOLD', p_date), 1000) THEN
        v_wht_rate := fn_stat_rate('ZW','WHT_TENDER', p_date); v_wht_type := 'tender_30';
    ELSIF NOT v.is_resident AND v.vendor_type IN ('subcontractor','professional','freelancer') THEN
        v_wht_rate := fn_stat_rate('ZW','WHT_NONRES_FEES', p_date); v_wht_type := 'non_resident_fees';
    END IF;
    v_wht  := round(p_amount * v_wht_rate / 100, 2);
    v_cash := p_amount - v_wht;
    IF COALESCE(v_zw_bank, FALSE) AND v.vendor_type <> 'government' THEN
        v_imtt := round(v_cash * fn_stat_rate('ZW','IMTT', p_date) / 100, 2);
    END IF;

    v_rate     := fn_fx_rate(b.currency_code, p_date);
    v_ap_usd   := round(p_amount * b.exchange_rate, 2);
    v_cash_usd := round(v_cash * v_rate, 2);
    v_wht_usd  := round(v_wht * v_rate, 2);
    v_fx       := v_ap_usd - v_cash_usd - v_wht_usd;          -- +ve = gain

    INSERT INTO vendor_payments (vendor_bill_id, payment_date, amount, method, reference, bank_account_id, withholding_tax, imtt_amount)
    VALUES (p_bill_id, p_date, p_amount, 'bank_transfer', p_reference, p_bank_account_id, v_wht, v_imtt)
    RETURNING vendor_payment_id INTO v_pay;

    v_je := fn_post_journal(p_date, format('Payment to %s for %s', v.name, b.bill_number), 'vendor_payment', v_pay,
        jsonb_build_array(
            jsonb_build_object('acc', v_ap, 'dr', v_ap_usd, 'vendor', v.vendor_id, 'desc','Settle accounts payable'),
            jsonb_build_object('acc','2430','cr', v_wht_usd, 'vendor', v.vendor_id, 'desc','Withholding tax retained for ZIMRA'),
            jsonb_build_object('acc', CASE WHEN v_fx >= 0 THEN '4800' ELSE '7300' END, 'cr', v_fx, 'desc','Exchange difference on settlement'),
            jsonb_build_object('acc','6610','dr', round(v_imtt * v_rate, 2), 'office', k.office_id, 'desc','IMTT 2% on transfer'),
            jsonb_build_object('acc', v_bank_gl, 'cr', v_cash_usd + round(v_imtt * v_rate, 2), 'desc','Bank transfer')),
        p_user);
    UPDATE vendor_payments SET journal_entry_id = v_je WHERE vendor_payment_id = v_pay;

    IF v_wht > 0 THEN
        INSERT INTO withholding_tax_deductions (vendor_payment_id, vendor_id, wht_type, gross_amount, rate_pct, wht_amount, deduction_date)
        VALUES (v_pay, v.vendor_id, v_wht_type, p_amount, v_wht_rate, v_wht, p_date);
    END IF;
    RETURN v_pay;
END $$;


/* ---------- 22.4 Fixed assets ---------- */

-- Carrying amount (and its parts) of an asset at a date
CREATE OR REPLACE FUNCTION fn_asset_nbv(p_asset_id BIGINT, p_as_at DATE)
RETURNS TABLE (gross NUMERIC, accumulated_depreciation NUMERIC, carrying_amount NUMERIC)
LANGUAGE plpgsql STABLE AS $$
DECLARE a fixed_assets%ROWTYPE; v_rev asset_revaluations%ROWTYPE; v_g NUMERIC; v_ad NUMERIC;
BEGIN
    SELECT * INTO a FROM fixed_assets WHERE asset_id = p_asset_id;
    IF a.acquisition_date > p_as_at OR (a.disposal_date IS NOT NULL AND a.disposal_date <= p_as_at) THEN
        RETURN QUERY SELECT 0::NUMERIC, 0::NUMERIC, 0::NUMERIC; RETURN;
    END IF;
    SELECT * INTO v_rev FROM asset_revaluations
     WHERE asset_id = p_asset_id AND valuation_date <= p_as_at AND valuation_type IN ('revaluation','fair_value')
     ORDER BY valuation_date DESC LIMIT 1;
    IF FOUND THEN
        v_g  := v_rev.fair_value;                            -- elimination method: acc. dep. restarts at 0
        SELECT COALESCE(SUM(amount), 0) INTO v_ad FROM asset_depreciation
         WHERE asset_id = p_asset_id AND period_end > v_rev.valuation_date AND period_end <= p_as_at;
    ELSE
        v_g  := a.cost;
        SELECT a.opening_acc_depreciation + COALESCE(SUM(amount), 0) INTO v_ad FROM asset_depreciation
         WHERE asset_id = p_asset_id AND period_end <= p_as_at;
    END IF;
    RETURN QUERY SELECT v_g, v_ad, v_g - v_ad;
END $$;

-- Monthly depreciation for one asset (straight-line on cost / revalued amount over remaining life,
-- or reducing balance). Full month in the month the asset becomes available for use.
CREATE OR REPLACE FUNCTION fn_asset_monthly_depreciation(p_asset_id BIGINT, p_period_end DATE) RETURNS NUMERIC
LANGUAGE plpgsql STABLE AS $$
DECLARE a fixed_assets%ROWTYPE; c asset_categories%ROWTYPE; n RECORD; v_life INT; v_used INT; v_rev DATE; v_dep NUMERIC;
BEGIN
    SELECT * INTO a FROM fixed_assets WHERE asset_id = p_asset_id;
    SELECT * INTO c FROM asset_categories WHERE asset_category_id = a.asset_category_id;
    IF c.depreciation_method = 'none' OR a.status NOT IN ('in_use','idle') OR a.available_for_use_date > p_period_end THEN
        RETURN 0;
    END IF;
    IF a.acquisition_date > (date_trunc('month', p_period_end) - INTERVAL '1 day')::DATE THEN
        -- first month in service: nothing depreciated yet
        SELECT a.cost AS gross, 0::NUMERIC AS accumulated_depreciation, a.cost AS carrying_amount INTO n;
    ELSE
        SELECT * INTO n FROM fn_asset_nbv(p_asset_id, (date_trunc('month', p_period_end) - INTERVAL '1 day')::DATE);
    END IF;
    IF n.carrying_amount <= a.residual_value THEN RETURN 0; END IF;
    IF c.depreciation_method = 'reducing_balance' THEN
        v_dep := round(n.carrying_amount * c.reducing_balance_rate / 100 / 12, 2);
    ELSE
        v_life := COALESCE(a.useful_life_months, c.useful_life_months);
        SELECT max(valuation_date) INTO v_rev FROM asset_revaluations
         WHERE asset_id = p_asset_id AND valuation_date < p_period_end AND valuation_type = 'revaluation';
        IF v_rev IS NULL THEN
            v_dep := round((a.cost - a.residual_value) / v_life, 2);
        ELSE
            v_used := (extract(year FROM age(v_rev, a.available_for_use_date)) * 12
                       + extract(month FROM age(v_rev, a.available_for_use_date)))::INT;
            v_dep := round((n.gross - a.residual_value) / GREATEST(v_life - v_used, 12), 2);
        END IF;
    END IF;
    RETURN GREATEST(LEAST(v_dep, n.carrying_amount - a.residual_value), 0);
END $$;

-- Post depreciation for every asset for the month ending p_period_end
CREATE OR REPLACE FUNCTION fn_run_depreciation(p_period_end DATE, p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE r RECORD; v_dep NUMERIC; v_je BIGINT; v_lines JSONB := '[]'::JSONB; v_total NUMERIC := 0;
BEGIN
    p_period_end := (date_trunc('month', p_period_end) + INTERVAL '1 month - 1 day')::DATE;
    CREATE TEMP TABLE IF NOT EXISTS tmp_dep (asset_id BIGINT, amount NUMERIC) ON COMMIT DROP;
    DELETE FROM tmp_dep;
    FOR r IN SELECT fa.asset_id FROM fixed_assets fa
              WHERE fa.status IN ('in_use','idle') AND fa.available_for_use_date <= p_period_end
                AND NOT EXISTS (SELECT 1 FROM asset_depreciation d WHERE d.asset_id = fa.asset_id AND d.period_end = p_period_end)
    LOOP
        v_dep := fn_asset_monthly_depreciation(r.asset_id, p_period_end);
        IF v_dep > 0 THEN INSERT INTO tmp_dep VALUES (r.asset_id, v_dep); END IF;
    END LOOP;

    FOR r IN SELECT ex.account_code AS exp_acc, ad.account_code AS ad_acc, fa.office_id, fa.department_id, SUM(t.amount) amt
               FROM tmp_dep t JOIN fixed_assets fa USING (asset_id)
               JOIN asset_categories c ON c.asset_category_id = fa.asset_category_id
               JOIN chart_of_accounts ex ON ex.account_id = c.dep_expense_account_id
               JOIN chart_of_accounts ad ON ad.account_id = c.acc_dep_account_id
              GROUP BY 1, 2, 3, 4
    LOOP
        v_lines := v_lines
          || jsonb_build_object('acc', r.exp_acc, 'dr', r.amt, 'office', r.office_id, 'dept', r.department_id, 'desc','Depreciation / amortisation')
          || jsonb_build_object('acc', r.ad_acc,  'cr', r.amt, 'office', r.office_id, 'desc','Accumulated depreciation');
        v_total := v_total + r.amt;
    END LOOP;
    IF v_total = 0 THEN RETURN NULL; END IF;

    v_je := fn_post_journal(p_period_end, 'Depreciation & amortisation ' || to_char(p_period_end, 'Mon YYYY'),
                            'depreciation', NULL, v_lines, p_user);
    INSERT INTO asset_depreciation (asset_id, period_end, amount, carrying_after, journal_entry_id)
    SELECT t.asset_id, p_period_end, t.amount, (SELECT carrying_amount FROM fn_asset_nbv(t.asset_id, p_period_end - 1)) - t.amount, v_je
      FROM tmp_dep t;
    -- carrying_after was computed before this month's row existed -> recompute exactly
    UPDATE asset_depreciation d SET carrying_after = (SELECT carrying_amount FROM fn_asset_nbv(d.asset_id, p_period_end))
     WHERE d.journal_entry_id = v_je;
    RETURN v_je;
END $$;

-- IAS 16 revaluation (elimination method) or IAS 40 fair-value remeasurement
CREATE OR REPLACE FUNCTION fn_revalue_asset(p_asset_id BIGINT, p_date DATE, p_fair_value NUMERIC, p_valuer TEXT,
                                            p_level SMALLINT DEFAULT 2, p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE a fixed_assets%ROWTYPE; c asset_categories%ROWTYPE; n RECORD; v_cost TEXT; v_ad TEXT; v_res TEXT;
        v_surplus NUMERIC; v_tax NUMERIC; v_rate NUMERIC; v_je BIGINT; v_type TEXT;
BEGIN
    SELECT * INTO a FROM fixed_assets WHERE asset_id = p_asset_id FOR UPDATE;
    SELECT * INTO c FROM asset_categories WHERE asset_category_id = a.asset_category_id;
    IF c.measurement_model = 'cost' THEN RAISE EXCEPTION 'Asset % uses the cost model - it cannot be revalued', a.asset_tag; END IF;
    SELECT * INTO n FROM fn_asset_nbv(p_asset_id, p_date);
    v_surplus := p_fair_value - n.carrying_amount;
    v_rate := fn_stat_rate('ZW','CIT',p_date) * (1 + fn_stat_rate('ZW','AIDS_LEVY',p_date) / 100);   -- 24.72
    v_tax := round(v_surplus * v_rate / 100, 2);
    SELECT account_code INTO v_cost FROM chart_of_accounts WHERE account_id = c.cost_account_id;
    SELECT account_code INTO v_ad   FROM chart_of_accounts WHERE account_id = c.acc_dep_account_id;
    SELECT account_code INTO v_res  FROM chart_of_accounts WHERE account_id = c.reval_reserve_account_id;

    IF c.measurement_model = 'fair_value' THEN            -- IAS 40: gain/loss in profit or loss (investing)
        v_type := 'fair_value';
        v_je := fn_post_journal(p_date, 'Fair value remeasurement - ' || a.name, 'fair_value', p_asset_id, jsonb_build_array(
            jsonb_build_object('acc', v_cost, 'dr', v_surplus, 'office', a.office_id, 'desc','Investment property to fair value'),
            jsonb_build_object('acc','4510', 'cr', v_surplus, 'office', a.office_id, 'desc','Fair value gain on investment property'),
            jsonb_build_object('acc','9020', 'dr', v_tax, 'desc','Deferred tax on fair value gain'),
            jsonb_build_object('acc','2900', 'cr', v_tax, 'desc','Deferred tax liability')), p_user);
        INSERT INTO asset_revaluations (asset_id, valuation_date, valuation_type, valuer, fair_value, carrying_before,
                                        surplus_deficit, to_profit_or_loss, deferred_tax, fair_value_level, journal_entry_id)
        VALUES (p_asset_id, p_date, v_type, p_valuer, p_fair_value, n.carrying_amount, v_surplus, v_surplus, v_tax, p_level, v_je);
    ELSE                                                    -- IAS 16 revaluation model: surplus to OCI net of deferred tax
        v_type := 'revaluation';
        v_je := fn_post_journal(p_date, 'Revaluation - ' || a.name, 'revaluation', p_asset_id, jsonb_build_array(
            jsonb_build_object('acc', v_ad,   'dr', n.accumulated_depreciation, 'office', a.office_id, 'desc','Eliminate accumulated depreciation'),
            jsonb_build_object('acc', v_cost, 'cr', n.accumulated_depreciation, 'office', a.office_id, 'desc','Eliminate accumulated depreciation'),
            jsonb_build_object('acc', v_cost, 'dr', v_surplus, 'office', a.office_id, 'desc','Revaluation to fair value'),
            jsonb_build_object('acc', COALESCE(v_res,'3300'), 'cr', v_surplus - v_tax, 'desc','Revaluation surplus (OCI)'),
            jsonb_build_object('acc','2900', 'cr', v_tax, 'desc','Deferred tax on revaluation (OCI)')), p_user);
        INSERT INTO asset_revaluations (asset_id, valuation_date, valuation_type, valuer, fair_value, carrying_before,
                                        surplus_deficit, to_oci, deferred_tax, fair_value_level, journal_entry_id)
        VALUES (p_asset_id, p_date, v_type, p_valuer, p_fair_value, n.carrying_amount, v_surplus, v_surplus - v_tax, v_tax, p_level, v_je);
    END IF;
    UPDATE fixed_assets SET revalued_amount = p_fair_value, last_revaluation_date = p_date WHERE asset_id = p_asset_id;
    RETURN v_je;
END $$;

-- Sell / scrap an asset: remove cost & accumulated depreciation, book the gain or loss
CREATE OR REPLACE FUNCTION fn_dispose_asset(p_asset_id BIGINT, p_date DATE, p_proceeds NUMERIC, p_bank_account_id BIGINT,
                                            p_buyer TEXT DEFAULT NULL, p_type TEXT DEFAULT 'sale',
                                            p_approver BIGINT DEFAULT NULL, p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE a fixed_assets%ROWTYPE; c asset_categories%ROWTYPE; n RECORD; v_cost TEXT; v_ad TEXT; v_bank TEXT; v_gain NUMERIC; v_je BIGINT;
BEGIN
    SELECT * INTO a FROM fixed_assets WHERE asset_id = p_asset_id FOR UPDATE;
    IF a.status IN ('disposed','written_off') THEN RAISE EXCEPTION 'Asset % is already %', a.asset_tag, a.status; END IF;
    SELECT * INTO c FROM asset_categories WHERE asset_category_id = a.asset_category_id;
    SELECT * INTO n FROM fn_asset_nbv(p_asset_id, p_date);
    SELECT account_code INTO v_cost FROM chart_of_accounts WHERE account_id = c.cost_account_id;
    SELECT account_code INTO v_ad   FROM chart_of_accounts WHERE account_id = c.acc_dep_account_id;
    SELECT ca.account_code INTO v_bank FROM bank_accounts b JOIN chart_of_accounts ca ON ca.account_id = b.gl_account_id
     WHERE b.bank_account_id = p_bank_account_id;
    v_gain := p_proceeds - n.carrying_amount;

    v_je := fn_post_journal(p_date, 'Disposal of ' || a.asset_tag || ' ' || a.name, 'asset_disposal', p_asset_id, jsonb_build_array(
        jsonb_build_object('acc', COALESCE(v_bank,'1010'), 'dr', p_proceeds, 'desc','Disposal proceeds'),
        jsonb_build_object('acc', v_ad,   'dr', n.accumulated_depreciation, 'office', a.office_id, 'desc','Remove accumulated depreciation'),
        jsonb_build_object('acc', v_cost, 'cr', n.gross, 'office', a.office_id, 'desc','Remove cost'),
        jsonb_build_object('acc', CASE WHEN v_gain >= 0 THEN '4700' ELSE '7200' END, 'cr', v_gain, 'office', a.office_id,
                           'desc', CASE WHEN v_gain >= 0 THEN 'Gain on disposal' ELSE 'Loss on disposal' END)), p_user);
    INSERT INTO asset_disposals (asset_id, disposal_date, disposal_type, proceeds, carrying_amount, gain_loss, buyer,
                                 bank_account_id, approved_by, journal_entry_id)
    VALUES (p_asset_id, p_date, p_type, p_proceeds, n.carrying_amount, v_gain, p_buyer, p_bank_account_id, p_approver, v_je);
    UPDATE fixed_assets SET status = 'disposed', disposal_date = p_date WHERE asset_id = p_asset_id;
    UPDATE asset_assignments SET returned_date = p_date WHERE asset_id = p_asset_id AND returned_date IS NULL;
    RETURN v_je;
END $$;


/* ---------- 22.5 Leases (IFRS 16) & loans ---------- */

CREATE OR REPLACE FUNCTION fn_generate_lease_schedule(p_lease_id BIGINT) RETURNS NUMERIC
LANGUAGE plpgsql AS $$
DECLARE
    l leases%ROWTYPE; v_r NUMERIC; v_step INT; v_pv NUMERIC := 0; v_pay NUMERIC; k INT; v_bal NUMERIC;
    v_int NUMERIC; v_rou_usd NUMERIC; v_dep NUMERIC; v_pay_k NUMERIC;
BEGIN
    SELECT * INTO l FROM leases WHERE lease_id = p_lease_id;
    IF l.role <> 'lessee' OR l.exemption IS NOT NULL THEN RETURN 0; END IF;
    DELETE FROM lease_schedule WHERE lease_id = p_lease_id;
    v_r := l.discount_rate_pct / 100 / 12;
    v_step := CASE l.payment_frequency WHEN 'monthly' THEN 1 WHEN 'quarterly' THEN 3 ELSE 12 END;

    -- present value of all payments (escalating once a year)
    FOR k IN 0 .. l.term_months - 1 LOOP
        IF k % v_step = 0 THEN
            v_pay := l.payment_amount * power(1 + l.annual_escalation_pct / 100, k / 12);
            v_pv  := v_pv + v_pay / power(1 + v_r, CASE WHEN l.payment_timing = 'advance' THEN k ELSE k + v_step END);
        END IF;
    END LOOP;
    v_pv := round(v_pv, 2);
    v_rou_usd := round(v_pv * l.commencement_fx_rate + l.initial_direct_costs - l.lease_incentives, 2);
    v_dep := round(v_rou_usd / l.term_months, 2);

    v_bal := v_pv;
    FOR k IN 0 .. l.term_months - 1 LOOP
        v_pay_k := CASE WHEN k % v_step = 0 THEN round(l.payment_amount * power(1 + l.annual_escalation_pct / 100, k / 12), 2) ELSE 0 END;
        IF l.payment_timing = 'advance' THEN
            v_int := round((v_bal - v_pay_k) * v_r, 2);
        ELSE
            v_int := round(v_bal * v_r, 2);
        END IF;
        IF k = l.term_months - 1 THEN                        -- clear rounding in the last period
            v_int := v_pay_k - v_bal;
            IF v_int < 0 THEN v_int := 0; END IF;
        END IF;
        INSERT INTO lease_schedule (lease_id, period_no, period_date, opening_liability, payment, interest, principal,
                                    closing_liability, rou_depreciation)
        VALUES (p_lease_id, k + 1, (date_trunc('month', l.commencement_date) + make_interval(months => k))::DATE,
                v_bal, v_pay_k, v_int, v_pay_k - v_int,
                CASE WHEN k = l.term_months - 1 THEN 0 ELSE v_bal - v_pay_k + v_int END,
                CASE WHEN k = l.term_months - 1 THEN v_rou_usd - v_dep * (l.term_months - 1) ELSE v_dep END);
        v_bal := v_bal - v_pay_k + v_int;
    END LOOP;
    UPDATE leases SET initial_liability = v_pv, initial_rou_asset = v_rou_usd WHERE lease_id = p_lease_id;
    RETURN v_pv;
END $$;

-- Recognise a new lease at commencement: Dr ROU asset / Cr lease liability (non-cash)
CREATE OR REPLACE FUNCTION fn_recognise_lease(p_lease_id BIGINT, p_user BIGINT DEFAULT NULL) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE l leases%ROWTYPE; v_je BIGINT;
BEGIN
    SELECT * INTO l FROM leases WHERE lease_id = p_lease_id FOR UPDATE;
    IF l.status <> 'draft' THEN RAISE EXCEPTION 'Lease % is already %', l.lease_number, l.status; END IF;
    UPDATE leases SET commencement_fx_rate = fn_fx_rate(currency_code, commencement_date) WHERE lease_id = p_lease_id;
    PERFORM fn_generate_lease_schedule(p_lease_id);
    SELECT * INTO l FROM leases WHERE lease_id = p_lease_id;
    v_je := fn_post_journal(l.commencement_date, 'Lease commencement ' || l.lease_number || ' - ' || l.description, 'lease', p_lease_id,
        jsonb_build_array(
            jsonb_build_object('acc', l.rou_account_code, 'dr', l.initial_rou_asset, 'office', l.office_id, 'desc','Right-of-use asset'),
            jsonb_build_object('acc','2700', 'cr', round(l.initial_liability * l.commencement_fx_rate, 2), 'office', l.office_id, 'desc','Lease liability'),
            jsonb_build_object('acc','2100', 'cr', l.initial_direct_costs - l.lease_incentives, 'desc','Initial direct costs less incentives')),
        p_user);
    UPDATE leases SET status = 'active', recognised_journal_id = v_je,
                      liability_usd_balance = round(initial_liability * commencement_fx_rate, 2), last_fx_rate = commencement_fx_rate
     WHERE lease_id = p_lease_id;
    RETURN v_je;
END $$;

/* Monthly lease accounting for all active leases for the month containing p_month:
   (1) remeasure the foreign-currency liability to this month's rate (IAS 21, P&L)
   (2) interest & ROU depreciation (non-cash journal)
   (3) the cash payment (pure cash journal: interest part -> financing/interest paid,
       principal part -> financing/lease principal) */
CREATE OR REPLACE FUNCTION fn_post_lease_month(p_month DATE, p_user BIGINT DEFAULT NULL) RETURNS INTEGER
LANGUAGE plpgsql AS $$
DECLARE
    v_m DATE := date_trunc('month', p_month)::DATE; v_end DATE; l RECORD; s lease_schedule%ROWTYPE;
    v_rate NUMERIC; v_fx NUMERIC; v_int NUMERIC; v_pay NUMERIC; v_bank TEXT; v_count INT := 0; v_je BIGINT;
BEGIN
    v_end := (v_m + INTERVAL '1 month - 1 day')::DATE;
    FOR l IN SELECT * FROM leases WHERE role = 'lessee' AND status = 'active' AND exemption IS NULL ORDER BY lease_id LOOP
        SELECT * INTO s FROM lease_schedule WHERE lease_id = l.lease_id AND period_date = v_m AND NOT is_posted;
        CONTINUE WHEN NOT FOUND;
        v_rate := fn_fx_rate(l.currency_code, v_end);

        -- (1) FX remeasurement of the opening liability
        v_fx := round(s.opening_liability * v_rate, 2) - l.liability_usd_balance;
        IF v_fx <> 0 THEN
            PERFORM fn_post_journal(v_end, 'Lease liability FX remeasurement ' || l.lease_number, 'fx_revaluation', l.lease_id,
                jsonb_build_array(jsonb_build_object('acc', CASE WHEN v_fx > 0 THEN '7300' ELSE '4800' END, 'dr', v_fx, 'office', l.office_id,
                                                     'desc','Exchange difference on lease liability'),
                                  jsonb_build_object('acc','2700','cr', v_fx, 'office', l.office_id, 'desc','Lease liability remeasured')), p_user);
        END IF;

        -- (2) interest + depreciation
        v_int := round(s.interest * v_rate, 2);
        v_je := fn_post_journal(v_end, 'Lease interest & ROU depreciation ' || l.lease_number, 'lease', l.lease_id,
            jsonb_build_array(
                jsonb_build_object('acc','8000','dr', v_int, 'office', l.office_id, 'desc','Interest on lease liability'),
                jsonb_build_object('acc','2705','cr', v_int, 'office', l.office_id, 'desc','Lease interest payable'),
                jsonb_build_object('acc','7010','dr', s.rou_depreciation, 'office', l.office_id, 'desc','Depreciation of right-of-use asset'),
                jsonb_build_object('acc', l.rou_acc_dep_account_code, 'cr', s.rou_depreciation, 'office', l.office_id, 'desc','Accumulated depreciation - ROU')),
            p_user);

        -- (3) payment from the branch's own bank account (or head office USD)
        v_pay := round(s.payment * v_rate, 2);
        IF v_pay > 0 THEN
            SELECT a.account_code INTO v_bank
              FROM bank_accounts b JOIN chart_of_accounts a ON a.account_id = b.gl_account_id
             WHERE b.currency_code = l.currency_code AND b.is_active AND b.account_type IN ('current','fca')
             ORDER BY (b.office_id = l.office_id) DESC NULLS LAST, b.bank_account_id LIMIT 1;
            PERFORM fn_post_journal(CASE WHEN l.payment_timing = 'advance' THEN v_m ELSE v_end END,
                'Lease payment ' || l.lease_number || ' - ' || l.description, 'lease_payment', l.lease_id,
                jsonb_build_array(
                    jsonb_build_object('acc','2705','dr', v_int, 'office', l.office_id, 'vendor', l.vendor_id, 'desc','Lease interest paid'),
                    jsonb_build_object('acc','2700','dr', v_pay - v_int, 'office', l.office_id, 'vendor', l.vendor_id, 'desc','Lease principal paid'),
                    jsonb_build_object('acc', COALESCE(v_bank,'1010'), 'cr', v_pay, 'desc','Rent paid to landlord')), p_user);
        ELSIF v_int > 0 THEN
            -- rent-free month: interest stays in the liability
            PERFORM fn_post_journal(v_end, 'Lease interest capitalised ' || l.lease_number, 'lease', l.lease_id,
                jsonb_build_array(jsonb_build_object('acc','2705','dr', v_int), jsonb_build_object('acc','2700','cr', v_int)), p_user);
        END IF;

        UPDATE lease_schedule SET is_posted = TRUE, journal_entry_id = v_je WHERE lease_id = l.lease_id AND period_no = s.period_no;
        UPDATE leases SET liability_usd_balance = round(s.closing_liability * v_rate, 2), last_fx_rate = v_rate,
                          status = CASE WHEN s.period_no = term_months THEN 'expired' ELSE status END
         WHERE lease_id = l.lease_id;
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END $$;

CREATE OR REPLACE FUNCTION fn_generate_loan_schedule(p_loan_id BIGINT) RETURNS NUMERIC
LANGUAGE plpgsql AS $$
DECLARE b borrowings%ROWTYPE; v_r NUMERIC; v_inst NUMERIC; v_bal NUMERIC; k INT; v_int NUMERIC;
BEGIN
    SELECT * INTO b FROM borrowings WHERE loan_id = p_loan_id;
    DELETE FROM loan_schedule WHERE loan_id = p_loan_id;
    v_r := b.interest_rate_pct / 100 / 12;
    v_inst := round(b.principal * v_r / (1 - power(1 + v_r, -b.term_months)), 2);
    v_bal := b.principal;
    FOR k IN 1 .. b.term_months LOOP
        v_int := round(v_bal * v_r, 2);
        INSERT INTO loan_schedule (loan_id, period_no, due_date, opening_balance, instalment, interest, principal, closing_balance)
        VALUES (p_loan_id, k, (b.drawdown_date + make_interval(months => k))::DATE, v_bal,
                CASE WHEN k = b.term_months THEN v_bal + v_int ELSE v_inst END, v_int,
                CASE WHEN k = b.term_months THEN v_bal ELSE v_inst - v_int END,
                CASE WHEN k = b.term_months THEN 0 ELSE v_bal - (v_inst - v_int) END);
        v_bal := CASE WHEN k = b.term_months THEN 0 ELSE v_bal - (v_inst - v_int) END;
    END LOOP;
    UPDATE borrowings SET monthly_instalment = v_inst WHERE loan_id = p_loan_id;
    RETURN v_inst;
END $$;

-- Pay loan instalments due in the month: Dr interest (financing) + Dr loan / Cr bank
CREATE OR REPLACE FUNCTION fn_post_loan_month(p_month DATE, p_user BIGINT DEFAULT NULL) RETURNS INTEGER
LANGUAGE plpgsql AS $$
DECLARE r RECORD; v_bank TEXT; v_count INT := 0; v_je BIGINT;
BEGIN
    FOR r IN SELECT s.*, b.loan_number, b.lender, b.bank_account_id
               FROM loan_schedule s JOIN borrowings b USING (loan_id)
              WHERE b.status = 'active' AND NOT s.is_posted
                AND s.due_date BETWEEN date_trunc('month', p_month)::DATE AND (date_trunc('month', p_month) + INTERVAL '1 month - 1 day')::DATE
    LOOP
        SELECT a.account_code INTO v_bank FROM bank_accounts k JOIN chart_of_accounts a ON a.account_id = k.gl_account_id
         WHERE k.bank_account_id = r.bank_account_id;
        v_je := fn_post_journal(r.due_date, format('Loan instalment %s - %s', r.loan_number, r.lender), 'loan', r.loan_id,
            jsonb_build_array(jsonb_build_object('acc','8010','dr', r.interest, 'desc','Interest on borrowings'),
                              jsonb_build_object('acc','2800','dr', r.principal, 'desc','Loan principal repaid'),
                              jsonb_build_object('acc', COALESCE(v_bank,'1010'), 'cr', r.instalment, 'desc','Loan instalment')), p_user);
        UPDATE loan_schedule SET is_posted = TRUE, journal_entry_id = v_je WHERE loan_id = r.loan_id AND period_no = r.period_no;
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END $$;


/* ---------- 22.6 Tax compliance ---------- */

-- Balance movement of an account in a period (debit - credit), excluding given journal sources
CREATE OR REPLACE FUNCTION fn_account_movement(p_code TEXT, p_from DATE, p_to DATE, p_exclude_sources TEXT[] DEFAULT '{}')
RETURNS NUMERIC LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(jl.debit - jl.credit), 0)
      FROM journal_lines jl
      JOIN journal_entries je ON je.journal_entry_id = jl.journal_entry_id
      JOIN chart_of_accounts a ON a.account_id = jl.account_id
     WHERE a.account_code = p_code AND je.status IN ('posted','reversed')
       AND je.entry_date BETWEEN p_from AND p_to
       AND NOT (je.source_type = ANY (p_exclude_sources));
$$;

CREATE OR REPLACE FUNCTION fn_account_balance(p_code TEXT, p_as_at DATE) RETURNS NUMERIC
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(jl.debit - jl.credit), 0)
      FROM journal_lines jl
      JOIN journal_entries je ON je.journal_entry_id = jl.journal_entry_id
      JOIN chart_of_accounts a ON a.account_id = jl.account_id
     WHERE a.account_code = p_code AND je.status IN ('posted','reversed') AND je.entry_date <= p_as_at;
$$;

-- ZIMRA VAT7 return for a month (output tax on 2200, input tax on 2210)
CREATE OR REPLACE FUNCTION fn_prepare_vat_return(p_month DATE, p_prepared_by BIGINT DEFAULT NULL) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE v_from DATE := date_trunc('month', p_month)::DATE; v_to DATE; v_out NUMERIC; v_in NUMERIC; v_id BIGINT; v_sales NUMERIC;
BEGIN
    v_to := (v_from + INTERVAL '1 month - 1 day')::DATE;
    v_out := -fn_account_movement('2200', v_from, v_to, ARRAY['tax_payment']);
    v_in  :=  fn_account_movement('2210', v_from, v_to, ARRAY['tax_payment']);
    SELECT COALESCE(SUM(subtotal), 0) INTO v_sales FROM invoices WHERE invoice_date BETWEEN v_from AND v_to AND status <> 'void';
    INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, credits_amount,
                             status, prepared_by)
    VALUES ('VAT-' || to_char(v_from, 'YYYY-MM'), 'VAT', (SELECT office_id FROM offices WHERE is_head_office), v_from, v_to,
            (v_from + INTERVAL '1 month' + INTERVAL '24 days')::DATE, v_out, v_in, 'draft', p_prepared_by)
    RETURNING tax_return_id INTO v_id;
    INSERT INTO tax_return_lines VALUES
        (v_id, 1, 'VAT7-1', 'Value of taxable supplies (all invoices, excl. VAT)', v_sales),
        (v_id, 2, 'VAT7-2', 'Output tax (15.5%)', v_out),
        (v_id, 3, 'VAT7-3', 'Input tax claimable', v_in),
        (v_id, 4, 'VAT7-4', 'Net VAT payable / (refundable)', v_out - v_in);
    RETURN v_id;
END $$;

-- Monthly payroll returns from approved payroll runs: ZIMRA P2 (PAYE + AIDS levy), NSSA P4, ZIMDEF,
-- and the branch payroll-tax returns (SARS EMP201, KRA P10, HMRC RTI/FPS)
CREATE OR REPLACE FUNCTION fn_prepare_payroll_returns(p_month DATE, p_prepared_by BIGINT DEFAULT NULL) RETURNS INTEGER
LANGUAGE plpgsql AS $$
DECLARE v_from DATE := date_trunc('month', p_month)::DATE; v_to DATE; r RECORD; v_id BIGINT; v_n INT := 0;
BEGIN
    v_to := (v_from + INTERVAL '1 month - 1 day')::DATE;
    FOR r IN
        SELECT pr.country_code,
               SUM(p.paye_tax * pr.exchange_rate) paye, SUM(p.aids_levy * pr.exchange_rate) aids,
               SUM((p.nssa_employee + p.employer_nssa + p.employer_wcif) * pr.exchange_rate) nssa,
               SUM(p.employer_zimdef * pr.exchange_rate) zimdef,
               SUM((p.paye_tax + p.nssa_employee + p.employer_nssa + p.employer_wcif) * pr.exchange_rate) branch,
               SUM(p.gross_pay * pr.exchange_rate) gross
          FROM payroll_runs pr JOIN payslips p USING (payroll_run_id)
         WHERE pr.period_start = v_from AND pr.status IN ('approved','paid')
         GROUP BY pr.country_code
    LOOP
        IF r.country_code = 'ZW' THEN
            INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, status, prepared_by)
            VALUES ('P2-' || to_char(v_from,'YYYY-MM'), 'PAYE', (SELECT office_id FROM offices WHERE is_head_office), v_from, v_to,
                    (v_from + INTERVAL '1 month' + INTERVAL '9 days')::DATE, round(r.paye + r.aids, 2), 'draft', p_prepared_by)
            RETURNING tax_return_id INTO v_id;
            INSERT INTO tax_return_lines VALUES (v_id,1,'P2-A','Gross remuneration', round(r.gross,2)),
                                                (v_id,2,'P2-B','PAYE deducted', round(r.paye,2)),
                                                (v_id,3,'P2-C','AIDS levy (3% of PAYE)', round(r.aids,2));
            INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, status, prepared_by)
            VALUES ('P4-' || to_char(v_from,'YYYY-MM'), 'NSSA', (SELECT office_id FROM offices WHERE is_head_office), v_from, v_to,
                    (v_from + INTERVAL '1 month' + INTERVAL '9 days')::DATE, round(r.nssa, 2), 'draft', p_prepared_by);
            INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, status, prepared_by)
            VALUES ('ZIMDEF-' || to_char(v_from,'YYYY-MM'), 'ZIMDEF', (SELECT office_id FROM offices WHERE is_head_office), v_from, v_to,
                    (v_from + INTERVAL '1 month' + INTERVAL '9 days')::DATE, round(r.zimdef, 2), 'draft', p_prepared_by);
            v_n := v_n + 3;
        ELSE
            INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, status, prepared_by)
            SELECT tt.tax_code || '-' || to_char(v_from,'YYYY-MM'), tt.tax_code,
                   (SELECT office_id FROM offices o WHERE o.country_code = r.country_code ORDER BY o.office_id LIMIT 1),
                   v_from, v_to, (v_from + INTERVAL '1 month' + make_interval(days => COALESCE(tt.due_day, 7) - 1))::DATE,
                   round(r.branch, 2), 'draft', p_prepared_by
              FROM tax_types tt WHERE tt.tax_code = r.country_code || '_PAYE';
            v_n := v_n + 1;
        END IF;
    END LOOP;
    RETURN v_n;
END $$;

-- Branch VAT/GST return (SARS VAT201, KRA VAT3, HMRC VAT100, UAE VAT201): output tax on the branch account.
-- Branch input VAT is expensed in this model (see fn_approve_vendor_bill), so the return is output tax only.
CREATE OR REPLACE FUNCTION fn_prepare_branch_vat_return(p_tax_code TEXT, p_from DATE, p_to DATE, p_prepared_by BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE tt tax_types%ROWTYPE; v_out NUMERIC; v_id BIGINT;
BEGIN
    SELECT * INTO tt FROM tax_types WHERE tax_code = p_tax_code;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unknown tax type %', p_tax_code; END IF;
    v_out := -fn_account_movement(tt.liability_account_code, p_from, p_to, ARRAY['tax_payment']);
    IF v_out = 0 THEN RETURN NULL; END IF;
    INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, status, prepared_by)
    VALUES (p_tax_code || '-' || to_char(p_to, 'YYYY-MM'), p_tax_code,
            (SELECT o.office_id FROM offices o JOIN tax_authorities a ON a.country_code = o.country_code
              WHERE a.authority_code = tt.authority_code ORDER BY o.office_id LIMIT 1),
            p_from, p_to, (date_trunc('month', p_to) + INTERVAL '1 month' + make_interval(days => COALESCE(tt.due_day, 25) - 1))::DATE,
            v_out, 'draft', p_prepared_by)
    RETURNING tax_return_id INTO v_id;
    RETURN v_id;
END $$;

-- Four QPD instalments of estimated corporate income tax (10/25/30/35%)
CREATE OR REPLACE FUNCTION fn_create_qpds(p_year INT, p_estimated_tax NUMERIC, p_prepared_by BIGINT DEFAULT NULL) RETURNS INTEGER
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, status, prepared_by, notes)
    SELECT format('QPD%s-%s', q.n, p_year), 'CIT_QPD', (SELECT office_id FROM offices WHERE is_head_office),
           make_date(p_year, q.n * 3 - 2, 1), (make_date(p_year, q.n * 3, 1) + INTERVAL '1 month - 1 day')::DATE,
           q.due, round(p_estimated_tax * q.pct / 100, 2), 'draft', p_prepared_by,
           format('QPD %s: %s%% of estimated tax of USD %s', q.n, q.pct, to_char(p_estimated_tax, 'FM999,999,990.00'))
      FROM (VALUES (1, 10, make_date(p_year,3,25)), (2, 25, make_date(p_year,6,25)),
                   (3, 30, make_date(p_year,9,25)), (4, 35, make_date(p_year,12,20))) AS q(n, pct, due);
    RETURN 4;
END $$;

CREATE OR REPLACE FUNCTION fn_file_tax_return(p_return_id BIGINT, p_date DATE DEFAULT CURRENT_DATE, p_ack TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    UPDATE tax_returns SET status = 'filed', filed_date = p_date,
                           acknowledgement_ref = COALESCE(p_ack, 'ACK-' || upper(substr(md5(tax_return_id::TEXT || p_date::TEXT), 1, 10)))
     WHERE tax_return_id = p_return_id AND status IN ('draft','overdue','not_started');
    IF NOT FOUND THEN RAISE EXCEPTION 'Return % cannot be filed in its current status', p_return_id; END IF;
END $$;

-- Pay a return: clears the liability accounts of the tax type against the bank (pure cash journal)
CREATE OR REPLACE FUNCTION fn_pay_tax_return(p_return_id BIGINT, p_bank_account_id BIGINT, p_date DATE DEFAULT CURRENT_DATE,
                                             p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE t tax_returns%ROWTYPE; tt tax_types%ROWTYPE; v_bank TEXT; v_lines JSONB; v_je BIGINT; v_aids NUMERIC;
BEGIN
    SELECT * INTO t FROM tax_returns WHERE tax_return_id = p_return_id FOR UPDATE;
    IF t.status = 'paid' THEN RAISE EXCEPTION 'Return % is already paid', t.return_number; END IF;
    SELECT * INTO tt FROM tax_types WHERE tax_code = t.tax_code;
    SELECT a.account_code INTO v_bank FROM bank_accounts b JOIN chart_of_accounts a ON a.account_id = b.gl_account_id
     WHERE b.bank_account_id = p_bank_account_id;

    IF t.tax_code = 'VAT' THEN
        v_lines := jsonb_build_array(jsonb_build_object('acc','2200','dr', t.gross_amount, 'desc','Output VAT settled'),
                                     jsonb_build_object('acc','2210','cr', t.credits_amount, 'desc','Input VAT claimed'));
    ELSIF t.tax_code = 'PAYE' THEN
        SELECT amount INTO v_aids FROM tax_return_lines WHERE tax_return_id = p_return_id AND box_code = 'P2-C';
        v_lines := jsonb_build_array(jsonb_build_object('acc','2400','dr', t.gross_amount - COALESCE(v_aids,0), 'desc','PAYE remitted'),
                                     jsonb_build_object('acc','2405','dr', COALESCE(v_aids,0), 'desc','AIDS levy remitted'));
    ELSE
        v_lines := jsonb_build_array(jsonb_build_object('acc', tt.liability_account_code, 'dr', t.amount_due, 'desc', tt.name));
    END IF;
    v_lines := v_lines
      || jsonb_build_array(jsonb_build_object('acc','6900','dr', t.penalty_amount + t.interest_amount, 'desc','Tax penalties & interest (not deductible)'),
                           jsonb_build_object('acc', v_bank, 'cr', t.amount_due + t.penalty_amount + t.interest_amount,
                                              'desc','Payment to ' || tt.authority_code));
    v_je := fn_post_journal(p_date, format('%s payment %s', tt.authority_code, t.return_number), 'tax_payment', p_return_id, v_lines, p_user);
    UPDATE tax_returns SET status = 'paid', paid_date = p_date, amount_paid = amount_due + penalty_amount + interest_amount,
                           bank_account_id = p_bank_account_id, journal_entry_id = v_je,
                           filed_date = COALESCE(filed_date, p_date)
     WHERE tax_return_id = p_return_id;
    RETURN v_je;
END $$;

-- Current tax provision to date: (profit before tax YTD x 24.72%) - provision already booked (IAS 12)
CREATE OR REPLACE FUNCTION fn_accrue_income_tax(p_as_at DATE, p_user BIGINT DEFAULT NULL) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE v_from DATE := date_trunc('year', p_as_at)::DATE; v_pbt NUMERIC; v_rate NUMERIC; v_booked NUMERIC; v_need NUMERIC;
BEGIN
    SELECT COALESCE(SUM(jl.credit - jl.debit), 0) INTO v_pbt
      FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id)
      JOIN chart_of_accounts a ON a.account_id = jl.account_id
     WHERE je.status IN ('posted','reversed') AND je.entry_date BETWEEN v_from AND p_as_at
       AND a.account_type IN ('revenue','expense') AND a.account_code NOT LIKE '90%';
    v_rate := fn_stat_rate('ZW','CIT',p_as_at) * (1 + fn_stat_rate('ZW','AIDS_LEVY',p_as_at) / 100);
    v_booked := fn_account_movement('9000', v_from, p_as_at);
    v_need := round(GREATEST(v_pbt, 0) * v_rate / 100, 2) - v_booked;
    IF v_need = 0 THEN RETURN NULL; END IF;
    RETURN fn_post_journal(p_as_at, 'Current income tax provision to ' || to_char(p_as_at, 'DD Mon YYYY'), 'tax', NULL,
        jsonb_build_array(jsonb_build_object('acc','9000','dr', v_need, 'desc','Current tax - Zimbabwe (24% + 3% AIDS levy)'),
                          jsonb_build_object('acc','2260','cr', v_need, 'desc','Income tax payable (ZIMRA)')), p_user);
END $$;

-- Deferred tax working (IAS 12): temporary differences at a date
CREATE OR REPLACE FUNCTION fn_deferred_tax_schedule(p_as_at DATE)
RETURNS TABLE (item TEXT, carrying_amount NUMERIC, tax_base NUMERIC, temporary_difference NUMERIC, deferred_tax NUMERIC)
LANGUAGE sql STABLE AS $$
    WITH rate AS (SELECT fn_stat_rate('ZW','CIT',p_as_at) * (1 + fn_stat_rate('ZW','AIDS_LEVY',p_as_at)/100) / 100 AS r),
    ppe AS (
        SELECT c.name AS item, SUM(n.carrying_amount) AS ca,
               SUM(CASE WHEN c.asset_class IN ('land','investment_property') THEN fa.cost
                        ELSE GREATEST(COALESCE(fa.tax_value_opening, fa.cost)
                             - fa.cost * c.tax_wear_tear_rate_pct / 100
                               * GREATEST(extract(year FROM p_as_at) - extract(year FROM COALESCE(fa.opening_date, fa.acquisition_date))
                                          + CASE WHEN fa.opening_date IS NULL THEN 1 ELSE 0 END, 0), 0) END) AS tb
          FROM fixed_assets fa
          JOIN asset_categories c ON c.asset_category_id = fa.asset_category_id
          CROSS JOIN LATERAL fn_asset_nbv(fa.asset_id, p_as_at) n
         WHERE fa.acquisition_date <= p_as_at AND (fa.disposal_date IS NULL OR fa.disposal_date > p_as_at)
         GROUP BY c.name
    ),
    other AS (
        SELECT 'Right-of-use assets' AS item, fn_account_balance('1600', p_as_at) + fn_account_balance('1601', p_as_at)
                 + fn_account_balance('1610', p_as_at) + fn_account_balance('1611', p_as_at) AS ca, 0::NUMERIC AS tb
        UNION ALL
        SELECT 'Lease liabilities', fn_account_balance('2700', p_as_at) + fn_account_balance('2705', p_as_at), 0
        UNION ALL
        SELECT 'Expected credit loss allowance', fn_account_balance('1105', p_as_at), 0
        UNION ALL
        SELECT 'Leave pay & bonus accruals', fn_account_balance('2510', p_as_at) + fn_account_balance('2520', p_as_at), 0
    )
    SELECT item, round(ca, 2), round(tb, 2), round(ca - tb, 2), round((ca - tb) * (SELECT r FROM rate), 2)
      FROM (SELECT * FROM ppe UNION ALL SELECT * FROM other) x
     WHERE ca <> 0 OR tb <> 0
     ORDER BY 1;
$$;


/* ---------- 22.7 Other period-end routines ---------- */

-- IFRS 9 simplified approach: set the ECL allowance to the provision-matrix requirement
CREATE OR REPLACE FUNCTION fn_update_ecl_provision(p_as_at DATE, p_user BIGINT DEFAULT NULL) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE v_required NUMERIC; v_current NUMERIC; v_move NUMERIC;
BEGIN
    WITH open_items AS (
        SELECT i.invoice_id, i.due_date,
               i.total_amount * i.exchange_rate
                 - COALESCE((SELECT SUM(pa.amount) FROM payment_allocations pa JOIN payments p ON p.payment_id = pa.payment_id
                              WHERE pa.invoice_id = i.invoice_id AND p.payment_date <= p_as_at), 0) * i.exchange_rate AS bal
          FROM invoices i
         WHERE i.status <> 'draft' AND i.status <> 'void' AND i.invoice_date <= p_as_at
    )
    SELECT COALESCE(SUM(o.bal * m.loss_rate_pct / 100), 0) INTO v_required
      FROM open_items o
      JOIN ecl_provision_matrix m ON GREATEST(p_as_at - o.due_date, 0) >= m.min_days
                                 AND (m.max_days IS NULL OR GREATEST(p_as_at - o.due_date, 0) <= m.max_days)
     WHERE o.bal > 0.005;
    v_current := -fn_account_balance('1105', p_as_at);
    v_move := round(v_required - v_current, 2);
    IF v_move = 0 THEN RETURN NULL; END IF;
    RETURN fn_post_journal(p_as_at, 'Expected credit loss allowance update (IFRS 9)', 'ecl', NULL,
        jsonb_build_array(jsonb_build_object('acc','7100','dr', v_move, 'desc','Impairment loss on trade receivables'),
                          jsonb_build_object('acc','1105','cr', v_move, 'desc','Loss allowance')), p_user);
END $$;

-- Move money between two company bank accounts (USD value). Not a cash flow - both sides are cash.
CREATE OR REPLACE FUNCTION fn_bank_transfer(p_from_bank BIGINT, p_to_bank BIGINT, p_amount_usd NUMERIC, p_date DATE,
                                            p_description TEXT DEFAULT 'Inter-account transfer', p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_from TEXT; v_to TEXT;
BEGIN
    SELECT a.account_code INTO v_from FROM bank_accounts b JOIN chart_of_accounts a ON a.account_id = b.gl_account_id WHERE b.bank_account_id = p_from_bank;
    SELECT a.account_code INTO v_to   FROM bank_accounts b JOIN chart_of_accounts a ON a.account_id = b.gl_account_id WHERE b.bank_account_id = p_to_bank;
    RETURN fn_post_journal(p_date, p_description, 'transfer', NULL,
        jsonb_build_array(jsonb_build_object('acc', v_to, 'dr', p_amount_usd), jsonb_build_object('acc', v_from, 'cr', p_amount_usd)), p_user);
END $$;
