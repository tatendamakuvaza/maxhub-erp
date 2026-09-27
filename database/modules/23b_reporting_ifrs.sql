
/* =====================================================================================
   23B. IFRS FINANCIAL STATEMENTS & MANAGEMENT REPORTING
   -------------------------------------------------------------------------------------
   SELECT * FROM erp.fn_ifrs_profit_or_loss('2026-01-01','2026-09-30');   -- IFRS 18 P&L + OCI
   SELECT * FROM erp.fn_ifrs_financial_position('2026-09-30');           -- balance sheet
   SELECT * FROM erp.fn_ifrs_cash_flows('2026-01-01','2026-09-30');      -- IAS 7 (direct method)
   SELECT * FROM erp.fn_ifrs_changes_in_equity('2026-01-01','2026-09-30');
   SELECT * FROM erp.fn_ifrs_mpm_note('2026-01-01','2026-09-30');        -- IFRS 18 MPM note
   SELECT * FROM erp.fn_ppe_movement('2026-01-01','2026-09-30');         -- IAS 16 note
   SELECT * FROM erp.fn_trial_balance('2026-09-30');
   ===================================================================================== */

-- Trial balance at a date
CREATE OR REPLACE FUNCTION fn_trial_balance(p_as_at DATE)
RETURNS TABLE (account_code VARCHAR, account_name VARCHAR, account_type account_type, ifrs_line VARCHAR,
               debit NUMERIC, credit NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT a.account_code, a.name, a.account_type, li.name,
           CASE WHEN SUM(jl.debit - jl.credit) > 0 THEN SUM(jl.debit - jl.credit) ELSE 0 END,
           CASE WHEN SUM(jl.debit - jl.credit) < 0 THEN -SUM(jl.debit - jl.credit) ELSE 0 END
      FROM chart_of_accounts a
      JOIN journal_lines jl    ON jl.account_id = a.account_id
      JOIN journal_entries je  ON je.journal_entry_id = jl.journal_entry_id
                              AND je.status IN ('posted','reversed') AND je.entry_date <= p_as_at
      LEFT JOIN ifrs_line_items li ON li.line_code = a.ifrs_line_code
     GROUP BY a.account_code, a.name, a.account_type, li.name
    HAVING SUM(jl.debit - jl.credit) <> 0
     ORDER BY a.account_code;
$$;

-- Amount per IFRS line item for a period (credit-positive) or at a date (balances)
CREATE OR REPLACE FUNCTION fn_ifrs_line_amounts(p_from DATE, p_to DATE)
RETURNS TABLE (line_code VARCHAR, amount NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT a.ifrs_line_code, SUM(jl.credit - jl.debit)
      FROM journal_lines jl
      JOIN journal_entries je  ON je.journal_entry_id = jl.journal_entry_id
      JOIN chart_of_accounts a ON a.account_id = jl.account_id
     WHERE je.status IN ('posted','reversed') AND je.entry_date BETWEEN p_from AND p_to
     GROUP BY a.ifrs_line_code;
$$;

/* Statement of profit or loss and other comprehensive income (IFRS 18)
   amount: income +, expense -.  Rows flagged is_subtotal are the IFRS 18 required
   subtotals / totals. */
CREATE OR REPLACE FUNCTION fn_ifrs_profit_or_loss(p_from DATE, p_to DATE)
RETURNS TABLE (sort_order INT, line_code VARCHAR, caption VARCHAR, category VARCHAR, amount NUMERIC, is_subtotal BOOLEAN)
LANGUAGE sql STABLE AS $$
    WITH amt AS (SELECT * FROM fn_ifrs_line_amounts(p_from, p_to)),
    pl AS (
        SELECT li.sort_order::INT * 10 AS so, li.line_code, li.name, li.ifrs18_category AS cat,
               COALESCE(amt.amount, 0) AS amount
          FROM ifrs_line_items li LEFT JOIN amt ON amt.line_code = li.line_code
         WHERE li.statement = 'PL'
    ),
    oci AS (
        SELECT li.sort_order::INT * 10 AS so, li.line_code, li.name, 'oci'::VARCHAR AS cat,
               COALESCE((SELECT SUM(jl.credit - jl.debit)
                           FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id)
                           JOIN chart_of_accounts a ON a.account_id = jl.account_id
                          WHERE a.ifrs_line_code IN ('SFP_REVAL','SFP_FXRES')
                            AND ((li.line_code = 'OCI_REVAL' AND a.ifrs_line_code = 'SFP_REVAL' AND je.source_type = 'revaluation')
                              OR (li.line_code = 'OCI_FX'    AND a.ifrs_line_code = 'SFP_FXRES'))
                            AND je.status IN ('posted','reversed') AND je.entry_date BETWEEN p_from AND p_to), 0) AS amount
          FROM ifrs_line_items li WHERE li.statement = 'OCI'
    ),
    sub AS (
        SELECT 1995 AS so, 'ST_OP'::VARCHAR AS code, 'Operating profit'::VARCHAR AS cap,
               (SELECT COALESCE(SUM(amount),0) FROM pl WHERE cat = 'operating') AS amount
        UNION ALL SELECT 2995, 'ST_PBFIT', 'Profit before financing and income taxes',
               (SELECT COALESCE(SUM(amount),0) FROM pl WHERE cat IN ('operating','investing'))
        UNION ALL SELECT 3995, 'ST_PBT', 'Profit before income taxes',
               (SELECT COALESCE(SUM(amount),0) FROM pl WHERE cat IN ('operating','investing','financing'))
        UNION ALL SELECT 4995, 'ST_PCONT', 'Profit from continuing operations',
               (SELECT COALESCE(SUM(amount),0) FROM pl WHERE cat <> 'discontinued')
        UNION ALL SELECT 5995, 'ST_PROFIT', 'PROFIT FOR THE PERIOD',
               (SELECT COALESCE(SUM(amount),0) FROM pl)
        UNION ALL SELECT 6995, 'ST_OCI', 'Other comprehensive income for the period, net of tax',
               (SELECT COALESCE(SUM(amount),0) FROM oci)
        UNION ALL SELECT 7995, 'ST_TCI', 'TOTAL COMPREHENSIVE INCOME FOR THE PERIOD',
               (SELECT COALESCE(SUM(amount),0) FROM pl) + (SELECT COALESCE(SUM(amount),0) FROM oci)
    )
    SELECT so, line_code, name, cat, round(amount, 2), FALSE FROM pl
    UNION ALL SELECT so, line_code, name, cat, round(amount, 2), FALSE FROM oci
    UNION ALL SELECT so, code, cap, 'subtotal', round(amount, 2), TRUE FROM sub
    ORDER BY 1;
$$;

/* Statement of financial position. amount is positive for assets and for equity/liabilities.
   Lease liabilities and borrowings are split into current / non-current from their schedules. */
CREATE OR REPLACE FUNCTION fn_ifrs_financial_position(p_as_at DATE)
RETURNS TABLE (sort_order INT, section VARCHAR, line_code VARCHAR, caption VARCHAR, amount NUMERIC, is_subtotal BOOLEAN)
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_lease NUMERIC; v_lease_cur NUMERIC; v_loan NUMERIC; v_loan_cur NUMERIC; v_tax NUMERIC; v_re NUMERIC;
BEGIN
    CREATE TEMP TABLE IF NOT EXISTS tmp_sfp (t_so INT, t_section VARCHAR, t_code VARCHAR, t_caption VARCHAR, t_amount NUMERIC, t_sub BOOLEAN) ON COMMIT DROP;
    DELETE FROM tmp_sfp;

    -- balances per line (debit-positive)
    INSERT INTO tmp_sfp
    SELECT li.sort_order, li.section, li.line_code, li.name,
           COALESCE(SUM(jl.debit - jl.credit), 0) * li.sign * -1, FALSE
      FROM ifrs_line_items li
      LEFT JOIN chart_of_accounts a ON a.ifrs_line_code = li.line_code
      LEFT JOIN journal_lines jl    ON jl.account_id = a.account_id
                                   AND EXISTS (SELECT 1 FROM journal_entries je WHERE je.journal_entry_id = jl.journal_entry_id
                                                  AND je.status IN ('posted','reversed') AND je.entry_date <= p_as_at)
     WHERE li.statement = 'SFP'
     GROUP BY li.sort_order, li.section, li.line_code, li.name, li.sign;

    -- retained earnings include all profit or loss to date
    SELECT COALESCE(SUM(jl.credit - jl.debit), 0) INTO v_re
      FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id)
      JOIN chart_of_accounts a ON a.account_id = jl.account_id
     WHERE a.account_type IN ('revenue','expense') AND je.status IN ('posted','reversed') AND je.entry_date <= p_as_at;
    UPDATE tmp_sfp SET t_amount = t_amount + v_re WHERE t_code = 'SFP_RE';

    -- lease liabilities: current portion = principal falling due in the next 12 months
    SELECT t_amount INTO v_lease FROM tmp_sfp WHERE t_code = 'SFP_LEASE';
    SELECT COALESCE(SUM(s.principal * fn_fx_rate(l.currency_code, p_as_at)), 0) INTO v_lease_cur
      FROM lease_schedule s JOIN leases l USING (lease_id)
     WHERE s.period_date > p_as_at AND s.period_date <= p_as_at + INTERVAL '12 months' AND l.recognised_journal_id IS NOT NULL
       AND l.commencement_date <= p_as_at;
    v_lease_cur := LEAST(round(v_lease_cur, 2), COALESCE(v_lease, 0));
    UPDATE tmp_sfp SET t_amount = COALESCE(v_lease,0) - v_lease_cur WHERE t_code = 'SFP_LEASE';
    UPDATE tmp_sfp SET t_amount = v_lease_cur WHERE t_code = 'SFP_LEASE_C';

    SELECT t_amount INTO v_loan FROM tmp_sfp WHERE t_code = 'SFP_BORR';
    SELECT COALESCE(SUM(s.principal), 0) INTO v_loan_cur FROM loan_schedule s JOIN borrowings b USING (loan_id)
     WHERE s.due_date > p_as_at AND s.due_date <= p_as_at + INTERVAL '12 months' AND b.drawdown_date <= p_as_at;
    v_loan_cur := LEAST(v_loan_cur, COALESCE(v_loan, 0));
    UPDATE tmp_sfp SET t_amount = COALESCE(v_loan,0) - v_loan_cur WHERE t_code = 'SFP_BORR';
    UPDATE tmp_sfp SET t_amount = v_loan_cur WHERE t_code = 'SFP_BORR_C';

    -- current tax: show as an asset if QPDs paid exceed the provision
    SELECT t_amount INTO v_tax FROM tmp_sfp WHERE t_code = 'SFP_TAX_L';
    IF v_tax < 0 THEN
        UPDATE tmp_sfp SET t_amount = -v_tax WHERE t_code = 'SFP_TAX_A';
        UPDATE tmp_sfp SET t_amount = 0 WHERE t_code = 'SFP_TAX_L';
    END IF;

    -- subtotals
    INSERT INTO tmp_sfp
    SELECT 1990, 'ASSETS', 'T_NCA', 'Total non-current assets', SUM(t_amount), TRUE FROM tmp_sfp WHERE t_section = 'Non-current assets' AND NOT t_sub
    UNION ALL SELECT 2990, 'ASSETS', 'T_CA', 'Total current assets', SUM(t_amount), TRUE FROM tmp_sfp WHERE t_section = 'Current assets' AND NOT t_sub
    UNION ALL SELECT 2999, 'ASSETS', 'T_A', 'TOTAL ASSETS', SUM(t_amount), TRUE FROM tmp_sfp WHERE t_section IN ('Non-current assets','Current assets') AND NOT t_sub
    UNION ALL SELECT 3990, 'EQUITY', 'T_E', 'Total equity', SUM(t_amount), TRUE FROM tmp_sfp WHERE t_section = 'Equity' AND NOT t_sub
    UNION ALL SELECT 4990, 'LIABILITIES', 'T_NCL', 'Total non-current liabilities', SUM(t_amount), TRUE FROM tmp_sfp WHERE t_section = 'Non-current liabilities' AND NOT t_sub
    UNION ALL SELECT 5990, 'LIABILITIES', 'T_CL', 'Total current liabilities', SUM(t_amount), TRUE FROM tmp_sfp WHERE t_section = 'Current liabilities' AND NOT t_sub
    UNION ALL SELECT 5995, 'LIABILITIES', 'T_L', 'Total liabilities', SUM(t_amount), TRUE FROM tmp_sfp WHERE t_section IN ('Non-current liabilities','Current liabilities') AND NOT t_sub
    UNION ALL SELECT 5999, 'LIABILITIES', 'T_EL', 'TOTAL EQUITY AND LIABILITIES', SUM(t_amount), TRUE FROM tmp_sfp WHERE t_section IN ('Equity','Non-current liabilities','Current liabilities') AND NOT t_sub;

    RETURN QUERY SELECT t.t_so, t.t_section, t.t_code, t.t_caption, round(t.t_amount, 2), t.t_sub FROM tmp_sfp t ORDER BY t.t_so;
