
/* =====================================================================================
   30. SEED - REFERENCE DATA, IFRS STRUCTURE, CHART OF ACCOUNTS, TAX TABLES, ACCESS
   -------------------------------------------------------------------------------------
   Demo data for Maxhub Pvt Ltd. People, clients and suppliers are fictional.
   Tax rates reflect published 2025/2026 Zimbabwe rates at the time of writing - VERIFY
   against current ZIMRA / NSSA public notices before relying on them.
   To install WITHOUT demo data run maxhub_erp_schema.sql instead (python database/build.py --schema).
   ===================================================================================== */

SET erp.skip_audit = 'on';      -- no audit rows for the bulk load (session only)

-- 30.1 Currencies, countries, FX ---------------------------------------------------------
INSERT INTO currencies (currency_code, name, symbol) VALUES
 ('USD','US Dollar','$'), ('ZWG','Zimbabwe Gold','ZiG'), ('ZAR','South African Rand','R'),
 ('KES','Kenyan Shilling','KSh'), ('GBP','Pound Sterling','£'), ('AED','UAE Dirham','AED'),
 ('EUR','Euro','€'), ('BWP','Botswana Pula','P'), ('ZMW','Zambian Kwacha','K');

INSERT INTO countries (country_code, name, default_currency) VALUES
 ('ZW','Zimbabwe','USD'), ('ZA','South Africa','ZAR'), ('KE','Kenya','KES'), ('GB','United Kingdom','GBP'),
 ('AE','United Arab Emirates','AED'), ('BW','Botswana','BWP'), ('ZM','Zambia','ZMW'), ('US','United States','USD'),
 ('MZ','Mozambique','USD');

-- Month-end rates (USD per 1 unit), Dec 2024 - Sep 2026. Gentle realistic drift.
INSERT INTO exchange_rates (from_currency, to_currency, rate_date, rate, source)
SELECT c.code, 'USD', (d + INTERVAL '1 month - 1 day')::DATE,
       round(c.base * (1 + c.drift * m.n + 0.012 * sin(m.n)::NUMERIC), 8), 'RBZ / central bank mid-rate (demo)'
  FROM (VALUES ('ZAR', 0.05450, -0.0010), ('KES', 0.00774, 0.0003), ('GBP', 1.27000, 0.0020),
               ('AED', 0.27229, 0.0000), ('EUR', 1.05000, 0.0030), ('ZWG', 0.03730, -0.0015),
               ('BWP', 0.07300, -0.0005), ('ZMW', 0.03600, -0.0008)) AS c(code, base, drift)
 CROSS JOIN LATERAL (SELECT g::DATE AS d, (row_number() OVER ()) - 1 AS n
                       FROM generate_series('2024-12-01'::DATE, '2026-09-01'::DATE, INTERVAL '1 month') g) m;
UPDATE exchange_rates SET rate = 0.27229 WHERE from_currency = 'AED';    -- dirham is pegged

INSERT INTO tax_rates (code, name, rate_percent, country_code, valid_from, tax_kind, gl_account_code) VALUES
 ('ZW-VAT', 'Zimbabwe VAT (standard, ZIMRA)', 15.500, 'ZW', '2023-01-01', 'vat', '2200'),
 ('ZA-VAT', 'South Africa VAT (SARS)',        15.000, 'ZA', '2018-04-01', 'vat', '2201'),
 ('KE-VAT', 'Kenya VAT (KRA)',                16.000, 'KE', '2013-09-02', 'vat', '2202'),
 ('GB-VAT', 'UK VAT (HMRC)',                  20.000, 'GB', '2011-01-04', 'vat', '2203'),
 ('AE-VAT', 'UAE VAT (FTA)',                   5.000, 'AE', '2018-01-01', 'vat', '2204'),
 ('ZERO',   'Zero-rated - exported services',  0.000, NULL, '2000-01-01', 'vat', '2200'),
 ('EXEMPT', 'Exempt',                          0.000, NULL, '2000-01-01', 'vat', '2200');

-- 30.2 Fiscal years (FY2024 holds only the opening balances) ------------------------------
INSERT INTO fiscal_years (name, start_date, end_date)
VALUES ('FY2024','2024-01-01','2024-12-31'), ('FY2025','2025-01-01','2025-12-31'), ('FY2026','2026-01-01','2026-12-31');
INSERT INTO fiscal_periods (fiscal_year_id, period_no, start_date, end_date)
SELECT fy.fiscal_year_id, m, make_date(extract(year FROM fy.start_date)::INT, m, 1),
       (make_date(extract(year FROM fy.start_date)::INT, m, 1) + INTERVAL '1 month - 1 day')::DATE
  FROM fiscal_years fy, generate_series(1, 12) AS m;

INSERT INTO firm_settings (legal_name, trading_name, registration_number, tax_number, vat_number, base_currency,
                           country_code, address, phone, email, website, default_payment_terms_days, default_tax_code,
                           zimra_tin, zimra_bp_number, nssa_employer_number, zimdef_number, praz_number, fiscal_device_serial,
                           date_of_incorporation, functional_currency, presentation_currency, ifrs18_adopted_from,
                           expense_presentation, auditor_name, company_secretary, email_domain)
VALUES ('Maxhub Pvt Ltd', 'Maxhub Forensic Data Analytics', '4521/2012', '2000451236', '220451236', 'USD', 'ZW',
        'Maxhub House, 45 Enterprise Road, Highlands, Harare, Zimbabwe', '+263 242 700 100', 'info@maxhub.co.zw',
        'www.maxhub.co.zw', 30, 'ZW-VAT', '2000451236', '0200451236', 'NSSA-EMP-0045123', 'ZDF-11873', 'PRAZ-SP-20931',
        'VD-MXH-0001', '2012-05-14', 'USD', 'USD', '2026-01-01', 'nature', 'Chartered Assurance Partners (Chartered Accountants Zimbabwe)',
        'Ruvimbo Zvobgo', 'maxhub.co.zw');

INSERT INTO document_sequences (doc_type, prefix, padding) VALUES
 ('invoice','INV-',5), ('payment','RCT-',5), ('journal','JE-',6),
 ('expense_report','EXP-',5), ('purchase_order','PO-',5), ('credit_note','CN-',5);

INSERT INTO activity_codes (activity_code, name, is_chargeable, counts_as_capacity_reduction) VALUES
 ('CLIENT','Client engagement work',TRUE,FALSE), ('BD','Business development & proposals',FALSE,FALSE),
 ('ADMIN','Firm administration',FALSE,FALSE), ('TRAINING','Training & CPD',FALSE,FALSE),
 ('KM','Knowledge management & methodology',FALSE,FALSE), ('LEAVE','Leave',FALSE,TRUE), ('HOLIDAY','Public holiday',FALSE,TRUE);

