
/* =====================================================================================
   33. SEED - CLIENTS, CONTACTS, SERVICES, RATE CARDS, CONTRACTS, PROJECTS & TEAMS, CRM
   ===================================================================================== */

-- 33.1 Clients (fictional) ----------------------------------------------------------------
CREATE TEMP TABLE seed_clients (code TEXT, name TEXT, industry TEXT, cc TEXT, city TEXT, terms INT, behaviour TEXT, manager TEXT);
INSERT INTO seed_clients VALUES
 ('C001','Zambezi Mining Holdings Ltd','Mining & Resources','ZW','Harare',30,'good','E002'),
 ('C002','Harare Metropolitan Bank Ltd','Banking & Financial Services','ZW','Harare',30,'good','E002'),
 ('C003','Kariba Agro Processors (Pvt) Ltd','Agriculture & Agro-processing','ZW','Chinhoyi',45,'slow','E010'),
 ('C004','Great Zimbabwe Insurance Company','Insurance & Pensions','ZW','Harare',30,'good','E010'),
 ('C005','Ministry of Finance - Public Accounts Unit','Government & Public Sector','ZW','Harare',60,'slow','E001'),
 ('C006','National Water & Sanitation Authority','Government & Public Sector','ZW','Harare',60,'bad','E010'),
 ('C007','Chimanimani Telecoms Ltd','Telecommunications','ZW','Harare',30,'good','E003'),
 ('C008','Victoria Retail Group Ltd','Retail & FMCG','ZW','Harare',30,'good','E003'),
 ('C009','Midlands Steel Works (Pvt) Ltd','Manufacturing','ZW','Kwekwe',45,'slow','E026'),
 ('C010','Matabeleland Breweries Ltd','Retail & FMCG','ZW','Bulawayo',30,'good','E026'),
 ('C011','Hwange Power & Energy Ltd','Energy & Utilities','ZW','Hwange',45,'slow','E012'),
 ('C012','Pension Fund of Zimbabwe Municipal Workers','Insurance & Pensions','ZW','Harare',30,'good','E011'),
 ('C013','Mutapa Microfinance Bank','Banking & Financial Services','ZW','Harare',30,'good','E012'),
 ('C014','Eastern Highlands Tea Estates','Agriculture & Agro-processing','ZW','Mutare',45,'good','E011'),
 ('C015','Sable Pharmaceuticals (Pvt) Ltd','Healthcare','ZW','Harare',30,'good','E013'),
 ('C016','Limpopo Logistics Ltd','Transport & Logistics','ZW','Beitbridge',30,'slow','E026'),
 ('C017','Zimbabwe Anti-Corruption Trust (NGO)','NGO & Development','ZW','Harare',30,'good','E002'),
 ('C018','Bindura Nickel & Gold Ltd','Mining & Resources','ZW','Bindura',30,'good','E013'),
 ('C019','Savanna Tobacco Merchants','Agriculture & Agro-processing','ZW','Harare',30,'good','E011'),
 ('C020','Harare Stock Brokers Association','Banking & Financial Services','ZW','Harare',30,'good','E003'),
 ('C021','Gauteng Provincial Treasury','Government & Public Sector','ZA','Johannesburg',30,'slow','E014'),
 ('C022','Rand Merchant Credit (Pty) Ltd','Banking & Financial Services','ZA','Johannesburg',30,'good','E014'),
 ('C023','Highveld Platinum Mines (Pty) Ltd','Mining & Resources','ZA','Rustenburg',30,'good','E014'),
 ('C024','Umoja Mobile Money Kenya Ltd','Telecommunications','KE','Nairobi',30,'good','E015'),
 ('C025','Rift Valley Horticulture Exporters','Agriculture & Agro-processing','KE','Naivasha',45,'slow','E015'),
 ('C026','East African Development Fund','NGO & Development','KE','Nairobi',30,'good','E015'),
 ('C027','Thames Commodity Traders Ltd','Mining & Resources','GB','London',30,'good','E016'),
 ('C028','Albion Private Equity LLP','Banking & Financial Services','GB','London',30,'good','E016'),
 ('C029','Gulf Horizon Trading LLC','Retail & FMCG','AE','Dubai',30,'good','E017'),
 ('C030','Emirates Frontier Bank PJSC','Banking & Financial Services','AE','Dubai',30,'good','E017'),
 ('C031','Copperbelt Energy Partners Plc','Energy & Utilities','ZM','Lusaka',45,'slow','E013'),
 ('C032','Kalahari Diamond Traders (Pty) Ltd','Mining & Resources','BW','Gaborone',30,'good','E002'),
 ('C033','Beira Corridor Port Services','Transport & Logistics','MZ','Beira',45,'bad','E010'),
 ('C034','Zimbabwe Electoral Support Programme (UN)','NGO & Development','ZW','Harare',30,'good','E003'),
 ('C035','Masvingo Sugar Estates Ltd','Agriculture & Agro-processing','ZW','Chiredzi',30,'good','E026'),
 ('C036','Hararians Property Fund','Real Estate','ZW','Harare',30,'good','E013'),
 ('C037','Nyanga Medical Group','Healthcare','ZW','Harare',30,'slow','E011'),
 ('C038','African Reinsurance Pool Ltd','Insurance & Pensions','KE','Nairobi',30,'good','E015'),
 ('C039','Sadc Clearing & Settlement House','Banking & Financial Services','ZA','Johannesburg',30,'good','E014'),
 ('C040','Chitungwiza Municipality','Government & Public Sector','ZW','Chitungwiza',60,'bad','E010');