END $$;

/* Statement of cash flows - direct method (IAS 7 as amended by IFRS 18).
   Every posted journal that touches a cash account is analysed: each non-cash line is
   classified by its account's cash-flow line (or the journal source override), and its
   cash effect is -(debit - credit).  Transfers between bank accounts net to nil.
   Interest paid -> financing; interest & dividends received -> investing. */
CREATE OR REPLACE FUNCTION fn_ifrs_cash_flows(p_from DATE, p_to DATE)
RETURNS TABLE (sort_order INT, category VARCHAR, cf_code VARCHAR, caption VARCHAR, amount NUMERIC, is_subtotal BOOLEAN)
LANGUAGE sql STABLE AS $$
    WITH cash_je AS (
        SELECT DISTINCT je.journal_entry_id, je.source_type
          FROM journal_entries je
          JOIN journal_lines jl    ON jl.journal_entry_id = je.journal_entry_id
          JOIN chart_of_accounts a ON a.account_id = jl.account_id AND a.is_cash
         WHERE je.status IN ('posted','reversed') AND je.entry_date BETWEEN p_from AND p_to
    ),
    flows AS (
        SELECT COALESCE(o.cf_code, a.cash_flow_code, 'CF_OP_SUPPLIERS') AS cf_code, SUM(jl.credit - jl.debit) AS amount
          FROM cash_je c
          JOIN journal_lines jl    ON jl.journal_entry_id = c.journal_entry_id
          JOIN chart_of_accounts a ON a.account_id = jl.account_id AND NOT a.is_cash
          LEFT JOIN cash_flow_source_overrides o ON o.source_type = c.source_type
         GROUP BY 1
    ),
    lines AS (
        SELECT cl.sort_order::INT * 10 AS so, cl.category, cl.cf_code, cl.name, COALESCE(f.amount, 0) AS amount
          FROM cash_flow_lines cl LEFT JOIN flows f ON f.cf_code = cl.cf_code
    ),
    cash_bal AS (
        SELECT COALESCE(SUM(CASE WHEN je.entry_date < p_from THEN jl.debit - jl.credit END), 0) AS opening,
               COALESCE(SUM(jl.debit - jl.credit), 0) AS closing
          FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id)
          JOIN chart_of_accounts a ON a.account_id = jl.account_id AND a.is_cash
         WHERE je.status IN ('posted','reversed') AND je.entry_date <= p_to
    )
    SELECT so, category, cf_code, name, round(amount, 2), FALSE FROM lines
    UNION ALL SELECT 1995, 'operating', 'T_OP', 'Net cash from operating activities', round((SELECT SUM(amount) FROM lines WHERE category = 'operating'), 2), TRUE
    UNION ALL SELECT 2995, 'investing', 'T_INV', 'Net cash used in investing activities', round((SELECT SUM(amount) FROM lines WHERE category = 'investing'), 2), TRUE
    UNION ALL SELECT 3995, 'financing', 'T_FIN', 'Net cash used in financing activities', round((SELECT SUM(amount) FROM lines WHERE category = 'financing'), 2), TRUE
    UNION ALL SELECT 4985, 'total', 'T_NET', 'Net increase / (decrease) in cash and cash equivalents', round((SELECT SUM(amount) FROM lines WHERE category <> 'fx'), 2), TRUE
    UNION ALL SELECT 4992, 'total', 'T_OPEN', 'Cash and cash equivalents at the beginning of the period', round((SELECT opening FROM cash_bal), 2), TRUE
    UNION ALL SELECT 4999, 'total', 'T_CLOSE', 'Cash and cash equivalents at the end of the period', round((SELECT closing FROM cash_bal), 2), TRUE
    ORDER BY 1;