INSERT INTO public_holidays (country_code, holiday_date, name) VALUES
 ('ZW','2025-01-01','New Year''s Day'), ('ZW','2025-02-21','National Youth Day'), ('ZW','2025-04-18','Good Friday / Independence Day'),
 ('ZW','2025-04-21','Easter Monday'), ('ZW','2025-05-01','Workers'' Day'), ('ZW','2025-05-26','Africa Day (observed)'),
 ('ZW','2025-08-11','Heroes'' Day'), ('ZW','2025-08-12','Defence Forces Day'), ('ZW','2025-12-22','Unity Day'),
 ('ZW','2025-12-25','Christmas Day'), ('ZW','2025-12-26','Boxing Day'),
 ('ZW','2026-01-01','New Year''s Day'), ('ZW','2026-02-21','National Youth Day'), ('ZW','2026-04-03','Good Friday'),
 ('ZW','2026-04-06','Easter Monday'), ('ZW','2026-04-18','Independence Day'), ('ZW','2026-05-01','Workers'' Day'),
 ('ZW','2026-05-25','Africa Day'), ('ZW','2026-08-10','Heroes'' Day'), ('ZW','2026-08-11','Defence Forces Day'),
 ('ZW','2026-12-22','Unity Day'), ('ZW','2026-12-25','Christmas Day'), ('ZW','2026-12-26','Boxing Day'),
 ('ZA','2026-03-21','Human Rights Day'), ('ZA','2026-04-27','Freedom Day'), ('ZA','2026-06-16','Youth Day'),
 ('ZA','2026-08-10','National Women''s Day (observed)'), ('ZA','2026-09-24','Heritage Day'),
 ('KE','2026-06-01','Madaraka Day'), ('KE','2026-10-20','Mashujaa Day'),
 ('GB','2026-05-04','Early May bank holiday'), ('GB','2026-05-25','Spring bank holiday'), ('GB','2026-08-31','Summer bank holiday'),
 ('AE','2026-03-20','Eid al-Fitr'), ('AE','2026-05-27','Eid al-Adha'), ('AE','2026-12-02','National Day');

-- 30.3 IFRS structure ---------------------------------------------------------------------
INSERT INTO ifrs_line_items (line_code, statement, section, name, ifrs18_category, sort_order, sign, standard_ref, nature_disclosure) VALUES
 -- Statement of profit or loss (by nature), IFRS 18 categories
 ('PL_REV',      'PL', 'Operating', 'Revenue from contracts with customers', 'operating', 10, 1, 'IFRS 15', NULL),
 ('PL_OOI',      'PL', 'Operating', 'Other operating income (incl. FX & disposal gains)', 'operating', 20, 1, 'IFRS 18.47', NULL),
 ('PL_EMP',      'PL', 'Operating', 'Employee benefits expense', 'operating', 30, 1, 'IAS 19; IFRS 18.83', 'employee_benefits'),
 ('PL_SUB',      'PL', 'Operating', 'Subcontractors and direct engagement costs', 'operating', 40, 1, 'IFRS 18', NULL),
 ('PL_PREM',     'PL', 'Operating', 'Premises and occupancy costs', 'operating', 50, 1, 'IFRS 16.6', NULL),
 ('PL_TECH',     'PL', 'Operating', 'Technology and communication costs', 'operating', 60, 1, NULL, NULL),
 ('PL_DEP',      'PL', 'Operating', 'Depreciation and amortisation', 'operating', 70, 1, 'IAS 16; IAS 38; IFRS 16', 'depreciation_amortisation'),
 ('PL_ECL',      'PL', 'Operating', 'Impairment losses on trade receivables', 'operating', 80, 1, 'IFRS 9; IFRS 18.82', 'impairment'),
 ('PL_OPEX',     'PL', 'Operating', 'Other operating expenses (incl. FX & disposal losses)', 'operating', 90, 1, NULL, NULL),
 ('PL_INV_RENT', 'PL', 'Investing', 'Rental income from investment property', 'investing', 200, 1, 'IAS 40; IFRS 18.53', NULL),
 ('PL_INV_FV',   'PL', 'Investing', 'Fair value gain on investment property', 'investing', 210, 1, 'IAS 40.35', NULL),
 ('PL_INV_INT',  'PL', 'Investing', 'Interest and dividend income', 'investing', 220, 1, 'IFRS 18.53', NULL),
 ('PL_FIN_LEASE','PL', 'Financing', 'Interest expense on lease liabilities', 'financing', 300, 1, 'IFRS 16.49; IFRS 18.61', NULL),
 ('PL_FIN_BORR', 'PL', 'Financing', 'Interest expense on borrowings', 'financing', 310, 1, 'IFRS 18.59', NULL),
 ('PL_TAX',      'PL', 'Income taxes', 'Income tax expense', 'income_taxes', 400, 1, 'IAS 12', NULL),
 ('PL_DISC',     'PL', 'Discontinued', 'Profit from discontinued operations', 'discontinued', 500, 1, 'IFRS 5', NULL),
 -- Other comprehensive income
 ('OCI_REVAL',   'OCI','Items that will not be reclassified to profit or loss', 'Revaluation of land and buildings, net of tax', NULL, 600, 1, 'IAS 16.39', NULL),
 ('OCI_FX',      'OCI','Items that may be reclassified to profit or loss', 'Exchange differences on translating foreign operations', NULL, 610, 1, 'IAS 21.39', NULL),
 -- Statement of financial position (sign -1 = debit balance shown positive)
 ('SFP_PPE',     'SFP','Non-current assets', 'Property, plant and equipment', NULL, 1010, -1, 'IAS 16', NULL),
 ('SFP_ROU',     'SFP','Non-current assets', 'Right-of-use assets', NULL, 1020, -1, 'IFRS 16', NULL),
 ('SFP_IP',      'SFP','Non-current assets', 'Investment property', NULL, 1030, -1, 'IAS 40', NULL),
 ('SFP_INT',     'SFP','Non-current assets', 'Intangible assets', NULL, 1040, -1, 'IAS 38', NULL),
 ('SFP_DTA',     'SFP','Non-current assets', 'Deferred tax assets', NULL, 1050, -1, 'IAS 12', NULL),
 ('SFP_ONCA',    'SFP','Non-current assets', 'Other non-current assets (rental deposits)', NULL, 1060, -1, NULL, NULL),
 ('SFP_TR',      'SFP','Current assets', 'Trade and other receivables', NULL, 2010, -1, 'IFRS 9', NULL),
 ('SFP_CA15',    'SFP','Current assets', 'Contract assets (unbilled work)', NULL, 2020, -1, 'IFRS 15.105', NULL),
 ('SFP_PREP',    'SFP','Current assets', 'Prepayments', NULL, 2030, -1, NULL, NULL),
 ('SFP_TAX_A',   'SFP','Current assets', 'Current tax receivable', NULL, 2040, -1, 'IAS 12', NULL),
 ('SFP_CASH',    'SFP','Current assets', 'Cash and cash equivalents', NULL, 2050, -1, 'IAS 7', NULL),
 ('SFP_SC',      'SFP','Equity', 'Share capital', NULL, 3010, 1, NULL, NULL),
 ('SFP_REVAL',   'SFP','Equity', 'Revaluation reserve', NULL, 3020, 1, 'IAS 16.41', NULL),
 ('SFP_FXRES',   'SFP','Equity', 'Foreign currency translation reserve', NULL, 3030, 1, 'IAS 21', NULL),
 ('SFP_RE',      'SFP','Equity', 'Retained earnings', NULL, 3040, 1, NULL, NULL),
 ('SFP_BORR',    'SFP','Non-current liabilities', 'Borrowings', NULL, 4010, 1, 'IFRS 9', NULL),
 ('SFP_LEASE',   'SFP','Non-current liabilities', 'Lease liabilities', NULL, 4020, 1, 'IFRS 16', NULL),
 ('SFP_DTL',     'SFP','Non-current liabilities', 'Deferred tax liabilities', NULL, 4030, 1, 'IAS 12', NULL),
 ('SFP_PROV_NC', 'SFP','Non-current liabilities', 'Provisions', NULL, 4040, 1, 'IAS 37', NULL),
 ('SFP_TP',      'SFP','Current liabilities', 'Trade and other payables', NULL, 5010, 1, NULL, NULL),
 ('SFP_EMP',     'SFP','Current liabilities', 'Employee benefit obligations', NULL, 5020, 1, 'IAS 19', NULL),
 ('SFP_STAT',    'SFP','Current liabilities', 'VAT, PAYE, NSSA and other statutory liabilities', NULL, 5030, 1, NULL, NULL),
 ('SFP_TAX_L',   'SFP','Current liabilities', 'Current tax payable', NULL, 5040, 1, 'IAS 12', NULL),
 ('SFP_CL15',    'SFP','Current liabilities', 'Contract liabilities (client advances)', NULL, 5050, 1, 'IFRS 15.106', NULL),
 ('SFP_LEASE_C', 'SFP','Current liabilities', 'Lease liabilities - current portion', NULL, 5060, 1, 'IFRS 16', NULL),
 ('SFP_BORR_C',  'SFP','Current liabilities', 'Borrowings - current portion', NULL, 5070, 1, NULL, NULL);