INSERT INTO clients (client_code, legal_name, trading_name, industry_id, status, registration_number, tax_number, vat_number, website, billing_email,
                     phone, address_line1, city, country_code, currency_code, payment_terms_days, credit_limit, account_manager_id, lead_source, notes)
SELECT c.code, c.name, split_part(c.name, ' ', 1) || ' ' || split_part(c.name, ' ', 2), i.industry_id, 'active',
       lpad((row_number() OVER (ORDER BY c.code) * 137)::TEXT, 4, '0') || '/' || (2000 + row_number() OVER (ORDER BY c.code) % 24),
       CASE c.cc WHEN 'ZW' THEN '2000' || lpad((row_number() OVER (ORDER BY c.code) * 7919)::TEXT, 6, '0') END,
       CASE c.cc WHEN 'ZW' THEN '2200' || lpad((row_number() OVER (ORDER BY c.code) * 7919)::TEXT, 5, '0') END,
       'www.' || lower(regexp_replace(split_part(c.name, ' ', 1), '[^A-Za-z]', '', 'g')) || '.example',
       'accounts@' || lower(regexp_replace(split_part(c.name, ' ', 1), '[^A-Za-z]', '', 'g')) || '.example',
       '+000 ' || lpad((row_number() OVER (ORDER BY c.code) * 4441)::TEXT, 7, '0'), 'Head Office', c.city, c.cc, 'USD', c.terms,
       CASE c.behaviour WHEN 'bad' THEN 150000 ELSE 600000 END,
       (SELECT employee_id FROM employees WHERE employee_number = c.manager),
       (ARRAY['Referral','Tender','Existing relationship','Website','Conference'])[1 + (row_number() OVER (ORDER BY c.code))::INT % 5],
       'Payment behaviour: ' || c.behaviour
  FROM seed_clients c JOIN industries i ON i.name = c.industry;

INSERT INTO client_contacts (client_id, first_name, last_name, job_title, email, phone, is_primary, is_billing_contact, is_decision_maker)
SELECT cl.client_id, v.fn, v.ln, v.title, lower(v.fn || '.' || v.ln) || '@' || split_part(cl.billing_email, '@', 2), cl.phone, v.prim, v.bill, v.dm
  FROM clients cl
 CROSS JOIN LATERAL (VALUES
      ((ARRAY['Grace','Peter','Linda','Joseph','Ann','Brian','Esther','Martin'])[1 + cl.client_id::INT % 8],
       (ARRAY['Mutero','Phiri','Govender','Otieno','Hughes','Musariri','Nel','Kamara'])[1 + cl.client_id::INT % 8],
       (ARRAY['Chief Executive Officer','Chief Financial Officer','Head of Internal Audit','Chief Risk Officer'])[1 + cl.client_id::INT % 4], TRUE, FALSE, TRUE),
      ((ARRAY['Rose','Sam','Mary','David','Julia','Kenneth'])[1 + cl.client_id::INT % 6],
       (ARRAY['Chari','Mokoena','Wanjiku','Brown','Dlamini','Moyo'])[1 + (cl.client_id::INT + 3) % 6], 'Accounts Payable Manager', FALSE, TRUE, FALSE)
 ) AS v(fn, ln, title, prim, bill, dm);