$$;

-- Statement of changes in equity
CREATE OR REPLACE FUNCTION fn_ifrs_changes_in_equity(p_from DATE, p_to DATE)
RETURNS TABLE (sort_order INT, caption TEXT, share_capital NUMERIC, revaluation_reserve NUMERIC,
               translation_reserve NUMERIC, retained_earnings NUMERIC, total_equity NUMERIC)
LANGUAGE sql STABLE AS $$
    WITH mv AS (
        SELECT a.ifrs_line_code AS line, je.source_type AS src, je.entry_date < p_from AS before,
               a.account_type, SUM(jl.credit - jl.debit) AS amt
          FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id)
          JOIN chart_of_accounts a ON a.account_id = jl.account_id
         WHERE je.status IN ('posted','reversed') AND je.entry_date <= p_to
           AND (a.account_type IN ('equity','revenue','expense'))
         GROUP BY 1, 2, 3, 4
    ),
    r AS (
        SELECT
          COALESCE(SUM(amt) FILTER (WHERE before AND line = 'SFP_SC'), 0)     AS o_sc,
          COALESCE(SUM(amt) FILTER (WHERE before AND line = 'SFP_REVAL'), 0)  AS o_rr,
          COALESCE(SUM(amt) FILTER (WHERE before AND line = 'SFP_FXRES'), 0)  AS o_tr,
          COALESCE(SUM(amt) FILTER (WHERE before AND (line = 'SFP_RE' OR account_type IN ('revenue','expense'))), 0) AS o_re,
          COALESCE(SUM(amt) FILTER (WHERE NOT before AND account_type IN ('revenue','expense')), 0) AS profit,
          COALESCE(SUM(amt) FILTER (WHERE NOT before AND line = 'SFP_REVAL' AND src = 'revaluation'), 0) AS oci_rr,
          COALESCE(SUM(amt) FILTER (WHERE NOT before AND line = 'SFP_FXRES'), 0) AS oci_tr,
          COALESCE(SUM(amt) FILTER (WHERE NOT before AND line = 'SFP_RE' AND src = 'dividend'), 0) AS div,
          COALESCE(SUM(amt) FILTER (WHERE NOT before AND line = 'SFP_REVAL' AND src <> 'revaluation'), 0) AS tr_rr,
          COALESCE(SUM(amt) FILTER (WHERE NOT before AND line = 'SFP_RE' AND src <> 'dividend'), 0) AS tr_re,
          COALESCE(SUM(amt) FILTER (WHERE NOT before AND line = 'SFP_SC'), 0) AS sc_mv
          FROM mv
    )
    SELECT 1, 'Balance at ' || to_char(p_from - 1, 'DD Month YYYY'), o_sc, o_rr, o_tr, o_re, o_sc + o_rr + o_tr + o_re FROM r
    UNION ALL SELECT 2, 'Profit for the period', 0, 0, 0, profit, profit FROM r
    UNION ALL SELECT 3, 'Other comprehensive income (net of tax)', 0, oci_rr, oci_tr, 0, oci_rr + oci_tr FROM r
    UNION ALL SELECT 4, 'Total comprehensive income', 0, oci_rr, oci_tr, profit, profit + oci_rr + oci_tr FROM r
    UNION ALL SELECT 5, 'Dividends declared', 0, 0, 0, div, div FROM r
    UNION ALL SELECT 6, 'Shares issued / transfers between reserves', sc_mv, tr_rr, 0, tr_re, sc_mv + tr_rr + tr_re FROM r
    UNION ALL SELECT 7, 'Balance at ' || to_char(p_to, 'DD Month YYYY'), o_sc + sc_mv, o_rr + oci_rr + tr_rr, o_tr + oci_tr,
                     o_re + profit + div + tr_re, o_sc + sc_mv + o_rr + oci_rr + tr_rr + o_tr + oci_tr + o_re + profit + div + tr_re FROM r
    ORDER BY 1;
