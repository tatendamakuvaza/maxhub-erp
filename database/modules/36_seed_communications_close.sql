
/* =====================================================================================
   36. SEED - COMMUNICATIONS, TAX COMPUTATION, PERIOD CLOSE, FINISHING TOUCHES
   ===================================================================================== */

-- 36.1 Mailing lists & shared mailboxes ---------------------------------------------------
INSERT INTO mailing_lists (address, display_name, list_type, is_all_staff, owner_employee_id, description)
VALUES ('all-staff@maxhub.co.zw', 'All Maxhub staff', 'distribution', TRUE, (SELECT employee_id FROM employees WHERE employee_number='E007'), 'Every employee in every office'),
       ('leadership@maxhub.co.zw', 'Leadership team', 'distribution', FALSE, (SELECT employee_id FROM employees WHERE employee_number='E001'), 'Partners, directors and heads of department'),
       ('info@maxhub.co.zw', 'General enquiries', 'shared', FALSE, (SELECT employee_id FROM employees WHERE employee_number='E020'), 'Website contact form & switchboard'),
       ('accounts@maxhub.co.zw', 'Accounts receivable', 'shared', FALSE, (SELECT employee_id FROM employees WHERE employee_number='E025'), 'Remittance advices & statements'),
       ('whistleblower@maxhub.co.zw', 'Ethics & whistle-blowing line', 'shared', FALSE, (SELECT employee_id FROM employees WHERE employee_number='E024'), 'Confidential - Internal Audit only');
INSERT INTO mailing_lists (address, display_name, list_type, department_id, owner_employee_id, description)
SELECT d.email, d.name, 'distribution', d.department_id, d.head_employee_id, 'Everyone in ' || d.name FROM departments d;
INSERT INTO mailing_lists (address, display_name, list_type, office_id, owner_employee_id, description)
SELECT o.email, o.name, 'distribution', o.office_id, o.manager_employee_id, 'Everyone based in ' || o.city FROM offices o;
INSERT INTO mailing_list_members (list_id, employee_id)
SELECT (SELECT list_id FROM mailing_lists WHERE address = 'leadership@maxhub.co.zw'), e.employee_id
  FROM employees e JOIN job_grades g USING (job_grade_id)
 WHERE g.level >= 6 OR e.employee_id IN (SELECT head_employee_id FROM departments);