-- 33.2 Service catalogue & rate cards -----------------------------------------------------
INSERT INTO services (service_line_id, code, name, default_unit, default_price)
SELECT (SELECT service_line_id FROM service_lines WHERE code = v.sl), v.code, v.name, v.unit, v.price
  FROM (VALUES ('FAI','FAI-INV','Fraud & corruption investigation','hour',NULL), ('FAI','FAI-AUD','Forensic audit','hour',NULL),
               ('FAI','FAI-LIT','Litigation support & expert witness','hour',NULL), ('FAI','FAI-AST','Asset tracing','fixed',25000),
               ('DAA','DAA-FRA','Fraud analytics & continuous monitoring','month',NULL), ('DAA','DAA-BI','BI dashboards & data platform','fixed',NULL),
               ('DAA','DAA-ML','Machine-learning risk scoring model','fixed',60000),
               ('CYB','CYB-DF','Digital forensics (device imaging & analysis)','hour',NULL), ('CYB','CYB-IR','Incident response retainer','month',NULL),
               ('CYB','CYB-PT','Penetration test','fixed',18000), ('CYB','CYB-ISO','ISO 27001 readiness','fixed',35000),
               ('RAS','RAS-IA','Outsourced internal audit','month',NULL), ('RAS','RAS-ERM','Enterprise risk management framework','fixed',30000),
               ('RAS','RAS-AML','AML/CFT compliance review','hour',NULL),
               ('TAX','TAX-DSP','ZIMRA dispute resolution','hour',NULL), ('TAX','TAX-HC','Tax health check','fixed',12000),
               ('TAX','TAX-TP','Transfer pricing documentation','fixed',28000),
               ('FAV','FAV-VAL','Business valuation','fixed',22000), ('FAV','FAV-FDD','Financial due diligence','hour',NULL),
               ('FAV','FAV-IFRS','IFRS 18 / IFRS 16 advisory','hour',NULL)) AS v(sl, code, name, unit, price);

INSERT INTO rate_cards (name, currency_code, valid_from, valid_to, is_default) VALUES
 ('Standard USD rates 2025','USD','2025-01-01','2025-12-31',FALSE), ('Standard USD rates 2026','USD','2026-01-01',NULL,TRUE);
INSERT INTO rate_card_lines (rate_card_id, job_grade_id, hourly_rate, daily_rate)
SELECT rc.rate_card_id, g.job_grade_id, round(g.default_bill_rate * CASE WHEN rc.name LIKE '%2025%' THEN 0.95 ELSE 1 END, 0),
       round(g.default_bill_rate * 8 * CASE WHEN rc.name LIKE '%2025%' THEN 0.95 ELSE 1 END, 0)
  FROM rate_cards rc CROSS JOIN job_grades g WHERE g.level > 0;

-- 33.3 Projects ---------------------------------------------------------------------------
CREATE TEMP TABLE seed_projects (code TEXT, name TEXT, client TEXT, sl TEXT, office TEXT, btype TEXT, start DATE, finish DATE,
                                 final_status TEXT, fees NUMERIC, team INT, tax TEXT, priority TEXT);
