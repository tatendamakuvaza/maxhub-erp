
/* =====================================================================================
   34. SEED - LEAVE, TIMESHEETS & TIME ENTRIES (5 Jan - 24 Sep 2026), PROJECT GOVERNANCE
   -------------------------------------------------------------------------------------
   * Every fee earner books 8 hours a day: client work on the engagements they are
     staffed on (according to their utilisation target), the rest internal time.
   * Public holidays and approved annual leave are booked as HOLIDAY / LEAVE.
   * Timesheets up to week 7 Sep are approved; week 14 Sep is waiting for approval;
     the current week (21 Sep) is still a draft.
   ===================================================================================== */

-- 34.1 Leave ------------------------------------------------------------------------------
INSERT INTO leave_requests (employee_id, leave_type_id, start_date, end_date, days_requested, reason, status, approver_id, created_at)
SELECT e.employee_id, (SELECT leave_type_id FROM leave_types WHERE code = 'AL'),
       w.ws, w.ws + 4, 5, 'Annual leave', 'submitted', COALESCE(e.manager_id, e.employee_id),
       w.ws - 21
  FROM employees e
 CROSS JOIN LATERAL (SELECT ('2026-01-12'::DATE + (7 * ((e.employee_id * 7) % 33))::INT) AS ws) w
 WHERE e.employee_number <> 'E001';
UPDATE leave_requests SET status = 'approved', decision_comment = 'Approved' WHERE status = 'submitted';

-- sick leave for some people, and a few requests still waiting for approval
INSERT INTO leave_requests (employee_id, leave_type_id, start_date, end_date, days_requested, reason, status, approver_id)
SELECT e.employee_id, (SELECT leave_type_id FROM leave_types WHERE code = 'SL'), d, d + 1, 2, 'Flu - doctor''s note attached', 'submitted', e.manager_id
  FROM employees e CROSS JOIN LATERAL (SELECT ('2026-02-03'::DATE + (7 * (e.employee_id % 28))::INT) AS d) x
 WHERE e.employee_id % 9 = 0 AND e.manager_id IS NOT NULL;
UPDATE leave_requests SET status = 'approved', decision_comment = 'Get well soon' WHERE status = 'submitted';

INSERT INTO leave_requests (employee_id, leave_type_id, start_date, end_date, days_requested, reason, status, approver_id)
SELECT e.employee_id, (SELECT leave_type_id FROM leave_types WHERE code = v.lt), v.s::DATE, v.e::DATE, v.d, v.r, 'submitted', e.manager_id
  FROM (VALUES ('E005','AL','2026-10-12','2026-10-16',5,'Family trip to Victoria Falls'),
               ('E031','AL','2026-10-26','2026-10-30',5,'Wedding'),
               ('E040','SP','2026-11-02','2026-11-06',5,'CFE exam preparation'),
               ('E052','AL','2026-12-21','2026-12-31',7,'Christmas holiday'),
               ('E063','CL','2026-09-28','2026-09-30',3,'Family bereavement')) AS v(num, lt, s, e, d, r)
  JOIN employees e ON e.employee_number = v.num;

-- 34.2 Timesheets -------------------------------------------------------------------------
UPDATE employees SET manager_id = (SELECT employee_id FROM employees WHERE employee_number = 'E004') WHERE employee_number = 'E005';

INSERT INTO timesheets (employee_id, week_start_date, status)
SELECT e.employee_id, w::DATE, 'draft'
  FROM employees e CROSS JOIN generate_series('2026-01-05'::DATE, '2026-09-21'::DATE, INTERVAL '7 days') w
 WHERE e.is_billable AND e.hire_date <= w::DATE + 4;

