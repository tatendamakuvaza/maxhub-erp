
/* =====================================================================================
   31. SEED - OFFICES, DEPARTMENTS, ~170 EMPLOYEES, BANK ACCOUNTS, LOGINS
   -------------------------------------------------------------------------------------
   Every employee gets a company e-mail firstname.lastname@maxhub.co.zw and a login with
   the same username.  DEMO PASSWORD FOR EVERY USER:  Maxhub@2026
   (change it after the first login - Account page, or ask IT to force a reset).
   ===================================================================================== */

-- 31.1 Offices / branches ----------------------------------------------------------------
INSERT INTO offices (code, name, office_type, occupancy, address_line1, address_line2, city, country_code,
                     functional_currency, tax_jurisdiction, phone, email, timezone, opened_date, is_head_office) VALUES
 ('HRE','Harare Head Office','head_office','owned','Maxhub House, 45 Enterprise Road','Highlands','Harare','ZW','USD','ZIMRA','+263 242 700 100','harare@maxhub.co.zw','Africa/Harare','2012-06-01',TRUE),
 ('BYO','Bulawayo Office','branch','owned','Maxhub Centre, 88 Jason Moyo Street','City Centre','Bulawayo','ZW','USD','ZIMRA','+263 292 880 100','bulawayo@maxhub.co.zw','Africa/Harare','2015-02-01',FALSE),
 ('JNB','Johannesburg Branch','branch','leased','140 West Street, 9th Floor','Sandton','Johannesburg','ZA','ZAR','SARS','+27 10 500 4100','johannesburg@maxhub.co.zw','Africa/Johannesburg','2018-07-01',FALSE),
 ('NBO','Nairobi Branch','branch','leased','Westlands Square, 7th Floor, Ring Road','Westlands','Nairobi','KE','KES','KRA','+254 20 450 7100','nairobi@maxhub.co.zw','Africa/Nairobi','2021-03-01',FALSE),
 ('LON','London Branch','branch','leased','1 Minster Court, Mincing Lane, 4th Floor','City of London','London','GB','GBP','HMRC','+44 20 3900 4100','london@maxhub.co.zw','Europe/London','2023-01-09',FALSE),
 ('DXB','Dubai Branch','branch','leased','Gate Village 5, Level 3','DIFC','Dubai','AE','AED','UAEFTA','+971 4 500 4100','dubai@maxhub.co.zw','Asia/Dubai','2024-02-01',FALSE);

-- 31.2 Departments & service lines --------------------------------------------------------
INSERT INTO departments (code, name, division, office_id, cost_center_code, email, phone_extension, description, is_revenue_generating)
SELECT v.code, v.name, v.div, (SELECT office_id FROM offices WHERE code = 'HRE'), v.cc, v.email, v.ext, v.descr, v.rev
  FROM (VALUES
   ('EXE','Executive Office','Leadership','CC100','executive@maxhub.co.zw','100','CEO, COO and executive support',FALSE),
   ('FAI','Forensic Audit & Investigations','Client Service','CC200','forensics@maxhub.co.zw','200','Fraud investigations, forensic audits, litigation support, asset tracing',TRUE),
   ('DAA','Data Analytics & AI','Client Service','CC210','analytics@maxhub.co.zw','210','Fraud analytics, continuous monitoring, BI dashboards, machine learning',TRUE),
   ('CYB','Cybersecurity & Digital Forensics','Client Service','CC220','cyber@maxhub.co.zw','220','Digital forensics lab, incident response, penetration testing, ISO 27001',TRUE),
   ('RAS','Risk Advisory & Internal Audit','Client Service','CC230','risk@maxhub.co.zw','230','Outsourced internal audit, ERM, AML/CFT, governance reviews',TRUE),
   ('TAX','Tax Advisory','Client Service','CC240','tax@maxhub.co.zw','240','ZIMRA disputes, tax health checks, transfer pricing, tax compliance outsourcing',TRUE),
   ('FAV','Financial Advisory & Valuations','Client Service','CC250','advisory@maxhub.co.zw','250','Valuations, due diligence, IFRS advisory, restructuring',TRUE),
   ('FIN','Finance & Accounting','Business Support','CC300','finance@maxhub.co.zw','300','Financial reporting, billing, payables, treasury, tax compliance, payroll accounting',FALSE),
   ('HRM','Human Resources','Business Support','CC310','hr@maxhub.co.zw','310','Recruitment, payroll, performance, learning & development',FALSE),
   ('ICT','Information Technology','Business Support','CC320','itsupport@maxhub.co.zw','320','Infrastructure, service desk, ERP administration, information security',FALSE),
   ('MBD','Marketing & Business Development','Business Support','CC330','marketing@maxhub.co.zw','330','Brand, bids & proposals, client relationship programmes',FALSE),
   ('PRC','Procurement & Supply Chain','Business Support','CC340','procurement@maxhub.co.zw','340','Sourcing, supplier management, PRAZ compliance',FALSE),
   ('FAC','Facilities & Administration','Business Support','CC350','facilities@maxhub.co.zw','350','Buildings, fleet, reception, security, office services',FALSE),
   ('LEG','Legal & Company Secretarial','Governance','CC400','legal@maxhub.co.zw','400','Contracts, board secretariat, regulatory compliance',FALSE),
   ('QRM','Quality & Risk Management','Governance','CC410','quality@maxhub.co.zw','410','Engagement quality reviews, independence, ISQM 1',FALSE),
   ('IAU','Internal Audit','Governance','CC420','internalaudit@maxhub.co.zw','420','Independent assurance to the Audit Committee',FALSE)
  ) AS v(code, name, div, cc, email, ext, descr, rev);

