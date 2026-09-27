
/* =====================================================================================
   16. REPORTING VIEWS
   ===================================================================================== */

-- 16.1 Monthly utilisation per consultant (billable hours / available capacity)
CREATE OR REPLACE VIEW v_employee_utilization_monthly AS
WITH hrs AS (
    SELECT te.employee_id,
           date_trunc('month', te.work_date)::DATE                AS month_start,
           SUM(te.hours)                                          AS total_hours,
           COALESCE(SUM(te.hours) FILTER (WHERE te.is_billable),0) AS billable_hours,
           COALESCE(SUM(te.billable_amount),0)                    AS billable_value
      FROM time_entries te
      JOIN timesheets ts ON ts.timesheet_id = te.timesheet_id
     WHERE ts.status IN ('submitted','approved')
     GROUP BY te.employee_id, date_trunc('month', te.work_date)
)
SELECT e.employee_id,
       e.employee_number,
       e.first_name || ' ' || e.last_name                                   AS employee_name,
       jg.name                                                              AS grade,
       d.name                                                               AS department,
       h.month_start,
       cap.capacity_hours,
       h.total_hours,
       h.billable_hours,
       h.billable_value,
       round(100 * h.billable_hours / NULLIF(cap.capacity_hours, 0), 1)     AS utilization_pct,
       e.target_utilization_pct,
       round(100 * h.billable_hours / NULLIF(cap.capacity_hours, 0), 1) - e.target_utilization_pct AS variance_to_target_pct
  FROM hrs h
  JOIN employees e        ON e.employee_id = h.employee_id
  LEFT JOIN job_grades jg ON jg.job_grade_id = e.job_grade_id
  LEFT JOIN departments d ON d.department_id = e.department_id
  LEFT JOIN offices o     ON o.office_id = e.office_id
  CROSS JOIN LATERAL (
      SELECT fn_working_days(h.month_start, (h.month_start + INTERVAL '1 month - 1 day')::DATE,
                             COALESCE(o.country_code, 'ZW')) * round(e.standard_hours_per_week / 5, 2) AS capacity_hours
  ) cap;