CREATE TEMP TABLE seed_days AS
SELECT t.timesheet_id, t.employee_id, t.week_start_date, d::DATE AS wd,
       (t.week_start_date - '2026-01-05'::DATE) / 7 + 1 AS wn, extract(isodow FROM d)::INT AS dow,
       o.country_code, e.target_utilization_pct AS tu, g.level,
       EXISTS (SELECT 1 FROM public_holidays h WHERE h.country_code = o.country_code AND h.holiday_date = d::DATE) AS is_holiday,
       EXISTS (SELECT 1 FROM leave_requests lr WHERE lr.employee_id = t.employee_id AND lr.status = 'approved'
                  AND d::DATE BETWEEN lr.start_date AND lr.end_date) AS is_leave
  FROM timesheets t
  JOIN employees e ON e.employee_id = t.employee_id
  JOIN job_grades g ON g.job_grade_id = e.job_grade_id
  JOIN offices o ON o.office_id = e.office_id
 CROSS JOIN LATERAL generate_series(t.week_start_date,
                                    t.week_start_date + CASE WHEN t.week_start_date = '2026-09-21' THEN 3 ELSE 4 END, INTERVAL '1 day') d
 WHERE d::DATE >= e.hire_date;

-- holidays & leave
INSERT INTO time_entries (timesheet_id, employee_id, project_id, activity_code, work_date, hours, is_billable, description)
SELECT timesheet_id, employee_id, NULL, CASE WHEN is_holiday THEN 'HOLIDAY' ELSE 'LEAVE' END, wd, 8, FALSE,
       CASE WHEN is_holiday THEN 'Public holiday' ELSE 'Annual / sick leave' END
  FROM seed_days WHERE is_holiday OR is_leave;

-- client work: split the day's billable hours across the engagements active that day (max 3)
CREATE TEMP TABLE seed_client_time AS
WITH active AS (
    SELECT d.*, pm.project_id,
           row_number() OVER (PARTITION BY d.employee_id, d.wd ORDER BY p.priority DESC, pm.allocation_pct DESC, p.project_id) AS rk
      FROM seed_days d
      JOIN project_members pm ON pm.employee_id = d.employee_id AND d.wd BETWEEN pm.start_date AND COALESCE(pm.end_date, 'infinity')
      JOIN projects p ON p.project_id = pm.project_id AND NOT p.is_internal AND d.wd BETWEEN p.start_date AND p.planned_end_date
     WHERE NOT d.is_holiday AND NOT d.is_leave
),
lim AS (SELECT *, count(*) OVER (PARTITION BY employee_id, wd) AS n FROM active WHERE rk <= 3)
SELECT timesheet_id, employee_id, project_id, wd, rk, n,
       GREATEST(0.5, round(LEAST(8, 8 * tu / 100 * (0.92 + ((employee_id * 31 + wn * 17 + dow * 7) % 19) / 100.0)) / n * 2) / 2) AS hours
  FROM lim;

INSERT INTO time_entries (timesheet_id, employee_id, project_id, task_id, activity_code, work_date, hours, is_billable, description)
SELECT c.timesheet_id, c.employee_id, c.project_id,
       (SELECT t.task_id FROM tasks t JOIN project_phases ph ON ph.phase_id = t.phase_id
         WHERE t.project_id = c.project_id AND c.wd BETWEEN ph.start_date AND ph.end_date
         ORDER BY (t.task_id + c.employee_id) % 3 LIMIT 1),
       'CLIENT', c.wd, c.hours, TRUE,
       (ARRAY['Data analysis & testing','Interviews and document review','Working papers & findings','Client meeting',
              'Report drafting','Evidence review & chain of custody','Analytics scripting & validation'])[1 + (c.employee_id + extract(doy FROM c.wd)::INT) % 7]
  FROM seed_client_time c;