INSERT INTO service_lines (code, name, description, department_id, revenue_target)
SELECT d.code, v.name, v.descr, d.department_id, v.target
  FROM (VALUES ('FAI','Forensic Audit & Investigations','Fraud & corruption investigations, forensic audits, expert witness', 5500000),
               ('DAA','Data Analytics & AI','Fraud analytics, data platforms, dashboards, AI models', 3800000),
               ('CYB','Cybersecurity & Digital Forensics','Digital evidence, incident response, cyber assurance', 2600000),
               ('RAS','Risk Advisory & Internal Audit','Internal audit co-sourcing, ERM, AML/CFT', 3200000),
               ('TAX','Tax Advisory','ZIMRA disputes, tax reviews, transfer pricing', 1900000),
               ('FAV','Financial Advisory & Valuations','Valuations, due diligence, IFRS advisory', 2000000)) AS v(code, name, descr, target)
  JOIN departments d ON d.code = v.code;

INSERT INTO job_grades (code, name, level, currency_code, min_salary, max_salary, default_cost_rate, default_bill_rate, target_utilization_pct) VALUES
 ('SUP','Business Support',    0, 'USD',   7000,  30000,  10,   0,  0),
 ('AN', 'Analyst',             1, 'USD',  10000,  15000,  11,  75, 85),
 ('CON','Consultant',          2, 'USD',  16000,  24000,  16, 110, 80),
 ('SC', 'Senior Consultant',   3, 'USD',  26000,  36000,  23, 145, 80),
 ('MGR','Manager',             4, 'USD',  40000,  52000,  34, 190, 70),
 ('SM', 'Senior Manager',      5, 'USD',  55000,  70000,  45, 240, 65),
 ('DIR','Director',            6, 'USD',  75000, 100000,  60, 300, 50),
 ('PTR','Partner',             7, 'USD', 110000, 170000,  90, 380, 40);

-- 31.3 Employees --------------------------------------------------------------------------
-- (a) named leadership team & key demo users
CREATE TEMP TABLE seed_people (num TEXT, fn TEXT, ln TEXT, gender TEXT, grade TEXT, title TEXT, dept TEXT, office TEXT, hire DATE);
INSERT INTO seed_people VALUES
 ('E001','Tendai','Moyo','Male','PTR','Managing Partner & Chief Executive Officer','EXE','HRE','2012-06-01'),
 ('E002','Rutendo','Chikore','Female','PTR','Partner - Forensic Audit & Investigations','FAI','HRE','2013-01-15'),
 ('E003','Farai','Ndlovu','Male','DIR','Director - Data Analytics & AI','DAA','HRE','2016-06-01'),
 ('E004','Nyasha','Mutasa','Female','MGR','Manager - Forensic Audit','FAI','HRE','2019-02-01'),
 ('E005','Kudakwashe','Banda','Male','CON','Consultant - Forensic Audit','FAI','HRE','2023-03-01'),
 ('E006','Blessing','Marufu','Female','DIR','Chief Financial Officer','FIN','HRE','2014-02-01'),
 ('E007','Chipo','Sibanda','Female','SM','Human Resources Director','HRM','HRE','2015-08-01'),
 ('E008','Tawanda','Gumbo','Male','MGR','IT Manager & ERP System Administrator','ICT','HRE','2017-05-02'),
 ('E009','Memory','Nkomo','Female','MGR','Tax Compliance Manager','FIN','HRE','2018-09-03'),
 ('E010','Simbarashe','Chiweshe','Male','PTR','Partner - Risk Advisory','RAS','HRE','2014-04-01'),
 ('E011','Thandiwe','Ncube','Female','PTR','Partner - Tax Advisory','TAX','HRE','2015-01-12'),
 ('E012','Tatenda','Mhlanga','Male','DIR','Director - Cybersecurity & Digital Forensics','CYB','HRE','2017-10-02'),
 ('E013','Rumbidzai','Makoni','Female','DIR','Director - Financial Advisory & Valuations','FAV','HRE','2016-03-01'),
 ('E014','Sipho','Mokoena','Male','DIR','Branch Director - Johannesburg','FAI','JNB','2018-07-01'),
 ('E015','Wanjiru','Kamau','Female','DIR','Branch Director - Nairobi','DAA','NBO','2021-03-01'),
 ('E016','Oliver','Thompson','Male','DIR','Branch Director - London','FAV','LON','2023-01-09'),
 ('E017','Omar','Haddad','Male','DIR','Branch Director - Dubai','FAI','DXB','2024-02-01'),
 ('E018','Mufaro','Chigumba','Male','PTR','Chief Operating Officer','EXE','HRE','2013-06-03'),
 ('E019','Ruvimbo','Zvobgo','Female','SM','Company Secretary & Head of Legal','LEG','HRE','2016-11-01'),
 ('E020','Tinashe','Mapfumo','Male','SM','Head of Marketing & Business Development','MBD','HRE','2017-02-06'),
 ('E021','Vimbai','Hove','Female','MGR','Procurement Manager','PRC','HRE','2019-06-03'),
 ('E022','Tapiwa','Mlambo','Male','MGR','Facilities & Administration Manager','FAC','HRE','2016-08-01'),
 ('E023','Fadzai','Madziva','Female','SM','Head of Quality & Risk Management','QRM','HRE','2018-01-08'),
 ('E024','Munyaradzi','Mandaza','Male','SM','Head of Internal Audit','IAU','HRE','2019-04-01'),
 ('E025','Chiedza','Mushonga','Female','SM','Financial Controller','FIN','HRE','2017-07-03'),
 ('E026','Nokuthula','Tshuma','Female','DIR','Office Head - Bulawayo','RAS','BYO','2015-02-01');