-- 36.2 Announcements ----------------------------------------------------------------------
INSERT INTO announcements (title, body, category, audience, department_id, office_id, author_id, is_pinned, publish_at, expires_at)
SELECT v.title, v.body, v.cat, v.aud, (SELECT department_id FROM departments WHERE code = v.dept), (SELECT office_id FROM offices WHERE code = v.office),
       (SELECT employee_id FROM employees WHERE employee_number = v.author), v.pin, v.pub::TIMESTAMPTZ, v.exp::TIMESTAMPTZ
  FROM (VALUES
   ('Welcome to the new Maxhub ERP','Colleagues, from today every timesheet, expense claim, leave request and approval runs through the Maxhub ERP. Log in with your company username (firstname.lastname) and change your password on first use. What you see depends on your department and role. Thank you for making Maxhub a data-driven firm. - Tendai',
    'general','all',NULL,NULL,'E001',TRUE,'2026-09-01 08:00+02',NULL),
   ('Early adoption of IFRS 18 for FY2026','The Board has approved early adoption of IFRS 18 (Presentation and Disclosure in Financial Statements) for the year ending 31 December 2026. Our income statement now shows Operating profit and Profit before financing and income taxes, and our MPMs (Adjusted operating profit, Adjusted EBITDA) are disclosed in a single note. Finance will run short training sessions in October.',
    'finance','all',NULL,NULL,'E006',TRUE,'2026-02-10 09:00+02',NULL),
   ('QPD 3 paid - 30% of estimated 2026 tax','The third Quarterly Payment Date instalment was paid to ZIMRA on 23 September, ahead of the 25 September deadline. VAT7 for September is due 25 October; PAYE/NSSA/ZIMDEF by 10 October.',
    'compliance','department','FIN',NULL,'E009',FALSE,'2026-09-23 12:00+02','2026-10-31 00:00+02'),
   ('Timesheets due every Friday by 17:00','Please submit your timesheet every Friday. Unsubmitted time cannot be billed and delays our invoicing. Managers approve by Monday 10:00.',
    'general','all',NULL,NULL,'E018',FALSE,'2026-09-18 08:30+02',NULL),
   ('Phishing alert: fake "ZIMRA refund" e-mails','We are seeing e-mails pretending to be ZIMRA offering tax refunds. Do not click links or open attachments. Forward suspicious mail to itsupport@maxhub.co.zw. Remember: IT will never ask for your password.',
    'it','all',NULL,NULL,'E008',TRUE,'2026-09-22 10:15+02','2026-10-22 00:00+02'),
   ('Fire drill - Maxhub House, Wednesday 30 September 10:00','All staff at Maxhub House must evacuate to the assembly point in the car park when the alarm sounds. Floor wardens will take the roll.',
    'health_safety','office',NULL,'HRE','E022',FALSE,'2026-09-21 09:00+02','2026-10-01 00:00+02'),
   ('Maxhub Annual Awards Dinner - 31 October','Save the date! Our annual awards dinner is at Meikles Hotel, Harare. Branch colleagues will join by live stream.',
    'event','all',NULL,NULL,'E007',FALSE,'2026-09-15 08:00+02','2026-11-01 00:00+02'),
   ('Nairobi office expansion complete','The additional floor space at Westlands Square is now furnished and open. Welcome to our three new colleagues in Data Analytics.',
    'general','office',NULL,'NBO','E015',FALSE,'2026-03-20 09:00+03',NULL),
   ('NSSA insurable earnings ceiling','Payroll reminder: NSSA contributions are 4.5% employee + 4.5% employer on insurable earnings capped at USD 700 per month. The ceiling is held in the statutory rates table - HR will update it when NSSA gazettes a change.',
    'hr','department','HRM',NULL,'E007',FALSE,'2026-01-12 08:00+02',NULL),
   ('New engagement: commodity trade-finance investigation','London has completed the Thames Commodity Traders investigation. Great teamwork across London, Harare and Dubai.',
    'general','all',NULL,NULL,'E016',FALSE,'2026-08-31 11:00+01',NULL)
  ) AS v(title, body, cat, aud, dept, office, author, pin, pub, exp);

INSERT INTO announcement_reads (announcement_id, employee_id, read_at)
SELECT a.announcement_id, e.employee_id, a.publish_at + make_interval(hours => (e.employee_id % 30)::INT)
  FROM announcements a CROSS JOIN employees e
 WHERE a.audience = 'all' AND (e.employee_id + a.announcement_id) % 3 <> 0
   AND a.publish_at + make_interval(hours => (e.employee_id % 30)::INT) < '2026-09-24 18:00+02';