INSERT INTO seed_projects VALUES
 ('P25-001','Procurement fraud investigation - mine supply contracts','C001','FAI','HRE','time_and_materials','2025-10-06','2026-06-30','completed',420000,5,'ZW-VAT','high'),
 ('P25-002','Forensic audit of loan book write-offs','C002','FAI','HRE','time_and_materials','2025-11-03','2026-04-30','completed',260000,4,'ZW-VAT','high'),
 ('P25-003','Outsourced internal audit FY2026','C004','RAS','HRE','retainer','2025-11-01','2026-12-31','active',264000,3,'ZW-VAT','medium'),
 ('P25-004','Continuous transaction monitoring platform','C007','DAA','HRE','milestone','2025-09-15','2026-10-31','active',380000,5,'ZW-VAT','high'),
 ('P25-005','Public finance management forensic review','C005','FAI','HRE','time_and_materials','2025-10-13','2026-12-18','active',520000,5,'ZW-VAT','critical'),
 ('P25-006','Tax dispute - ZIMRA transfer pricing assessment','C014','TAX','HRE','time_and_materials','2025-11-10','2026-05-29','completed',145000,3,'ZW-VAT','high'),
 ('P25-007','Valuation for rights issue','C018','FAV','HRE','fixed_fee','2025-11-17','2026-02-27','completed',95000,3,'ZW-VAT','medium'),
 ('P25-008','Incident response retainer','C013','CYB','HRE','retainer','2025-10-01','2026-09-30','active',144000,2,'ZW-VAT','high'),
 ('P25-009','Payroll ghost-worker analytics','C040','DAA','HRE','time_and_materials','2025-11-24','2026-07-31','completed',150000,3,'ZW-VAT','medium'),
 ('P25-010','Internal audit co-source - Bulawayo operations','C010','RAS','BYO','retainer','2025-10-01','2026-12-31','active',168000,3,'ZW-VAT','medium'),
 ('P26-011','Asset tracing - misappropriated fuel stocks','C016','FAI','BYO','time_and_materials','2026-01-12','2026-08-28','completed',135000,3,'ZW-VAT','high'),
 ('P26-012','AML/CFT compliance review & RBZ remediation','C013','RAS','HRE','time_and_materials','2026-01-19','2026-06-26','completed',118000,3,'ZW-VAT','high'),
 ('P26-013','Digital forensics - executive email leak','C008','CYB','HRE','time_and_materials','2026-02-02','2026-04-30','completed',88000,3,'ZW-VAT','critical'),
 ('P26-014','Fraud risk scoring model (machine learning)','C002','DAA','HRE','milestone','2026-02-09','2026-11-30','active',240000,4,'ZW-VAT','high'),
 ('P26-015','Water billing revenue-leakage investigation','C006','FAI','HRE','time_and_materials','2026-02-16','2026-10-30','active',210000,4,'ZW-VAT','high'),
 ('P26-016','ISO 27001 readiness & penetration test','C020','CYB','HRE','fixed_fee','2026-03-02','2026-08-28','completed',72000,3,'ZW-VAT','medium'),
 ('P26-017','Tax health check & VAT recovery review','C019','TAX','HRE','fixed_fee','2026-03-09','2026-06-30','completed',42000,2,'ZW-VAT','medium'),
 ('P26-018','Enterprise risk management framework','C012','RAS','HRE','fixed_fee','2026-03-16','2026-09-30','active',68000,3,'ZW-VAT','medium'),
 ('P26-019','Financial due diligence - acquisition of distributor','C015','FAV','HRE','time_and_materials','2026-03-23','2026-06-19','completed',96000,3,'ZW-VAT','high'),
 ('P26-020','Donor-funds forensic audit','C017','FAI','HRE','time_and_materials','2026-04-06','2026-09-30','active',98000,3,'ZERO','medium'),
 ('P26-021','Procurement analytics dashboard (Power BI)','C011','DAA','HRE','fixed_fee','2026-04-13','2026-09-30','active',85000,3,'ZW-VAT','medium'),
 ('P26-022','Steel inventory shrinkage investigation','C009','FAI','BYO','time_and_materials','2026-04-20','2026-10-30','active',125000,3,'ZW-VAT','high'),
 ('P26-023','Transfer pricing documentation 2025','C001','TAX','HRE','fixed_fee','2026-05-04','2026-08-28','completed',56000,2,'ZW-VAT','medium'),
 ('P26-024','Revenue assurance review - mobile money','C007','RAS','HRE','time_and_materials','2026-05-11','2026-11-27','active',142000,3,'ZW-VAT','high'),
 ('P26-025','Cyber incident - ransomware recovery & forensics','C011','CYB','HRE','time_and_materials','2026-06-01','2026-09-30','active',112000,3,'ZW-VAT','critical'),
 ('P26-026','IFRS 18 transition advisory','C004','FAV','HRE','time_and_materials','2026-06-08','2026-12-18','active',84000,2,'ZW-VAT','medium'),
 ('P26-027','Sugar out-grower payments audit','C035','RAS','BYO','time_and_materials','2026-06-15','2026-10-30','active',76000,2,'ZW-VAT','medium'),
 ('P26-028','Election-support procurement review','C034','FAI','HRE','time_and_materials','2026-07-06','2026-12-18','active',115000,3,'ZERO','high'),
 ('P26-029','Property fund valuation (IFRS 13)','C036','FAV','HRE','fixed_fee','2026-07-13','2026-10-16','active',48000,2,'ZW-VAT','medium'),
 ('P26-030','Medical aid claims fraud analytics','C037','DAA','HRE','time_and_materials','2026-08-03','2026-12-18','active',92000,3,'ZW-VAT','medium'),
 ('P25-031','Provincial treasury forensic investigation','C021','FAI','JNB','time_and_materials','2025-11-03','2026-09-30','active',310000,4,'ZA-VAT','high'),
 ('P26-032','Credit-fraud analytics programme','C022','DAA','JNB','time_and_materials','2026-01-19','2026-10-30','active',190000,3,'ZA-VAT','high'),
 ('P26-033','Platinum royalty dispute - litigation support','C023','FAI','JNB','time_and_materials','2026-03-02','2026-09-30','active',145000,3,'ZA-VAT','high'),
 ('P26-034','Settlement-system cyber assessment','C039','CYB','JNB','fixed_fee','2026-05-04','2026-08-28','completed',65000,2,'ZA-VAT','medium'),
 ('P25-035','Mobile-money fraud detection models','C024','DAA','NBO','time_and_materials','2025-11-10','2026-10-30','active',230000,4,'KE-VAT','high'),
 ('P26-036','Grant compliance internal audit','C026','RAS','NBO','retainer','2026-01-01','2026-12-31','active',108000,2,'ZERO','medium'),
 ('P26-037','Export proceeds forensic review','C025','FAI','NBO','time_and_materials','2026-03-09','2026-07-31','completed',78000,2,'KE-VAT','medium'),
 ('P26-038','Reinsurance claims analytics','C038','DAA','NBO','time_and_materials','2026-06-01','2026-11-27','active',88000,2,'ZERO','medium'),
 ('P25-039','Commodity trade-finance fraud investigation','C027','FAI','LON','time_and_materials','2025-11-17','2026-08-28','completed',360000,3,'GB-VAT','critical'),
 ('P26-040','Buy-side due diligence - African fintech','C028','FAV','LON','time_and_materials','2026-02-02','2026-05-29','completed',210000,3,'GB-VAT','high'),
 ('P26-041','Portfolio company valuations Q2-Q4','C028','FAV','LON','milestone','2026-06-01','2026-12-18','active',150000,2,'GB-VAT','medium'),
 ('P26-042','Trade-based money laundering review','C029','FAI','DXB','time_and_materials','2026-01-12','2026-08-28','completed',185000,3,'AE-VAT','high'),
 ('P26-043','Bank cyber forensics & insider threat','C030','CYB','DXB','time_and_materials','2026-04-06','2026-12-18','active',160000,2,'AE-VAT','high'),
 ('P26-044','Hydro concession forensic audit (Zambia)','C031','FAI','HRE','time_and_materials','2026-02-23','2026-09-30','active',175000,3,'ZERO','high'),
 ('P26-045','Diamond sales-channel analytics (Botswana)','C032','DAA','HRE','time_and_materials','2026-03-16','2026-10-30','active',120000,3,'ZERO','medium'),
 ('P26-046','Port concession revenue audit (Mozambique)','C033','RAS','HRE','time_and_materials','2026-02-09','2026-07-31','completed',94000,2,'ZERO','medium'),
 ('P26-047','Tobacco auction floor tax review','C019','TAX','HRE','time_and_materials','2026-07-20','2026-11-27','active',46000,2,'ZW-VAT','low'),
 ('P26-048','Brewery excise & VAT dispute','C010','TAX','BYO','time_and_materials','2026-05-18','2026-10-30','active',38000,1,'ZW-VAT','medium');