-- (b) the rest of the firm: department, office, grade, head-count
CREATE TEMP TABLE seed_headcount (dept TEXT, office TEXT, grade TEXT, n INT);
INSERT INTO seed_headcount VALUES
 ('FAI','HRE','SM',2), ('FAI','HRE','MGR',2), ('FAI','HRE','SC',4), ('FAI','HRE','CON',4), ('FAI','HRE','AN',4),
 ('DAA','HRE','SM',1), ('DAA','HRE','MGR',2), ('DAA','HRE','SC',4), ('DAA','HRE','CON',4), ('DAA','HRE','AN',4),
 ('CYB','HRE','SM',1), ('CYB','HRE','MGR',1), ('CYB','HRE','SC',3), ('CYB','HRE','CON',3), ('CYB','HRE','AN',2),
 ('RAS','HRE','SM',1), ('RAS','HRE','MGR',2), ('RAS','HRE','SC',3), ('RAS','HRE','CON',3), ('RAS','HRE','AN',3),
 ('TAX','HRE','SM',1), ('TAX','HRE','MGR',1), ('TAX','HRE','SC',2), ('TAX','HRE','CON',3), ('TAX','HRE','AN',2),
 ('FAV','HRE','MGR',1), ('FAV','HRE','SC',2), ('FAV','HRE','CON',2), ('FAV','HRE','AN',1),
 ('FIN','HRE','MGR',1), ('FIN','HRE','SUP',6), ('HRM','HRE','MGR',1), ('HRM','HRE','SUP',4),
 ('ICT','HRE','SUP',5), ('LEG','HRE','SUP',2), ('MBD','HRE','MGR',1), ('MBD','HRE','SUP',3),
 ('PRC','HRE','SUP',2), ('FAC','HRE','SUP',5), ('QRM','HRE','SUP',1), ('IAU','HRE','SUP',1), ('EXE','HRE','SUP',2),
 ('RAS','BYO','MGR',1), ('RAS','BYO','SC',2), ('RAS','BYO','CON',2), ('RAS','BYO','AN',1),
 ('FAI','BYO','SC',1), ('FAI','BYO','CON',2), ('FAI','BYO','AN',1), ('TAX','BYO','CON',1), ('FIN','BYO','SUP',1), ('FAC','BYO','SUP',1),
 ('FAI','JNB','MGR',1), ('FAI','JNB','SC',1), ('FAI','JNB','CON',2), ('FAI','JNB','AN',1),
 ('DAA','JNB','SC',1), ('DAA','JNB','CON',1), ('CYB','JNB','CON',1), ('FIN','JNB','SUP',1), ('FAC','JNB','SUP',1),
 ('DAA','NBO','MGR',1), ('DAA','NBO','SC',1), ('DAA','NBO','CON',2), ('DAA','NBO','AN',1),
 ('RAS','NBO','SC',1), ('RAS','NBO','CON',1), ('FIN','NBO','SUP',1),
 ('FAV','LON','MGR',1), ('FAV','LON','SC',1), ('FAV','LON','CON',1), ('FAI','LON','SC',1), ('MBD','LON','SUP',1),
 ('FAI','DXB','MGR',1), ('FAI','DXB','SC',1), ('FAI','DXB','CON',1), ('CYB','DXB','CON',1), ('FIN','DXB','SUP',1);