-- 36.3 Internal messages ------------------------------------------------------------------
CREATE TEMP TABLE seed_msgs (n INT, sender TEXT, recipients TEXT[], subject TEXT, body TEXT, prio TEXT, sent TIMESTAMPTZ, read_by TEXT[]);
INSERT INTO seed_msgs VALUES
 (1,'E004',ARRAY['E005'],'Timesheet for week of 14 September','Hi Kuda, please make sure your time on the loan-book forensic audit is split by task before I approve. Thanks, Nyasha','normal','2026-09-21 08:40+02',ARRAY[]::TEXT[]),
 (2,'E002',ARRAY['E004','E005'],'Zambezi Mining - draft report review','Team, the partner review of the procurement fraud report is set for Tuesday 29 September at 10:00 in the Boardroom (4th floor). Please circulate the working papers by Monday.','high','2026-09-23 16:05+02',ARRAY['E004']),
 (3,'E009',ARRAY['E006','E025'],'QPD 3 paid to ZIMRA','QPD 3 (30%) was paid on 23 Sep via CBZ. Acknowledgement is filed in TaRMS. Next: VAT7 for September due 25 October.','normal','2026-09-23 12:10+02',ARRAY['E006','E025']),
 (4,'E006',ARRAY['E009'],'RE: QPD 3 paid to ZIMRA','Thanks Memory. Please also prepare the IFRS 18 MPM reconciliation for the Audit Committee pack.','normal','2026-09-23 13:02+02',ARRAY[]::TEXT[]),
 (5,'E008',ARRAY['E001','E006','E007','E018'],'ERP go-live: access by department','All staff logins are active. Access is automatic by department and grade (e.g. Finance = Accountant, Finance managers = Finance Manager). Accounts lock for 15 minutes after 5 wrong passwords. Please ask your teams to change the demo password.','high','2026-09-01 07:45+02',ARRAY['E001','E006','E007']),
 (6,'E007',ARRAY['E006'],'September payroll ready for approval','The September payroll runs for Zimbabwe and the four branches are prepared in the ERP. Please review and approve by the 24th so salaries go out on the 25th.','high','2026-09-22 15:30+02',ARRAY[]::TEXT[]),
 (7,'E022',ARRAY['E008','E021'],'Bulawayo solar installation','SolarTech will commission the 60kW system at Maxhub Centre next week. The asset is in the register as under construction until handover.','normal','2026-09-16 11:20+02',ARRAY['E008','E021']),
 (8,'E025',ARRAY['E006'],'August management accounts','August is closed. Revenue YTD USD 9.7m; operating profit USD 2.6m. The IFRS statements are available on the Financial Statements page.','normal','2026-09-10 17:45+02',ARRAY['E006']),
 (9,'E020',ARRAY['E002','E003','E010'],'Proposal deadline - Lusaka Water tender','The Lusaka Water revenue-assurance tender closes 9 October. Can each practice send CVs and a fee estimate by 2 October?','normal','2026-09-18 09:12+02',ARRAY['E003']),
 (10,'E014',ARRAY['E018'],'Johannesburg Q3 pipeline','Gauteng Treasury phase 2 looks likely (USD 160k). Rand Merchant Credit has asked for a model-validation proposal.','normal','2026-09-14 14:30+02',ARRAY['E018']),
 (11,'E023',ARRAY['E004'],'QRM review booked','Your engagement file for P25-001 is scheduled for an ISQM 1 quality review on 5 October.','normal','2026-09-24 09:00+02',ARRAY[]::TEXT[]),
 (12,'E001',ARRAY['E002','E010','E011','E018'],'Board pack - Q3','Partners, please send your practice updates for the Q3 board pack by 2 October.','high','2026-09-24 07:30+02',ARRAY[]::TEXT[]);

INSERT INTO internal_messages (sender_id, subject, body, priority, sent_at)
SELECT (SELECT employee_id FROM employees WHERE employee_number = m.sender), m.subject, m.body, m.prio, m.sent FROM seed_msgs m ORDER BY m.n;
UPDATE internal_messages im SET thread_id = (SELECT message_id FROM internal_messages WHERE subject = 'QPD 3 paid to ZIMRA') WHERE subject LIKE 'RE: QPD 3%';
INSERT INTO message_recipients (message_id, recipient_id, read_at)
SELECT im.message_id, e.employee_id, CASE WHEN e.employee_number = ANY (m.read_by) THEN m.sent + INTERVAL '35 minutes' END
  FROM seed_msgs m
  JOIN internal_messages im ON im.subject = m.subject AND im.sent_at = m.sent
  JOIN employees e ON e.employee_number = ANY (m.recipients);

-- a company-wide message via the all-staff list
INSERT INTO internal_messages (sender_id, subject, body, priority, sent_to_list_id, sent_at)
VALUES ((SELECT employee_id FROM employees WHERE employee_number='E007'), 'Wellness Wednesday - free health screening',
        'CIMAS will run free blood-pressure and glucose screening at Maxhub House and Maxhub Centre on Wednesday. Branch staff can claim a screening through the medical aid.',
        'low', (SELECT list_id FROM mailing_lists WHERE address = 'all-staff@maxhub.co.zw'), '2026-09-21 12:00+02');
INSERT INTO message_recipients (message_id, recipient_id, read_at)
SELECT currval(pg_get_serial_sequence('internal_messages','message_id')), e.employee_id,
       CASE WHEN e.employee_id % 2 = 0 THEN '2026-09-21 13:00+02'::TIMESTAMPTZ END
  FROM employees e;

-- 36.4 System e-mail outbox ----------------------------------------------------------------
INSERT INTO email_outbox (to_address, subject, body, template_code, related_entity, related_id, status, attempts, queued_at, sent_at)
SELECT e.email, 'Reminder: submit your timesheet for the week of 14 September',
       'Hi ' || e.first_name || ', your timesheet for the week starting 14 Sep is still not submitted. Please submit it in the Maxhub ERP.',
       'timesheet_reminder', 'timesheet', t.timesheet_id, 'sent', 1, '2026-09-18 17:05+02', '2026-09-18 17:05+02'
  FROM timesheets t JOIN employees e USING (employee_id) WHERE t.week_start_date = '2026-09-14' AND t.status IN ('draft','rejected');