$$;

/* IFRS 18 note: Management-defined performance measures, reconciled to the closest
   IFRS subtotal with the income-tax effect of each reconciling item. */
CREATE OR REPLACE FUNCTION fn_ifrs_mpm_note(p_from DATE, p_to DATE)
RETURNS TABLE (mpm_code VARCHAR, mpm_name VARCHAR, sort_order INT, caption VARCHAR, amount NUMERIC, tax_effect NUMERIC)
LANGUAGE sql STABLE AS $$
    WITH base AS (SELECT amount FROM fn_ifrs_profit_or_loss(p_from, p_to) WHERE line_code = 'ST_OP'),
    adj AS (
        SELECT m.mpm_code, ma.caption, ma.tax_rate_pct,
               -COALESCE((SELECT SUM(jl.credit - jl.debit) FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id)
                           WHERE jl.account_id = ma.account_id AND je.status IN ('posted','reversed')
                             AND je.entry_date BETWEEN p_from AND p_to), 0) AS amount
          FROM mpm_definitions m JOIN mpm_adjustments ma ON ma.mpm_code = m.mpm_code
         WHERE m.is_active
    ),
    adj_grp AS (SELECT mpm_code, caption, SUM(amount) AS amount, SUM(amount * tax_rate_pct / 100) AS tax FROM adj GROUP BY 1, 2)
    SELECT m.mpm_code, m.name, 1, ('Operating profit (IFRS 18 subtotal)')::VARCHAR, round((SELECT amount FROM base), 2), NULL::NUMERIC
      FROM mpm_definitions m WHERE m.is_active
    UNION ALL
    SELECT g.mpm_code, m.name, 2, ('Add back: ' || g.caption)::VARCHAR, round(g.amount, 2), round(-g.tax, 2)
      FROM adj_grp g JOIN mpm_definitions m USING (mpm_code)
    UNION ALL
    SELECT m.mpm_code, m.name, 9, m.name, round((SELECT amount FROM base) + COALESCE((SELECT SUM(amount) FROM adj_grp g WHERE g.mpm_code = m.mpm_code), 0), 2),
           round(-COALESCE((SELECT SUM(tax) FROM adj_grp g WHERE g.mpm_code = m.mpm_code), 0), 2)
      FROM mpm_definitions m WHERE m.is_active
    ORDER BY 1, 3, 4;