DO $$
DECLARE
    zw_f TEXT[] := ARRAY['Tatenda','Rudo','Farai','Chipo','Tafadzwa','Nyasha','Tinashe','Rumbidzai','Takudzwa','Tsitsi',
                         'Ruvimbo','Simba','Vimbai','Tapiwa','Fadzai','Munashe','Chiedza','Tawanda','Nokuthula','Sibusiso',
                         'Thandeka','Nkosana','Sipho','Lindiwe','Busisiwe','Themba','Shingai','Kundai','Panashe','Anesu',
                         'Ropafadzo','Tanaka','Tariro','Mufaro','Ngoni','Dudzai','Kudzai','Rutendo','Tendekai','Mazvita',
                         'Tonderai','Chengetai','Petronella','Gift','Precious','Brighton','Prudence','Admire','Loveness','Obert'];
    zw_l TEXT[] := ARRAY['Moyo','Ncube','Sibanda','Dube','Ndlovu','Mpofu','Chikore','Mutasa','Banda','Marufu',
                         'Chinembiri','Gumbo','Mhlanga','Nkomo','Chirwa','Mushonga','Makoni','Zvobgo','Chiweshe','Mukanya',
                         'Nyathi','Tshuma','Mlambo','Chigumba','Madziva','Mapfumo','Chidzikwe','Mandaza','Hove','Mutsvangwa',
                         'Chakanyuka','Matongo','Mazarura','Musonza','Chitando','Nyoni','Mangena','Dhliwayo','Kadenge','Makumbe'];
    za_f TEXT[] := ARRAY['Thabo','Lerato','Naledi','Pieter','Zanele','Johan','Ayanda','Kagiso','Refilwe','Bongani','Palesa','Riaan'];
    za_l TEXT[] := ARRAY['Nkosi','van der Merwe','Dlamini','Botha','Khumalo','Naidoo','Pillay','Mahlangu','Coetzee','Molefe'];
    ke_f TEXT[] := ARRAY['Achieng','Brian','Njeri','Kevin','Wambui','Dennis','Akinyi','Collins','Mercy','Kiprono'];
    ke_l TEXT[] := ARRAY['Otieno','Kariuki','Mutua','Njoroge','Kiptoo','Wafula','Odhiambo','Chege','Mwangi','Wekesa'];
    gb_f TEXT[] := ARRAY['Charlotte','James','Amelia','Harry','Sophie','Daniel','Priya','Thomas'];
    gb_l TEXT[] := ARRAY['Clarke','Hughes','Patel','Walker','Bennett','Evans','Morgan','Shaw'];
    ae_f TEXT[] := ARRAY['Fatima','Ahmed','Priya','Rahul','Layla','Yusuf','Aisha','Karim'];
    ae_l TEXT[] := ARRAY['Al Mansoori','Khan','Menon','Nair','Farouk','Saleh','Rahman','Qureshi'];
    sup_titles JSONB := '{"FIN":["Accountant","Accounts Payable Officer","Accounts Receivable & Billing Officer","Payroll Accountant","Treasury Officer","Assistant Accountant","Management Accountant"],
                          "HRM":["HR Officer","Payroll & Benefits Officer","Talent Acquisition Officer","Learning & Development Officer"],
                          "ICT":["Systems Administrator","Service Desk Analyst","Network Engineer","Database Administrator","Information Security Officer"],
                          "LEG":["Legal Officer","Compliance Officer"],
                          "MBD":["Marketing Officer","Bids & Proposals Coordinator","Digital Marketing Specialist","Business Development Executive"],
                          "PRC":["Procurement Officer","Stores & Asset Clerk"],
                          "FAC":["Facilities Officer","Receptionist","Driver","Office Assistant","Fleet Coordinator"],
                          "QRM":["Quality Reviewer"], "IAU":["Internal Auditor"], "EXE":["Executive Assistant","Executive Office Administrator"]}';
    dept_short JSONB := '{"FAI":"Forensic Audit","DAA":"Data Analytics","CYB":"Cybersecurity","RAS":"Risk Advisory","TAX":"Tax Advisory","FAV":"Financial Advisory",
                          "FIN":"Finance","HRM":"Human Resources","MBD":"Marketing","ICT":"IT","FAC":"Facilities","PRC":"Procurement"}';
    r RECORD; k INT; i INT := 26; v_fn TEXT; v_ln TEXT; v_email TEXT; v_try INT; v_country TEXT; v_title TEXT; v_hire DATE;
    v_grade job_grades%ROWTYPE; v_lvl INT; v_sup_i INT := 0;
BEGIN
    FOR r IN SELECT h.*, o.country_code FROM seed_headcount h JOIN offices o ON o.code = h.office ORDER BY h.office, h.dept, h.grade LOOP
        SELECT * INTO v_grade FROM job_grades WHERE code = r.grade;
        FOR k IN 1 .. r.n LOOP
            i := i + 1;
            v_try := 0;
            LOOP
                CASE r.country_code
                    WHEN 'ZA' THEN v_fn := za_f[1 + (i * 7 + v_try) % array_length(za_f,1)]; v_ln := za_l[1 + (i * 3 + v_try * 5) % array_length(za_l,1)];
                    WHEN 'KE' THEN v_fn := ke_f[1 + (i * 7 + v_try) % array_length(ke_f,1)]; v_ln := ke_l[1 + (i * 3 + v_try * 5) % array_length(ke_l,1)];
                    WHEN 'GB' THEN v_fn := gb_f[1 + (i * 5 + v_try) % array_length(gb_f,1)]; v_ln := gb_l[1 + (i * 3 + v_try * 3) % array_length(gb_l,1)];
                    WHEN 'AE' THEN v_fn := ae_f[1 + (i * 5 + v_try) % array_length(ae_f,1)]; v_ln := ae_l[1 + (i * 3 + v_try * 3) % array_length(ae_l,1)];
                    ELSE           v_fn := zw_f[1 + (i * 7 + v_try) % array_length(zw_f,1)]; v_ln := zw_l[1 + (i * 13 + v_try * 7) % array_length(zw_l,1)];
                END CASE;
                v_email := lower(regexp_replace(v_fn, '[^A-Za-z]', '', 'g') || '.' || regexp_replace(v_ln, '[^A-Za-z]', '', 'g')) || '@maxhub.co.zw';
                EXIT WHEN NOT EXISTS (SELECT 1 FROM seed_people WHERE lower(fn || '.' || regexp_replace(ln, '[^A-Za-z]', '', 'g')) || '@maxhub.co.zw' = v_email)
                      AND NOT EXISTS (SELECT 1 FROM employees WHERE email = v_email);
                v_try := v_try + 1;
            END LOOP;

            IF r.grade = 'SUP' THEN
                v_sup_i := v_sup_i + 1;
                v_title := sup_titles -> r.dept ->> ((v_sup_i + k) % jsonb_array_length(sup_titles -> r.dept));
            ELSIF (SELECT is_revenue_generating FROM departments WHERE code = r.dept) THEN
                v_title := v_grade.name || ' - ' || (dept_short ->> r.dept);
            ELSE
                v_title := COALESCE(dept_short ->> r.dept, r.dept) || ' ' || CASE r.grade WHEN 'MGR' THEN 'Manager' ELSE v_grade.name END;
            END IF;
            v_lvl := v_grade.level;
            v_hire := CASE v_lvl WHEN 5 THEN '2016-01-11'::DATE + (i * 47 % 1500) WHEN 4 THEN '2017-03-01'::DATE + (i * 53 % 1800)
                                 WHEN 3 THEN '2019-02-01'::DATE + (i * 41 % 1400) WHEN 2 THEN '2021-01-11'::DATE + (i * 37 % 1300)
                                 WHEN 1 THEN '2023-01-09'::DATE + (i * 29 % 1050) ELSE '2015-06-01'::DATE + (i * 61 % 3500) END;
            INSERT INTO seed_people VALUES ('E' || lpad(i::TEXT, 3, '0'), v_fn, v_ln, CASE WHEN i % 2 = 0 THEN 'Female' ELSE 'Male' END,
                                            r.grade, v_title, r.dept, r.office, LEAST(v_hire, '2026-02-02'::DATE));
            INSERT INTO employees (employee_number, first_name, last_name, email, hire_date)   -- placeholder row to reserve the e-mail
            VALUES ('TMP' || i, v_fn, v_ln, v_email, '2020-01-01');
        END LOOP;
    END LOOP;
    DELETE FROM employees WHERE employee_number LIKE 'TMP%';
    EXECUTE 'ALTER TABLE employees ALTER COLUMN employee_id RESTART WITH 1';