INSERT INTO email_outbox (to_address, subject, body, template_code, related_entity, related_id, status, attempts, queued_at, sent_at)
SELECT e.email, 'Your payslip for August 2026', 'Your August 2026 payslip is available in the Maxhub ERP (People > My payslips).',
       'payslip', 'payslip', p.payslip_id, 'sent', 1, '2026-08-25 06:00+02', '2026-08-25 06:01+02'
  FROM payslips p JOIN payroll_runs r USING (payroll_run_id) JOIN employees e USING (employee_id) WHERE r.period_start = '2026-08-01';
INSERT INTO email_outbox (to_address, cc_address, subject, body, template_code, related_entity, related_id, status, attempts, queued_at, sent_at)
SELECT c.billing_email, 'accounts@maxhub.co.zw', 'Tax invoice ' || i.invoice_number || ' from Maxhub Pvt Ltd',
       'Please find attached fiscalised tax invoice ' || i.invoice_number || ' (FDMS ' || i.fiscal_invoice_number || ') for USD ' || to_char(i.total_amount, 'FM999,999,990.00') || '.',
       'invoice', 'invoice', i.invoice_id, 'sent', 1, i.invoice_date + TIME '17:00', i.invoice_date + TIME '17:01'
  FROM invoices i JOIN clients c USING (client_id) WHERE i.invoice_date >= '2026-07-01' AND i.status <> 'draft';
INSERT INTO email_outbox (to_address, subject, body, template_code, status, attempts, last_error, queued_at)
VALUES ('accounts@beiracorridor.example', 'Statement of account - overdue invoices', 'Our records show overdue invoices on your account. Please arrange payment.',
        'statement', 'failed', 3, 'SMTP 550: mailbox unavailable', '2026-09-22 08:00+02'),
       ('ruvimbo.zvobgo@maxhub.co.zw', 'Board resolution register updated', 'The Q3 board resolutions have been added to the register.', 'notification', 'queued', 0, NULL, '2026-09-24 16:40+02');

INSERT INTO calendar_events (title, event_type, starts_at, ends_at, location, office_id, organiser_id, description)
SELECT v.t, v.ty, v.s::TIMESTAMPTZ, v.e::TIMESTAMPTZ, v.loc, (SELECT office_id FROM offices WHERE code = v.o),
       (SELECT employee_id FROM employees WHERE employee_number = v.org), v.d
  FROM (VALUES ('ZIMRA QPD 3 deadline (30%)','deadline','2026-09-25 00:00+02',NULL,'ZIMRA TaRMS','HRE','E009','Paid 23 Sep'),
               ('Fire drill - Maxhub House','meeting','2026-09-30 10:00+02','2026-09-30 10:30+02','Car park assembly point','HRE','E022',NULL),
               ('Audit Committee meeting (Q3)','board','2026-10-08 09:00+02','2026-10-08 12:00+02','Boardroom, 4th floor','HRE','E019','IFRS 18 MPM note & internal audit report'),
               ('PAYE / NSSA / ZIMDEF returns due','deadline','2026-10-10 00:00+02',NULL,'ZIMRA / NSSA portals','HRE','E009',NULL),
               ('IFRS 18 training for practice leads','training','2026-10-14 14:00+02','2026-10-14 16:00+02','Maxhub Academy, Borrowdale','HRE','E006',NULL),
               ('VAT7 September due','deadline','2026-10-25 00:00+02',NULL,'ZIMRA TaRMS','HRE','E009',NULL),
               ('Maxhub Annual Awards Dinner','social','2026-10-31 18:30+02','2026-10-31 23:00+02','Meikles Hotel, Harare','HRE','E007',NULL),
               ('QPD 4 deadline (35%)','deadline','2026-12-20 00:00+02',NULL,'ZIMRA TaRMS','HRE','E009',NULL)) AS v(t, ty, s, e, loc, o, org, d);

INSERT INTO notifications (user_id, title, message, link, created_at)
SELECT u.user_id, 'Timesheets waiting for your approval',
       count(*) || ' timesheet(s) for the week of 14 Sep are waiting for you.', 'Timesheets > Approvals', '2026-09-21 08:00+02'
  FROM timesheets t JOIN employees e ON e.employee_id = t.employee_id JOIN app_users u ON u.employee_id = e.manager_id
 WHERE t.status = 'submitted' GROUP BY u.user_id;