INSERT INTO projects (project_code, name, description, client_id, service_line_id, project_manager_id, engagement_partner_id, office_id, status,
                      billing_type, is_internal, start_date, planned_end_date, currency_code, budget_hours, budget_fees, budget_expenses,
                      budget_cost, completion_pct, priority)
SELECT p.code, p.name, p.name || ' for ' || c.legal_name, c.client_id, sl.service_line_id,
       -- engagement manager: a manager/senior manager of the practice in the delivering office (or the branch head)
       COALESCE((SELECT e.employee_id FROM employees e JOIN job_grades g USING (job_grade_id)
                  WHERE e.department_id = sl.department_id AND e.office_id = o.office_id AND g.level IN (4,5)
                  ORDER BY (e.employee_id + length(p.code) + ascii(right(p.code,1))) % 5, e.employee_id LIMIT 1),
                o.manager_employee_id),
       CASE WHEN o.code = 'HRE' THEN (SELECT head_employee_id FROM departments WHERE department_id = sl.department_id) ELSE o.manager_employee_id END,
       o.office_id, 'active', p.btype::contract_type, FALSE, p.start, p.finish, 'USD',
       round(p.fees / 140, 0), p.fees, round(p.fees * 0.04, 0), round(p.fees * 0.45, 0), 0, p.priority::priority_level
  FROM seed_projects p JOIN clients c ON c.client_code = p.client JOIN service_lines sl ON sl.code = p.sl JOIN offices o ON o.code = p.office;