-- 16.2 Project financials: budget vs actual, WIP, margin
CREATE OR REPLACE VIEW v_project_financials AS
WITH t AS (
    SELECT te.project_id,
           SUM(te.hours)                                                    AS actual_hours,
           SUM(te.cost_amount)                                              AS labour_cost,
           SUM(te.billable_amount)                                          AS billable_value,
           SUM(te.billable_amount) FILTER (WHERE te.invoice_line_id IS NULL AND ts.status = 'approved') AS unbilled_wip
      FROM time_entries te JOIN timesheets ts ON ts.timesheet_id = te.timesheet_id
     WHERE te.project_id IS NOT NULL AND ts.status IN ('submitted','approved')
     GROUP BY te.project_id
), x AS (
    SELECT ei.project_id, SUM(ei.amount_base) AS expense_cost
      FROM expense_items ei JOIN expense_reports er ON er.expense_report_id = ei.expense_report_id
     WHERE er.status = 'approved' AND ei.project_id IS NOT NULL
     GROUP BY ei.project_id
), s AS (
    SELECT project_id, SUM(subtotal) AS subcontractor_cost
      FROM vendor_bills WHERE status <> 'void' AND project_id IS NOT NULL
     GROUP BY project_id
), i AS (
    SELECT project_id, SUM(subtotal) AS invoiced_net, SUM(amount_paid) AS collected
      FROM invoices WHERE status NOT IN ('draft','void') AND project_id IS NOT NULL
     GROUP BY project_id
)
SELECT p.project_id,
       p.project_code,
       p.name                                   AS project_name,
       c.legal_name                             AS client,
       p.status,
       p.billing_type,
       p.currency_code,
       p.budget_hours,
       COALESCE(t.actual_hours, 0)              AS actual_hours,
       round(100 * COALESCE(t.actual_hours,0) / NULLIF(p.budget_hours, 0), 1) AS hours_burn_pct,
       p.budget_fees,
       COALESCE(t.billable_value, 0)            AS billable_value,
       COALESCE(i.invoiced_net, 0)              AS invoiced_net,
       COALESCE(i.collected, 0)                 AS collected,
       CASE WHEN p.billing_type IN ('fixed_fee','milestone')        -- earned but not yet invoiced (negative = billed in advance)
            THEN round(p.budget_fees * p.completion_pct / 100, 2) - COALESCE(i.invoiced_net, 0)
            WHEN p.billing_type = 'retainer' THEN 0                    -- retainer hours are covered by the monthly fee
            ELSE COALESCE(t.unbilled_wip, 0) END                              AS unbilled_wip,
       CASE WHEN p.billing_type IN ('fixed_fee','milestone')
            THEN round(p.budget_fees * p.completion_pct / 100, 2)
            WHEN p.billing_type = 'retainer' THEN COALESCE(i.invoiced_net, 0)
            ELSE COALESCE(t.billable_value, 0) END                            AS revenue_earned,
       COALESCE(t.labour_cost, 0)               AS labour_cost,
       COALESCE(x.expense_cost, 0)              AS expense_cost,
       COALESCE(s.subcontractor_cost, 0)        AS subcontractor_cost,
       CASE WHEN p.billing_type IN ('fixed_fee','milestone')
            THEN round(p.budget_fees * p.completion_pct / 100, 2)
            WHEN p.billing_type = 'retainer' THEN COALESCE(i.invoiced_net, 0)
            ELSE COALESCE(t.billable_value, 0) END
         - COALESCE(t.labour_cost, 0) - COALESCE(x.expense_cost, 0) - COALESCE(s.subcontractor_cost, 0) AS gross_margin,
       round(100 * (CASE WHEN p.billing_type IN ('fixed_fee','milestone')
                         THEN p.budget_fees * p.completion_pct / 100
                         WHEN p.billing_type = 'retainer' THEN COALESCE(i.invoiced_net, 0)
                         ELSE COALESCE(t.billable_value, 0) END
                    - COALESCE(t.labour_cost,0) - COALESCE(x.expense_cost,0) - COALESCE(s.subcontractor_cost,0))
             / NULLIF(CASE WHEN p.billing_type IN ('fixed_fee','milestone')
                           THEN p.budget_fees * p.completion_pct / 100
                           WHEN p.billing_type = 'retainer' THEN COALESCE(i.invoiced_net, 0)
                           ELSE COALESCE(t.billable_value, 0) END, 0), 1)      AS gross_margin_pct
  FROM projects p
  LEFT JOIN clients c ON c.client_id = p.client_id
  LEFT JOIN t ON t.project_id = p.project_id
  LEFT JOIN x ON x.project_id = p.project_id
  LEFT JOIN s ON s.project_id = p.project_id
  LEFT JOIN i ON i.project_id = p.project_id
 WHERE NOT p.is_internal;

-- 16.3 Unbilled work in progress (approved, billable, not yet invoiced)
CREATE OR REPLACE VIEW v_unbilled_wip AS
SELECT p.project_code, p.name AS project_name, c.legal_name AS client,
       e.first_name || ' ' || e.last_name AS employee_name,
       min(te.work_date) AS earliest_date, max(te.work_date) AS latest_date,
       SUM(te.hours) AS hours, SUM(te.billable_amount) AS wip_value,
       CURRENT_DATE - min(te.work_date) AS days_unbilled
  FROM time_entries te
  JOIN timesheets ts ON ts.timesheet_id = te.timesheet_id
  JOIN projects p    ON p.project_id = te.project_id
  JOIN clients c     ON c.client_id = p.client_id
  JOIN employees e   ON e.employee_id = te.employee_id
 WHERE ts.status = 'approved' AND te.is_billable AND te.invoice_line_id IS NULL
   AND p.billing_type = 'time_and_materials'
 GROUP BY p.project_code, p.name, c.legal_name, e.first_name, e.last_name;