$$;

-- IAS 16 / IAS 38 / IAS 40 movement schedule by asset category
CREATE OR REPLACE FUNCTION fn_ppe_movement(p_from DATE, p_to DATE)
RETURNS TABLE (category VARCHAR, standard VARCHAR, opening_nbv NUMERIC, additions NUMERIC, revaluations NUMERIC,
               disposals NUMERIC, depreciation NUMERIC, closing_nbv NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT c.name, c.standard,
           round(SUM((SELECT carrying_amount FROM fn_asset_nbv(fa.asset_id, p_from - 1))), 2),
           round(SUM(CASE WHEN fa.acquisition_date BETWEEN p_from AND p_to THEN fa.cost ELSE 0 END), 2),
           round(COALESCE(SUM((SELECT SUM(surplus_deficit) FROM asset_revaluations r WHERE r.asset_id = fa.asset_id
                                 AND r.valuation_date BETWEEN p_from AND p_to)), 0), 2),
           round(-COALESCE(SUM((SELECT carrying_amount FROM asset_disposals d WHERE d.asset_id = fa.asset_id
                                 AND d.disposal_date BETWEEN p_from AND p_to)), 0), 2),
           round(-COALESCE(SUM((SELECT SUM(amount) FROM asset_depreciation d WHERE d.asset_id = fa.asset_id
                                 AND d.period_end BETWEEN p_from AND p_to)), 0), 2),
           round(SUM((SELECT carrying_amount FROM fn_asset_nbv(fa.asset_id, p_to))), 2)
      FROM fixed_assets fa JOIN asset_categories c ON c.asset_category_id = fa.asset_category_id
     GROUP BY c.name, c.standard, c.code
     ORDER BY c.code;
$$;

-- Segment information (IFRS 8): revenue and direct costs by service line and by office
CREATE OR REPLACE VIEW v_segment_revenue AS
SELECT date_trunc('month', je.entry_date)::DATE AS month_start,
       COALESCE(sl.name, 'Other / unallocated') AS service_line,
       COALESCE(o.name, 'Head office') AS office,
       COALESCE(o.country_code, 'ZW') AS country_code,
       SUM(jl.credit - jl.debit) AS revenue
  FROM journal_lines jl
  JOIN journal_entries je  ON je.journal_entry_id = jl.journal_entry_id AND je.status IN ('posted','reversed')
  JOIN chart_of_accounts a ON a.account_id = jl.account_id AND a.ifrs_line_code = 'PL_REV'
  LEFT JOIN projects p     ON p.project_id = jl.project_id
  LEFT JOIN service_lines sl ON sl.service_line_id = p.service_line_id
  LEFT JOIN offices o      ON o.office_id = COALESCE(jl.office_id, p.office_id)
 GROUP BY 1, 2, 3, 4;

CREATE OR REPLACE VIEW v_fixed_asset_register AS
SELECT fa.asset_id, fa.asset_tag, fa.name, c.name AS category, c.asset_class, c.standard, c.measurement_model,
       fa.status, o.name AS office, d.name AS department,
       e.first_name || ' ' || e.last_name AS custodian,
       fa.make_model, fa.serial_number, fa.registration_number, fa.acquisition_date, fa.cost,
       n.gross, n.accumulated_depreciation, n.carrying_amount,
       CASE WHEN c.depreciation_method = 'none' THEN 0 ELSE fn_asset_monthly_depreciation(fa.asset_id, CURRENT_DATE) END AS monthly_depreciation,
       fa.insured_value, fa.warranty_expiry, fa.last_revaluation_date
  FROM fixed_assets fa
  JOIN asset_categories c ON c.asset_category_id = fa.asset_category_id
  LEFT JOIN offices o     ON o.office_id = fa.office_id
  LEFT JOIN departments d ON d.department_id = fa.department_id
  LEFT JOIN employees e   ON e.employee_id = fa.custodian_employee_id
  CROSS JOIN LATERAL fn_asset_nbv(fa.asset_id, CURRENT_DATE) n;

CREATE OR REPLACE VIEW v_lease_register AS
SELECT l.lease_id, l.lease_number, l.description, l.role, l.asset_class, o.name AS office, l.currency_code,
       l.commencement_date, l.end_date, l.term_months,
       GREATEST((extract(year FROM age(l.end_date, CURRENT_DATE)) * 12 + extract(month FROM age(l.end_date, CURRENT_DATE)))::INT, 0) AS months_remaining,
       l.payment_amount, l.payment_frequency, l.discount_rate_pct, l.exemption, l.status,
       l.initial_liability, l.initial_rou_asset,
       (SELECT s.closing_liability FROM lease_schedule s WHERE s.lease_id = l.lease_id AND s.is_posted
         ORDER BY s.period_no DESC LIMIT 1) AS liability_lease_ccy,
       l.liability_usd_balance AS liability_usd,
       l.initial_rou_asset - COALESCE((SELECT SUM(s.rou_depreciation) FROM lease_schedule s WHERE s.lease_id = l.lease_id AND s.is_posted), 0) AS rou_carrying_usd,
       v.name AS landlord, l.tenant_name
  FROM leases l
  LEFT JOIN offices o ON o.office_id = l.office_id
  LEFT JOIN vendors v ON v.vendor_id = l.vendor_id;

CREATE OR REPLACE VIEW v_tax_calendar AS
SELECT t.tax_return_id, t.return_number, t.tax_code, tt.name AS tax_name, tt.authority_code, tt.return_form,
       o.name AS office, t.period_start, t.period_end, t.due_date, t.amount_due, t.amount_paid,
       CASE WHEN t.status NOT IN ('paid','cancelled') AND t.due_date < CURRENT_DATE THEN 'overdue'::TEXT ELSE t.status::TEXT END AS status,
       t.due_date - CURRENT_DATE AS days_to_due, t.filed_date, t.paid_date, t.acknowledgement_ref
  FROM tax_returns t
  JOIN tax_types tt ON tt.tax_code = t.tax_code
  LEFT JOIN offices o ON o.office_id = t.office_id;

CREATE OR REPLACE VIEW v_payroll_summary AS
SELECT pr.payroll_run_id, pr.run_number, pr.country_code, pr.period_start, pr.pay_date, pr.currency_code, pr.status,
       pr.employee_count,
       round(SUM(p.gross_pay * pr.exchange_rate), 2)       AS gross_usd,
       round(SUM(p.paye_tax * pr.exchange_rate), 2)        AS income_tax_usd,
       round(SUM(p.aids_levy * pr.exchange_rate), 2)       AS aids_levy_usd,
       round(SUM((p.nssa_employee + p.employer_nssa) * pr.exchange_rate), 2) AS social_security_usd,
       round(SUM(p.employer_wcif * pr.exchange_rate), 2)   AS wcif_other_usd,
       round(SUM(p.employer_zimdef * pr.exchange_rate), 2) AS zimdef_usd,
       round(SUM(p.net_pay * pr.exchange_rate), 2)         AS net_pay_usd,
       round(SUM(p.employer_cost * pr.exchange_rate), 2)   AS employer_cost_usd
  FROM payroll_runs pr JOIN payslips p USING (payroll_run_id)
 GROUP BY pr.payroll_run_id;

CREATE OR REPLACE VIEW v_staff_directory AS
SELECT e.employee_id, e.employee_number, e.first_name || ' ' || e.last_name AS full_name, e.job_title,
       d.name AS department, o.name AS office, o.city, e.email, e.work_phone_ext, e.mobile_phone,
       m.first_name || ' ' || m.last_name AS manager, e.status
  FROM employees e
  LEFT JOIN departments d ON d.department_id = e.department_id
  LEFT JOIN offices o     ON o.office_id = e.office_id
  LEFT JOIN employees m   ON m.employee_id = e.manager_id
 WHERE e.status <> 'terminated';

CREATE OR REPLACE VIEW v_user_access AS
SELECT u.user_id, u.username, u.email, e.first_name || ' ' || e.last_name AS full_name, d.name AS department,
       g.name AS grade, u.is_active, (u.locked_until IS NOT NULL AND u.locked_until > now()) AS is_locked,
       u.must_change_password, u.last_login_at, u.failed_logins,
       (SELECT string_agg(r.code, ', ' ORDER BY r.code) FROM user_roles ur JOIN roles r USING (role_id) WHERE ur.user_id = u.user_id) AS roles
  FROM app_users u
  LEFT JOIN employees e   ON e.employee_id = u.employee_id
  LEFT JOIN departments d ON d.department_id = e.department_id
  LEFT JOIN job_grades g  ON g.job_grade_id = e.job_grade_id;

CREATE OR REPLACE VIEW v_inbox AS
SELECT r.recipient_id, m.message_id, m.thread_id, m.subject, m.body, m.priority, m.sent_at,
       s.first_name || ' ' || s.last_name AS sender, s.email AS sender_email,
       r.recipient_type, r.read_at, r.is_starred, r.is_archived, ml.address AS via_list
  FROM message_recipients r
  JOIN internal_messages m ON m.message_id = r.message_id
  JOIN employees s         ON s.employee_id = m.sender_id
  LEFT JOIN mailing_lists ml ON ml.list_id = m.sent_to_list_id;

-- Announcements visible to each employee (company-wide, their department, their office)
CREATE OR REPLACE VIEW v_employee_announcements AS
SELECT e.employee_id, a.announcement_id, a.title, a.body, a.category, a.audience, a.is_pinned, a.publish_at, a.expires_at,
       au.first_name || ' ' || au.last_name AS author,
       EXISTS (SELECT 1 FROM announcement_reads ar WHERE ar.announcement_id = a.announcement_id AND ar.employee_id = e.employee_id) AS is_read
  FROM employees e
  JOIN announcements a ON a.audience = 'all'
                       OR (a.audience = 'department' AND a.department_id = e.department_id)
                       OR (a.audience = 'office' AND a.office_id = e.office_id)
  JOIN employees au    ON au.employee_id = a.author_id
 WHERE a.publish_at <= now() AND (a.expires_at IS NULL OR a.expires_at > now());
