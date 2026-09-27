
/* =====================================================================================
   35. SEED - 21 MONTHS OF OPERATIONS (January 2025 - 24 September 2026)
   -------------------------------------------------------------------------------------
   Everything is posted through the ERP's own business functions, so the ledger is
   balanced and every figure ties back to a source document:
     billing & receipts, payroll (ZW + 4 branches), statutory returns (ZIMRA/NSSA/ZIMDEF,
     SARS, KRA, HMRC, FTA), supplier bills & payments (WHT, IMTT), capex, depreciation,
     IFRS 16 leases, loan instalments, rental income, interest, QPDs, income-tax accruals,
     IFRS 9 ECL, revaluations (IAS 16/40), dividends, year-end accruals.
   Jan-Oct 2025 revenue comes from the legacy billing system (summary journals); detailed
   invoicing starts in November 2025 and time-based billing in January 2026.
   Months up to 31 August 2026 are closed; September 2026 is the open month.
   ===================================================================================== */

-- 35.1 Expense claim categories -----------------------------------------------------------
INSERT INTO expense_categories (code, name, gl_account_id, is_billable_default, requires_receipt, max_amount_per_item)
SELECT v.code, v.name, fn_account_id(v.gl), v.bill, TRUE, v.max
  FROM (VALUES ('TRAVEL','Air & road travel','5300',TRUE,2500), ('ACCOM','Accommodation','5310',TRUE,400),
               ('MEALS','Meals & subsistence','5320',TRUE,150), ('MILEAGE','Private vehicle mileage','6800',FALSE,600),
               ('TRAIN','Training & exam fees','6300',FALSE,1500), ('CLIENTENT','Client entertainment','6400',FALSE,300),
               ('DATA','Mobile data & airtime','6500',FALSE,100)) AS v(code, name, gl, bill, max);

-- additional suppliers used below
INSERT INTO vendors (vendor_code, name, vendor_type, tax_number, is_resident, tax_clearance_expiry, email, country_code, currency_code, payment_terms_days, default_expense_account_id)
VALUES ('V045','Non-executive directors (board fees)','professional','BOARD',TRUE,'2026-12-31','board@maxhub.co.zw','ZW','USD',7,fn_account_id('6710')),
       ('V046','Chiedza Children''s Home Trust (CSR)','government','CSR',TRUE,NULL,'info@chiedzahome.example','ZW','USD',7,fn_account_id('6950'));

-- 35.2 Seed helper functions (temporary - they disappear after this session) ------------
CREATE FUNCTION pg_temp.emp(p TEXT) RETURNS BIGINT LANGUAGE sql AS $$ SELECT employee_id FROM erp.employees WHERE employee_number = p $$;
CREATE FUNCTION pg_temp.bank(p TEXT) RETURNS BIGINT LANGUAGE sql AS $$
    SELECT b.bank_account_id FROM erp.bank_accounts b JOIN erp.chart_of_accounts a ON a.account_id = b.gl_account_id WHERE a.account_code = p $$;
CREATE FUNCTION pg_temp.bal(p TEXT) RETURNS NUMERIC LANGUAGE sql AS $$ SELECT erp.fn_account_balance(p, '2099-12-31') $$;
CREATE FUNCTION pg_temp.eom(d DATE) RETURNS DATE LANGUAGE sql AS $$ SELECT (date_trunc('month', d) + INTERVAL '1 month - 1 day')::DATE $$;