-- 16.4 Accounts receivable ageing
CREATE OR REPLACE VIEW v_ar_aging AS
SELECT i.invoice_id, i.invoice_number, c.client_code, c.legal_name AS client,
       i.invoice_date, i.due_date, i.currency_code, i.total_amount, i.amount_paid, i.balance_due,
       GREATEST(CURRENT_DATE - i.due_date, 0) AS days_overdue,
       CASE WHEN CURRENT_DATE <= i.due_date          THEN i.balance_due ELSE 0 END AS current_due,
       CASE WHEN CURRENT_DATE - i.due_date BETWEEN 1  AND 30 THEN i.balance_due ELSE 0 END AS days_1_30,
       CASE WHEN CURRENT_DATE - i.due_date BETWEEN 31 AND 60 THEN i.balance_due ELSE 0 END AS days_31_60,
       CASE WHEN CURRENT_DATE - i.due_date BETWEEN 61 AND 90 THEN i.balance_due ELSE 0 END AS days_61_90,
       CASE WHEN CURRENT_DATE - i.due_date > 90              THEN i.balance_due ELSE 0 END AS days_over_90
  FROM invoices i JOIN clients c ON c.client_id = i.client_id
 WHERE i.status IN ('issued','partially_paid','overdue') AND i.balance_due > 0;

CREATE OR REPLACE VIEW v_client_ar_summary AS
SELECT client_code, client, currency_code,
       COUNT(*) AS open_invoices,
       SUM(balance_due)  AS total_outstanding,
       SUM(current_due)  AS current_due,
       SUM(days_1_30)    AS days_1_30,
       SUM(days_31_60)   AS days_31_60,
       SUM(days_61_90)   AS days_61_90,
       SUM(days_over_90) AS days_over_90
  FROM v_ar_aging
 GROUP BY client_code, client, currency_code;

-- 16.5 Sales pipeline
CREATE OR REPLACE VIEW v_sales_pipeline AS
SELECT o.stage,
       sl.name                     AS service_line,
       o.currency_code,
       COUNT(*)                    AS opportunities,
       SUM(o.estimated_value)      AS total_value,
       SUM(o.weighted_value)       AS weighted_value,
       min(o.expected_close_date)  AS next_expected_close
  FROM opportunities o
  LEFT JOIN service_lines sl ON sl.service_line_id = o.service_line_id
 GROUP BY o.stage, sl.name, o.currency_code;

-- 16.6 Timesheet compliance for the last 4 complete weeks
CREATE OR REPLACE VIEW v_timesheet_compliance AS
SELECT e.employee_number,
       e.first_name || ' ' || e.last_name AS employee_name,
       m.first_name || ' ' || m.last_name AS manager_name,
       w.week_start::DATE                 AS week_start_date,
       COALESCE(ts.status::TEXT, 'missing') AS timesheet_status,
       COALESCE(ts.total_hours, 0)        AS hours_logged,
       e.standard_hours_per_week          AS expected_hours
  FROM employees e
  LEFT JOIN employees m ON m.employee_id = e.manager_id
  CROSS JOIN generate_series(date_trunc('week', CURRENT_DATE) - INTERVAL '4 weeks',
                             date_trunc('week', CURRENT_DATE) - INTERVAL '1 week',
                             INTERVAL '1 week') AS w(week_start)
  LEFT JOIN timesheets ts ON ts.employee_id = e.employee_id AND ts.week_start_date = w.week_start::DATE
 WHERE e.status = 'active' AND e.hire_date <= w.week_start::DATE;

-- 16.7 Resource capacity vs plan (weekly)
CREATE OR REPLACE VIEW v_resource_capacity AS
SELECT e.employee_id,
       e.first_name || ' ' || e.last_name AS employee_name,
       jg.name                            AS grade,
       ra.week_start_date,
       e.standard_hours_per_week          AS capacity_hours,
       SUM(ra.planned_hours)              AS planned_hours,
       e.standard_hours_per_week - SUM(ra.planned_hours) AS available_hours,
       round(100 * SUM(ra.planned_hours) / NULLIF(e.standard_hours_per_week, 0), 1) AS planned_load_pct,
       string_agg(p.project_code || ':' || ra.planned_hours, ', ' ORDER BY p.project_code) AS breakdown
  FROM resource_allocations ra
  JOIN employees e        ON e.employee_id = ra.employee_id
  LEFT JOIN job_grades jg ON jg.job_grade_id = e.job_grade_id
  JOIN projects p         ON p.project_id = ra.project_id
 GROUP BY e.employee_id, e.first_name, e.last_name, jg.name, ra.week_start_date, e.standard_hours_per_week;