INSERT INTO cash_flow_lines (cf_code, category, name, sort_order) VALUES
 ('CF_OP_RECEIPTS',   'operating', 'Cash receipts from clients', 10),
 ('CF_OP_OTHER_REC',  'operating', 'Other operating receipts', 20),
 ('CF_OP_SUPPLIERS',  'operating', 'Cash paid to suppliers', 30),
 ('CF_OP_EMPLOYEES',  'operating', 'Cash paid to and on behalf of employees (incl. PAYE & NSSA)', 40),
 ('CF_OP_TAXES',      'operating', 'VAT paid to tax authorities (net)', 50),
 ('CF_OP_INCOME_TAX', 'operating', 'Income taxes paid (QPDs and final)', 60),
 ('CF_INV_PPE',       'investing', 'Purchase of property, plant, equipment and intangibles', 200),
 ('CF_INV_DISPOSAL',  'investing', 'Proceeds from disposal of property, plant and equipment', 210),
 ('CF_INV_RENT',      'investing', 'Rental income received from investment property', 220),
 ('CF_INV_INTEREST',  'investing', 'Interest and dividends received', 230),
 ('CF_FIN_BORROW',    'financing', 'Repayment of borrowings', 300),
 ('CF_FIN_LEASE',     'financing', 'Principal elements of lease payments', 310),
 ('CF_FIN_INTEREST',  'financing', 'Interest paid (lease liabilities and borrowings)', 320),
 ('CF_FIN_DIVIDENDS', 'financing', 'Dividends paid to shareholders', 330),
 ('CF_FIN_SHARES',    'financing', 'Proceeds from issue of shares', 340),
 ('CF_FX',            'fx',        'Effect of exchange rate changes on cash and cash equivalents', 499);

-- 30.4 Chart of accounts ------------------------------------------------------------------
INSERT INTO chart_of_accounts (account_code, name, account_type, is_postable) VALUES
 ('1000','ASSETS','asset',FALSE), ('2000','LIABILITIES','liability',FALSE), ('3000','EQUITY','equity',FALSE),
 ('4000-H','REVENUE & OTHER INCOME','revenue',FALSE), ('5000-H','EMPLOYEE & ENGAGEMENT COSTS','expense',FALSE),
 ('6000-H','OPERATING EXPENSES','expense',FALSE), ('7000-H','DEPRECIATION, IMPAIRMENT & OTHER','expense',FALSE),
 ('8000-H','FINANCE COSTS','expense',FALSE), ('9000-H','INCOME TAX','expense',FALSE);