-- create + approve a supplier bill (amount in the supplier's currency)
CREATE FUNCTION pg_temp.bill(p_vendor TEXT, p_no TEXT, p_date DATE, p_net NUMERIC, p_vat BOOLEAN, p_acc TEXT, p_office TEXT,
                             p_dept TEXT, p_project BIGINT, p_desc TEXT) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v erp.vendors%ROWTYPE; v_id BIGINT;
BEGIN
    SELECT * INTO v FROM erp.vendors WHERE vendor_code = p_vendor;
    INSERT INTO erp.vendor_bills (vendor_id, project_id, bill_number, bill_date, due_date, currency_code, subtotal, tax_amount,
                                  expense_account_id, office_id, department_id, description)
    VALUES (v.vendor_id, p_project, p_no, p_date, p_date + v.payment_terms_days, v.currency_code, round(p_net, 2),
            CASE WHEN p_vat THEN round(p_net * 0.155, 2) ELSE 0 END,
            CASE WHEN p_acc IS NOT NULL THEN erp.fn_account_id(p_acc) END,
            (SELECT office_id FROM erp.offices WHERE code = p_office), (SELECT department_id FROM erp.departments WHERE code = p_dept), p_desc)
    RETURNING vendor_bill_id INTO v_id;
    PERFORM erp.fn_approve_vendor_bill(v_id, pg_temp.emp('E025'));
    RETURN v_id;
END $$;

-- top a bank account up to a target (USD value) from the client-receipts nostro
CREATE FUNCTION pg_temp.top_up(p_code TEXT, p_target NUMERIC, p_date DATE) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_need NUMERIC := round(p_target - pg_temp.bal(p_code), -3); v_src TEXT;
BEGIN
    IF v_need > 0 THEN
        -- fund from client receipts; call the money-market deposit when the nostro is short
        v_src := CASE WHEN pg_temp.bal('1013') >= v_need + 250000 THEN '1013' ELSE '1017' END;
        PERFORM erp.fn_bank_transfer(pg_temp.bank(v_src), pg_temp.bank(p_code), v_need, p_date,
                                     'Funding transfer to ' || (SELECT name FROM erp.bank_accounts WHERE bank_account_id = pg_temp.bank(p_code)));
    END IF;
END $$;

-- issue an invoice and plan when the client will pay it (by payment behaviour)
CREATE TEMP TABLE seed_receipts (invoice_id BIGINT PRIMARY KEY, pay_date DATE, pct NUMERIC);
CREATE FUNCTION pg_temp.issue(p_invoice BIGINT) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE i erp.invoices%ROWTYPE; v_beh TEXT; v_pay DATE; v_pct NUMERIC := 1;
BEGIN
    PERFORM erp.fn_issue_invoice(p_invoice, (SELECT user_id FROM erp.app_users WHERE username = 'chiedza.mushonga'));
    SELECT * INTO i FROM erp.invoices WHERE invoice_id = p_invoice;
    UPDATE erp.invoices SET issued_at = invoice_date + TIME '16:00' WHERE invoice_id = p_invoice;
    SELECT split_part(notes, ': ', 2) INTO v_beh FROM erp.clients WHERE client_id = i.client_id;
    v_pay := CASE v_beh WHEN 'good' THEN i.due_date - 3 + (i.invoice_id % 9)::INT
                        WHEN 'slow' THEN i.due_date + 12 + (i.invoice_id % 30)::INT
                        ELSE i.due_date + 40 + (i.invoice_id % 70)::INT END;
    IF v_beh = 'bad' AND i.invoice_id % 10 < 3 THEN RETURN; END IF;          -- never paid (ECL / collections)
    IF v_beh = 'slow' AND i.invoice_id % 7 = 0 THEN v_pct := 0.5; END IF;     -- part payment
    INSERT INTO seed_receipts VALUES (p_invoice, GREATEST(v_pay, i.invoice_date + 5), v_pct);
END $$;

-- 35.3 Recurring supplier bills -------------------------------------------------------------
-- freq: M = monthly, Q = Jan/Apr/Jul/Oct, B = every 2nd month, A<mm> = annually in month mm
CREATE TEMP TABLE seed_recurring (vendor TEXT, office TEXT, dept TEXT, amount NUMERIC, vat BOOLEAN, acc TEXT, freq TEXT, descr TEXT, project TEXT);
INSERT INTO seed_recurring VALUES
 ('V001','HRE','FAC',6800,TRUE,NULL,'M','Electricity - Maxhub House',NULL),
 ('V001','BYO','FAC',1450,TRUE,NULL,'M','Electricity - Maxhub Centre',NULL),
 ('V002','HRE','FAC',4200,FALSE,NULL,'M','Rates, refuse & water - Maxhub House',NULL),
 ('V003','BYO','FAC',1100,FALSE,NULL,'M','Rates & water - Maxhub Centre',NULL),
 ('V004','HRE','ICT',7600,TRUE,NULL,'M','Fibre internet, MPLS to Bulawayo & branch VPN',NULL),
 ('V005','HRE','ICT',4700,TRUE,NULL,'M','Corporate mobile lines & data bundles',NULL),
 ('V006','HRE','ICT',9800,FALSE,NULL,'M','Microsoft 365 E5 licences (mailboxes @maxhub.co.zw)',NULL),
 ('V007','HRE','DAA',15500,FALSE,NULL,'M','AWS cloud - analytics platform & secure evidence storage',NULL),
 ('V008','HRE','FAI',26000,FALSE,NULL,'A01','Relativity annual support & maintenance',NULL),
 ('V009','HRE','FAC',5600,TRUE,NULL,'M','Guarding & armed response - Maxhub House',NULL),
 ('V010','HRE','FAC',2300,FALSE,NULL,'M','Office cleaning services',NULL),
 ('V011','HRE','FIN',154800,TRUE,'1300','A01','Annual insurance premiums (property, motor, PI, cyber, EEI)',NULL),
 ('V012','HRE','FIN',30000,TRUE,'2500','A02','External audit FY - final fee (accrued at year end)',NULL),
 ('V012','HRE','FIN',16000,TRUE,NULL,'A09','External audit - interim review',NULL),
 ('V013','HRE','LEG',3400,TRUE,NULL,'Q','Legal retainer - contracts & employment matters',NULL),
 ('V014','HRE','MBD',5600,TRUE,NULL,'M','Brand, digital marketing & events',NULL),
 ('V015','HRE','FAI',9200,TRUE,NULL,'M','Air travel & car hire for engagements',NULL),
 ('V016','HRE','FAI',12500,FALSE,NULL,'B','Subcontract forensic accountants - public finance review','P25-005'),
 ('V017','HRE','DAA',18000,FALSE,NULL,'Q','Subcontract data engineers (South Africa)','P25-004'),
 ('V018','HRE','FAC',5300,TRUE,NULL,'M','Fleet fuel',NULL),
 ('V019','HRE','FAC',1900,TRUE,NULL,'M','Vehicle servicing & repairs',NULL),
 ('V020','HRE','FAC',2100,TRUE,NULL,'M','Stationery, printing & office consumables',NULL),
 ('V020','HRE','FAC',180,TRUE,'6100','M','Low-value equipment rental (IFRS 16 exemption)',NULL),
 ('V021','HRE','HRM',14500,FALSE,NULL,'A01','ICAZ / professional body subscriptions',NULL),
 ('V022','HRE','FAI',9800,FALSE,NULL,'A02','ACFE memberships & CFE exam fees',NULL),
 ('V043','HRE','FAC',1560,TRUE,NULL,'A02','Generator 500-hour services',NULL),
 ('V043','HRE','FAC',1560,TRUE,NULL,'A06','Generator 500-hour services',NULL),
 ('V043','HRE','FAC',1560,TRUE,NULL,'A10','Generator 500-hour services',NULL),
 ('V045','HRE','EXE',18000,FALSE,NULL,'Q','Non-executive directors'' fees',NULL),
 ('V046','HRE','EXE',5000,FALSE,NULL,'A11','CSR donation - Chiedza Children''s Home',NULL),
 ('V032','JNB','FAC',68000,FALSE,NULL,'M','Sandton office services, utilities & parking (ZAR)',NULL),
 ('V033','NBO','FAC',520000,FALSE,NULL,'M','Westlands service charge & utilities (KES)',NULL),
 ('V034','LON','FAC',6800,FALSE,NULL,'M','Service charge, business rates & utilities (GBP)',NULL),
 ('V035','DXB','FAC',21000,FALSE,NULL,'M','DIFC service charge & utilities (AED)',NULL);

-- 35.4 The month-by-month run -----------------------------------------------------------
DO $$
DECLARE
    c_cutoff CONSTANT DATE := '2026-09-24';             -- nothing is dated after this
    c_closed CONSTANT DATE := '2026-08-31';             -- last month-end that has been closed
    m DATE; d0 DATE; d1 DATE; prev0 DATE; prev1 DATE; y INT; mo INT;
    r RECORD; v_id BIGINT; v_run BIGINT; v_amt NUMERIC; v_lines JSONB; v_season NUMERIC; v_total NUMERIC; v_je BIGINT;
    v_cfo BIGINT := pg_temp.emp('E006'); v_hr BIGINT := pg_temp.emp('E007'); v_tax BIGINT := pg_temp.emp('E009');
    v_fin_user BIGINT := (SELECT user_id FROM app_users WHERE username = 'chiedza.mushonga');
    v_legacy_prev NUMERIC := 0; v_bill_no INT := 0; v_rep BIGINT; k INT;
BEGIN
    PERFORM set_config('erp.current_user_id', v_fin_user::TEXT, TRUE);

    -- FY2024 year-end items settled in January 2025 (statutory returns)
    INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, credits_amount, status, prepared_by)
    VALUES ('VAT-2024-12','VAT',(SELECT office_id FROM offices WHERE code='HRE'),'2024-12-01','2024-12-31','2025-01-25',196500,41200,'draft',v_tax),
           ('P2-2024-12','PAYE',(SELECT office_id FROM offices WHERE code='HRE'),'2024-12-01','2024-12-31','2025-01-10',91050,0,'draft',v_tax),
           ('P4-2024-12','NSSA',(SELECT office_id FROM offices WHERE code='HRE'),'2024-12-01','2024-12-31','2025-01-10',14800,0,'draft',v_tax),
           ('ZIMDEF-2024-12','ZIMDEF',(SELECT office_id FROM offices WHERE code='HRE'),'2024-12-01','2024-12-31','2025-01-10',3700,0,'draft',v_tax),
           ('ZA_PAYE-2024-12','ZA_PAYE',(SELECT office_id FROM offices WHERE code='JNB'),'2024-12-01','2024-12-31','2025-01-07',20000,0,'draft',v_tax),
           ('KE_PAYE-2024-12','KE_PAYE',(SELECT office_id FROM offices WHERE code='NBO'),'2024-12-01','2024-12-31','2025-01-09',11000,0,'draft',v_tax),
           ('GB_PAYE-2024-12','GB_PAYE',(SELECT office_id FROM offices WHERE code='LON'),'2024-12-01','2024-12-31','2025-01-22',30000,0,'draft',v_tax),
           ('ITF12C-2024','CIT_FINAL',(SELECT office_id FROM offices WHERE code='HRE'),'2024-01-01','2024-12-31','2025-04-30',342000,0,'draft',v_tax);
    INSERT INTO tax_return_lines VALUES ((SELECT tax_return_id FROM tax_returns WHERE return_number = 'P2-2024-12'), 1, 'P2-C', 'AIDS levy (3% of PAYE)', 2650);
    PERFORM fn_create_qpds(2025, 1250000, v_tax);

    FOR m IN SELECT g::DATE FROM generate_series('2025-01-01'::DATE, '2026-09-01'::DATE, INTERVAL '1 month') g LOOP
        d0 := m; d1 := pg_temp.eom(m); prev0 := (m - INTERVAL '1 month')::DATE; prev1 := m - 1;
        y := extract(year FROM m); mo := extract(month FROM m);

        ------------------------------------------------ 1st of the month: treasury
        IF pg_temp.bal('1013') < 800000 THEN     -- keep the receipts nostro liquid
            PERFORM fn_bank_transfer(pg_temp.bank('1017'), pg_temp.bank('1013'), round(1200000 - pg_temp.bal('1013'), -3), d0, 'Call from money market to nostro');
        END IF;
        PERFORM pg_temp.top_up('1010', 1600000, d0);
        PERFORM pg_temp.top_up('1018', 90000, d0);
        PERFORM pg_temp.top_up('1012', 260000, d0);
        PERFORM pg_temp.top_up('1014', 190000, d0);
        PERFORM pg_temp.top_up('1015', 380000, d0);
        PERFORM pg_temp.top_up('1016', 190000, d0);
        PERFORM fn_post_loan_month(d0);
        -- rent from tenants of Maxhub House floors 5-6 (investment property), VAT 15.5%
        SELECT SUM(payment_amount * CASE WHEN y >= 2026 THEN 1.05 ELSE 1 END) INTO v_amt FROM leases WHERE role = 'lessor';
        PERFORM fn_post_journal(d0, 'Rent received - Maxhub House tenants ' || to_char(d0, 'Mon YYYY'), 'rental_income', NULL, jsonb_build_array(
            jsonb_build_object('acc','1013','dr', round(v_amt * 1.155, 2)),
            jsonb_build_object('acc','4500','cr', v_amt, 'office', (SELECT office_id FROM offices WHERE code='HRE'), 'desc','Rental income'),
            jsonb_build_object('acc','2200','cr', round(v_amt * 0.155, 2), 'desc','Output VAT on commercial rent')));
        -- new leases commencing this month (IFRS 16 recognition)
        FOR r IN SELECT lease_id FROM leases WHERE role = 'lessee' AND exemption IS NULL AND status = 'draft' AND commencement_date BETWEEN d0 AND d1 LOOP
            PERFORM fn_recognise_lease(r.lease_id);
        END LOOP;
        -- short-term lease rent (exempt, expensed)
        IF d0 BETWEEN '2026-05-01' AND '2026-09-01' THEN
            PERFORM fn_post_journal(d0, 'Short-term site office rent - Victoria Falls', 'vendor_payment', NULL, jsonb_build_array(
                jsonb_build_object('acc','6100','dr', 1200, 'office', (SELECT office_id FROM offices WHERE code='HRE')),
                jsonb_build_object('acc','6610','dr', 24), jsonb_build_object('acc','1010','cr', 1224)));
        END IF;

        ------------------------------------------------ 5th: supplier bills
        FOR r IN SELECT * FROM seed_recurring
                  WHERE freq = 'M' OR (freq = 'Q' AND mo IN (1,4,7,10)) OR (freq = 'B' AND mo % 2 = 0)
                     OR (freq LIKE 'A%' AND substr(freq, 2)::INT = mo) LOOP
            CONTINUE WHEN d0 + 4 > c_cutoff;
            v_bill_no := v_bill_no + 1;
            PERFORM pg_temp.bill(r.vendor, upper(r.vendor) || '-' || to_char(d0, 'YYMM') || '-' || v_bill_no, d0 + 4,
                                 r.amount * CASE WHEN y >= 2026 THEN 1.06 ELSE 1 END, r.vat, r.acc, r.office, r.dept,
                                 (SELECT project_id FROM projects WHERE project_code = r.project), r.descr || ' - ' || to_char(d0, 'Mon YYYY'));
        END LOOP;

        ------------------------------------------------ capital expenditure (IAS 16 / IAS 38)
        IF m = '2025-03-01' THEN
            v_id := pg_temp.bill('V023', 'AXIS-INV-25-0311', '2025-03-11', 30000, TRUE, '1530', 'HRE', 'ICT', NULL, 'Dell Latitude 7450 laptops x20 (new joiners)');
            INSERT INTO fixed_assets (asset_tag, name, asset_category_id, status, office_id, department_id, custodian_employee_id, vendor_id, vendor_bill_id,
                                      serial_number, make_model, acquisition_date, available_for_use_date, cost, useful_life_months, insured_value, insurance_policy_id)
            SELECT 'MXH-IT-' || lpad(e.employee_id::TEXT, 5, '0'), 'Laptop - Dell Latitude 7450', (SELECT asset_category_id FROM asset_categories WHERE code='IT'),
                   'in_use', e.office_id, e.department_id, e.employee_id, (SELECT vendor_id FROM vendors WHERE vendor_code='V023'), v_id,
                   'DL' || upper(substr(md5('25' || e.employee_id), 1, 7)), 'Dell Latitude 7450', '2025-03-11', '2025-03-14', 1500, 36, 1500,
                   (SELECT policy_id FROM insurance_policies WHERE policy_number = 'HGI-EEI-2026-118')
              FROM employees e
             WHERE NOT EXISTS (SELECT 1 FROM fixed_assets fa WHERE fa.custodian_employee_id = e.employee_id)
               AND e.hire_date <= '2025-03-31' AND e.job_title NOT IN ('Driver','Office Assistant')
             ORDER BY e.employee_id LIMIT 20;
        ELSIF m = '2025-07-01' THEN
            v_id := pg_temp.bill('V023', 'AXIS-INV-25-0707', '2025-07-07', 150000, TRUE, '1800', 'HRE', 'ICT', NULL, 'Maxhub ERP implementation - capitalised development (IAS 38)');
            INSERT INTO fixed_assets (asset_tag, name, asset_category_id, status, office_id, department_id, custodian_employee_id, vendor_id, vendor_bill_id,
                                      make_model, acquisition_date, available_for_use_date, cost, useful_life_months)
            VALUES ('MXH-SW-003', 'Maxhub ERP platform (PostgreSQL + dashboard) - development costs', (SELECT asset_category_id FROM asset_categories WHERE code='SW'),
                    'in_use', (SELECT office_id FROM offices WHERE code='HRE'), (SELECT department_id FROM departments WHERE code='ICT'), pg_temp.emp('E008'),
                    (SELECT vendor_id FROM vendors WHERE vendor_code='V023'), v_id, 'In-house / Axis', '2025-07-07', '2025-08-01', 150000, 60);
        ELSIF m = '2025-09-01' THEN
            v_id := pg_temp.bill('V025', 'DOF-25-0915', '2025-09-15', 22000, TRUE, '1540', 'BYO', 'FAC', NULL, 'Bulawayo office refurbishment - furniture');
            INSERT INTO fixed_assets (asset_tag, name, asset_category_id, status, office_id, department_id, vendor_id, vendor_bill_id, acquisition_date, available_for_use_date, cost)
            VALUES ('MXH-FF-007','Bulawayo office refurbishment - furniture', (SELECT asset_category_id FROM asset_categories WHERE code='FF'), 'in_use',
                    (SELECT office_id FROM offices WHERE code='BYO'), (SELECT department_id FROM departments WHERE code='FAC'), (SELECT vendor_id FROM vendors WHERE vendor_code='V025'),
                    v_id, '2025-09-15', '2025-09-22', 22000);
        ELSIF m = '2026-02-01' THEN
            v_id := pg_temp.bill('V023', 'AXIS-INV-26-0216', '2026-02-16', 40300, TRUE, '1530', 'HRE', 'ICT', NULL, 'Dell laptops x26 - 2025/26 joiners & refresh');
            INSERT INTO fixed_assets (asset_tag, name, asset_category_id, status, office_id, department_id, custodian_employee_id, vendor_id, vendor_bill_id,
                                      serial_number, make_model, acquisition_date, available_for_use_date, cost, useful_life_months, insured_value, insurance_policy_id)
            SELECT 'MXH-IT-' || lpad(e.employee_id::TEXT, 5, '0'), 'Laptop - Dell Latitude 7450 (2026)', (SELECT asset_category_id FROM asset_categories WHERE code='IT'),
                   'in_use', e.office_id, e.department_id, e.employee_id, (SELECT vendor_id FROM vendors WHERE vendor_code='V023'), v_id,
                   'DL' || upper(substr(md5('26' || e.employee_id), 1, 7)), 'Dell Latitude 7450', '2026-02-16', '2026-02-18', 1550, 36, 1550,
                   (SELECT policy_id FROM insurance_policies WHERE policy_number = 'HGI-EEI-2026-118')
              FROM employees e
             WHERE NOT EXISTS (SELECT 1 FROM fixed_assets fa WHERE fa.custodian_employee_id = e.employee_id AND fa.asset_tag LIKE 'MXH-IT-0%')
               AND e.job_title NOT IN ('Driver','Office Assistant')
             ORDER BY e.employee_id LIMIT 26;
        ELSIF m = '2026-03-01' THEN
            v_id := pg_temp.bill('V025', 'DOF-26-0309', '2026-03-09', 18000, TRUE, '1540', 'NBO', 'FAC', NULL, 'Nairobi office expansion - furniture');
            INSERT INTO fixed_assets (asset_tag, name, asset_category_id, status, office_id, department_id, vendor_id, vendor_bill_id, acquisition_date, available_for_use_date, cost)
            VALUES ('MXH-FF-008','Nairobi office expansion - furniture', (SELECT asset_category_id FROM asset_categories WHERE code='FF'), 'in_use',
                    (SELECT office_id FROM offices WHERE code='NBO'), (SELECT department_id FROM departments WHERE code='FAC'), (SELECT vendor_id FROM vendors WHERE vendor_code='V025'),
                    v_id, '2026-03-09', '2026-03-16', 18000);
        ELSIF m = '2026-04-01' THEN
            v_id := pg_temp.bill('V024', 'ZMD-26-0414', '2026-04-14', 116000, TRUE, '1520', 'HRE', 'FAC', NULL, 'Toyota Hilux 2.8GD-6 double cab x2');
            INSERT INTO fixed_assets (asset_tag, name, asset_category_id, status, office_id, department_id, custodian_employee_id, vendor_id, vendor_bill_id,
                                      serial_number, registration_number, make_model, acquisition_date, available_for_use_date, cost, residual_value, insured_value, insurance_policy_id)
            SELECT 'MXH-MV-0' || (12 + g.n), 'Toyota Hilux 2.8GD-6 double cab', (SELECT asset_category_id FROM asset_categories WHERE code='MV'), 'in_use',
                   (SELECT office_id FROM offices WHERE code='HRE'), (SELECT department_id FROM departments WHERE code = CASE g.n WHEN 1 THEN 'CYB' ELSE 'DAA' END),
                   pg_temp.emp(CASE g.n WHEN 1 THEN 'E012' ELSE 'E003' END), (SELECT vendor_id FROM vendors WHERE vendor_code='V024'), v_id,
                   'AHTJB3DD20K30001' || (2 + g.n), 'AGK ' || (4410 + g.n), 'Toyota Hilux 2.8GD-6 D/C', '2026-04-14', '2026-04-20', 58000, 5800, 58000,
                   (SELECT policy_id FROM insurance_policies WHERE policy_number = 'HGI-MOT-2026-115')
              FROM generate_series(1, 2) AS g(n);
        ELSIF m = '2026-05-01' THEN
            v_id := pg_temp.bill('V023', 'AXIS-INV-26-0518', '2026-05-18', 65000, TRUE, '1530', 'HRE', 'CYB', NULL, 'GPU forensic & AI processing server');
            INSERT INTO fixed_assets (asset_tag, name, asset_category_id, status, office_id, department_id, custodian_employee_id, vendor_id, vendor_bill_id,
                                      serial_number, make_model, acquisition_date, available_for_use_date, cost, useful_life_months, insured_value, insurance_policy_id)
            VALUES ('MXH-IT-SRV-003','GPU server - password recovery & AI analytics', (SELECT asset_category_id FROM asset_categories WHERE code='IT'), 'in_use',
                    (SELECT office_id FROM offices WHERE code='HRE'), (SELECT department_id FROM departments WHERE code='CYB'), pg_temp.emp('E012'),
                    (SELECT vendor_id FROM vendors WHERE vendor_code='V023'), v_id, 'SRV-GPU-0003', 'Supermicro 4x NVIDIA L40S', '2026-05-18', '2026-05-25', 65000, 48, 65000,
                    (SELECT policy_id FROM insurance_policies WHERE policy_number = 'HGI-EEI-2026-118'));
        ELSIF m = '2026-06-01' THEN
            v_id := pg_temp.bill('V026', 'MAG-26-0610', '2026-06-10', 40000, FALSE, '1800', 'HRE', 'CYB', NULL, 'Magnet AXIOM & GRAYKEY perpetual licences');
            INSERT INTO fixed_assets (asset_tag, name, asset_category_id, status, office_id, department_id, custodian_employee_id, vendor_id, vendor_bill_id,
                                      make_model, acquisition_date, available_for_use_date, cost, useful_life_months)
            VALUES ('MXH-SW-004','Magnet AXIOM digital forensics licences', (SELECT asset_category_id FROM asset_categories WHERE code='SW'), 'in_use',
                    (SELECT office_id FROM offices WHERE code='HRE'), (SELECT department_id FROM departments WHERE code='CYB'), pg_temp.emp('E012'),
                    (SELECT vendor_id FROM vendors WHERE vendor_code='V026'), v_id, 'Magnet AXIOM', '2026-06-10', '2026-06-10', 40000, 60);
        ELSIF m = '2026-09-01' THEN
            v_id := pg_temp.bill('V044', 'STA-26-0915', '2026-09-15', 48000, TRUE, '1550', 'BYO', 'FAC', NULL, '60kW solar & battery system - Maxhub Centre Bulawayo');
            INSERT INTO fixed_assets (asset_tag, name, asset_category_id, status, office_id, department_id, vendor_id, vendor_bill_id, make_model,
                                      acquisition_date, available_for_use_date, cost, insured_value, insurance_policy_id)
            VALUES ('MXH-OE-007','60kW solar & battery system - Maxhub Centre', (SELECT asset_category_id FROM asset_categories WHERE code='OE'), 'under_construction',
                    (SELECT office_id FROM offices WHERE code='BYO'), (SELECT department_id FROM departments WHERE code='FAC'), (SELECT vendor_id FROM vendors WHERE vendor_code='V044'),
                    v_id, 'Hybrid PV + Li-ion', '2026-09-15', '2026-09-15', 48000, 48000, (SELECT policy_id FROM insurance_policies WHERE policy_number = 'HGI-PROP-2026-114'));
        END IF;

        ------------------------------------------------ opening-balance clean-up (January / February 2025)
        IF m = '2025-01-01' THEN
            PERFORM fn_post_journal('2025-01-15', 'Settlement of legacy trade payables', 'legacy', NULL, jsonb_build_array(
                jsonb_build_object('acc','2100','dr', 418000), jsonb_build_object('acc','6610','dr', 8360), jsonb_build_object('acc','1010','cr', 426360)));
            PERFORM fn_post_journal('2025-01-20', 'Settlement of December 2024 accruals', 'legacy', NULL, jsonb_build_array(
                jsonb_build_object('acc','2500','dr', 152000), jsonb_build_object('acc','6610','dr', 3040), jsonb_build_object('acc','1010','cr', 155040)));
            PERFORM fn_post_journal('2025-01-07', 'December 2024 pension & medical aid remittances', 'payroll_payment', NULL, jsonb_build_array(
                jsonb_build_object('acc','2420','dr', 52000), jsonb_build_object('acc','2425','dr', 21500), jsonb_build_object('acc','1010','cr', 73500)));
        END IF;
        IF m <= '2025-03-01' THEN   -- client advances earned (IFRS 15 contract liabilities -> revenue)
            PERFORM fn_post_journal(d1, 'Contract liabilities recognised as revenue (performance obligations satisfied)', 'legacy', NULL, jsonb_build_array(
                jsonb_build_object('acc','2600','dr', round(158000 / 3.0, 2)),
                jsonb_build_object('acc','4010','cr', round(158000 / 3.0, 2), 'office', (SELECT office_id FROM offices WHERE code='HRE'))));
        END IF;
        IF y = 2025 THEN            -- prepaid insurance & licences at go-live expensed over 2025
            PERFORM fn_post_journal(d1, 'Prepayments released - legacy', 'accrual', NULL, jsonb_build_array(
                jsonb_build_object('acc','6140','dr', round(176000 / 12.0, 2)), jsonb_build_object('acc','1300','cr', round(176000 / 12.0, 2))));
        END IF;
        IF mo = 1 AND y = 2026 THEN NULL; END IF;
        IF y >= 2025 AND d1 <= c_closed THEN   -- insurance premium (paid each January) released monthly
            SELECT COALESCE(SUM(subtotal), 0) / 12 INTO v_amt FROM vendor_bills b JOIN vendors v USING (vendor_id)
             WHERE v.vendor_code = 'V011' AND extract(year FROM b.bill_date) = y;
            IF v_amt > 0 THEN
                PERFORM fn_post_journal(d1, 'Insurance premium released ' || to_char(d1, 'Mon YYYY'), 'accrual', NULL, jsonb_build_array(
                    jsonb_build_object('acc','6140','dr', round(v_amt, 2)), jsonb_build_object('acc','1300','cr', round(v_amt, 2))));
            END IF;
        END IF;

        ------------------------------------------------ 7th-10th: statutory payments for last month
        FOR r IN SELECT t.tax_return_id, t.tax_code, tt.authority_code, o.code AS office
                   FROM tax_returns t JOIN tax_types tt USING (tax_code) LEFT JOIN offices o ON o.office_id = t.office_id
                  WHERE t.status = 'draft' AND t.tax_code IN ('PAYE','NSSA','ZIMDEF','ZA_PAYE','KE_PAYE','GB_PAYE')
                    AND t.period_end < d0 LOOP
            CONTINUE WHEN d0 + 7 > c_cutoff;
            PERFORM fn_file_tax_return(r.tax_return_id, d0 + 5);
            PERFORM fn_pay_tax_return(r.tax_return_id,
                pg_temp.bank(CASE r.office WHEN 'JNB' THEN '1012' WHEN 'NBO' THEN '1014' WHEN 'LON' THEN '1015' ELSE '1010' END), d0 + 7);
        END LOOP;
        IF m >= '2025-02-01' AND d0 + 6 <= c_cutoff THEN
            SELECT COALESCE(SUM(jl.credit), 0) INTO v_amt FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id)
             WHERE je.source_type = 'payroll' AND je.entry_date BETWEEN prev0 AND prev1 AND jl.account_id = fn_account_id('2420');
            SELECT COALESCE(SUM(jl.credit), 0) INTO v_total FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id)
             WHERE je.source_type = 'payroll' AND je.entry_date BETWEEN prev0 AND prev1 AND jl.account_id = fn_account_id('2425');
            PERFORM fn_post_journal(d0 + 6, 'Pension fund & medical aid remittance ' || to_char(prev0, 'Mon YYYY'), 'payroll_payment', NULL, jsonb_build_array(
                jsonb_build_object('acc','2420','dr', v_amt, 'desc','Maxhub Staff Pension Fund / branch schemes'),
                jsonb_build_object('acc','2425','dr', v_total, 'desc','CIMAS / First Mutual Health'),
                jsonb_build_object('acc','1010','cr', v_amt + v_total)));
            -- withholding tax deducted from suppliers last month -> ZIMRA
            v_amt := -fn_account_movement('2430', prev0, prev1, ARRAY['tax_payment']);
            IF v_amt > 0 THEN
                INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, status, prepared_by)
                VALUES ('WHT-' || to_char(prev0, 'YYYY-MM'), 'WHT', (SELECT office_id FROM offices WHERE code='HRE'), prev0, prev1, d0 + 9, v_amt, 'draft', v_tax)
                RETURNING tax_return_id INTO v_id;
                PERFORM fn_file_tax_return(v_id, d0 + 6);
                PERFORM fn_pay_tax_return(v_id, pg_temp.bank('1010'), d0 + 8);
            END IF;
        END IF;

        ------------------------------------------------ 20th-24th: VAT returns for last month
        IF d0 + 19 <= c_cutoff THEN
            IF m > '2025-01-01' THEN v_id := fn_prepare_vat_return(prev0, v_tax);
            ELSE SELECT tax_return_id INTO v_id FROM tax_returns WHERE return_number = 'VAT-2024-12'; END IF;
            PERFORM fn_file_tax_return(v_id, d0 + 19);
            IF m < '2026-09-01' THEN                       -- August VAT7 is filed; payment is scheduled for the 25th
                PERFORM fn_pay_tax_return(v_id, pg_temp.bank('1010'), d0 + 23);
            END IF;
            -- branch VAT
            IF m > '2025-01-01' THEN
                v_id := fn_prepare_branch_vat_return('KE_VAT', prev0, prev1, v_tax);
                IF v_id IS NOT NULL THEN PERFORM fn_file_tax_return(v_id, d0 + 17); PERFORM fn_pay_tax_return(v_id, pg_temp.bank('1014'), d0 + 18); END IF;
                IF mo % 2 = 1 THEN
                    v_id := fn_prepare_branch_vat_return('ZA_VAT', (prev0 - INTERVAL '1 month')::DATE, prev1, v_tax);
                    IF v_id IS NOT NULL THEN PERFORM fn_file_tax_return(v_id, d0 + 20); PERFORM fn_pay_tax_return(v_id, pg_temp.bank('1012'), d0 + 22); END IF;
                END IF;
                IF mo IN (2,5,8,11) THEN
                    v_id := fn_prepare_branch_vat_return('GB_VAT', (prev0 - INTERVAL '2 months')::DATE, prev1, v_tax);
                    IF v_id IS NOT NULL THEN PERFORM fn_file_tax_return(v_id, d0 + 5); PERFORM fn_pay_tax_return(v_id, pg_temp.bank('1015'), d0 + 6); END IF;
                    v_id := fn_prepare_branch_vat_return('AE_VAT', (prev0 - INTERVAL '2 months')::DATE, prev1, v_tax);
                    IF v_id IS NOT NULL THEN PERFORM fn_file_tax_return(v_id, d0 + 20); PERFORM fn_pay_tax_return(v_id, pg_temp.bank('1016'), d0 + 22); END IF;
                END IF;
            END IF;
        END IF;

        ------------------------------------------------ income tax returns & payments (QPDs / final / branches)
        IF m = '2026-01-01' THEN
            PERFORM fn_create_qpds(2026, 1150000, v_tax);                 -- estimate based on FY2025 results
        ELSIF m = '2026-04-01' THEN                                        -- ITF12C: FY2025 balance of tax
            INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, status, prepared_by, notes)
            VALUES ('ITF12C-2025', 'CIT_FINAL', (SELECT office_id FROM offices WHERE code='HRE'), '2025-01-01', '2025-12-31', '2026-04-30',
                    GREATEST(-fn_account_balance('2260','2025-12-31'), 0), 'draft', v_tax, 'FY2025 self-assessment - balance after QPDs');
        ELSIF m = '2026-06-01' THEN                                        -- branch corporate taxes for FY2025
            FOR r IN SELECT o.code, o.office_id, tt.tax_code,
                            -COALESCE((SELECT SUM(jl.debit - jl.credit) FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id)
                                        WHERE jl.account_id = fn_account_id('2265') AND jl.office_id = o.office_id AND je.entry_date <= '2025-12-31'), 0) AS due
                       FROM offices o JOIN (VALUES ('JNB','ZA_CIT','1012'), ('NBO','KE_CIT','1014'), ('LON','GB_CT','1015'), ('DXB','AE_CT','1016')) AS b(code, tc, bank)
                         ON b.code = o.code JOIN tax_types tt ON tt.tax_code = b.tc LOOP
                CONTINUE WHEN r.due <= 0;
                INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, status, prepared_by)
                VALUES (r.tax_code || '-2025', r.tax_code, r.office_id, '2025-01-01', '2025-12-31', '2026-06-30', r.due, 'draft', v_tax)
                RETURNING tax_return_id INTO v_id;
                PERFORM fn_file_tax_return(v_id, '2026-06-24');
                PERFORM fn_pay_tax_return(v_id, pg_temp.bank(CASE r.code WHEN 'JNB' THEN '1012' WHEN 'NBO' THEN '1014' WHEN 'LON' THEN '1015' ELSE '1016' END), '2026-06-26');
            END LOOP;
        END IF;
        FOR r IN SELECT tax_return_id, due_date FROM tax_returns
                  WHERE tax_code IN ('CIT_QPD','CIT_FINAL') AND status = 'draft' AND due_date BETWEEN d0 AND d1 AND due_date - 2 <= c_cutoff LOOP
            PERFORM fn_file_tax_return(r.tax_return_id, r.due_date - 3);
            PERFORM fn_pay_tax_return(r.tax_return_id, pg_temp.bank('1010'), r.due_date - 2);
        END LOOP;

        ------------------------------------------------ expense claims (2026: billable to T&M engagements)
        IF y = 2026 THEN
            FOR r IN SELECT DISTINCT ON (pm.employee_id) pm.employee_id, pm.project_id, e.manager_id
                       FROM project_members pm JOIN projects p ON p.project_id = pm.project_id AND p.billing_type = 'time_and_materials' AND NOT p.is_internal
                       JOIN employees e ON e.employee_id = pm.employee_id
                      WHERE d0 + 10 BETWEEN pm.start_date AND COALESCE(pm.end_date, 'infinity') AND e.manager_id IS NOT NULL
                        AND (pm.employee_id + mo) % 9 = 0
                      ORDER BY pm.employee_id, p.project_id LIMIT 14 LOOP
                CONTINUE WHEN d0 + 12 > c_cutoff;
                INSERT INTO expense_reports (employee_id, title, currency_code) VALUES (r.employee_id,
                    'Field work ' || to_char(d0, 'Mon YYYY') || ' - ' || (SELECT project_code FROM projects WHERE project_id = r.project_id), 'USD')
                RETURNING expense_report_id INTO v_rep;
                INSERT INTO expense_items (expense_report_id, expense_date, expense_category_id, project_id, description, merchant, amount, is_billable)
                SELECT v_rep, d0 + x.dd, (SELECT expense_category_id FROM expense_categories WHERE code = x.cat), r.project_id, x.descr, x.merchant,
                       x.amt + (r.employee_id % 7) * 11, TRUE
                  FROM (VALUES (6,'TRAVEL','Return trip to client site','Fastjet / Zambezi Travel',420),
                               (7,'ACCOM','Hotel - 2 nights','Rainbow Hotels',260), (7,'MEALS','Meals while on site','Various',55)) AS x(dd, cat, descr, merchant, amt);
                CALL sp_submit_expense_report(v_rep);
                IF d0 + 14 <= c_cutoff AND NOT (m = '2026-09-01' AND r.employee_id % 2 = 0) THEN
                    CALL sp_approve_expense_report(v_rep, r.manager_id, d0 + 14);
                    IF d0 + 24 <= c_cutoff THEN
                        SELECT total_amount INTO v_amt FROM expense_reports WHERE expense_report_id = v_rep;
                        PERFORM fn_post_journal(d0 + 24, 'Reimbursement ' || (SELECT report_number FROM expense_reports WHERE expense_report_id = v_rep),
                            'expense', v_rep, jsonb_build_array(jsonb_build_object('acc','2300','dr', v_amt, 'employee', r.employee_id),
                                                               jsonb_build_object('acc','1010','cr', v_amt)));
                        UPDATE expense_reports SET reimbursed_at = (d0 + 24) + TIME '11:00' WHERE expense_report_id = v_rep;
                    END IF;
                END IF;
            END LOOP;
        END IF;

        ------------------------------------------------ supplier payments falling due this month
        FOR r IN SELECT b.vendor_bill_id, b.total_amount - b.amount_paid AS bal, b.due_date, b.currency_code, b.bill_number, o.code AS office
                   FROM vendor_bills b LEFT JOIN offices o ON o.office_id = b.office_id
                  WHERE b.status IN ('approved','partially_paid') AND b.due_date <= LEAST(d1, c_cutoff)
                  ORDER BY b.due_date LOOP
            PERFORM fn_pay_vendor_bill(r.vendor_bill_id, r.bal,
                pg_temp.bank(CASE r.currency_code WHEN 'ZAR' THEN '1012' WHEN 'KES' THEN '1014' WHEN 'GBP' THEN '1015' WHEN 'AED' THEN '1016'
                                                  ELSE CASE WHEN r.office = 'BYO' THEN '1018' ELSE '1010' END END),
                GREATEST(r.due_date, d0), 'EFT ' || r.bill_number);
        END LOOP;

        ------------------------------------------------ client receipts
        IF m <= '2026-01-01' THEN                 -- legacy ledger collections
            v_amt := v_legacy_prev + CASE WHEN m = '2025-01-01' THEN 2180000 * 0.6 WHEN m = '2025-02-01' THEN 2180000 * 0.4 ELSE 0 END;
            IF v_amt > 0 THEN
                PERFORM fn_post_journal(d0 + 17, 'Client receipts - legacy ledger ' || to_char(d0, 'Mon YYYY'), 'legacy', NULL, jsonb_build_array(
                    jsonb_build_object('acc','1013','dr', v_amt), jsonb_build_object('acc','1100','cr', v_amt, 'desc','Receipts against legacy invoices')));
            END IF;
        END IF;
        FOR r IN SELECT s.invoice_id, s.pay_date, s.pct, i.client_id, i.balance_due, i.total_amount, i.invoice_number
                   FROM seed_receipts s JOIN invoices i USING (invoice_id)
                  WHERE s.pay_date BETWEEN d0 AND LEAST(d1, c_cutoff) AND i.balance_due > 0 ORDER BY s.pay_date LOOP
            v_amt := LEAST(r.balance_due, round(r.total_amount * r.pct, 2));
            v_id := fn_record_client_payment(r.client_id, v_amt, pg_temp.bank('1013'), r.pay_date, 'bank_transfer', 'EFT ' || r.invoice_number, FALSE);
            INSERT INTO payment_allocations (payment_id, invoice_id, amount) VALUES (v_id, r.invoice_id, v_amt);
            IF r.pct < 1 THEN UPDATE seed_receipts SET pay_date = pay_date + 35, pct = 1 WHERE invoice_id = r.invoice_id; END IF;
        END LOOP;

        ------------------------------------------------ 25th: payroll
        FOR r IN SELECT DISTINCT o.country_code FROM employees e JOIN offices o USING (office_id) ORDER BY 1 LOOP
            v_run := fn_run_payroll(r.country_code, d0, d0 + 24);
            IF d1 <= c_closed THEN
                PERFORM fn_approve_payroll(v_run, CASE WHEN r.country_code = 'ZW' THEN v_cfo ELSE v_hr END);
                UPDATE payroll_runs SET approved_at = (d0 + 21) + TIME '15:00' WHERE payroll_run_id = v_run;
                PERFORM fn_pay_payroll(v_run, pg_temp.bank(CASE r.country_code WHEN 'ZA' THEN '1012' WHEN 'KE' THEN '1014' WHEN 'GB' THEN '1015'
                                                                                WHEN 'AE' THEN '1016' ELSE '1010' END));
            END IF;
        END LOOP;
        IF d1 <= c_closed THEN PERFORM fn_prepare_payroll_returns(d0, v_tax); END IF;

        ------------------------------------------------ month end (closed months only)
        CONTINUE WHEN d1 > c_closed;

        -- revenue & invoicing
        IF m <= '2025-12-01' THEN
            -- legacy billing system; in Nov/Dec 2025 engagements not yet migrated still bill through it (~60%)
            v_season := (ARRAY[0.86, 0.95, 1.05, 0.93, 1.06, 1.10, 1.00, 1.04, 1.09, 1.07, 1.02, 0.85])[mo];
            v_total := round(1360000 * v_season * CASE WHEN m >= '2025-11-01' THEN 0.6 ELSE 1 END, 2);
            v_lines := jsonb_build_array(jsonb_build_object('acc','1100','dr', 0));   -- placeholder, replaced below
            v_lines := '[]'::JSONB; v_amt := 0;
            FOR r IN SELECT o.office_id, o.code, s.share, t.gl, t.rate
                       FROM (VALUES ('HRE',0.70), ('BYO',0.07), ('JNB',0.09), ('NBO',0.06), ('LON',0.05), ('DXB',0.03)) AS s(code, share)
                       JOIN offices o ON o.code = s.code
                       JOIN (VALUES ('HRE','2200',0.124), ('BYO','2200',0.155), ('JNB','2201',0.15), ('NBO','2202',0.16),
                                    ('LON','2203',0.20), ('DXB','2204',0.05)) AS t(code, gl, rate) ON t.code = s.code LOOP
                v_lines := v_lines
                  || jsonb_build_object('acc','4000','cr', round(v_total * r.share * 0.68, 2), 'office', r.office_id, 'desc','Fees - legacy billing')
                  || jsonb_build_object('acc','4010','cr', round(v_total * r.share * 0.22, 2), 'office', r.office_id, 'desc','Fixed fees - legacy billing')
                  || jsonb_build_object('acc','4020','cr', round(v_total * r.share * 0.10, 2), 'office', r.office_id, 'desc','Retainers - legacy billing')
                  || jsonb_build_object('acc', r.gl, 'cr', round(v_total * r.share * r.rate, 2), 'desc','Output VAT');
                v_amt := v_amt + round(v_total * r.share * 0.68, 2) + round(v_total * r.share * 0.22, 2) + round(v_total * r.share * 0.10, 2)
                               + round(v_total * r.share * r.rate, 2);
            END LOOP;
            v_lines := jsonb_build_array(jsonb_build_object('acc','1100','dr', v_amt, 'desc','Legacy billing - trade receivables')) || v_lines;
            PERFORM fn_post_journal(d1, 'Billing summary from legacy system - ' || to_char(d1, 'Mon YYYY'), 'legacy', NULL, v_lines);
            v_legacy_prev := v_amt;
        END IF;
        IF m >= '2025-11-01' THEN
            -- time & materials: invoice approved time + billable expenses
            IF y = 2026 THEN
                FOR r IN SELECT DISTINCT p.project_id, sp.tax FROM projects p JOIN seed_projects sp ON sp.code = p.project_code
                           JOIN time_entries te ON te.project_id = p.project_id AND te.is_billable AND te.invoice_line_id IS NULL AND te.work_date <= d1
                          WHERE p.billing_type = 'time_and_materials' LOOP
                    v_id := fn_generate_invoice_from_time(r.project_id, d0 - 40, d1, d1, r.tax, TRUE, v_fin_user);
                    PERFORM pg_temp.issue(v_id);
                END LOOP;
            ELSE   -- Nov/Dec 2025: first invoices from the new system, based on agreed monthly fee estimates
                FOR r IN SELECT p.project_id, p.client_id, p.contract_id, p.budget_fees, p.start_date, p.planned_end_date, c.payment_terms_days, sp.tax
                           FROM projects p JOIN seed_projects sp ON sp.code = p.project_code JOIN clients c ON c.client_id = p.client_id
                          WHERE p.billing_type = 'time_and_materials' AND p.start_date <= d1 - 10 LOOP
                    INSERT INTO invoices (client_id, project_id, contract_id, invoice_date, due_date, currency_code, notes, created_by)
                    VALUES (r.client_id, r.project_id, r.contract_id, d1, d1 + r.payment_terms_days, 'USD',
                            'Professional services ' || to_char(d1, 'FMMonth YYYY'), v_fin_user) RETURNING invoice_id INTO v_id;
                    v_amt := round(r.budget_fees / GREATEST((r.planned_end_date - r.start_date) / 30.0, 1) * 0.9, -1);
                    INSERT INTO invoice_lines (invoice_id, line_no, line_type, description, quantity, unit, unit_price, tax_rate_id, project_id)
                    VALUES (v_id, 1, 'time', 'Professional services - ' || to_char(d1, 'FMMonth YYYY') || ' (per engagement letter)',
                            round(v_amt / 150), 'hour', 150, (SELECT tax_rate_id FROM tax_rates WHERE code = r.tax), r.project_id);
                    PERFORM pg_temp.issue(v_id);
                END LOOP;
            END IF;
            -- retainers
            FOR r IN SELECT p.project_id, p.client_id, p.contract_id, ct.retainer_fee_per_month, ct.payment_terms_days, sp.tax
                       FROM projects p JOIN contracts ct ON ct.contract_id = p.contract_id JOIN seed_projects sp ON sp.code = p.project_code
                      WHERE p.billing_type = 'retainer' AND p.start_date <= d1 AND p.planned_end_date >= d0 LOOP
                INSERT INTO invoices (client_id, project_id, contract_id, invoice_date, due_date, currency_code, notes, created_by)
                VALUES (r.client_id, r.project_id, r.contract_id, d1, d1 + r.payment_terms_days, 'USD', 'Monthly retainer ' || to_char(d1, 'FMMonth YYYY'), v_fin_user)
                RETURNING invoice_id INTO v_id;
                INSERT INTO invoice_lines (invoice_id, line_no, line_type, description, quantity, unit, unit_price, tax_rate_id, project_id)
                VALUES (v_id, 1, 'retainer', 'Monthly retainer - ' || to_char(d1, 'FMMonth YYYY'), 1, 'month', r.retainer_fee_per_month,
                        (SELECT tax_rate_id FROM tax_rates WHERE code = r.tax), r.project_id);
                PERFORM pg_temp.issue(v_id);
            END LOOP;
            -- milestones reached this month
            FOR r IN SELECT ms.milestone_id, sp.tax FROM contract_milestones ms JOIN contracts ct USING (contract_id)
                       JOIN projects p ON p.contract_id = ct.contract_id JOIN seed_projects sp ON sp.code = p.project_code
                      WHERE ms.status = 'pending' AND ms.due_date <= d1 LOOP
                UPDATE contract_milestones SET status = 'achieved', achieved_date = LEAST(due_date, d1) WHERE milestone_id = r.milestone_id;
                v_id := fn_invoice_milestone(r.milestone_id, d1, r.tax, v_fin_user);
                PERFORM pg_temp.issue(v_id);
            END LOOP;
        END IF;

        -- depreciation, leases, interest, bank charges
        PERFORM fn_run_depreciation(d1, v_fin_user);
        PERFORM fn_post_lease_month(d0, v_fin_user);
        v_amt := round(pg_temp.bal('1017') * 0.07 / 12, 2);
        PERFORM fn_post_journal(d1, 'Interest on money market call account (7% p.a.)', 'interest', NULL, jsonb_build_array(
            jsonb_build_object('acc','1017','dr', v_amt), jsonb_build_object('acc','4600','cr', v_amt)));
        PERFORM fn_post_journal(d1, 'Bank charges ' || to_char(d1, 'Mon YYYY'), 'manual', NULL, jsonb_build_array(
            jsonb_build_object('acc','6600','dr', 1385),
            jsonb_build_object('acc','1010','cr', 620), jsonb_build_object('acc','1013','cr', 410), jsonb_build_object('acc','1018','cr', 55),
            jsonb_build_object('acc','1012','cr', 90), jsonb_build_object('acc','1014','cr', 70), jsonb_build_object('acc','1015','cr', 85),
            jsonb_build_object('acc','1016','cr', 55)));
        -- quarter-end sweep of surplus cash into the money market
        IF pg_temp.bal('1013') > 2500000 THEN
            PERFORM fn_bank_transfer(pg_temp.bank('1013'), pg_temp.bank('1017'), round(pg_temp.bal('1013') - 1500000, -4), d1, 'Sweep surplus cash to money market');
        END IF;

        -- income taxes (IAS 12): Zimbabwe provision every month; branch taxes each quarter
        PERFORM fn_accrue_income_tax(d1, v_fin_user);
        IF mo IN (3,6,9,12) THEN
            FOR r IN SELECT o.office_id, o.code, s.rate FROM offices o
                       JOIN (VALUES ('JNB',27.0), ('NBO',30.0), ('LON',25.0), ('DXB',9.0)) AS s(code, rate) ON s.code = o.code LOOP
                SELECT COALESCE(SUM(jl.credit - jl.debit), 0) INTO v_amt FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id)
                  JOIN chart_of_accounts a ON a.account_id = jl.account_id
                 WHERE a.ifrs_line_code = 'PL_REV' AND jl.office_id = r.office_id AND je.entry_date BETWEEN (d0 - INTERVAL '2 months')::DATE AND d1;
                v_amt := round(v_amt * 0.22 * r.rate / 100, 2);     -- branch profit ~22% of branch revenue
                IF v_amt > 0 THEN
                    PERFORM fn_post_journal(d1, 'Branch income tax provision - ' || r.code, 'tax', NULL, jsonb_build_array(
                        jsonb_build_object('acc','9010','dr', v_amt, 'office', r.office_id), jsonb_build_object('acc','2265','cr', v_amt, 'office', r.office_id)));
                END IF;
            END LOOP;
            PERFORM fn_update_ecl_provision(d1, v_fin_user);
        END IF;

        -- year end 2025
        IF m = '2025-12-01' THEN
            PERFORM fn_revalue_asset(fa.asset_id, '2025-12-31', v.fv, 'Knight Frank Zimbabwe (independent valuers)', 3::SMALLINT, v_fin_user)
               FROM fixed_assets fa JOIN (VALUES ('MXH-LND-001',1240000), ('MXH-BLD-001',3650000), ('MXH-LND-002',275000),
                                                 ('MXH-BLD-002',820000), ('MXH-LND-003',560000), ('MXH-IP-001',1560000)) AS v(tag, fv) ON v.tag = fa.asset_tag;
            PERFORM fn_post_journal('2025-12-31', 'Leave pay accrual adjustment (IAS 19)', 'accrual', NULL, jsonb_build_array(
                jsonb_build_object('acc','5160','dr', 21000), jsonb_build_object('acc','2510','cr', 21000)));
            PERFORM fn_post_journal('2025-12-31', 'Staff bonus accrual FY2025 (paid March 2026)', 'accrual', NULL, jsonb_build_array(
                jsonb_build_object('acc','5150','dr', 380000), jsonb_build_object('acc','2520','cr', 380000)));
            PERFORM fn_post_journal('2025-12-31', 'External audit fee accrual FY2025', 'accrual', NULL, jsonb_build_array(
                jsonb_build_object('acc','6700','dr', 30000), jsonb_build_object('acc','2500','cr', 30000)));
            PERFORM fn_accrue_income_tax('2025-12-31', v_fin_user);
            -- deferred tax to the IAS 12 schedule (movement not already booked through OCI / P&L)
            SELECT SUM(deferred_tax) INTO v_amt FROM fn_deferred_tax_schedule('2025-12-31');
            v_amt := round(v_amt - (-(pg_temp.bal('2900')) + pg_temp.bal('1900')), 2);
            IF v_amt <> 0 THEN
                PERFORM fn_post_journal('2025-12-31', 'Deferred tax movement FY2025 (IAS 12)', 'tax', NULL, jsonb_build_array(
                    jsonb_build_object('acc','9020','dr', v_amt), jsonb_build_object('acc','2900','cr', v_amt)));
            END IF;
        END IF;

        -- interim / final dividends
        IF m = '2025-09-01' THEN
            PERFORM fn_post_journal('2025-09-30', 'Interim dividend FY2025 declared (USD 1.00 per share)', 'dividend', NULL, jsonb_build_array(
                jsonb_build_object('acc','3200','dr', 1000000), jsonb_build_object('acc','2950','cr', 1000000)));
        END IF;
        IF m = '2026-04-01' THEN
            PERFORM fn_post_journal('2026-04-15', 'Final dividend FY2025 declared at AGM (USD 1.50 per share)', 'dividend', NULL, jsonb_build_array(
                jsonb_build_object('acc','3200','dr', 1500000), jsonb_build_object('acc','2950','cr', 1500000)));
        END IF;
    END LOOP;

    -- dividends paid (net to shareholders + 10% resident shareholders' tax to ZIMRA)
    PERFORM fn_post_journal('2025-10-15', 'Interim dividend paid - net to shareholders and 10% shareholders tax to ZIMRA', 'dividend', NULL, jsonb_build_array(
        jsonb_build_object('acc','2950','dr', 1000000), jsonb_build_object('acc','1017','cr', 1000000)));
    PERFORM fn_post_journal('2026-05-08', 'Final dividend paid - net to shareholders and 10% shareholders tax to ZIMRA', 'dividend', NULL, jsonb_build_array(
        jsonb_build_object('acc','2950','dr', 1500000), jsonb_build_object('acc','1017','cr', 1500000)));
    -- FY2025 bonuses paid with March 2026 salaries
    PERFORM fn_post_journal('2026-03-25', 'FY2025 performance bonuses paid', 'payroll_payment', NULL, jsonb_build_array(
        jsonb_build_object('acc','2520','dr', 380000), jsonb_build_object('acc','1010','cr', 380000)));
    -- asset disposal
    PERFORM fn_dispose_asset((SELECT asset_id FROM fixed_assets WHERE asset_tag = 'MXH-MV-008'), '2026-07-15', 9000, pg_temp.bank('1010'),
                             'Public auction - Harare Auctioneers', 'sale', v_cfo, v_fin_user);
END $$;