-- internal projects (non-billable)
INSERT INTO projects (project_code, name, client_id, service_line_id, project_manager_id, office_id, status, billing_type, is_internal, start_date, planned_end_date)
VALUES ('INT-26-BD','Business development & proposals 2026', NULL, NULL, (SELECT employee_id FROM employees WHERE employee_number='E020'),
        (SELECT office_id FROM offices WHERE code='HRE'), 'active', 'time_and_materials', TRUE, '2026-01-01', '2026-12-31'),
       ('INT-26-KM','Methodology, tools & knowledge management 2026', NULL, NULL, (SELECT employee_id FROM employees WHERE employee_number='E023'),
        (SELECT office_id FROM offices WHERE code='HRE'), 'active', 'time_and_materials', TRUE, '2026-01-01', '2026-12-31');

-- contracts for every client project
INSERT INTO contracts (contract_number, client_id, title, contract_type, status, start_date, end_date, currency_code, contract_value, rate_card_id,
                       payment_terms_days, billing_frequency, retainer_hours_per_month, retainer_fee_per_month, signed_date, client_signatory, firm_signatory_id)
SELECT 'ENG-' || p.project_code, p.client_id, p.name, p.billing_type, 'active', p.start_date, p.planned_end_date, 'USD', p.budget_fees,
       (SELECT rate_card_id FROM rate_cards WHERE is_default), c.payment_terms_days,
       CASE p.billing_type WHEN 'milestone' THEN 'milestone' WHEN 'fixed_fee' THEN 'milestone' ELSE 'monthly' END,
       CASE WHEN p.billing_type = 'retainer' THEN 80 END,
       CASE WHEN p.billing_type = 'retainer'
            THEN round(p.budget_fees / GREATEST((extract(year FROM age(p.planned_end_date, p.start_date)) * 12 + extract(month FROM age(p.planned_end_date, p.start_date)) + 1), 1), 0) END,
       p.start_date - 7, (SELECT first_name || ' ' || last_name FROM client_contacts WHERE client_id = p.client_id AND is_primary),
       p.engagement_partner_id
  FROM projects p JOIN clients c ON c.client_id = p.client_id WHERE NOT p.is_internal;
UPDATE projects p SET contract_id = ct.contract_id FROM contracts ct WHERE ct.contract_number = 'ENG-' || p.project_code;

-- milestones for fixed-fee / milestone engagements (evenly spread over the engagement)
INSERT INTO contract_milestones (contract_id, seq, name, due_date, amount)
SELECT ct.contract_id, m.seq, m.name,
       (ct.start_date + ((ct.end_date - ct.start_date) * m.pct_time)::INT)::DATE, round(ct.contract_value * m.pct_fee, 2)
  FROM contracts ct
 CROSS JOIN (VALUES (1, 'Mobilisation & inception report', 0.10, 0.25), (2, 'Fieldwork / build complete', 0.55, 0.40),
                    (3, 'Final report / go-live & sign-off', 1.00, 0.35)) AS m(seq, name, pct_time, pct_fee)
 WHERE ct.contract_type IN ('fixed_fee','milestone');

-- phases & tasks
INSERT INTO project_phases (project_id, seq, name, start_date, end_date, budget_hours, status)
SELECT p.project_id, ph.seq, ph.name, p.start_date + ((p.planned_end_date - p.start_date) * ph.s)::INT,
       p.start_date + ((p.planned_end_date - p.start_date) * ph.e)::INT, round(p.budget_hours * (ph.e - ph.s)), 'active'
  FROM projects p CROSS JOIN (VALUES (1,'Planning & scoping',0,0.15), (2,'Fieldwork & analysis',0.15,0.80), (3,'Reporting & close-out',0.80,1.0)) AS ph(seq, name, s, e)
 WHERE NOT p.is_internal;

INSERT INTO tasks (project_id, phase_id, name, status, priority, estimated_hours, start_date, due_date, is_billable)
SELECT ph.project_id, ph.phase_id, t.name, 'todo', 'medium', 40, ph.start_date, ph.end_date, TRUE
  FROM project_phases ph
  JOIN LATERAL (SELECT unnest(CASE ph.seq WHEN 1 THEN ARRAY['Kick-off meeting & data request','Risk assessment & work plan']
                                          WHEN 2 THEN ARRAY['Data extraction & analytics','Interviews & document review','Findings working papers']
                                          ELSE ARRAY['Draft report & QRM review','Client presentation & final report'] END) AS name) t ON TRUE;