-- internal time for the rest of each working day
INSERT INTO time_entries (timesheet_id, employee_id, project_id, activity_code, work_date, hours, is_billable, description)
SELECT d.timesheet_id, d.employee_id,
       CASE x.act WHEN 'BD' THEN (SELECT project_id FROM projects WHERE project_code = 'INT-26-BD')
                  WHEN 'KM' THEN (SELECT project_id FROM projects WHERE project_code = 'INT-26-KM') END,
       x.act, d.wd, 8 - COALESCE(s.billed, 0), FALSE,
       CASE x.act WHEN 'BD' THEN 'Proposals & client development' WHEN 'KM' THEN 'Methodology & tools'
                  WHEN 'TRAINING' THEN 'CPD / certification study' ELSE 'Admin, e-mail & internal meetings' END
  FROM seed_days d
  LEFT JOIN (SELECT employee_id, wd, SUM(hours) AS billed FROM seed_client_time GROUP BY 1, 2) s ON s.employee_id = d.employee_id AND s.wd = d.wd
 CROSS JOIN LATERAL (SELECT CASE WHEN d.level >= 5 THEN 'BD' ELSE (ARRAY['ADMIN','KM','TRAINING','ADMIN','BD'])[1 + (d.employee_id + d.dow) % 5] END AS act) x
 WHERE NOT d.is_holiday AND NOT d.is_leave AND 8 - COALESCE(s.billed, 0) > 0;

-- statuses
UPDATE timesheets t SET status = 'approved', submitted_at = (t.week_start_date + 4) + TIME '17:10',
       approved_by = COALESCE(e.manager_id, (SELECT employee_id FROM employees WHERE employee_number = 'E018')),
       approved_at = (t.week_start_date + 8) + TIME '09:30'
  FROM employees e WHERE e.employee_id = t.employee_id AND t.week_start_date <= '2026-09-07';
UPDATE timesheets t SET status = 'submitted', submitted_at = '2026-09-18 16:45+02'
 WHERE t.week_start_date = '2026-09-14' AND t.employee_id % 4 <> 0;
UPDATE timesheets t SET status = 'approved', submitted_at = '2026-09-18 16:45+02', approved_by = e.manager_id, approved_at = '2026-09-21 08:30+02'
  FROM employees e WHERE e.employee_id = t.employee_id AND t.week_start_date = '2026-09-14' AND t.employee_id % 4 = 0 AND e.manager_id IS NOT NULL;
UPDATE timesheets t SET status = 'rejected', approved_by = e.manager_id,
       rejection_reason = 'Please split the hours between the two engagements and add task descriptions.'
  FROM employees e WHERE e.employee_id = t.employee_id AND t.week_start_date = '2026-09-14' AND t.employee_id IN (37, 58);
UPDATE timesheets SET status = 'submitted', submitted_at = '2026-09-18 16:45+02'
 WHERE week_start_date = '2026-09-14' AND status = 'draft';

-- 34.3 Project progress, governance & forecast --------------------------------------------
UPDATE projects p SET status = 'completed', actual_end_date = sp.finish, completion_pct = 100
  FROM seed_projects sp WHERE sp.code = p.project_code AND sp.final_status = 'completed';
UPDATE projects p
   SET completion_pct = LEAST(95, round(100.0 * (CURRENT_DATE - p.start_date) / GREATEST(p.planned_end_date - p.start_date, 1)))
 WHERE p.status = 'active' AND NOT p.is_internal;
UPDATE project_phases ph SET status = CASE WHEN p.status = 'completed' OR ph.end_date < CURRENT_DATE THEN 'completed'::project_status
                                           WHEN ph.start_date > CURRENT_DATE THEN 'planned'::project_status ELSE 'active'::project_status END
  FROM projects p WHERE p.project_id = ph.project_id;
UPDATE tasks t SET status = CASE ph.status WHEN 'completed' THEN 'done'::task_status WHEN 'active' THEN 'in_progress'::task_status ELSE 'todo'::task_status END,
       assignee_id = (SELECT pm.employee_id FROM project_members pm WHERE pm.project_id = t.project_id ORDER BY (pm.employee_id + t.task_id) % 5 LIMIT 1),
       completed_at = CASE WHEN ph.status = 'completed' THEN ph.end_date + TIME '17:00' END
  FROM project_phases ph WHERE ph.phase_id = t.phase_id;