-- 16.8 Project health dashboard
CREATE OR REPLACE VIEW v_project_health AS
SELECT p.project_code, p.name AS project_name, p.status,
       pm.first_name || ' ' || pm.last_name AS project_manager,
       sr.report_date AS last_status_report, sr.overall_rag, sr.schedule_rag, sr.budget_rag,
       (SELECT COUNT(*) FROM project_risks r  WHERE r.project_id = p.project_id AND r.status IN ('open','mitigating'))    AS open_risks,
       (SELECT MAX(risk_score) FROM project_risks r WHERE r.project_id = p.project_id AND r.status IN ('open','mitigating')) AS top_risk_score,
       (SELECT COUNT(*) FROM project_issues i WHERE i.project_id = p.project_id AND i.status IN ('open','in_progress'))    AS open_issues,
       (SELECT COUNT(*) FROM deliverables d   WHERE d.project_id = p.project_id AND d.status NOT IN ('accepted')
                                               AND d.due_date < CURRENT_DATE)                                            AS overdue_deliverables,
       f.hours_burn_pct, p.completion_pct, f.gross_margin_pct
  FROM projects p
  LEFT JOIN employees pm ON pm.employee_id = p.project_manager_id
  LEFT JOIN LATERAL (SELECT * FROM project_status_reports s WHERE s.project_id = p.project_id
                     ORDER BY report_date DESC LIMIT 1) sr ON TRUE
  LEFT JOIN v_project_financials f ON f.project_id = p.project_id
 WHERE p.status IN ('planned','active','on_hold');

-- 16.9 Trial balance (posted journals only)
CREATE OR REPLACE VIEW v_trial_balance AS
SELECT a.account_code, a.name AS account_name, a.account_type,
       COALESCE(SUM(jl.debit), 0)  AS total_debit,
       COALESCE(SUM(jl.credit), 0) AS total_credit,
       CASE WHEN a.account_type IN ('asset','expense')
            THEN COALESCE(SUM(jl.debit),0) - COALESCE(SUM(jl.credit),0)
            ELSE COALESCE(SUM(jl.credit),0) - COALESCE(SUM(jl.debit),0) END AS balance
  FROM chart_of_accounts a
  LEFT JOIN journal_lines jl   ON jl.account_id = a.account_id
  LEFT JOIN journal_entries je ON je.journal_entry_id = jl.journal_entry_id
 WHERE a.is_postable AND (je.status IN ('posted','reversed') OR jl.journal_line_id IS NULL)
 GROUP BY a.account_code, a.name, a.account_type;

-- 16.10 Monthly income statement
CREATE OR REPLACE VIEW v_income_statement_monthly AS
SELECT date_trunc('month', je.entry_date)::DATE AS month_start,
       a.account_type, a.account_code, a.name AS account_name,
       SUM(CASE WHEN a.account_type = 'revenue' THEN jl.credit - jl.debit ELSE jl.debit - jl.credit END) AS amount
  FROM journal_lines jl
  JOIN journal_entries je  ON je.journal_entry_id = jl.journal_entry_id
  JOIN chart_of_accounts a ON a.account_id = jl.account_id
 WHERE je.status IN ('posted','reversed') AND a.account_type IN ('revenue','expense')
 GROUP BY 1, 2, 3, 4;

-- 16.11 Leave balances with names
CREATE OR REPLACE VIEW v_leave_balances AS
SELECT e.employee_number, e.first_name || ' ' || e.last_name AS employee_name,
       lt.name AS leave_type, lb.leave_year, lb.entitled_days, lb.carried_forward_days,
       lb.taken_days, lb.remaining_days
  FROM leave_balances lb
  JOIN employees e    ON e.employee_id = lb.employee_id
  JOIN leave_types lt ON lt.leave_type_id = lb.leave_type_id;

-- 16.12 Certifications expiring in the next 90 days
CREATE OR REPLACE VIEW v_expiring_certifications AS
SELECT e.employee_number, e.first_name || ' ' || e.last_name AS employee_name,
       c.name AS certification, c.issuing_body, c.expiry_date, c.expiry_date - CURRENT_DATE AS days_left
  FROM certifications c JOIN employees e ON e.employee_id = c.employee_id
 WHERE c.expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 90 AND e.status = 'active';