-- 33.4 Teams: manager + partner + consultants of the practice (same office first, then any office)
INSERT INTO project_members (project_id, employee_id, project_role, start_date, end_date, allocation_pct)
SELECT p.project_id, p.project_manager_id, 'Engagement Manager', p.start_date, p.planned_end_date, 50 FROM projects p WHERE NOT p.is_internal
UNION
SELECT p.project_id, p.engagement_partner_id, 'Engagement Partner', p.start_date, p.planned_end_date, 10 FROM projects p
 WHERE NOT p.is_internal AND p.engagement_partner_id <> p.project_manager_id;

INSERT INTO project_members (project_id, employee_id, project_role, start_date, end_date, allocation_pct)
SELECT x.project_id, x.employee_id, CASE WHEN x.level = 3 THEN 'Senior Consultant' WHEN x.level = 2 THEN 'Consultant' ELSE 'Analyst' END,
       x.start_date, x.planned_end_date, 80
  FROM (SELECT p.project_id, p.start_date, p.planned_end_date, e.employee_id, g.level, sp.team,
               row_number() OVER (PARTITION BY p.project_id
                                  ORDER BY (e.office_id = p.office_id) DESC,
                                           (SELECT count(*) FROM project_members pm WHERE pm.employee_id = e.employee_id),
                                           (e.employee_id * 7 + p.project_id * 13) % 11) AS rn
          FROM projects p
          JOIN seed_projects sp ON sp.code = p.project_code
          JOIN service_lines sl ON sl.service_line_id = p.service_line_id
          JOIN employees e ON e.is_billable AND (e.department_id = sl.department_id OR e.office_id = p.office_id AND p.office_id <> (SELECT office_id FROM offices WHERE is_head_office))
          JOIN job_grades g ON g.job_grade_id = e.job_grade_id AND g.level BETWEEN 1 AND 3
         WHERE e.hire_date < p.planned_end_date
       ) x
 WHERE x.rn <= x.team
ON CONFLICT DO NOTHING;

-- make sure every fee earner has at least one engagement (bench staff join the largest active project of their practice)
INSERT INTO project_members (project_id, employee_id, project_role, start_date, end_date, allocation_pct)
SELECT DISTINCT ON (e.employee_id) p.project_id, e.employee_id, 'Consultant', GREATEST(p.start_date, e.hire_date), p.planned_end_date, 60
  FROM employees e JOIN job_grades g USING (job_grade_id)
  JOIN projects p ON NOT p.is_internal AND p.service_line_id = e.service_line_id
 WHERE e.is_billable AND NOT EXISTS (SELECT 1 FROM project_members pm WHERE pm.employee_id = e.employee_id)
 ORDER BY e.employee_id, (p.office_id = e.office_id) DESC, p.budget_fees DESC
ON CONFLICT DO NOTHING;

-- everyone may book internal time
INSERT INTO project_members (project_id, employee_id, project_role, start_date, end_date, allocation_pct)
SELECT p.project_id, e.employee_id, 'Contributor', '2026-01-01', '2026-12-31', 5
  FROM projects p CROSS JOIN employees e WHERE p.is_internal AND e.is_billable;

-- 33.5 CRM pipeline -----------------------------------------------------------------------
INSERT INTO leads (company_name, contact_name, email, industry_id, source, estimated_value, status, owner_id, notes, created_at)
SELECT v.co, v.contact, v.email, (SELECT industry_id FROM industries WHERE name = v.ind), v.src, v.val, v.status,
       (SELECT employee_id FROM employees WHERE employee_number = v.owner), v.notes, v.created::TIMESTAMPTZ
  FROM (VALUES
   ('Karoi Grain Marketing Co-op','Tafara Mashingaidze','tafara@karoigrain.example','Agriculture & Agro-processing','Referral',65000,'qualified','E020','Suspected side-selling; needs forensic review','2026-08-11'),
   ('Mazowe Gold Refiners','Janet Ruzvidzo','janet@mazowegold.example','Mining & Resources','Conference',140000,'contacted','E002','Met at ICAZ Winter School','2026-08-25'),
   ('Lusaka Water Utility','Chanda Mwape','cmwape@lwsc.example','Energy & Utilities','Tender',210000,'new','E013','Public tender - revenue assurance','2026-09-15'),
   ('Nairobi County Revenue Board','Peter Kiprotich','pkiprotich@ncrb.example','Government & Public Sector','Tender',180000,'qualified','E015','Analytics for revenue collection','2026-07-28'),
   ('Sandton Asset Managers','Nomsa Ndaba','nomsa@sam.example','Banking & Financial Services','Website',55000,'contacted','E014','Cyber due diligence','2026-09-02'),
   ('Mutare Timber Holdings','Kuda Chipunza','kuda@mth.example','Manufacturing','Referral',38000,'disqualified','E026','Budget not approved','2026-05-19'),
   ('Dubai Gold Souk Traders','Imran Sheikh','imran@dgst.example','Retail & FMCG','Existing relationship',120000,'qualified','E017','AML review for DMCC licence','2026-08-30'),
   ('Harare Polytechnic Pension Fund','Grace Mudenda','grace@hppf.example','Insurance & Pensions','Referral',46000,'new','E011','Tax & investment compliance review','2026-09-21')
  ) AS v(co, contact, email, ind, src, val, status, owner, notes, created);