INSERT INTO project_status_reports (project_id, report_date, overall_rag, schedule_rag, budget_rag, scope_rag, summary, accomplishments, next_steps, author_id)
SELECT p.project_id, r.d,
       CASE WHEN p.priority = 'critical' AND r.d > '2026-08-01' THEN 'A' WHEN p.project_id % 7 = 0 THEN 'R' ELSE 'G' END,
       CASE WHEN p.project_id % 5 = 0 THEN 'A' ELSE 'G' END, CASE WHEN p.project_id % 7 = 0 THEN 'R' ELSE 'G' END, 'G',
       'Engagement progressing; key findings shared with the client steering committee.',
       'Data analytics completed for the period; interviews held with management.',
       'Finalise findings and prepare draft report for QRM review.', p.project_manager_id
  FROM projects p CROSS JOIN (VALUES ('2026-07-31'::DATE), ('2026-08-28'::DATE), ('2026-09-18'::DATE)) AS r(d)
 WHERE p.status = 'active' AND NOT p.is_internal AND p.start_date < r.d;

INSERT INTO project_risks (project_id, title, description, probability, impact, mitigation, owner_id, status, raised_date)
SELECT p.project_id, v.t, v.d, v.p, v.i, v.m, p.project_manager_id, 'open', p.start_date + 20
  FROM projects p
 CROSS JOIN (VALUES ('Delayed access to client data','ERP extracts not yet provided by client IT',3,4,'Escalate via steering committee; use sample data'),
                    ('Key witness unavailable','Former employee has left the country',2,4,'Arrange remote interview through counsel')) AS v(t, d, p, i, m)
 WHERE p.status = 'active' AND NOT p.is_internal AND (p.project_id + length(v.t)) % 3 = 0;

INSERT INTO project_issues (project_id, title, description, priority, status, raised_by, assigned_to, raised_date)
SELECT p.project_id, 'Scope change requested by client', 'Client asked to extend the review period by 12 months.', 'high', 'open',
       p.project_manager_id, p.engagement_partner_id, '2026-09-10'
  FROM projects p WHERE p.status = 'active' AND NOT p.is_internal AND p.project_id % 6 = 1;

INSERT INTO deliverables (project_id, name, owner_id, due_date, delivered_date, status)
SELECT p.project_id, d.name, p.project_manager_id, p.start_date + ((p.planned_end_date - p.start_date) * d.f)::INT,
       CASE WHEN p.start_date + ((p.planned_end_date - p.start_date) * d.f)::INT < CURRENT_DATE THEN p.start_date + ((p.planned_end_date - p.start_date) * d.f)::INT END,
       CASE WHEN p.start_date + ((p.planned_end_date - p.start_date) * d.f)::INT < CURRENT_DATE THEN 'accepted' ELSE 'pending' END
  FROM projects p CROSS JOIN (VALUES ('Inception report', 0.1), ('Interim findings', 0.6), ('Final report', 1.0)) AS d(name, f)
 WHERE NOT p.is_internal;

INSERT INTO resource_allocations (employee_id, project_id, week_start_date, planned_hours, is_tentative)
SELECT pm.employee_id, pm.project_id, w::DATE, CASE WHEN pm.project_role LIKE 'Engagement%' THEN 8 ELSE 24 END, w::DATE > '2026-10-12'
  FROM project_members pm JOIN projects p ON p.project_id = pm.project_id AND p.status = 'active' AND NOT p.is_internal
 CROSS JOIN generate_series('2026-09-28'::DATE, '2026-10-26'::DATE, INTERVAL '7 days') w
 WHERE w::DATE <= p.planned_end_date
ON CONFLICT DO NOTHING;
