
/* =====================================================================================
   17. INDEXES (foreign keys & frequent filters)
   ===================================================================================== */
CREATE INDEX ix_employees_manager        ON employees (manager_id);
CREATE INDEX ix_employees_department     ON employees (department_id);
CREATE INDEX ix_employees_status         ON employees (status);
CREATE INDEX ix_clients_account_manager  ON clients (account_manager_id);
CREATE INDEX ix_clients_status           ON clients (status);
CREATE INDEX ix_contacts_client          ON client_contacts (client_id);
CREATE INDEX ix_opportunities_client     ON opportunities (client_id);
CREATE INDEX ix_opportunities_stage      ON opportunities (stage, expected_close_date);
CREATE INDEX ix_crm_activities_client    ON crm_activities (client_id, activity_date DESC);
CREATE INDEX ix_contracts_client         ON contracts (client_id);
CREATE INDEX ix_projects_client          ON projects (client_id);
CREATE INDEX ix_projects_status          ON projects (status);
CREATE INDEX ix_projects_pm              ON projects (project_manager_id);
CREATE INDEX ix_tasks_project            ON tasks (project_id, status);
CREATE INDEX ix_tasks_assignee           ON tasks (assignee_id) WHERE status <> 'done';
CREATE INDEX ix_project_members_emp      ON project_members (employee_id);
CREATE INDEX ix_alloc_week               ON resource_allocations (week_start_date);
CREATE INDEX ix_timesheets_status        ON timesheets (status, week_start_date);
CREATE INDEX ix_time_entries_timesheet   ON time_entries (timesheet_id);
CREATE INDEX ix_time_entries_emp_date    ON time_entries (employee_id, work_date);
CREATE INDEX ix_time_entries_project     ON time_entries (project_id, work_date);
CREATE INDEX ix_time_entries_unbilled    ON time_entries (project_id) WHERE invoice_line_id IS NULL AND is_billable;
CREATE INDEX ix_expense_items_report     ON expense_items (expense_report_id);
CREATE INDEX ix_expense_items_project    ON expense_items (project_id);
CREATE INDEX ix_invoices_client          ON invoices (client_id, status);
CREATE INDEX ix_invoices_project         ON invoices (project_id);
CREATE INDEX ix_invoices_open_due        ON invoices (due_date) WHERE status IN ('issued','partially_paid','overdue');
CREATE INDEX ix_invoice_lines_invoice    ON invoice_lines (invoice_id);
CREATE INDEX ix_payments_client          ON payments (client_id, payment_date);
CREATE INDEX ix_payment_alloc_invoice    ON payment_allocations (invoice_id);
CREATE INDEX ix_journal_entries_date     ON journal_entries (entry_date);
CREATE INDEX ix_journal_lines_account    ON journal_lines (account_id);
CREATE INDEX ix_journal_lines_project    ON journal_lines (project_id);
CREATE INDEX ix_leave_requests_emp       ON leave_requests (employee_id, start_date);
CREATE INDEX ix_documents_entity         ON documents (entity_type, entity_id);
CREATE INDEX ix_comments_entity          ON comments (entity_type, entity_id);
CREATE INDEX ix_notifications_user       ON notifications (user_id) WHERE NOT is_read;
CREATE INDEX ix_audit_log_table_pk       ON audit_log (table_name, record_pk);
CREATE INDEX ix_audit_log_changed_at     ON audit_log (changed_at);


-- indexes for the new modules
CREATE INDEX ix_journal_lines_office     ON journal_lines (office_id);
CREATE INDEX ix_payslips_employee        ON payslips (employee_id);
CREATE INDEX ix_fixed_assets_category    ON fixed_assets (asset_category_id);
CREATE INDEX ix_fixed_assets_custodian   ON fixed_assets (custodian_employee_id);
CREATE INDEX ix_asset_dep_period         ON asset_depreciation (period_end);
CREATE INDEX ix_lease_schedule_period    ON lease_schedule (period_date);
CREATE INDEX ix_tax_returns_due          ON tax_returns (due_date, status);
CREATE INDEX ix_msg_recipients_inbox     ON message_recipients (recipient_id, read_at);
CREATE INDEX ix_login_attempts_time      ON login_attempts (attempted_at);
CREATE INDEX ix_login_attempts_user      ON login_attempts (user_id);
CREATE INDEX ix_user_sessions_user       ON user_sessions (user_id);
CREATE INDEX ix_invoices_date            ON invoices (invoice_date);


/* =====================================================================================
   HARDENING
   ===================================================================================== */

-- The audit log is append-only: block UPDATE / DELETE from any application session
CREATE OR REPLACE FUNCTION fn_audit_log_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'audit_log is append-only';
END $$;
CREATE TRIGGER trg_audit_log_immutable BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log_immutable();

-- Pin search_path on every routine so they work regardless of the caller's search_path
-- (and cannot be hijacked by objects in other schemas).
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT p.oid::regprocedure AS sig, p.prokind
               FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'erp'
    LOOP
        EXECUTE format('ALTER %s %s SET search_path = erp, public',
                       CASE r.prokind WHEN 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END, r.sig);
    END LOOP;
END $$;