END $$;

INSERT INTO employees (employee_number, first_name, last_name, email, phone, mobile_phone, work_phone_ext, gender, date_of_birth,
                       national_id, hire_date, employment_type, status, job_grade_id, job_title, department_id, office_id, service_line_id,
                       is_billable, target_utilization_pct, cost_rate_hourly, default_bill_rate, currency_code, nationality,
                       tax_number, social_security_number, pension_member, medical_aid_member, medical_aid_scheme,
                       bank_name, bank_account_number, emergency_contact_name, emergency_contact_phone, work_permit_expiry)
SELECT p.num, p.fn, p.ln,
       lower(regexp_replace(p.fn, '[^A-Za-z]', '', 'g') || '.' || regexp_replace(p.ln, '[^A-Za-z]', '', 'g')) || '@maxhub.co.zw',
       o.phone, CASE o.country_code WHEN 'ZW' THEN '+263 77 ' ELSE '+' END || lpad((1000000 + n.rn * 7919 % 8999999)::TEXT, 7, '0'),
       d.phone_extension::INT + n.rn % 90 || '', p.gender,
       ('1968-01-01'::DATE + ((7 - g.level) * 1460 + n.rn * 97 % 1400)::INT),
       CASE o.country_code WHEN 'ZW' THEN lpad((10 + n.rn % 80)::TEXT, 2, '0') || '-' || lpad((200000 + n.rn * 3571 % 799999)::TEXT, 6, '0') || 'X' || lpad((n.rn % 90 + 10)::TEXT, 2, '0') END,
       p.hire, 'full_time', 'active', g.job_grade_id, p.title, d.department_id, o.office_id,
       (SELECT service_line_id FROM service_lines sl WHERE sl.code = p.dept),
       d.is_revenue_generating AND g.level > 0, g.target_utilization_pct,
       NULL, CASE WHEN d.is_revenue_generating AND g.level > 0
                  THEN round(g.default_bill_rate * CASE o.code WHEN 'LON' THEN 1.8 WHEN 'DXB' THEN 1.5 WHEN 'JNB' THEN 1.1 WHEN 'BYO' THEN 0.9 ELSE 1 END, 0) END,
       o.functional_currency,
       CASE o.country_code WHEN 'ZW' THEN 'Zimbabwean' WHEN 'ZA' THEN 'South African' WHEN 'KE' THEN 'Kenyan' WHEN 'GB' THEN 'British'
                           ELSE CASE WHEN n.rn % 2 = 0 THEN 'Zimbabwean' ELSE 'Indian' END END,
       CASE o.country_code WHEN 'ZW' THEN '2' || lpad((n.rn * 104729 % 999999999)::TEXT, 9, '0') WHEN 'KE' THEN 'A0' || lpad((n.rn * 7127)::TEXT, 8, '0') || 'K'
                           WHEN 'GB' THEN 'QQ' || lpad((n.rn * 123457 % 999999)::TEXT, 6, '0') || 'C' ELSE 'TX' || lpad((n.rn * 7919)::TEXT, 9, '0') END,
       CASE o.country_code WHEN 'ZW' THEN 'NSSA' || lpad((n.rn * 3083 % 9999999)::TEXT, 7, '0') ELSE NULL END,
       TRUE, o.country_code = 'ZW', CASE WHEN o.country_code = 'ZW' THEN CASE WHEN n.rn % 3 = 0 THEN 'First Mutual Health' ELSE 'CIMAS' END END,
       CASE o.country_code WHEN 'ZW' THEN CASE WHEN n.rn % 2 = 0 THEN 'CBZ Bank' ELSE 'Stanbic Bank' END WHEN 'ZA' THEN 'FNB' WHEN 'KE' THEN 'NCBA Bank'
                           WHEN 'GB' THEN 'Barclays' ELSE 'Emirates NBD' END,
       lpad((n.rn * 99991 % 9999999999)::TEXT, 10, '0'),
       'Next of kin', '+263 71 ' || lpad((n.rn * 4441 % 9999999)::TEXT, 7, '0'),
       CASE WHEN o.country_code = 'AE' THEN '2027-01-31'::DATE WHEN o.country_code = 'GB' THEN '2027-12-31'::DATE END
  FROM (SELECT sp.*, row_number() OVER (ORDER BY sp.num) AS rn FROM seed_people sp) n
  JOIN seed_people p ON p.num = n.num
  JOIN job_grades g  ON g.code = p.grade
  JOIN departments d ON d.code = p.dept
  JOIN offices o     ON o.code = p.office
 ORDER BY p.num;