INSERT INTO opportunities (opportunity_code, client_id, name, service_line_id, stage, probability_pct, estimated_value, expected_close_date,
                           actual_close_date, owner_id, competitor, lost_reason)
SELECT v.code, (SELECT client_id FROM clients WHERE client_code = v.client), v.name, (SELECT service_line_id FROM service_lines WHERE code = v.sl),
       v.stage::opportunity_stage, v.prob, v.val, v.close::DATE, v.actual::DATE, (SELECT employee_id FROM employees WHERE employee_number = v.owner), v.comp, v.lost
  FROM (VALUES
   ('OPP-26-001','C001','Group-wide fraud risk assessment 2027','FAI','proposal',50,280000,'2026-10-30',NULL,'E002','Big-4 firm',NULL),
   ('OPP-26-002','C002','Anti-fraud analytics phase 2','DAA','negotiation',75,210000,'2026-10-15',NULL,'E003',NULL,NULL),
   ('OPP-26-003','C005','Treasury single account forensic audit','FAI','qualification',25,450000,'2026-12-15',NULL,'E001','Auditor-General team',NULL),
   ('OPP-26-004','C007','SOC-as-a-service (managed detection)','CYB','proposal',40,180000,'2026-11-20',NULL,'E012',NULL,NULL),
   ('OPP-26-005','C012','Outsourced internal audit 2027-2029','RAS','negotiation',70,390000,'2026-10-31',NULL,'E010',NULL,NULL),
   ('OPP-26-006','C022','Model validation & credit-risk analytics','DAA','proposal',45,160000,'2026-11-06',NULL,'E014',NULL,NULL),
   ('OPP-26-007','C024','Agent-network fraud investigation','FAI','qualification',30,120000,'2026-12-04',NULL,'E015',NULL,NULL),
   ('OPP-26-008','C028','Fintech portfolio IFRS 18 readiness','FAV','proposal',55,95000,'2026-10-23',NULL,'E016',NULL,NULL),
   ('OPP-26-009','C030','Insider-threat programme design','CYB','won',100,140000,'2026-03-31','2026-03-28','E017',NULL,NULL),
   ('OPP-26-010','C015','Post-acquisition integration audit','FAV','won',100,96000,'2026-03-20','2026-03-18','E013',NULL,NULL),
   ('OPP-26-011','C009','Cost-reduction diagnostic','FAV','lost',0,70000,'2026-05-29','2026-05-27','E026','Local boutique firm','Price - competitor 30% cheaper'),
   ('OPP-26-012','C016','Fleet telematics analytics','DAA','lost',0,55000,'2026-06-30','2026-06-22','E026',NULL,'Client postponed the project to 2027'),
   ('OPP-26-013','C031','Hydro concession phase 2','FAI','negotiation',65,160000,'2026-10-20',NULL,'E013',NULL,NULL),
   ('OPP-26-014','C034','Results-management system audit','CYB','proposal',35,130000,'2026-11-27',NULL,'E012','International firm',NULL),
   ('OPP-26-015','C038','Claims-fraud analytics roll-out (6 countries)','DAA','qualification',20,300000,'2027-01-29',NULL,'E015',NULL,NULL)
  ) AS v(code, client, name, sl, stage, prob, val, close, actual, owner, comp, lost);

INSERT INTO crm_activities (activity_type, subject, details, activity_date, client_id, opportunity_id, employee_id, follow_up_date, is_completed)
SELECT (ARRAY['meeting','call','email','presentation'])[1 + (o.opportunity_id % 4)::INT],
       'Follow-up: ' || o.name, 'Discussed scope, timelines and fees.', '2026-09-24 10:00+02'::TIMESTAMPTZ - make_interval(days => (o.opportunity_id * 3 % 40)::INT),
       o.client_id, o.opportunity_id, o.owner_id, '2026-09-24'::DATE + (o.opportunity_id % 14)::INT, o.stage IN ('won','lost')
  FROM opportunities o;