INSERT INTO chart_of_accounts (account_code, name, account_type, parent_account_id, ifrs_line_code, cash_flow_code, is_cash, is_control)
SELECT v.code, v.name, v.t::account_type, (SELECT account_id FROM chart_of_accounts WHERE account_code = v.parent),
       v.ifrs, v.cf, v.cash, v.ctrl
  FROM (VALUES
   -- cash & cash equivalents
   ('1010','Bank - CBZ USD Current (Harare HQ)',        'asset','1000','SFP_CASH',NULL,TRUE,FALSE),
   ('1011','Bank - Stanbic ZWG Current',                'asset','1000','SFP_CASH',NULL,TRUE,FALSE),
   ('1012','Bank - FNB ZAR (Johannesburg)',             'asset','1000','SFP_CASH',NULL,TRUE,FALSE),
   ('1013','Bank - Stanbic USD Nostro (client receipts)','asset','1000','SFP_CASH',NULL,TRUE,FALSE),
   ('1014','Bank - NCBA KES (Nairobi)',                 'asset','1000','SFP_CASH',NULL,TRUE,FALSE),
   ('1015','Bank - Barclays GBP (London)',              'asset','1000','SFP_CASH',NULL,TRUE,FALSE),
   ('1016','Bank - Emirates NBD AED (Dubai)',           'asset','1000','SFP_CASH',NULL,TRUE,FALSE),
   ('1017','Money market call deposit - USD',           'asset','1000','SFP_CASH',NULL,TRUE,FALSE),
   ('1018','Bank - CABS USD (Bulawayo)',                'asset','1000','SFP_CASH',NULL,TRUE,FALSE),
   ('1020','Petty cash',                                'asset','1000','SFP_CASH',NULL,TRUE,FALSE),
   -- receivables
   ('1100','Trade receivables',                         'asset','1000','SFP_TR','CF_OP_RECEIPTS',FALSE,TRUE),
   ('1105','Loss allowance - expected credit losses',   'asset','1000','SFP_TR','CF_OP_RECEIPTS',FALSE,FALSE),
   ('1150','Contract assets - unbilled revenue (WIP)',  'asset','1000','SFP_CA15','CF_OP_RECEIPTS',FALSE,FALSE),
   ('1200','Staff advances & loans',                    'asset','1000','SFP_TR','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('1210','Tenant & other receivables',                'asset','1000','SFP_TR','CF_INV_RENT',FALSE,FALSE),
   ('1300','Prepayments',                               'asset','1000','SFP_PREP','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('1310','Rental & utility deposits (current)',       'asset','1000','SFP_TR','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('1420','Withholding tax credits receivable',        'asset','1000','SFP_TR','CF_OP_RECEIPTS',FALSE,FALSE),
   -- PPE (IAS 16)
   ('1500','Land - at valuation',                       'asset','1000','SFP_PPE','CF_INV_PPE',FALSE,TRUE),
   ('1510','Buildings - at valuation',                  'asset','1000','SFP_PPE','CF_INV_PPE',FALSE,TRUE),
   ('1511','Buildings - accumulated depreciation',      'asset','1000','SFP_PPE','CF_INV_DISPOSAL',FALSE,TRUE),
   ('1520','Motor vehicles - cost',                     'asset','1000','SFP_PPE','CF_INV_PPE',FALSE,TRUE),
   ('1521','Motor vehicles - accumulated depreciation', 'asset','1000','SFP_PPE','CF_INV_DISPOSAL',FALSE,TRUE),
   ('1530','Computer equipment - cost',                 'asset','1000','SFP_PPE','CF_INV_PPE',FALSE,TRUE),
   ('1531','Computer equipment - accumulated depreciation','asset','1000','SFP_PPE','CF_INV_DISPOSAL',FALSE,TRUE),
   ('1540','Furniture & fittings - cost',               'asset','1000','SFP_PPE','CF_INV_PPE',FALSE,TRUE),
   ('1541','Furniture & fittings - accumulated depreciation','asset','1000','SFP_PPE','CF_INV_DISPOSAL',FALSE,TRUE),
   ('1550','Office equipment - cost',                   'asset','1000','SFP_PPE','CF_INV_PPE',FALSE,TRUE),
   ('1551','Office equipment - accumulated depreciation','asset','1000','SFP_PPE','CF_INV_DISPOSAL',FALSE,TRUE),
   ('1560','Leasehold improvements - cost',             'asset','1000','SFP_PPE','CF_INV_PPE',FALSE,TRUE),
   ('1561','Leasehold improvements - accumulated depreciation','asset','1000','SFP_PPE','CF_INV_DISPOSAL',FALSE,TRUE),
   ('1565','Forensic lab equipment - cost',             'asset','1000','SFP_PPE','CF_INV_PPE',FALSE,TRUE),
   ('1566','Forensic lab equipment - accumulated depreciation','asset','1000','SFP_PPE','CF_INV_DISPOSAL',FALSE,TRUE),
   ('1570','Capital work in progress',                  'asset','1000','SFP_PPE','CF_INV_PPE',FALSE,TRUE),
   -- ROU (IFRS 16), investment property (IAS 40), intangibles (IAS 38), other
   ('1600','Right-of-use assets - property',            'asset','1000','SFP_ROU','CF_INV_PPE',FALSE,TRUE),
   ('1601','Right-of-use property - accumulated depreciation','asset','1000','SFP_ROU','CF_INV_PPE',FALSE,TRUE),
   ('1610','Right-of-use assets - vehicles & equipment','asset','1000','SFP_ROU','CF_INV_PPE',FALSE,TRUE),
   ('1611','Right-of-use vehicles - accumulated depreciation','asset','1000','SFP_ROU','CF_INV_PPE',FALSE,TRUE),
   ('1700','Investment property - at fair value',       'asset','1000','SFP_IP','CF_INV_PPE',FALSE,TRUE),
   ('1800','Software & licences - cost',                'asset','1000','SFP_INT','CF_INV_PPE',FALSE,TRUE),
   ('1801','Software & licences - accumulated amortisation','asset','1000','SFP_INT','CF_INV_DISPOSAL',FALSE,TRUE),
   ('1900','Deferred tax asset',                        'asset','1000','SFP_DTA',NULL,FALSE,FALSE),
   ('1950','Long-term rental deposits',                 'asset','1000','SFP_ONCA','CF_OP_SUPPLIERS',FALSE,FALSE),
   -- liabilities
   ('2100','Trade payables',                            'liability','2000','SFP_TP','CF_OP_SUPPLIERS',FALSE,TRUE),
   ('2110','Payables - capital expenditure',            'liability','2000','SFP_TP','CF_INV_PPE',FALSE,TRUE),
   ('2150','Net salaries payable',                      'liability','2000','SFP_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2200','VAT output tax - ZIMRA',                    'liability','2000','SFP_STAT','CF_OP_TAXES',FALSE,FALSE),
   ('2201','VAT output tax - SARS (Johannesburg)',      'liability','2000','SFP_STAT','CF_OP_TAXES',FALSE,FALSE),
   ('2202','VAT output tax - KRA (Nairobi)',            'liability','2000','SFP_STAT','CF_OP_TAXES',FALSE,FALSE),
   ('2203','VAT output tax - HMRC (London)',            'liability','2000','SFP_STAT','CF_OP_TAXES',FALSE,FALSE),
   ('2204','VAT output tax - UAE FTA (Dubai)',          'liability','2000','SFP_STAT','CF_OP_TAXES',FALSE,FALSE),
   ('2210','VAT input tax - ZIMRA',                     'liability','2000','SFP_STAT','CF_OP_TAXES',FALSE,FALSE),
   ('2260','Income tax payable - ZIMRA',                'liability','2000','SFP_TAX_L','CF_OP_INCOME_TAX',FALSE,FALSE),
   ('2265','Income tax payable - branches',             'liability','2000','SFP_TAX_L','CF_OP_INCOME_TAX',FALSE,FALSE),
   ('2300','Employee reimbursements payable',           'liability','2000','SFP_TP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2400','PAYE payable - ZIMRA',                      'liability','2000','SFP_STAT','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2405','AIDS levy payable - ZIMRA',                 'liability','2000','SFP_STAT','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2410','NSSA payable (POBS & WCIF)',                'liability','2000','SFP_STAT','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2415','ZIMDEF levy payable',                       'liability','2000','SFP_STAT','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2420','Pension fund contributions payable',        'liability','2000','SFP_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2425','Medical aid contributions payable',         'liability','2000','SFP_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2430','Withholding tax payable - ZIMRA',           'liability','2000','SFP_STAT','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('2450','Branch payroll taxes & social security payable','liability','2000','SFP_STAT','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2500','Accrued expenses',                          'liability','2000','SFP_TP','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('2510','Leave pay accrual (IAS 19)',                'liability','2000','SFP_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2520','Bonus accrual (IAS 19)',                    'liability','2000','SFP_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2550','Provisions - dilapidations & legal (IAS 37)','liability','2000','SFP_PROV_NC','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('2600','Contract liabilities - client advances',    'liability','2000','SFP_CL15','CF_OP_RECEIPTS',FALSE,FALSE),
   ('2650','Tenant deposits held',                      'liability','2000','SFP_TP','CF_INV_RENT',FALSE,FALSE),
   ('2700','Lease liabilities (IFRS 16)',               'liability','2000','SFP_LEASE','CF_FIN_LEASE',FALSE,TRUE),
   ('2705','Lease interest payable',                    'liability','2000','SFP_LEASE','CF_FIN_INTEREST',FALSE,FALSE),
   ('2800','Borrowings - CBZ mortgage loan',            'liability','2000','SFP_BORR','CF_FIN_BORROW',FALSE,TRUE),
   ('2900','Deferred tax liability',                    'liability','2000','SFP_DTL',NULL,FALSE,FALSE),
   ('2950','Dividends payable',                         'liability','2000','SFP_TP','CF_FIN_DIVIDENDS',FALSE,FALSE),
   -- equity
   ('3100','Share capital (ordinary shares)',           'equity','3000','SFP_SC','CF_FIN_SHARES',FALSE,FALSE),
   ('3200','Retained earnings',                         'equity','3000','SFP_RE','CF_FIN_DIVIDENDS',FALSE,FALSE),
   ('3300','Revaluation reserve (IAS 16)',              'equity','3000','SFP_REVAL',NULL,FALSE,FALSE),
   ('3400','Foreign currency translation reserve',      'equity','3000','SFP_FXRES',NULL,FALSE,FALSE),
   -- revenue & other income
   ('4000','Fees - time & materials',                   'revenue','4000-H','PL_REV','CF_OP_RECEIPTS',FALSE,FALSE),
   ('4010','Fees - fixed fee & milestones',             'revenue','4000-H','PL_REV','CF_OP_RECEIPTS',FALSE,FALSE),
   ('4020','Retainer fees',                             'revenue','4000-H','PL_REV','CF_OP_RECEIPTS',FALSE,FALSE),
   ('4100','Recoverable expenses billed',               'revenue','4000-H','PL_REV','CF_OP_RECEIPTS',FALSE,FALSE),
   ('4500','Rental income - investment property',       'revenue','4000-H','PL_INV_RENT','CF_INV_RENT',FALSE,FALSE),
   ('4510','Fair value gains - investment property',    'revenue','4000-H','PL_INV_FV',NULL,FALSE,FALSE),
   ('4600','Interest income',                           'revenue','4000-H','PL_INV_INT','CF_INV_INTEREST',FALSE,FALSE),
   ('4610','Dividend income',                           'revenue','4000-H','PL_INV_INT','CF_INV_INTEREST',FALSE,FALSE),
   ('4700','Gain on disposal of PPE',                   'revenue','4000-H','PL_OOI','CF_INV_DISPOSAL',FALSE,FALSE),
   ('4800','Foreign exchange gains',                    'revenue','4000-H','PL_OOI','CF_FX',FALSE,FALSE),
   ('4900','Other income',                              'revenue','4000-H','PL_OOI','CF_OP_OTHER_REC',FALSE,FALSE),
   -- employee benefits (by nature)
   ('5100','Salaries - fee earners',                    'expense','5000-H','PL_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('5110','Salaries - business support',               'expense','5000-H','PL_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('5120','Employer NSSA / social security & WCIF',    'expense','5000-H','PL_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('5125','ZIMDEF & training levies',                  'expense','5000-H','PL_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('5130','Employer pension contributions',            'expense','5000-H','PL_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('5140','Employer medical aid contributions',        'expense','5000-H','PL_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('5150','Staff bonuses',                             'expense','5000-H','PL_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('5160','Leave pay',                                 'expense','5000-H','PL_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('5170','Staff welfare & recruitment',               'expense','5000-H','PL_EMP','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('5200','Subcontractor fees',                        'expense','5000-H','PL_SUB','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('5300','Project travel',                            'expense','5000-H','PL_SUB','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('5310','Project accommodation',                     'expense','5000-H','PL_SUB','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('5320','Project meals & subsistence',               'expense','5000-H','PL_SUB','CF_OP_SUPPLIERS',FALSE,FALSE),
   -- operating expenses
   ('6100','Short-term & low-value lease rentals',      'expense','6000-H','PL_PREM','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6110','Rates, electricity & water',                'expense','6000-H','PL_PREM','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6120','Repairs & maintenance',                     'expense','6000-H','PL_PREM','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6130','Security & cleaning',                       'expense','6000-H','PL_PREM','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6140','Insurance',                                 'expense','6000-H','PL_OPEX','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6200','Software licences & subscriptions',         'expense','6000-H','PL_TECH','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6210','Cloud hosting & data services',             'expense','6000-H','PL_TECH','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6300','Training & professional subscriptions',     'expense','6000-H','PL_OPEX','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6400','Marketing & business development',          'expense','6000-H','PL_OPEX','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6500','Telephone & internet',                      'expense','6000-H','PL_TECH','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6600','Bank charges',                              'expense','6000-H','PL_OPEX','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6610','IMTT (2% transfer tax)',                    'expense','6000-H','PL_OPEX','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6700','Audit, legal & professional fees',          'expense','6000-H','PL_OPEX','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6710','Non-executive directors'' fees',            'expense','6000-H','PL_OPEX','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6800','Motor vehicle running costs',               'expense','6000-H','PL_OPEX','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6900','General administration',                    'expense','6000-H','PL_OPEX','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6950','Donations & corporate social responsibility','expense','6000-H','PL_OPEX','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('7000','Depreciation - property, plant & equipment','expense','7000-H','PL_DEP',NULL,FALSE,FALSE),
   ('7010','Depreciation - right-of-use assets',        'expense','7000-H','PL_DEP',NULL,FALSE,FALSE),
   ('7020','Amortisation - intangible assets',          'expense','7000-H','PL_DEP',NULL,FALSE,FALSE),
   ('7100','Impairment losses on trade receivables (ECL)','expense','7000-H','PL_ECL','CF_OP_RECEIPTS',FALSE,FALSE),
   ('7200','Loss on disposal of PPE',                   'expense','7000-H','PL_OPEX','CF_INV_DISPOSAL',FALSE,FALSE),
   ('7300','Foreign exchange losses',                   'expense','7000-H','PL_OPEX','CF_FX',FALSE,FALSE),
   -- financing & tax
   ('8000','Interest on lease liabilities',             'expense','8000-H','PL_FIN_LEASE','CF_FIN_INTEREST',FALSE,FALSE),
   ('8010','Interest on borrowings',                    'expense','8000-H','PL_FIN_BORR','CF_FIN_INTEREST',FALSE,FALSE),
   ('9000','Current tax - Zimbabwe (CIT + AIDS levy)',  'expense','9000-H','PL_TAX','CF_OP_INCOME_TAX',FALSE,FALSE),
   ('9010','Current tax - foreign branches',            'expense','9000-H','PL_TAX','CF_OP_INCOME_TAX',FALSE,FALSE),
   ('9020','Deferred tax',                              'expense','9000-H','PL_TAX',NULL,FALSE,FALSE)
  ) AS v(code, name, t, parent, ifrs, cf, cash, ctrl);

INSERT INTO cash_flow_source_overrides (source_type, cf_code) VALUES
 ('asset_disposal','CF_INV_DISPOSAL'), ('payroll_payment','CF_OP_EMPLOYEES'), ('dividend','CF_FIN_DIVIDENDS');

-- IFRS 9 provision matrix (simplified approach, lifetime ECL)
INSERT INTO ecl_provision_matrix (bucket, min_days, max_days, loss_rate_pct, sort_order) VALUES
 ('Current', 0, 0, 0.50, 1), ('1-30', 1, 30, 1.50, 2), ('31-60', 31, 60, 4.00, 3),
 ('61-90', 61, 90, 10.00, 4), ('90+', 91, NULL, 35.00, 5);

-- IFRS 18 management-defined performance measures
INSERT INTO mpm_definitions (mpm_code, name, description, why_useful, base_subtotal, sort_order) VALUES
 ('ADJ_OP', 'Adjusted operating profit',
  'Operating profit excluding foreign exchange gains and losses and gains/losses on disposal of property, plant and equipment.',
  'Management uses it to assess the performance of the consulting business without currency movements and one-off asset sales, and it is the basis of the staff bonus pool.',
  'Operating profit', 1),
 ('ADJ_EBITDA', 'Adjusted EBITDA',
  'Operating profit before depreciation, amortisation, foreign exchange differences and gains/losses on disposal of PPE.',
  'Used by the Board and by CBZ Bank in the mortgage-loan covenant (net debt / adjusted EBITDA) to measure cash-generating capacity.',
  'Operating profit', 2);
INSERT INTO mpm_adjustments (mpm_code, account_id, caption)
SELECT m, fn_account_id(a), c FROM (VALUES
  ('ADJ_OP','4800','Foreign exchange differences'), ('ADJ_OP','7300','Foreign exchange differences'),
  ('ADJ_OP','4700','(Gain) / loss on disposal of PPE'), ('ADJ_OP','7200','(Gain) / loss on disposal of PPE'),
  ('ADJ_EBITDA','7000','Depreciation and amortisation'), ('ADJ_EBITDA','7010','Depreciation and amortisation'),
  ('ADJ_EBITDA','7020','Depreciation and amortisation'),
  ('ADJ_EBITDA','4800','Foreign exchange differences'), ('ADJ_EBITDA','7300','Foreign exchange differences'),
  ('ADJ_EBITDA','4700','(Gain) / loss on disposal of PPE'), ('ADJ_EBITDA','7200','(Gain) / loss on disposal of PPE')) AS x(m, a, c);

-- 30.5 Tax authorities, tax types, statutory rates, PAYE tables ---------------------------
INSERT INTO tax_authorities (authority_code, name, country_code, website, portal_name) VALUES
 ('ZIMRA',  'Zimbabwe Revenue Authority', 'ZW', 'www.zimra.co.zw', 'TaRMS'),
 ('NSSA',   'National Social Security Authority', 'ZW', 'www.nssa.org.zw', 'NSSA e-Services'),
 ('ZIMDEF', 'Zimbabwe Manpower Development Fund', 'ZW', 'www.zimdef.org.zw', 'ZIMDEF returns'),
 ('SARS',   'South African Revenue Service', 'ZA', 'www.sars.gov.za', 'eFiling'),
 ('KRA',    'Kenya Revenue Authority', 'KE', 'www.kra.go.ke', 'iTax'),
 ('HMRC',   'HM Revenue & Customs', 'GB', 'www.gov.uk/hmrc', 'PAYE Online / MTD'),
 ('UAEFTA', 'Federal Tax Authority (UAE)', 'AE', 'tax.gov.ae', 'EmaraTax');

INSERT INTO tax_types (tax_code, name, authority_code, return_form, frequency, due_day, liability_account_code, offset_account_code, description) VALUES
 ('VAT',      'Value Added Tax (15.5%)',                 'ZIMRA','VAT7',       'monthly', 25, '2200', '2210', 'Output tax less input tax; Category C monthly filer; fiscalised invoices (FDMS).'),
 ('PAYE',     'PAYE + AIDS levy',                        'ZIMRA','P2',         'monthly', 10, '2400', NULL,   'Employees tax per ZIMRA tables plus 3% AIDS levy on the tax; ITF16 annual reconciliation.'),
 ('NSSA',     'NSSA POBS & WCIF contributions',          'NSSA', 'P4',         'monthly', 10, '2410', NULL,   '4.5% employee + 4.5% employer on insurable earnings (ceiling USD 700) plus employer WCIF.'),
 ('ZIMDEF',   'ZIMDEF manpower development levy (1%)',   'ZIMDEF','ZIMDEF return','monthly', 10, '2415', NULL, '1% of the gross wage bill, employer only.'),
 ('WHT',      'Withholding taxes (30% tender / 15% non-resident fees)', 'ZIMRA','REV5','monthly', 10, '2430', NULL, 'Tax withheld from supplier payments and paid over to ZIMRA.'),
 ('CIT_QPD',  'Corporate income tax - QPD instalment',   'ZIMRA','ITF12B',     'qpd',     NULL, '2260', NULL, 'QPDs: 25 Mar 10%, 25 Jun 25%, 25 Sep 30%, 20 Dec 35% of estimated tax.'),
 ('CIT_FINAL','Corporate income tax - final return',     'ZIMRA','ITF12C',     'annual',  30,   '2260', NULL, 'Annual self-assessment return due 30 April; balance of tax payable.'),
 ('IMTT',     'Intermediated Money Transfer Tax (2%)',   'ZIMRA',NULL,         'per_transaction', NULL, NULL, NULL, 'Deducted by banks on electronic transfers; expensed in 6610.'),
 ('ZA_PAYE',  'SARS PAYE, UIF & SDL',                    'SARS', 'EMP201',     'monthly', 7,  '2450', NULL, 'Johannesburg branch payroll taxes.'),
 ('ZA_VAT',   'SARS VAT (15%)',                          'SARS', 'VAT201',     'bi_monthly', 25, '2201', NULL, 'Johannesburg branch VAT.'),
 ('ZA_CIT',   'SARS corporate income tax (27%)',         'SARS', 'ITR14',      'annual',  NULL, '2265', NULL, 'Tax on profits of the South African branch (permanent establishment).'),
 ('KE_PAYE',  'KRA PAYE, NSSF, SHIF & housing levy',     'KRA',  'P10',        'monthly', 9,  '2450', NULL, 'Nairobi branch payroll taxes.'),
 ('KE_VAT',   'KRA VAT (16%)',                           'KRA',  'VAT3',       'monthly', 20, '2202', NULL, 'Nairobi branch VAT.'),
 ('KE_CIT',   'KRA corporation tax - branch (30%)',      'KRA',  'IT2C',       'annual',  NULL, '2265', NULL, 'Kenyan branch profits.'),
 ('GB_PAYE',  'HMRC PAYE & National Insurance',          'HMRC', 'RTI FPS/EPS','monthly', 22, '2450', NULL, 'London branch payroll taxes.'),
 ('GB_VAT',   'HMRC VAT (20%)',                          'HMRC', 'VAT100 (MTD)','quarterly', 7, '2203', NULL, 'London branch VAT.'),
 ('GB_CT',    'HMRC corporation tax (25%)',              'HMRC', 'CT600',      'annual',  NULL, '2265', NULL, 'UK permanent establishment profits.'),
 ('AE_VAT',   'UAE VAT (5%)',                            'UAEFTA','VAT201',    'quarterly', 28, '2204', NULL, 'Dubai branch VAT.'),
 ('AE_CT',    'UAE corporate tax (9%)',                  'UAEFTA','CT return', 'annual',  NULL, '2265', NULL, '9% on taxable income above AED 375,000.');

INSERT INTO statutory_rates (country_code, rate_code, description, rate_pct, amount, currency_code, effective_from, source_note) VALUES
 ('ZW','CIT',                  'Corporate income tax rate', 24.000, NULL, NULL, '2023-01-01', 'Income Tax Act [Chapter 23:06]'),
 ('ZW','AIDS_LEVY',            'AIDS levy on income tax / PAYE', 3.000, NULL, NULL, '2000-01-01', 'Finance Act'),
 ('ZW','VAT',                  'VAT standard rate', 15.500, NULL, NULL, '2023-01-01', 'Finance Act 2023'),
 ('ZW','NSSA_EE',              'NSSA POBS - employee share', 4.500, NULL, NULL, '2019-01-01', 'SI 2019; verify NSSA notices'),
 ('ZW','NSSA_ER',              'NSSA POBS - employer share', 4.500, NULL, NULL, '2019-01-01', 'SI 2019; verify NSSA notices'),
 ('ZW','NSSA_CEILING',         'NSSA insurable earnings ceiling (per month)', NULL, 700.00, 'USD', '2024-01-01', 'NSSA; verify current ceiling'),
 ('ZW','NSSA_WCIF',            'Workers Compensation Insurance Fund - employer (industry rate)', 1.000, NULL, NULL, '2024-01-01', 'Rate depends on industry class'),
 ('ZW','ZIMDEF',               'ZIMDEF levy - employer, % of wage bill', 1.000, NULL, NULL, '1996-01-01', 'Manpower Planning & Development Act'),
 ('ZW','PENSION_EE',           'Company pension fund - employee contribution (% of basic)', 5.000, NULL, NULL, '2015-01-01', 'Maxhub Staff Pension Fund rules'),
 ('ZW','PENSION_ER',           'Company pension fund - employer contribution (% of basic)', 7.500, NULL, NULL, '2015-01-01', 'Maxhub Staff Pension Fund rules'),
 ('ZW','PENSION_CAP',          'Deductible pension contributions cap (per month)', NULL, 450.00, 'USD', '2023-01-01', 'USD 5,400 per year'),
 ('ZW','MEDICAL_CREDIT',       'Medical aid tax credit (% of contributions)', 50.000, NULL, NULL, '2020-01-01', 'Income Tax Act credits'),
 ('ZW','WHT_TENDER',           'Withholding on payments to suppliers without ITF263 tax clearance', 30.000, NULL, NULL, '2015-01-01', 'Section 80 Income Tax Act'),
 ('ZW','WHT_TENDER_THRESHOLD', 'Threshold for 30% withholding (per contract)', NULL, 1000.00, 'USD', '2019-01-01', 'Verify current ZIMRA threshold'),
 ('ZW','WHT_NONRES_FEES',      'Non-residents tax on fees', 15.000, NULL, NULL, '2019-01-01', 'Income Tax Act'),
 ('ZW','WHT_DIVIDENDS',        'Resident shareholders tax on dividends (unlisted)', 10.000, NULL, NULL, '2019-01-01', 'Income Tax Act'),
 ('ZW','IMTT',                 'Intermediated Money Transfer Tax', 2.000, NULL, NULL, '2018-10-01', 'Finance Act'),
 ('ZW','CGT',                  'Capital gains tax', 20.000, NULL, NULL, '2019-01-01', 'Capital Gains Tax Act'),
 ('ZA','CIT','SA corporate income tax', 27.000, NULL, NULL, '2022-04-01', 'SARS'),
 ('ZA','INCOME_TAX_EFFECTIVE','Branch payroll: effective PAYE rate (simplified)', 24.000, NULL, NULL, '2025-03-01', 'Simplified - use SARS tables in production'),
 ('ZA','SOCIAL_EE','UIF - employee', 1.000, NULL, NULL, '2021-06-01', 'UIF'),
 ('ZA','SOCIAL_ER','UIF - employer', 1.000, NULL, NULL, '2021-06-01', 'UIF'),
 ('ZA','SOCIAL_CEILING','UIF earnings ceiling (per month)', NULL, 17712.00, 'ZAR', '2021-06-01', 'UIF'),
 ('ZA','OTHER_ER','Skills Development Levy - employer', 1.000, NULL, NULL, '2001-01-01', 'SDL'),
 ('ZA','PENSION_EE','Provident fund - employee', 5.000, NULL, NULL, '2020-01-01', 'Company scheme'),
 ('ZA','PENSION_ER','Provident fund - employer', 5.000, NULL, NULL, '2020-01-01', 'Company scheme'),
 ('KE','CIT','Kenya corporation tax - branch', 30.000, NULL, NULL, '2023-07-01', 'KRA'),
 ('KE','INCOME_TAX_EFFECTIVE','Branch payroll: effective PAYE rate incl. SHIF & housing levy (simplified)', 28.000, NULL, NULL, '2025-01-01', 'Simplified'),
 ('KE','SOCIAL_EE','NSSF - employee', 6.000, NULL, NULL, '2025-02-01', 'NSSF Act 2013 phase 3'),
 ('KE','SOCIAL_ER','NSSF - employer', 6.000, NULL, NULL, '2025-02-01', 'NSSF Act 2013 phase 3'),
 ('KE','SOCIAL_CEILING','NSSF upper earnings limit (per month)', NULL, 72000.00, 'KES', '2025-02-01', 'NSSF'),
 ('KE','OTHER_ER','Affordable housing levy - employer', 1.500, NULL, NULL, '2024-03-19', 'Affordable Housing Act 2024'),
 ('GB','CIT','UK corporation tax (main rate)', 25.000, NULL, NULL, '2023-04-01', 'HMRC'),
 ('GB','INCOME_TAX_EFFECTIVE','Branch payroll: effective income tax rate (simplified)', 22.000, NULL, NULL, '2025-04-06', 'Simplified'),
 ('GB','SOCIAL_EE','Employee Class 1 NIC', 8.000, NULL, NULL, '2024-04-06', 'HMRC'),
 ('GB','SOCIAL_ER','Employer Class 1 NIC', 15.000, NULL, NULL, '2025-04-06', 'HMRC'),
 ('GB','PENSION_EE','Workplace pension - employee (auto-enrolment)', 5.000, NULL, NULL, '2019-04-06', 'The Pensions Regulator'),
 ('GB','PENSION_ER','Workplace pension - employer (auto-enrolment)', 3.000, NULL, NULL, '2019-04-06', 'The Pensions Regulator'),
 ('AE','CIT','UAE corporate tax (above AED 375,000)', 9.000, NULL, NULL, '2023-06-01', 'Federal Decree-Law 47/2022'),
 ('AE','INCOME_TAX_EFFECTIVE','No personal income tax', 0.000, NULL, NULL, '2000-01-01', 'UAE');

-- ZIMRA USD PAYE tables (monthly). Verify every January against the ZIMRA tax tables.
INSERT INTO paye_tax_bands (country_code, currency_code, effective_from, lower_limit, upper_limit, rate_pct, deduct_amount)
SELECT 'ZW', 'USD', y.d, b.lo, b.hi, b.rate, b.less
  FROM (VALUES ('2025-01-01'::DATE), ('2026-01-01'::DATE)) AS y(d)
 CROSS JOIN (VALUES (0.00, 100.00, 0, 0), (100.01, 300.00, 20, 20), (300.01, 1000.00, 25, 35),
                    (1000.01, 2000.00, 30, 85), (2000.01, 3000.00, 35, 185), (3000.01, NULL, 40, 335)) AS b(lo, hi, rate, less);

-- 30.6 Security: roles, permissions, policy ----------------------------------------------
INSERT INTO security_policy (policy_id) VALUES (1);

INSERT INTO roles (code, name, description, is_system) VALUES
 ('ADMIN',           'System Administrator',        'Full access to every module, users, roles and audit logs (ICT managers)', TRUE),
 ('EXECUTIVE',       'Executive / Partner',         'Partners, directors and the executive team - all business pages and approvals', TRUE),
 ('FINANCE_MANAGER', 'Finance Manager',             'CFO, financial controller & finance managers - GL, billing, tax, assets, leases, reporting', TRUE),
 ('ACCOUNTANT',      'Accountant',                  'Finance department staff - billing, receipts, journals, statements', TRUE),
 ('TAX_OFFICER',     'Tax Compliance Officer',      'Prepares and files ZIMRA / NSSA returns', TRUE),
 ('HR_MANAGER',      'HR Manager',                  'People records, leave, payroll approval, announcements', TRUE),
 ('PAYROLL_OFFICER', 'Payroll / HR Officer',        'Runs payroll and views payslips', TRUE),
 ('PROJECT_MANAGER', 'Engagement Manager',          'Manages engagements, approves team timesheets and expenses', TRUE),
 ('CONSULTANT',      'Consultant',                  'Client-service staff - projects, timesheets, expenses', TRUE),
 ('BD_MANAGER',      'Marketing & BD',              'CRM: clients, leads, opportunities', TRUE),
 ('FACILITIES',      'Facilities & Procurement',    'Fixed-asset register, maintenance, office leases', TRUE),
 ('IT_SUPPORT',      'IT Support',                  'IT equipment register, user accounts and password resets', TRUE),
 ('AUDITOR',         'Internal Audit / Compliance', 'Read-only access to finance, tax, assets and the audit trail', TRUE),
 ('EMPLOYEE',        'Employee self-service',       'Every staff member: home, timesheets, expenses, leave, messages', TRUE);

INSERT INTO permissions (code, module, description) VALUES
 ('page.home','pages','Home / my workspace'), ('page.dashboard','pages','Firm dashboard (KPIs)'),
 ('page.projects','pages','Projects'), ('page.timesheets','pages','Timesheets'), ('page.expenses','pages','Expense claims'),
 ('page.crm','pages','CRM'), ('page.billing','pages','Billing & receivables'), ('page.finance','pages','General ledger & budgets'),
 ('page.reports','pages','IFRS financial statements'), ('page.people','pages','People & leave'), ('page.payroll','pages','Payroll'),
 ('page.assets','pages','Fixed assets'), ('page.leases','pages','Leases & borrowings'), ('page.tax','pages','Tax compliance (ZIMRA/NSSA)'),
 ('page.comms','pages','Messages, announcements & directory'), ('page.admin','pages','Administration (users, roles, audit)'),
 ('timesheet.approve','time','Approve timesheets of direct reports'), ('timesheet.approve_all','time','Approve any timesheet'),
 ('expense.approve','expenses','Approve expense claims of direct reports'), ('expense.approve_all','expenses','Approve any expense claim'),
 ('project.manage','projects','Create/update projects, risks, issues, status reports'),
 ('client.manage','crm','Create clients, leads and opportunities'),
 ('invoice.issue','billing','Generate and issue invoices'), ('payment.record','billing','Record client receipts'),
 ('gl.post','finance','Post manual journals'), ('report.financial','finance','View financial statements & firm financial KPIs'),
 ('employee.manage','hr','Maintain employee records, onboard logins'), ('leave.approve_all','hr','Approve any leave request'),
 ('payroll.run','payroll','Run and approve payroll'), ('payroll.view_all','payroll','See every payslip'),
 ('asset.manage','assets','Maintain the asset register, assignments, maintenance'), ('depreciation.run','assets','Run monthly depreciation'),
 ('lease.manage','leases','Maintain leases and post monthly lease accounting'),
 ('tax.manage','tax','Prepare, file and pay tax returns'),
 ('announcement.publish','comms','Publish company announcements'), ('message.all_staff','comms','Message all-staff lists'),
 ('user.manage','admin','Create users, reset passwords, unlock accounts, change roles'), ('audit.view','admin','View audit trail & login history');

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
  FROM roles r JOIN permissions p ON
       r.code = 'ADMIN'
    OR (r.code = 'EMPLOYEE'        AND p.code IN ('page.home','page.timesheets','page.expenses','page.people','page.comms'))
    OR (r.code = 'CONSULTANT'      AND p.code IN ('page.projects'))
    OR (r.code = 'PROJECT_MANAGER' AND p.code IN ('page.projects','page.dashboard','page.crm','project.manage','timesheet.approve','expense.approve'))
    OR (r.code = 'EXECUTIVE'       AND (p.code LIKE 'page.%' AND p.code <> 'page.admin'
                                        OR p.code IN ('timesheet.approve','timesheet.approve_all','expense.approve','expense.approve_all',
                                                      'leave.approve_all','project.manage','client.manage','invoice.issue','report.financial',
                                                      'payroll.view_all','announcement.publish','message.all_staff','audit.view')))
    OR (r.code = 'FINANCE_MANAGER' AND p.code IN ('page.dashboard','page.billing','page.finance','page.reports','page.assets','page.leases',
                                                  'page.tax','page.payroll','page.crm','invoice.issue','payment.record','gl.post','report.financial',
                                                  'depreciation.run','asset.manage','lease.manage','tax.manage','expense.approve_all','payroll.view_all',
                                                  'announcement.publish'))
    OR (r.code = 'ACCOUNTANT'      AND p.code IN ('page.billing','page.finance','page.reports','page.assets','page.leases','page.tax',
                                                  'invoice.issue','payment.record','gl.post','report.financial'))
    OR (r.code = 'TAX_OFFICER'     AND p.code IN ('page.tax','page.finance','page.reports','page.payroll','tax.manage','report.financial','payroll.view_all'))
    OR (r.code = 'HR_MANAGER'      AND p.code IN ('page.people','page.payroll','employee.manage','leave.approve_all','payroll.run','payroll.view_all',
                                                  'announcement.publish','message.all_staff'))
    OR (r.code = 'PAYROLL_OFFICER' AND p.code IN ('page.payroll','payroll.run','payroll.view_all'))
    OR (r.code = 'BD_MANAGER'      AND p.code IN ('page.crm','page.dashboard','client.manage'))
    OR (r.code = 'FACILITIES'      AND p.code IN ('page.assets','page.leases','asset.manage'))
    OR (r.code = 'IT_SUPPORT'      AND p.code IN ('page.assets','page.admin','asset.manage','user.manage'))
    OR (r.code = 'AUDITOR'         AND p.code IN ('page.dashboard','page.billing','page.finance','page.reports','page.assets','page.leases',
                                                  'page.tax','page.payroll','report.financial','audit.view','payroll.view_all'));

-- 30.7 HR reference -----------------------------------------------------------------------
INSERT INTO leave_types (code, name, annual_entitlement_days, is_paid, carry_forward_max_days, requires_document) VALUES
 ('AL','Annual Leave',22,TRUE,10,FALSE), ('SL','Sick Leave',30,TRUE,0,TRUE),
 ('ML','Maternity Leave',98,TRUE,0,TRUE), ('SP','Study / Exam Leave',5,TRUE,0,FALSE),
 ('CL','Compassionate Leave',5,TRUE,0,FALSE), ('UL','Unpaid Leave',0,FALSE,0,FALSE);

INSERT INTO skills (name, category) VALUES
 ('Forensic Accounting','Forensic'), ('Fraud Investigation','Forensic'), ('Litigation Support & Expert Witness','Forensic'),
 ('eDiscovery (Relativity)','Forensic'), ('Data Analytics (Python)','Data'), ('SQL','Data'), ('Power BI','Data'),
 ('Machine Learning','Data'), ('Digital Forensics (EnCase / FTK)','Cyber'), ('Penetration Testing','Cyber'),
 ('ISO 27001','Cyber'), ('Internal Audit','Risk'), ('AML/CFT Compliance','Risk'), ('Enterprise Risk Management','Risk'),
 ('Zimbabwe Tax (ZIMRA)','Tax'), ('Transfer Pricing','Tax'), ('IFRS Reporting','Finance'), ('Business Valuation','Finance'),
 ('Financial Due Diligence','Finance'), ('Project Management','General');

INSERT INTO industries (name) VALUES
 ('Banking & Financial Services'), ('Insurance & Pensions'), ('Mining & Resources'), ('Telecommunications'),
 ('Government & Public Sector'), ('Retail & FMCG'), ('Agriculture & Agro-processing'), ('Energy & Utilities'),
 ('NGO & Development'), ('Manufacturing'), ('Healthcare'), ('Transport & Logistics'), ('Real Estate');