-- Reporting lines: branch staff -> branch head; department staff -> next senior level; heads -> CEO/COO
UPDATE employees e SET manager_id = (SELECT employee_id FROM employees WHERE employee_number = CASE o.code
        WHEN 'BYO' THEN 'E026' WHEN 'JNB' THEN 'E014' WHEN 'NBO' THEN 'E015' WHEN 'LON' THEN 'E016' WHEN 'DXB' THEN 'E017' END)
  FROM offices o
 WHERE o.office_id = e.office_id AND o.code <> 'HRE' AND e.employee_number NOT IN ('E014','E015','E016','E017','E026');

UPDATE departments d SET head_employee_id = (SELECT employee_id FROM employees WHERE employee_number = v.num)
  FROM (VALUES ('EXE','E001'), ('FAI','E002'), ('DAA','E003'), ('CYB','E012'), ('RAS','E010'), ('TAX','E011'), ('FAV','E013'),
               ('FIN','E006'), ('HRM','E007'), ('ICT','E008'), ('MBD','E020'), ('PRC','E021'), ('FAC','E022'), ('LEG','E019'),
               ('QRM','E023'), ('IAU','E024')) AS v(code, num)
 WHERE d.code = v.code;

UPDATE employees e
   SET manager_id = COALESCE(
         (SELECT m.employee_id FROM employees m JOIN job_grades mg ON mg.job_grade_id = m.job_grade_id
           WHERE m.department_id = e.department_id AND m.office_id = e.office_id AND m.employee_id <> e.employee_id
             AND mg.level = (SELECT min(g2.level) FROM employees e2 JOIN job_grades g2 ON g2.job_grade_id = e2.job_grade_id
                              WHERE e2.department_id = e.department_id AND e2.office_id = e.office_id AND g2.level > g.level)
           ORDER BY (m.employee_id + e.employee_id) % 3, m.employee_id LIMIT 1),
         (SELECT head_employee_id FROM departments WHERE department_id = e.department_id))
  FROM job_grades g, offices o
 WHERE g.job_grade_id = e.job_grade_id AND o.office_id = e.office_id AND o.code = 'HRE' AND e.manager_id IS NULL
   AND e.employee_id NOT IN (SELECT head_employee_id FROM departments WHERE head_employee_id IS NOT NULL);

UPDATE employees SET manager_id = (SELECT employee_id FROM employees WHERE employee_number = 'E001')
 WHERE employee_id IN (SELECT head_employee_id FROM departments) AND employee_number <> 'E001';
UPDATE employees SET manager_id = (SELECT employee_id FROM employees WHERE employee_number = 'E018')
 WHERE employee_number IN ('E014','E015','E016','E017','E026');
UPDATE employees SET manager_id = NULL WHERE employee_number = 'E001';
UPDATE employees SET manager_id = (SELECT employee_id FROM employees WHERE employee_number = 'E006') WHERE employee_number IN ('E009','E025');
UPDATE employees SET manager_id = (SELECT employee_id FROM employees WHERE employee_number = 'E002') WHERE employee_number = 'E004';

UPDATE offices o SET manager_employee_id = (SELECT employee_id FROM employees WHERE employee_number = v.num)
  FROM (VALUES ('HRE','E018'), ('BYO','E026'), ('JNB','E014'), ('NBO','E015'), ('LON','E016'), ('DXB','E017')) AS v(code, num)
 WHERE o.code = v.code;
UPDATE service_lines sl SET lead_employee_id = d.head_employee_id FROM departments d WHERE d.department_id = sl.department_id;

-- 31.4 Compensation (local currency). 2026 increase of 7% from 1 January.
INSERT INTO employee_compensation (employee_id, effective_date, base_salary_annual, monthly_allowances, bonus_target_pct, currency_code, change_reason)
SELECT e.employee_id, GREATEST(e.hire_date, '2024-01-01'::DATE),
       round(x.usd * 0.93 * x.mult / x.fx, -2), round(x.usd * 0.93 * x.mult / x.fx / 12 * x.allow, -1),
       CASE WHEN g.level >= 5 THEN 20 WHEN g.level >= 3 THEN 12 ELSE 8 END, e.currency_code, 'Salary on appointment / 2024 review'
  FROM employees e JOIN job_grades g USING (job_grade_id) JOIN offices o ON o.office_id = e.office_id
  CROSS JOIN LATERAL (SELECT
        CASE WHEN g.code = 'SUP' THEN 7500 + (e.employee_id * 37 % 100) * 120
             ELSE g.min_salary + (g.max_salary - g.min_salary) * (e.employee_id * 37 % 100) / 100.0 END
          * CASE WHEN g.code = 'SUP' AND e.job_title ~ '(Receptionist|Driver|Office Assistant)' THEN 0.6 ELSE 1 END AS usd,
        CASE o.country_code WHEN 'ZA' THEN 1.2 WHEN 'KE' THEN 0.9 WHEN 'GB' THEN 1.9 WHEN 'AE' THEN 1.6 ELSE 1 END AS mult,
        fn_fx_rate(e.currency_code, '2025-12-31') AS fx,
        CASE o.country_code WHEN 'ZW' THEN 0.12 ELSE 0.05 END AS allow) x;