-- 36.5 FY2025 corporate income tax computation (ITF12C) ------------------------------------
INSERT INTO income_tax_computations (fiscal_year_id, profit_before_tax, add_backs, capital_allowances, exempt_income, foreign_branch_profit,
                                     taxable_income, tax_rate_pct, income_tax, aids_levy, foreign_tax_credit, total_tax, qpds_paid, status, filed_date, notes)
SELECT fy.fiscal_year_id, x.pbt, x.addb, x.ca, x.fv, 0,
       x.pbt + x.addb - x.ca - x.fv, 24, round((x.pbt + x.addb - x.ca - x.fv) * 0.24, 2), round((x.pbt + x.addb - x.ca - x.fv) * 0.24 * 0.03, 2),
       0, round((x.pbt + x.addb - x.ca - x.fv) * 0.2472, 2),
       (SELECT COALESCE(SUM(amount_paid), 0) FROM tax_returns WHERE tax_code = 'CIT_QPD' AND period_start >= '2025-01-01' AND period_end <= '2025-12-31'),
       'filed', '2026-04-28', 'Add-backs: accounting depreciation, donations, fines & non-deductible entertainment. Allowances: wear & tear per ZIMRA rates.'
  FROM fiscal_years fy
 CROSS JOIN LATERAL (SELECT (SELECT amount FROM fn_ifrs_profit_or_loss('2025-01-01','2025-12-31') WHERE line_code = 'ST_PBT') AS pbt,
                            fn_account_movement('7000','2025-01-01','2025-12-31') + fn_account_movement('7020','2025-01-01','2025-12-31')
                              + fn_account_movement('6950','2025-01-01','2025-12-31') AS addb,
                            round(fn_account_movement('7000','2025-01-01','2025-12-31') * 0.92, 2) AS ca,
                            110000::NUMERIC AS fv) x
 WHERE fy.name = 'FY2025';
-- the final balance was paid through the ITF12C return seeded in module 35
UPDATE tax_returns SET notes = 'FY2024 final - paid' WHERE return_number = 'ITF12C-2024';

-- 36.6 Period close -----------------------------------------------------------------------
INSERT INTO period_close_tasks (fiscal_period_id, task_name, owner_role, due_date, completed_by, completed_at)
SELECT fp.fiscal_period_id, t.name, t.role, fp.end_date + t.days, (SELECT employee_id FROM employees WHERE employee_number = t.who),
       CASE WHEN fp.end_date <= '2026-08-31' THEN (fp.end_date + t.days) + TIME '16:00' END
  FROM fiscal_periods fp JOIN fiscal_years fy USING (fiscal_year_id)
 CROSS JOIN (VALUES ('Issue all month-end invoices', 'ACCOUNTANT', 1, 'E025'), ('Run depreciation', 'FINANCE_MANAGER', 2, 'E025'),
                    ('Post IFRS 16 lease entries', 'FINANCE_MANAGER', 2, 'E025'), ('Bank reconciliations (all accounts)', 'ACCOUNTANT', 4, 'E025'),
                    ('Prepare VAT7, P2 and P4 returns', 'TAX_OFFICER', 5, 'E009'), ('Review AR ageing & ECL', 'FINANCE_MANAGER', 5, 'E006'),
                    ('Management accounts to CFO', 'FINANCE_MANAGER', 8, 'E025')) AS t(name, role, days, who)
 WHERE fy.name = 'FY2026' AND fp.period_no <= 9;

UPDATE fiscal_periods SET is_closed = TRUE
 WHERE fiscal_year_id = (SELECT fiscal_year_id FROM fiscal_years WHERE name = 'FY2025')
    OR (fiscal_year_id = (SELECT fiscal_year_id FROM fiscal_years WHERE name = 'FY2026') AND end_date <= '2026-08-31');
UPDATE fiscal_years SET is_closed = TRUE WHERE name IN ('FY2024','FY2025');

-- 36.7 Finish ------------------------------------------------------------------------------
SELECT set_config('erp.current_user_id', '', false);
SET erp.skip_audit = 'off';
-- refresh planner statistics for the ERP tables
DO $$ DECLARE t RECORD; BEGIN
    FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'erp' LOOP
        EXECUTE format('ANALYZE erp.%I', t.tablename);
    END LOOP;
END $$;