INSERT INTO employee_compensation (employee_id, effective_date, base_salary_annual, monthly_allowances, bonus_target_pct, currency_code, change_reason)
SELECT employee_id, '2026-01-01', round(base_salary_annual * 1.07, -2), round(monthly_allowances * 1.07, -1), bonus_target_pct, currency_code,
       'Annual review 2026 (+7%)'
  FROM employee_compensation WHERE effective_date < '2026-01-01';

UPDATE employees e SET cost_rate_hourly = round(c.base_salary_annual * fn_fx_rate(c.currency_code, '2025-12-31') * 1.35 / 1760, 2)
  FROM employee_compensation c WHERE c.employee_id = e.employee_id AND c.effective_date = '2026-01-01';

-- 31.5 Bank accounts ----------------------------------------------------------------------
INSERT INTO bank_accounts (name, bank_name, branch, account_number, swift_code, account_type, currency_code, gl_account_id, office_id)
SELECT v.name, v.bank, v.branch, v.acc, v.swift, v.t, v.cur, fn_account_id(v.gl), (SELECT office_id FROM offices WHERE code = v.office)
  FROM (VALUES
   ('Operating USD - Harare',       'CBZ Bank',              'Kwame Nkrumah Avenue', '01120456789012', 'COBZZWHA','current',     'USD','1010','HRE'),
   ('Client receipts USD Nostro',   'Stanbic Bank Zimbabwe', 'Harare Corporate',     '9140004512375',  'SBICZWHX','fca',         'USD','1013','HRE'),
   ('Operating ZWG',                'Stanbic Bank Zimbabwe', 'Harare Corporate',     '9140004512367',  'SBICZWHX','current',     'ZWG','1011','HRE'),
   ('Money market call account',    'CBZ Bank',              'Treasury',             '01120456789999', 'COBZZWHA','money_market','USD','1017','HRE'),
   ('Bulawayo operating USD',       'CABS',                  'Bulawayo Main',        '1003458712',     'CABSZWHX','current',     'USD','1018','BYO'),
   ('Johannesburg operating ZAR',   'FNB',                   'Sandton',              '62845120045',    'FIRNZAJJ','current',     'ZAR','1012','JNB'),
   ('Nairobi operating KES',        'NCBA Bank',             'Westlands',            '1004512078',     'CBAFKENX','current',     'KES','1014','NBO'),
   ('London operating GBP',         'Barclays Bank UK',      'Canary Wharf',         '43125698',       'BARCGB22','current',     'GBP','1015','LON'),
   ('Dubai operating AED',          'Emirates NBD',          'DIFC',                 '1015004512301',  'EBILAEAD','current',     'AED','1016','DXB'),
   ('Petty cash - Harare',          'Cash on hand',          'Maxhub House',         'PC-HRE-01',      NULL,      'petty_cash',  'USD','1020','HRE')
  ) AS v(name, bank, branch, acc, swift, t, cur, gl, office);

-- 31.6 Access: department + grade -> roles, then one login per employee -------------------
INSERT INTO department_role_rules (department_id, min_grade_level, max_grade_level, role_id, description)
SELECT (SELECT department_id FROM departments WHERE code = v.dept), v.lo, v.hi, (SELECT role_id FROM roles WHERE code = v.role), v.descr
  FROM (VALUES
   (NULL, 0, 99, 'EMPLOYEE',        'Every employee: self-service'),
   ('FAI',1, 3, 'CONSULTANT','Fee earners'), ('DAA',1,3,'CONSULTANT','Fee earners'), ('CYB',1,3,'CONSULTANT','Fee earners'),
   ('RAS',1, 3, 'CONSULTANT','Fee earners'), ('TAX',1,3,'CONSULTANT','Fee earners'), ('FAV',1,3,'CONSULTANT','Fee earners'),
   ('FAI',4, 5, 'PROJECT_MANAGER','Managers run engagements'), ('DAA',4,5,'PROJECT_MANAGER','Managers run engagements'),
   ('CYB',4, 5, 'PROJECT_MANAGER','Managers run engagements'), ('RAS',4,5,'PROJECT_MANAGER','Managers run engagements'),
   ('TAX',4, 5, 'PROJECT_MANAGER','Managers run engagements'), ('FAV',4,5,'PROJECT_MANAGER','Managers run engagements'),
   ('FAI',4, 5, 'CONSULTANT','Managers also deliver'), ('DAA',4,5,'CONSULTANT','Managers also deliver'),
   ('CYB',4, 5, 'CONSULTANT','Managers also deliver'), ('RAS',4,5,'CONSULTANT','Managers also deliver'),
   ('TAX',4, 5, 'CONSULTANT','Managers also deliver'), ('FAV',4,5,'CONSULTANT','Managers also deliver'),
   ('FAI',6, 7, 'EXECUTIVE','Partners & directors'), ('DAA',6,7,'EXECUTIVE','Partners & directors'),
   ('CYB',6, 7, 'EXECUTIVE','Partners & directors'), ('RAS',6,7,'EXECUTIVE','Partners & directors'),
   ('TAX',6, 7, 'EXECUTIVE','Partners & directors'), ('FAV',6,7,'EXECUTIVE','Partners & directors'),
   ('FAI',6, 7, 'PROJECT_MANAGER','Engagement partners'), ('DAA',6,7,'PROJECT_MANAGER','Engagement partners'),
   ('CYB',6, 7, 'PROJECT_MANAGER','Engagement partners'), ('RAS',6,7,'PROJECT_MANAGER','Engagement partners'),
   ('TAX',6, 7, 'PROJECT_MANAGER','Engagement partners'), ('FAV',6,7,'PROJECT_MANAGER','Engagement partners'),
   ('EXE',6, 7, 'EXECUTIVE','Executive team'),
   ('FIN',0, 3, 'ACCOUNTANT','Finance staff'), ('FIN',4, 7, 'FINANCE_MANAGER','Finance leadership'), ('FIN',4,7,'ACCOUNTANT','Finance leadership'),
   ('HRM',0, 3, 'PAYROLL_OFFICER','HR officers'), ('HRM',4, 7, 'HR_MANAGER','HR leadership'),
   ('ICT',0, 3, 'IT_SUPPORT','IT staff'), ('ICT',4, 7, 'ADMIN','IT manager = system administrator'), ('ICT',4,7,'IT_SUPPORT','IT manager'),
   ('MBD',0, 7, 'BD_MANAGER','Marketing & BD'),
   ('PRC',0, 7, 'FACILITIES','Procurement'), ('FAC',0, 7, 'FACILITIES','Facilities'),
   ('LEG',0, 7, 'AUDITOR','Legal & compliance (read-only oversight)'), ('QRM',0, 7, 'AUDITOR','Quality & risk'),
   ('IAU',0, 7, 'AUDITOR','Internal audit')
  ) AS v(dept, lo, hi, role, descr);

DO $$
DECLARE v_hash TEXT := crypt('Maxhub@2026', gen_salt('bf', 10));   -- one bcrypt hash for the demo password
BEGIN
    INSERT INTO app_users (employee_id, username, email, password_hash, must_change_password, password_changed_at, last_login_at)
    SELECT e.employee_id, split_part(e.email, '@', 1), e.email, v_hash, FALSE, '2026-08-01 08:00+02',
           '2026-09-24 08:00+02'::TIMESTAMPTZ - make_interval(mins => (e.employee_id * 37 % 900)::INT)
      FROM employees e ORDER BY e.employee_id;           -- roles are assigned by trigger from department rules
    INSERT INTO password_history (user_id, password_hash, changed_at) SELECT user_id, password_hash, password_changed_at FROM app_users;
END $$;

-- manual extra role: the tax compliance manager also files ZIMRA returns
INSERT INTO user_roles (user_id, role_id, source)
SELECT u.user_id, r.role_id, 'manual' FROM app_users u, roles r WHERE u.username = 'memory.nkomo' AND r.code = 'TAX_OFFICER';

-- a few realistic log-in records (including a lock-out)
INSERT INTO login_attempts (username_tried, user_id, success, failure_reason, ip_address, user_agent, attempted_at)
SELECT u.username, u.user_id, TRUE, NULL, '10.10.' || (u.user_id % 20) || '.' || (u.user_id % 250 + 1), 'Chrome on Windows 11', u.last_login_at
  FROM app_users u;
INSERT INTO login_attempts (username_tried, user_id, success, failure_reason, ip_address, user_agent, attempted_at) VALUES
 ('kudakwashe.banda', (SELECT user_id FROM app_users WHERE username = 'kudakwashe.banda'), FALSE, 'wrong_password', '10.10.4.51', 'Chrome on Windows 11', '2026-09-23 07:58+02'),
 ('admin', NULL, FALSE, 'unknown_user', '196.27.100.14', 'python-requests/2.31', '2026-09-22 02:14+02'),
 ('administrator', NULL, FALSE, 'unknown_user', '196.27.100.14', 'python-requests/2.31', '2026-09-22 02:14+02');

-- 31.7 Leave balances & skills ------------------------------------------------------------
INSERT INTO leave_balances (employee_id, leave_type_id, leave_year, entitled_days, carried_forward_days)
SELECT e.employee_id, lt.leave_type_id, y, lt.annual_entitlement_days, CASE WHEN lt.code = 'AL' THEN (e.employee_id % 6) ELSE 0 END
  FROM employees e CROSS JOIN leave_types lt CROSS JOIN (VALUES (2025), (2026)) AS yy(y)
 WHERE lt.code IN ('AL','SL','SP');

INSERT INTO employee_skills (employee_id, skill_id, proficiency, years_experience)
SELECT e.employee_id, s.skill_id, LEAST(5, 2 + g.level / 2), g.level * 2 + 1
  FROM employees e JOIN job_grades g USING (job_grade_id) JOIN departments d USING (department_id)
  JOIN skills s ON s.category = CASE d.code WHEN 'FAI' THEN 'Forensic' WHEN 'DAA' THEN 'Data' WHEN 'CYB' THEN 'Cyber'
                                            WHEN 'RAS' THEN 'Risk' WHEN 'TAX' THEN 'Tax' WHEN 'FAV' THEN 'Finance' END
 WHERE (e.employee_id + s.skill_id) % 2 = 0 OR g.level >= 5;
