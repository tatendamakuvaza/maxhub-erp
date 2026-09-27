
/* =====================================================================================
   15. BUSINESS LOGIC - FUNCTIONS, TRIGGERS & PROCEDURES
   ===================================================================================== */

/* ---------- 15.1 Generic helpers ---------- */

-- Keep updated_at current
CREATE OR REPLACE FUNCTION fn_set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END $$;

-- Generic audit trail. TG_ARGV[0] = name of primary-key column
CREATE OR REPLACE FUNCTION fn_audit() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_user BIGINT := NULLIF(current_setting('erp.current_user_id', true), '')::BIGINT;
    v_row  JSONB  := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
BEGIN
    -- bulk data loads (seed/migration) can switch auditing off for their session only
    IF current_setting('erp.skip_audit', true) = 'on' THEN RETURN NULL; END IF;
    INSERT INTO audit_log (table_name, record_pk, action, old_data, new_data, changed_by)
    VALUES (TG_TABLE_NAME,
            v_row ->> TG_ARGV[0],
            TG_OP,
            CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) END,
            CASE WHEN TG_OP IN ('UPDATE','INSERT') THEN to_jsonb(NEW) END,
            v_user);
    RETURN NULL;
END $$;

-- Next formatted document number, e.g. INV-2026-00001
CREATE OR REPLACE FUNCTION fn_next_doc_number(p_doc_type TEXT, p_date DATE DEFAULT CURRENT_DATE)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
    r document_sequences%ROWTYPE;
BEGIN
    UPDATE document_sequences
       SET next_value = next_value + 1
     WHERE doc_type = p_doc_type
    RETURNING * INTO r;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No document sequence configured for "%"', p_doc_type;
    END IF;
    RETURN r.prefix
        || CASE WHEN r.include_year THEN to_char(p_date, 'YYYY') || '-' ELSE '' END
        || lpad((r.next_value - 1)::TEXT, r.padding, '0');
END $$;

-- Trigger wrapper: TG_ARGV[0] = doc_type, TG_ARGV[1] = column to fill
CREATE OR REPLACE FUNCTION fn_assign_doc_number() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE j JSONB := to_jsonb(NEW); v_date DATE;
BEGIN
    IF j ->> TG_ARGV[1] IS NULL THEN
        -- number the document in the year of its own date (invoice_date, payment_date, entry_date ...)
        v_date := COALESCE((j->>'invoice_date')::DATE, (j->>'payment_date')::DATE, (j->>'entry_date')::DATE,
                           (j->>'order_date')::DATE, CURRENT_DATE);
        NEW := jsonb_populate_record(NEW, jsonb_build_object(TG_ARGV[1], fn_next_doc_number(TG_ARGV[0], v_date)));
    END IF;
    RETURN NEW;
END $$;

-- Look up a GL account id by code (raises if missing)
CREATE OR REPLACE FUNCTION fn_account_id(p_code TEXT) RETURNS BIGINT LANGUAGE plpgsql STABLE AS $$
DECLARE v_id BIGINT;
BEGIN
    SELECT account_id INTO v_id FROM chart_of_accounts WHERE account_code = p_code AND is_active;
    IF v_id IS NULL THEN
        RAISE EXCEPTION 'GL account % not found or inactive', p_code;
    END IF;
    RETURN v_id;
END $$;

-- Working days (Mon-Fri, excluding public holidays) between two dates inclusive
CREATE OR REPLACE FUNCTION fn_working_days(p_from DATE, p_to DATE, p_country CHAR(2) DEFAULT 'ZW')
RETURNS INTEGER LANGUAGE sql STABLE AS $$
    SELECT count(*)::INT
      FROM generate_series(p_from, p_to, INTERVAL '1 day') AS g(d)
     WHERE extract(isodow FROM g.d) < 6
       AND NOT EXISTS (SELECT 1 FROM public_holidays h
                        WHERE h.country_code = p_country AND h.holiday_date = g.d::DATE);
$$;


/* ---------- 15.2 Time entry rules ---------- */

CREATE OR REPLACE FUNCTION fn_time_entry_validate() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_ts        timesheets%ROWTYPE;
    v_member    project_members%ROWTYPE;
    v_emp       employees%ROWTYPE;
    v_proj      projects%ROWTYPE;
    v_card_rate NUMERIC;
    v_day_total NUMERIC;
BEGIN
    -- Allow the billing process to stamp invoice_line_id on locked entries
    IF TG_OP = 'UPDATE'
       AND (NEW.hours, NEW.work_date, NEW.project_id, NEW.task_id, NEW.is_billable, NEW.bill_rate,
            NEW.cost_rate, NEW.employee_id, NEW.timesheet_id)
           IS NOT DISTINCT FROM
           (OLD.hours, OLD.work_date, OLD.project_id, OLD.task_id, OLD.is_billable, OLD.bill_rate,
            OLD.cost_rate, OLD.employee_id, OLD.timesheet_id) THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' AND OLD.invoice_line_id IS NOT NULL THEN
        RAISE EXCEPTION 'Time entry % has already been invoiced and cannot be changed', OLD.time_entry_id;
    END IF;

    SELECT * INTO v_ts FROM timesheets WHERE timesheet_id = NEW.timesheet_id;
    IF v_ts.status NOT IN ('draft','rejected') THEN
        RAISE EXCEPTION 'Timesheet % is % - entries are locked', v_ts.timesheet_id, v_ts.status;
    END IF;
    IF NEW.employee_id IS NULL THEN
        NEW.employee_id := v_ts.employee_id;
    ELSIF NEW.employee_id <> v_ts.employee_id THEN
        RAISE EXCEPTION 'Time entry employee does not match timesheet owner';
    END IF;
    IF NEW.work_date NOT BETWEEN v_ts.week_start_date AND v_ts.week_start_date + 6 THEN
        RAISE EXCEPTION 'Work date % is outside timesheet week starting %', NEW.work_date, v_ts.week_start_date;
    END IF;

    -- Max 24h per person per day
    SELECT COALESCE(SUM(hours), 0) INTO v_day_total
      FROM time_entries
     WHERE employee_id = NEW.employee_id AND work_date = NEW.work_date
       AND time_entry_id <> NEW.time_entry_id;
    IF v_day_total + NEW.hours > 24 THEN
        RAISE EXCEPTION 'Total hours for % on % would exceed 24', NEW.employee_id, NEW.work_date;
    END IF;

    SELECT * INTO v_emp FROM employees WHERE employee_id = NEW.employee_id;

    IF NEW.project_id IS NULL THEN
        -- internal time is never billable
        NEW.is_billable := FALSE;
        NEW.bill_rate   := 0;
        NEW.cost_rate   := COALESCE(NEW.cost_rate, v_emp.cost_rate_hourly, 0);
        IF NEW.activity_code = 'CLIENT' THEN NEW.activity_code := 'ADMIN'; END IF;
        RETURN NEW;
    END IF;

    SELECT * INTO v_proj FROM projects WHERE project_id = NEW.project_id;
    IF v_proj.status NOT IN ('active','planned') THEN
        RAISE EXCEPTION 'Project % is % - time cannot be booked', v_proj.project_code, v_proj.status;
    END IF;
    IF v_proj.is_internal THEN
        NEW.is_billable := FALSE;
    END IF;

    -- Must be staffed on the project on that date
    SELECT * INTO v_member
      FROM project_members
     WHERE project_id = NEW.project_id AND employee_id = NEW.employee_id
       AND NEW.work_date BETWEEN start_date AND COALESCE(end_date, 'infinity'::DATE)
     ORDER BY start_date DESC
     LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Employee % is not assigned to project % on %',
              v_emp.employee_number, v_proj.project_code, NEW.work_date;
    END IF;

    -- Task must belong to the project
    IF NEW.task_id IS NOT NULL AND NOT EXISTS
       (SELECT 1 FROM tasks WHERE task_id = NEW.task_id AND project_id = NEW.project_id) THEN
        RAISE EXCEPTION 'Task % does not belong to project %', NEW.task_id, v_proj.project_code;
    END IF;

    -- Rate defaulting: project member -> contract rate card -> employee default -> grade default
    IF NEW.bill_rate IS NULL THEN
        SELECT rcl.hourly_rate INTO v_card_rate
          FROM contracts c
          JOIN rate_card_lines rcl ON rcl.rate_card_id = c.rate_card_id
         WHERE c.contract_id = v_proj.contract_id
           AND rcl.job_grade_id = v_emp.job_grade_id;

        NEW.bill_rate := COALESCE(v_member.bill_rate, v_card_rate, v_emp.default_bill_rate,
                                  (SELECT default_bill_rate FROM job_grades WHERE job_grade_id = v_emp.job_grade_id), 0);
    END IF;
    IF NEW.cost_rate IS NULL THEN
        NEW.cost_rate := COALESCE(v_member.cost_rate, v_emp.cost_rate_hourly,
                                  (SELECT default_cost_rate FROM job_grades WHERE job_grade_id = v_emp.job_grade_id), 0);
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_time_entries_validate
    BEFORE INSERT OR UPDATE ON time_entries
    FOR EACH ROW EXECUTE FUNCTION fn_time_entry_validate();

CREATE OR REPLACE FUNCTION fn_time_entry_lock_delete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.invoice_line_id IS NOT NULL THEN
        RAISE EXCEPTION 'Invoiced time entry % cannot be deleted', OLD.time_entry_id;
    END IF;
    IF EXISTS (SELECT 1 FROM timesheets WHERE timesheet_id = OLD.timesheet_id AND status IN ('submitted','approved')) THEN
        RAISE EXCEPTION 'Entries on a submitted/approved timesheet cannot be deleted';
    END IF;
    RETURN OLD;
END $$;

CREATE TRIGGER trg_time_entries_lock_delete
    BEFORE DELETE ON time_entries
    FOR EACH ROW EXECUTE FUNCTION fn_time_entry_lock_delete();

-- Keep timesheets.total_hours in sync
CREATE OR REPLACE FUNCTION fn_timesheet_total() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_ids BIGINT[];
BEGIN
    v_ids := CASE TG_OP
               WHEN 'INSERT' THEN ARRAY[NEW.timesheet_id]
               WHEN 'DELETE' THEN ARRAY[OLD.timesheet_id]
               ELSE ARRAY[NEW.timesheet_id, OLD.timesheet_id] END;
    UPDATE timesheets t
       SET total_hours = COALESCE((SELECT SUM(hours) FROM time_entries e WHERE e.timesheet_id = t.timesheet_id), 0)
     WHERE t.timesheet_id = ANY (v_ids);
    RETURN NULL;
END $$;

CREATE TRIGGER trg_time_entries_total
    AFTER INSERT OR UPDATE OF hours, timesheet_id OR DELETE ON time_entries
    FOR EACH ROW EXECUTE FUNCTION fn_timesheet_total();

-- Timesheet workflow
CREATE OR REPLACE PROCEDURE sp_submit_timesheet(p_timesheet_id BIGINT)
LANGUAGE plpgsql AS $$
DECLARE v_status approval_status; v_hours NUMERIC;
BEGIN
    SELECT status, total_hours INTO v_status, v_hours FROM timesheets WHERE timesheet_id = p_timesheet_id FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Timesheet % not found', p_timesheet_id; END IF;
    IF v_status NOT IN ('draft','rejected') THEN
        RAISE EXCEPTION 'Only draft/rejected timesheets can be submitted (current: %)', v_status;
    END IF;
    IF v_hours <= 0 THEN RAISE EXCEPTION 'Cannot submit an empty timesheet'; END IF;
    UPDATE timesheets SET status = 'submitted', submitted_at = now(), rejection_reason = NULL
     WHERE timesheet_id = p_timesheet_id;
END $$;

CREATE OR REPLACE PROCEDURE sp_approve_timesheet(p_timesheet_id BIGINT, p_approver_id BIGINT)
LANGUAGE plpgsql AS $$
DECLARE v_ts timesheets%ROWTYPE;
BEGIN
    SELECT * INTO v_ts FROM timesheets WHERE timesheet_id = p_timesheet_id FOR UPDATE;
    IF v_ts.status <> 'submitted' THEN
        RAISE EXCEPTION 'Timesheet % is not submitted (current: %)', p_timesheet_id, v_ts.status;
    END IF;
    IF v_ts.employee_id = p_approver_id THEN
        RAISE EXCEPTION 'Employees cannot approve their own timesheets';
    END IF;
    UPDATE timesheets SET status = 'approved', approved_by = p_approver_id, approved_at = now()
     WHERE timesheet_id = p_timesheet_id;
END $$;

CREATE OR REPLACE PROCEDURE sp_reject_timesheet(p_timesheet_id BIGINT, p_approver_id BIGINT, p_reason TEXT)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE timesheets SET status = 'rejected', approved_by = p_approver_id, approved_at = NULL,
                          rejection_reason = p_reason
     WHERE timesheet_id = p_timesheet_id AND status = 'submitted';
    IF NOT FOUND THEN RAISE EXCEPTION 'Timesheet % is not in submitted state', p_timesheet_id; END IF;
END $$;


/* ---------- 15.3 Leave management ---------- */

CREATE OR REPLACE FUNCTION fn_leave_balance_sync() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_year SMALLINT := extract(year FROM NEW.start_date);
    v_remaining NUMERIC;
BEGIN
    IF NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved' THEN
        INSERT INTO leave_balances (employee_id, leave_type_id, leave_year, entitled_days)
        SELECT NEW.employee_id, NEW.leave_type_id, v_year, lt.annual_entitlement_days
          FROM leave_types lt WHERE lt.leave_type_id = NEW.leave_type_id
        ON CONFLICT DO NOTHING;

        SELECT remaining_days INTO v_remaining FROM leave_balances
         WHERE employee_id = NEW.employee_id AND leave_type_id = NEW.leave_type_id AND leave_year = v_year
         FOR UPDATE;
        IF v_remaining < NEW.days_requested THEN
            RAISE EXCEPTION 'Insufficient leave balance: % day(s) remaining, % requested', v_remaining, NEW.days_requested;
        END IF;

        UPDATE leave_balances SET taken_days = taken_days + NEW.days_requested
         WHERE employee_id = NEW.employee_id AND leave_type_id = NEW.leave_type_id AND leave_year = v_year;
        NEW.decided_at := now();

    ELSIF OLD.status = 'approved' AND NEW.status <> 'approved' THEN
        UPDATE leave_balances SET taken_days = taken_days - OLD.days_requested
         WHERE employee_id = OLD.employee_id AND leave_type_id = OLD.leave_type_id
           AND leave_year = extract(year FROM OLD.start_date);
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_leave_balance_sync
    BEFORE UPDATE OF status ON leave_requests
    FOR EACH ROW EXECUTE FUNCTION fn_leave_balance_sync();


/* ---------- 15.4 Invoicing ---------- */

-- Tax + default revenue account on each invoice line; lines locked once invoice issued
CREATE OR REPLACE FUNCTION fn_invoice_line_before() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status invoice_status; v_rate NUMERIC;
BEGIN
    SELECT status INTO v_status FROM invoices
     WHERE invoice_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.invoice_id ELSE NEW.invoice_id END;
    IF v_status <> 'draft' THEN
        RAISE EXCEPTION 'Invoice is % - lines can only be changed while draft', v_status;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;

    SELECT rate_percent INTO v_rate FROM tax_rates WHERE tax_rate_id = NEW.tax_rate_id;
    NEW.tax_amount := round(round(NEW.quantity * NEW.unit_price * (1 - NEW.discount_pct / 100), 2)
                            * COALESCE(v_rate, 0) / 100, 2);

    IF NEW.revenue_account_id IS NULL THEN
        NEW.revenue_account_id := fn_account_id(CASE NEW.line_type
                                    WHEN 'time'          THEN '4000'
                                    WHEN 'fixed_fee'     THEN '4010'
                                    WHEN 'milestone'     THEN '4010'
                                    WHEN 'retainer'      THEN '4020'
                                    WHEN 'expense'       THEN '4100'
                                    WHEN 'subcontractor' THEN '4100'
                                    ELSE '4900' END);
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_invoice_lines_before
    BEFORE INSERT OR UPDATE OR DELETE ON invoice_lines
    FOR EACH ROW EXECUTE FUNCTION fn_invoice_line_before();

-- Roll line totals up to invoice header
CREATE OR REPLACE FUNCTION fn_invoice_recalc() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT := CASE WHEN TG_OP = 'DELETE' THEN OLD.invoice_id ELSE NEW.invoice_id END;
BEGIN
    UPDATE invoices i
       SET subtotal     = s.net,
           tax_amount   = s.tax,
           total_amount = s.net + s.tax
      FROM (SELECT COALESCE(SUM(line_net),0) AS net, COALESCE(SUM(tax_amount),0) AS tax
              FROM invoice_lines WHERE invoice_id = v_id) s
     WHERE i.invoice_id = v_id;
    RETURN NULL;
END $$;

CREATE TRIGGER trg_invoice_lines_recalc
    AFTER INSERT OR UPDATE OR DELETE ON invoice_lines
    FOR EACH ROW EXECUTE FUNCTION fn_invoice_recalc();

-- Build a draft invoice from approved, unbilled billable time (+ optional rebillable expenses)
CREATE OR REPLACE FUNCTION fn_generate_invoice_from_time(
    p_project_id       BIGINT,
    p_period_from      DATE,
    p_period_to        DATE,
    p_invoice_date     DATE    DEFAULT CURRENT_DATE,
    p_tax_code         TEXT    DEFAULT 'ZW-VAT',
    p_include_expenses BOOLEAN DEFAULT TRUE,
    p_created_by       BIGINT  DEFAULT NULL
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    v_proj       projects%ROWTYPE;
    v_terms      SMALLINT;
    v_tax_id     BIGINT;
    v_invoice_id BIGINT;
    v_line_id    BIGINT;
    v_line_no    SMALLINT := 0;
    r            RECORD;
BEGIN
    SELECT * INTO v_proj FROM projects WHERE project_id = p_project_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Project % not found', p_project_id; END IF;
    IF v_proj.is_internal THEN RAISE EXCEPTION 'Internal projects cannot be invoiced'; END IF;
    IF v_proj.billing_type IN ('fixed_fee','milestone') THEN
        RAISE EXCEPTION 'Project % is % - use fn_invoice_milestone instead', v_proj.project_code, v_proj.billing_type;
    END IF;

    SELECT COALESCE(ct.payment_terms_days, c.payment_terms_days) INTO v_terms
      FROM clients c LEFT JOIN contracts ct ON ct.contract_id = v_proj.contract_id
     WHERE c.client_id = v_proj.client_id;

    SELECT tax_rate_id INTO v_tax_id FROM tax_rates WHERE code = p_tax_code AND is_active;

    INSERT INTO invoices (client_id, project_id, contract_id, invoice_date, due_date, currency_code, created_by, notes)
    VALUES (v_proj.client_id, v_proj.project_id, v_proj.contract_id, p_invoice_date, p_invoice_date + v_terms,
            v_proj.currency_code, p_created_by,
            format('Professional services for %s, period %s to %s', v_proj.name,
                   to_char(p_period_from, 'DD Mon YYYY'), to_char(p_period_to, 'DD Mon YYYY')))
    RETURNING invoice_id INTO v_invoice_id;

    -- Time: one line per consultant per rate
    FOR r IN
        SELECT te.employee_id,
               e.first_name || ' ' || e.last_name AS emp_name,
               COALESCE(jg.name, 'Consultant')    AS grade_name,
               te.bill_rate,
               SUM(te.hours)                      AS hours
          FROM time_entries te
          JOIN timesheets ts ON ts.timesheet_id = te.timesheet_id
          JOIN employees  e  ON e.employee_id   = te.employee_id
          LEFT JOIN job_grades jg ON jg.job_grade_id = e.job_grade_id
         WHERE te.project_id = p_project_id
           AND te.is_billable
           AND te.invoice_line_id IS NULL
           AND ts.status = 'approved'
           AND te.work_date BETWEEN p_period_from AND p_period_to
         GROUP BY te.employee_id, e.first_name, e.last_name, jg.name, jg.level, te.bill_rate
         ORDER BY jg.level DESC NULLS LAST, e.last_name
    LOOP
        v_line_no := v_line_no + 1;
        INSERT INTO invoice_lines (invoice_id, line_no, line_type, description, quantity, unit, unit_price,
                                   tax_rate_id, project_id)
        VALUES (v_invoice_id, v_line_no, 'time',
                format('%s (%s) - professional services', r.emp_name, r.grade_name),
                r.hours, 'hour', r.bill_rate, v_tax_id, p_project_id)
        RETURNING invoice_line_id INTO v_line_id;

        UPDATE time_entries te
           SET invoice_line_id = v_line_id
          FROM timesheets ts
         WHERE ts.timesheet_id = te.timesheet_id
           AND ts.status = 'approved'
           AND te.project_id = p_project_id
           AND te.employee_id = r.employee_id
           AND te.bill_rate = r.bill_rate
           AND te.is_billable
           AND te.invoice_line_id IS NULL
           AND te.work_date BETWEEN p_period_from AND p_period_to;
    END LOOP;

    -- Rebillable expenses from approved expense reports
    IF p_include_expenses THEN
        FOR r IN
            SELECT ei.expense_item_id, ei.description, ec.name AS category,
                   round(ei.amount_base * (1 + ei.markup_pct / 100), 2) AS amount
              FROM expense_items ei
              JOIN expense_reports er    ON er.expense_report_id = ei.expense_report_id
              JOIN expense_categories ec ON ec.expense_category_id = ei.expense_category_id
             WHERE ei.project_id = p_project_id
               AND ei.is_billable
               AND ei.invoice_line_id IS NULL
               AND er.status = 'approved'
               AND ei.expense_date BETWEEN p_period_from AND p_period_to
             ORDER BY ei.expense_date
        LOOP
            v_line_no := v_line_no + 1;
            INSERT INTO invoice_lines (invoice_id, line_no, line_type, description, quantity, unit, unit_price,
                                       tax_rate_id, project_id)
            VALUES (v_invoice_id, v_line_no, 'expense', format('Reimbursable expense - %s: %s', r.category, r.description),
                    1, 'each', r.amount, v_tax_id, p_project_id)
            RETURNING invoice_line_id INTO v_line_id;

            UPDATE expense_items SET invoice_line_id = v_line_id WHERE expense_item_id = r.expense_item_id;
        END LOOP;
    END IF;

    IF v_line_no = 0 THEN
        RAISE EXCEPTION 'Nothing to invoice for project % between % and %',
              v_proj.project_code, p_period_from, p_period_to;
    END IF;

    RETURN v_invoice_id;
END $$;

-- Draft invoice for a fixed-fee milestone
CREATE OR REPLACE FUNCTION fn_invoice_milestone(
    p_milestone_id BIGINT, p_invoice_date DATE DEFAULT CURRENT_DATE,
    p_tax_code TEXT DEFAULT 'ZW-VAT', p_created_by BIGINT DEFAULT NULL
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    v_ms   contract_milestones%ROWTYPE;
    v_ct   contracts%ROWTYPE;
    v_proj_id BIGINT;
    v_inv  BIGINT;
BEGIN
    SELECT * INTO v_ms FROM contract_milestones WHERE milestone_id = p_milestone_id FOR UPDATE;
    IF v_ms.status <> 'achieved' THEN
        RAISE EXCEPTION 'Milestone % must be achieved before invoicing (current: %)', p_milestone_id, v_ms.status;
    END IF;
    SELECT * INTO v_ct FROM contracts WHERE contract_id = v_ms.contract_id;
    SELECT project_id INTO v_proj_id FROM projects WHERE contract_id = v_ct.contract_id ORDER BY project_id LIMIT 1;

    INSERT INTO invoices (client_id, project_id, contract_id, invoice_date, due_date, currency_code, created_by, notes)
    VALUES (v_ct.client_id, v_proj_id, v_ct.contract_id, p_invoice_date, p_invoice_date + v_ct.payment_terms_days,
            v_ct.currency_code, p_created_by, format('%s - milestone %s', v_ct.title, v_ms.seq))
    RETURNING invoice_id INTO v_inv;

    INSERT INTO invoice_lines (invoice_id, line_no, line_type, description, quantity, unit, unit_price,
                               tax_rate_id, project_id, milestone_id)
    VALUES (v_inv, 1, 'milestone', format('Milestone %s: %s', v_ms.seq, v_ms.name), 1, 'fixed', v_ms.amount,
            (SELECT tax_rate_id FROM tax_rates WHERE code = p_tax_code), v_proj_id, v_ms.milestone_id);

    UPDATE contract_milestones SET invoice_id = v_inv WHERE milestone_id = p_milestone_id;
    RETURN v_inv;
END $$;


/* ---------- 15.5 General ledger integrity ---------- */

-- Derive fiscal period, block posting into closed periods
CREATE OR REPLACE FUNCTION fn_journal_entry_before() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_period fiscal_periods%ROWTYPE;
BEGIN
    SELECT * INTO v_period FROM fiscal_periods
     WHERE NEW.entry_date BETWEEN start_date AND end_date
     ORDER BY period_no LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No fiscal period defined for %', NEW.entry_date;
    END IF;
    IF v_period.is_closed AND (TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status) THEN
        RAISE EXCEPTION 'Fiscal period for % is closed', NEW.entry_date;
    END IF;
    NEW.fiscal_period_id := v_period.fiscal_period_id;

    IF TG_OP = 'UPDATE' AND OLD.status = 'posted' AND NEW.status = 'draft' THEN
        RAISE EXCEPTION 'Posted journals cannot be returned to draft - create a reversal instead';
    END IF;
    IF NEW.status = 'posted' AND NEW.posted_at IS NULL THEN
        NEW.posted_at := now();
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_journal_entries_before
    BEFORE INSERT OR UPDATE ON journal_entries
    FOR EACH ROW EXECUTE FUNCTION fn_journal_entry_before();

-- Lines of posted journals are immutable; only postable accounts allowed
CREATE OR REPLACE FUNCTION fn_journal_line_before() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status TEXT;
BEGIN
    SELECT status INTO v_status FROM journal_entries
     WHERE journal_entry_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.journal_entry_id ELSE NEW.journal_entry_id END;
    IF v_status IN ('posted','reversed') THEN
        RAISE EXCEPTION 'Journal is % - lines cannot be modified', v_status;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    IF NOT EXISTS (SELECT 1 FROM chart_of_accounts WHERE account_id = NEW.account_id AND is_postable AND is_active) THEN
        RAISE EXCEPTION 'Account % is not postable', NEW.account_id;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_journal_lines_before
    BEFORE INSERT OR UPDATE OR DELETE ON journal_lines
    FOR EACH ROW EXECUTE FUNCTION fn_journal_line_before();

-- Debits must equal credits for every posted journal (checked at commit)
CREATE OR REPLACE FUNCTION fn_journal_balanced() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT; v_status TEXT; v_dr NUMERIC; v_cr NUMERIC;
BEGIN
    IF TG_OP = 'DELETE' THEN v_id := OLD.journal_entry_id; ELSE v_id := NEW.journal_entry_id; END IF;
    SELECT status INTO v_status FROM journal_entries WHERE journal_entry_id = v_id;
    IF v_status = 'posted' THEN
        SELECT COALESCE(SUM(debit),0), COALESCE(SUM(credit),0) INTO v_dr, v_cr
          FROM journal_lines WHERE journal_entry_id = v_id;
        IF v_dr <> v_cr OR v_dr = 0 THEN
            RAISE EXCEPTION 'Journal % is unbalanced (DR % / CR %)', v_id, v_dr, v_cr;
        END IF;
    END IF;
    RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER trg_journal_entries_balanced
    AFTER INSERT OR UPDATE ON journal_entries
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_journal_balanced();

CREATE CONSTRAINT TRIGGER trg_journal_lines_balanced
    AFTER INSERT OR UPDATE OR DELETE ON journal_lines
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_journal_balanced();

-- Reverse a posted journal
CREATE OR REPLACE FUNCTION fn_reverse_journal(p_journal_entry_id BIGINT, p_date DATE DEFAULT CURRENT_DATE)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_new BIGINT; v_je journal_entries%ROWTYPE;
BEGIN
    SELECT * INTO v_je FROM journal_entries WHERE journal_entry_id = p_journal_entry_id FOR UPDATE;
    IF v_je.status <> 'posted' THEN RAISE EXCEPTION 'Only posted journals can be reversed'; END IF;

    INSERT INTO journal_entries (entry_date, description, source_type, source_id, reversal_of_id)
    VALUES (p_date, 'REVERSAL: ' || v_je.description, 'adjustment', v_je.source_id, v_je.journal_entry_id)
    RETURNING journal_entry_id INTO v_new;

    INSERT INTO journal_lines (journal_entry_id, line_no, account_id, debit, credit, description,
                               client_id, vendor_id, project_id, department_id, employee_id)
    SELECT v_new, line_no, account_id, credit, debit, description, client_id, vendor_id, project_id, department_id, employee_id
      FROM journal_lines WHERE journal_entry_id = p_journal_entry_id;

    UPDATE journal_entries SET status = 'posted'   WHERE journal_entry_id = v_new;
    UPDATE journal_entries SET status = 'reversed' WHERE journal_entry_id = p_journal_entry_id;
    RETURN v_new;
END $$;


/* ---------- 15.6 Posting documents to the GL ---------- */

-- Issue an invoice: DR Accounts Receivable / CR Revenue (+ CR VAT output)
CREATE OR REPLACE FUNCTION fn_issue_invoice(p_invoice_id BIGINT, p_user_id BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    v_inv  invoices%ROWTYPE;
    v_je   BIGINT;
    v_line SMALLINT := 1;
    v_office BIGINT;
    r      RECORD;
BEGIN
    SELECT * INTO v_inv FROM invoices WHERE invoice_id = p_invoice_id FOR UPDATE;
    SELECT office_id INTO v_office FROM projects WHERE project_id = v_inv.project_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Invoice % not found', p_invoice_id; END IF;
    IF v_inv.status <> 'draft' THEN RAISE EXCEPTION 'Invoice % is already %', v_inv.invoice_number, v_inv.status; END IF;
    IF v_inv.total_amount <= 0 THEN RAISE EXCEPTION 'Invoice % has no value', v_inv.invoice_number; END IF;

    INSERT INTO journal_entries (entry_date, description, source_type, source_id, created_by)
    VALUES (v_inv.invoice_date, 'Invoice ' || v_inv.invoice_number, 'invoice', v_inv.invoice_id, p_user_id)
    RETURNING journal_entry_id INTO v_je;

    INSERT INTO journal_lines (journal_entry_id, line_no, account_id, debit, description, client_id, project_id, office_id)
    VALUES (v_je, v_line, fn_account_id('1100'), round(v_inv.total_amount * v_inv.exchange_rate, 2),
            'Accounts receivable', v_inv.client_id, v_inv.project_id, v_office);

    FOR r IN SELECT revenue_account_id, project_id, SUM(line_net) AS net
               FROM invoice_lines WHERE invoice_id = p_invoice_id
              GROUP BY revenue_account_id, project_id HAVING SUM(line_net) <> 0
    LOOP
        v_line := v_line + 1;
        INSERT INTO journal_lines (journal_entry_id, line_no, account_id, credit, description, client_id, project_id, office_id)
        VALUES (v_je, v_line, r.revenue_account_id, round(r.net * v_inv.exchange_rate, 2), 'Fee revenue',
                v_inv.client_id, r.project_id, v_office);
    END LOOP;

    -- output tax goes to the liability account of each tax rate (ZIMRA VAT, SARS VAT, HMRC VAT ...)
    FOR r IN SELECT COALESCE(tr.gl_account_code, '2200') AS acc, tr.name, SUM(il.tax_amount) AS tax
               FROM invoice_lines il LEFT JOIN tax_rates tr ON tr.tax_rate_id = il.tax_rate_id
              WHERE il.invoice_id = p_invoice_id
              GROUP BY 1, 2 HAVING SUM(il.tax_amount) <> 0
    LOOP
        v_line := v_line + 1;
        INSERT INTO journal_lines (journal_entry_id, line_no, account_id, credit, description, client_id, office_id)
        VALUES (v_je, v_line, fn_account_id(r.acc), round(r.tax * v_inv.exchange_rate, 2),
                'Output tax - ' || COALESCE(r.name, 'VAT'), v_inv.client_id, v_office);
    END LOOP;
    -- FX rounding: converting each line separately can leave a cent difference - put it on the revenue line
    UPDATE journal_lines jl SET credit = jl.credit + d.diff
      FROM (SELECT SUM(debit) - SUM(credit) AS diff FROM journal_lines WHERE journal_entry_id = v_je) d
     WHERE jl.journal_entry_id = v_je AND jl.line_no = 2 AND d.diff <> 0;

    UPDATE journal_entries SET status = 'posted' WHERE journal_entry_id = v_je;

    UPDATE invoices SET status = 'issued', issued_at = now(), journal_entry_id = v_je
     WHERE invoice_id = p_invoice_id;

    UPDATE contract_milestones SET status = 'invoiced'
     WHERE milestone_id IN (SELECT milestone_id FROM invoice_lines WHERE invoice_id = p_invoice_id AND milestone_id IS NOT NULL);

    RETURN v_je;
END $$;

-- Payment allocation rules
CREATE OR REPLACE FUNCTION fn_payment_allocation_before() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_pay payments%ROWTYPE; v_inv invoices%ROWTYPE; v_allocated NUMERIC;
BEGIN
    SELECT * INTO v_pay FROM payments WHERE payment_id = NEW.payment_id;
    SELECT * INTO v_inv FROM invoices WHERE invoice_id = NEW.invoice_id FOR UPDATE;

    IF v_pay.client_id <> v_inv.client_id THEN
        RAISE EXCEPTION 'Payment and invoice belong to different clients';
    END IF;
    IF v_pay.currency_code <> v_inv.currency_code THEN
        RAISE EXCEPTION 'Payment currency % differs from invoice currency %', v_pay.currency_code, v_inv.currency_code;
    END IF;
    IF v_inv.status NOT IN ('issued','partially_paid','overdue') THEN
        RAISE EXCEPTION 'Invoice % is % and cannot receive payments', v_inv.invoice_number, v_inv.status;
    END IF;

    SELECT COALESCE(SUM(amount),0) INTO v_allocated FROM payment_allocations
     WHERE payment_id = NEW.payment_id AND invoice_id <> NEW.invoice_id;
    IF v_allocated + NEW.amount > v_pay.amount + v_pay.withholding_tax THEN
        RAISE EXCEPTION 'Allocation exceeds payment amount';
    END IF;

    IF NEW.amount > v_inv.balance_due + COALESCE(CASE WHEN TG_OP = 'UPDATE' THEN OLD.amount END, 0) THEN
        RAISE EXCEPTION 'Allocation % exceeds invoice balance %', NEW.amount, v_inv.balance_due;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_payment_allocations_before
    BEFORE INSERT OR UPDATE ON payment_allocations
    FOR EACH ROW EXECUTE FUNCTION fn_payment_allocation_before();

-- Update invoice paid amount and status
CREATE OR REPLACE FUNCTION fn_payment_allocation_after() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT := CASE WHEN TG_OP = 'DELETE' THEN OLD.invoice_id ELSE NEW.invoice_id END;
BEGIN
    UPDATE invoices i
       SET amount_paid = p.paid,
           status = CASE
                      WHEN p.paid >= i.total_amount THEN 'paid'::invoice_status
                      WHEN p.paid > 0              THEN 'partially_paid'::invoice_status
                      WHEN i.due_date < CURRENT_DATE THEN 'overdue'::invoice_status
                      ELSE 'issued'::invoice_status
                    END
      FROM (SELECT COALESCE(SUM(amount),0) AS paid FROM payment_allocations WHERE invoice_id = v_id) p
     WHERE i.invoice_id = v_id;
    RETURN NULL;
END $$;

CREATE TRIGGER trg_payment_allocations_after
    AFTER INSERT OR UPDATE OR DELETE ON payment_allocations
    FOR EACH ROW EXECUTE FUNCTION fn_payment_allocation_after();

-- Record a client receipt, post DR Bank / CR AR and auto-allocate oldest invoices first (FIFO)
CREATE OR REPLACE FUNCTION fn_record_client_payment(
    p_client_id       BIGINT,
    p_amount          NUMERIC,
    p_bank_account_id BIGINT,
    p_payment_date    DATE           DEFAULT CURRENT_DATE,
    p_method          payment_method DEFAULT 'bank_transfer',
    p_reference       TEXT           DEFAULT NULL,
    p_auto_allocate   BOOLEAN        DEFAULT TRUE
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    v_bank      bank_accounts%ROWTYPE;
    v_pay_id    BIGINT;
    v_je        BIGINT;
    v_remaining NUMERIC := p_amount;
    v_alloc     NUMERIC;
    r           RECORD;
BEGIN
    SELECT * INTO v_bank FROM bank_accounts WHERE bank_account_id = p_bank_account_id AND is_active;
    IF NOT FOUND THEN RAISE EXCEPTION 'Bank account % not found/inactive', p_bank_account_id; END IF;

    INSERT INTO payments (client_id, payment_date, amount, currency_code, method, reference, bank_account_id)
    VALUES (p_client_id, p_payment_date, p_amount, v_bank.currency_code, p_method, p_reference, p_bank_account_id)
    RETURNING payment_id INTO v_pay_id;

    INSERT INTO journal_entries (entry_date, description, source_type, source_id)
    VALUES (p_payment_date, 'Client receipt ' || COALESCE(p_reference, ''), 'payment', v_pay_id)
    RETURNING journal_entry_id INTO v_je;

    INSERT INTO journal_lines (journal_entry_id, line_no, account_id, debit, description, client_id)
    VALUES (v_je, 1, v_bank.gl_account_id, p_amount, 'Receipt to ' || v_bank.name, p_client_id);
    INSERT INTO journal_lines (journal_entry_id, line_no, account_id, credit, description, client_id)
    VALUES (v_je, 2, fn_account_id('1100'), p_amount, 'Settle accounts receivable', p_client_id);
    UPDATE journal_entries SET status = 'posted' WHERE journal_entry_id = v_je;
    UPDATE payments SET journal_entry_id = v_je WHERE payment_id = v_pay_id;

    IF p_auto_allocate THEN
        FOR r IN SELECT invoice_id, balance_due FROM invoices
                  WHERE client_id = p_client_id AND currency_code = v_bank.currency_code
                    AND status IN ('issued','partially_paid','overdue') AND balance_due > 0
                  ORDER BY due_date, invoice_id
        LOOP
            EXIT WHEN v_remaining <= 0;
            v_alloc := LEAST(v_remaining, r.balance_due);
            INSERT INTO payment_allocations (payment_id, invoice_id, amount) VALUES (v_pay_id, r.invoice_id, v_alloc);
            v_remaining := v_remaining - v_alloc;
        END LOOP;
    END IF;
    RETURN v_pay_id;
END $$;

-- Nightly job: flag overdue invoices
CREATE OR REPLACE FUNCTION fn_mark_overdue_invoices() RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE v_count INTEGER;
BEGIN
    UPDATE invoices SET status = 'overdue'
     WHERE status IN ('issued') AND due_date < CURRENT_DATE AND balance_due > 0;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END $$;


/* ---------- 15.7 Expenses ---------- */

CREATE OR REPLACE FUNCTION fn_expense_item_before() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status approval_status; v_max NUMERIC;
BEGIN
    SELECT status INTO v_status FROM expense_reports
     WHERE expense_report_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.expense_report_id ELSE NEW.expense_report_id END;
    IF TG_OP = 'UPDATE'
       AND (NEW.amount, NEW.expense_date, NEW.project_id, NEW.is_billable, NEW.expense_category_id)
           IS NOT DISTINCT FROM (OLD.amount, OLD.expense_date, OLD.project_id, OLD.is_billable, OLD.expense_category_id) THEN
        RETURN NEW;   -- e.g. billing stamping invoice_line_id
    END IF;
    IF v_status NOT IN ('draft','rejected') THEN
        RAISE EXCEPTION 'Expense report is % - items are locked', v_status;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    SELECT max_amount_per_item INTO v_max FROM expense_categories WHERE expense_category_id = NEW.expense_category_id;
    IF v_max IS NOT NULL AND NEW.amount * NEW.exchange_rate > v_max THEN
        RAISE EXCEPTION 'Expense % exceeds category limit %', NEW.amount, v_max;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_expense_items_before
    BEFORE INSERT OR UPDATE OR DELETE ON expense_items
    FOR EACH ROW EXECUTE FUNCTION fn_expense_item_before();

CREATE OR REPLACE FUNCTION fn_expense_report_total() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT := CASE WHEN TG_OP = 'DELETE' THEN OLD.expense_report_id ELSE NEW.expense_report_id END;
BEGIN
    UPDATE expense_reports
       SET total_amount = COALESCE((SELECT SUM(amount_base) FROM expense_items WHERE expense_report_id = v_id), 0)
     WHERE expense_report_id = v_id;
    RETURN NULL;
END $$;

CREATE TRIGGER trg_expense_items_total
    AFTER INSERT OR UPDATE OR DELETE ON expense_items
    FOR EACH ROW EXECUTE FUNCTION fn_expense_report_total();

CREATE OR REPLACE PROCEDURE sp_submit_expense_report(p_report_id BIGINT)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE expense_reports SET status = 'submitted', submitted_at = now()
     WHERE expense_report_id = p_report_id AND status IN ('draft','rejected') AND total_amount > 0;
    IF NOT FOUND THEN RAISE EXCEPTION 'Expense report % cannot be submitted', p_report_id; END IF;
END $$;

-- Approve and post: DR expense accounts / CR Employee reimbursements payable
CREATE OR REPLACE PROCEDURE sp_approve_expense_report(p_report_id BIGINT, p_approver_id BIGINT, p_date DATE DEFAULT CURRENT_DATE)
LANGUAGE plpgsql AS $$
DECLARE v_er expense_reports%ROWTYPE; v_je BIGINT; v_line SMALLINT := 0; r RECORD;
BEGIN
    SELECT * INTO v_er FROM expense_reports WHERE expense_report_id = p_report_id FOR UPDATE;
    IF v_er.status <> 'submitted' THEN RAISE EXCEPTION 'Expense report % is not submitted', p_report_id; END IF;
    IF v_er.employee_id = p_approver_id THEN RAISE EXCEPTION 'Cannot approve own expense report'; END IF;

    INSERT INTO journal_entries (entry_date, description, source_type, source_id)
    VALUES (p_date, 'Expense claim ' || v_er.report_number, 'expense', p_report_id)
    RETURNING journal_entry_id INTO v_je;

    FOR r IN SELECT ec.gl_account_id, ei.project_id, SUM(ei.amount_base) AS amt
               FROM expense_items ei JOIN expense_categories ec USING (expense_category_id)
              WHERE ei.expense_report_id = p_report_id
              GROUP BY ec.gl_account_id, ei.project_id
    LOOP
        v_line := v_line + 1;
        INSERT INTO journal_lines (journal_entry_id, line_no, account_id, debit, project_id, employee_id, description)
        VALUES (v_je, v_line, r.gl_account_id, r.amt, r.project_id, v_er.employee_id, v_er.title);
    END LOOP;

    INSERT INTO journal_lines (journal_entry_id, line_no, account_id, credit, employee_id, description)
    VALUES (v_je, v_line + 1, fn_account_id('2300'), v_er.total_amount, v_er.employee_id, 'Reimbursement due to employee');

    UPDATE journal_entries SET status = 'posted' WHERE journal_entry_id = v_je;
    UPDATE expense_reports SET status = 'approved', approved_by = p_approver_id,
           approved_at = LEAST(now(), p_date + TIME '17:00'), journal_entry_id = v_je
     WHERE expense_report_id = p_report_id;
END $$;


/* ---------- 15.8 Procurement ---------- */

CREATE OR REPLACE FUNCTION fn_po_total() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT := CASE WHEN TG_OP = 'DELETE' THEN OLD.po_id ELSE NEW.po_id END;
BEGIN
    UPDATE purchase_orders
       SET total_amount = COALESCE((SELECT SUM(line_total) FROM purchase_order_lines WHERE po_id = v_id), 0)
     WHERE po_id = v_id;
    RETURN NULL;
END $$;

CREATE TRIGGER trg_po_lines_total
    AFTER INSERT OR UPDATE OR DELETE ON purchase_order_lines
    FOR EACH ROW EXECUTE FUNCTION fn_po_total();

CREATE OR REPLACE FUNCTION fn_vendor_payment_after() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT := CASE WHEN TG_OP = 'DELETE' THEN OLD.vendor_bill_id ELSE NEW.vendor_bill_id END;
BEGIN
    UPDATE vendor_bills b
       SET amount_paid = p.paid,
           status = CASE WHEN p.paid >= b.total_amount THEN 'paid'
                         WHEN p.paid > 0 THEN 'partially_paid'
                         ELSE 'approved' END
      FROM (SELECT COALESCE(SUM(amount),0) AS paid FROM vendor_payments WHERE vendor_bill_id = v_id) p
     WHERE b.vendor_bill_id = v_id;
    IF (SELECT amount_paid > total_amount FROM vendor_bills WHERE vendor_bill_id = v_id) THEN
        RAISE EXCEPTION 'Payments exceed vendor bill total';
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER trg_vendor_payments_after
    AFTER INSERT OR UPDATE OR DELETE ON vendor_payments
    FOR EACH ROW EXECUTE FUNCTION fn_vendor_payment_after();


/* ---------- 15.9 Attach generic triggers (updated_at, doc numbers, audit) ---------- */

DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT c.table_name
          FROM information_schema.columns c
          JOIN information_schema.tables t
            ON t.table_schema = c.table_schema AND t.table_name = c.table_name AND t.table_type = 'BASE TABLE'
         WHERE c.table_schema = 'erp' AND c.column_name = 'updated_at'
    LOOP
        EXECUTE format('CREATE TRIGGER trg_%s_updated_at BEFORE UPDATE ON erp.%I
                        FOR EACH ROW EXECUTE FUNCTION erp.fn_set_updated_at()', r.table_name, r.table_name);
    END LOOP;
END $$;

CREATE TRIGGER trg_invoices_number        BEFORE INSERT ON invoices        FOR EACH ROW EXECUTE FUNCTION fn_assign_doc_number('invoice',        'invoice_number');
CREATE TRIGGER trg_payments_number        BEFORE INSERT ON payments        FOR EACH ROW EXECUTE FUNCTION fn_assign_doc_number('payment',        'payment_number');
CREATE TRIGGER trg_journal_number         BEFORE INSERT ON journal_entries FOR EACH ROW EXECUTE FUNCTION fn_assign_doc_number('journal',        'entry_number');
CREATE TRIGGER trg_expense_reports_number BEFORE INSERT ON expense_reports FOR EACH ROW EXECUTE FUNCTION fn_assign_doc_number('expense_report', 'report_number');
CREATE TRIGGER trg_purchase_orders_number BEFORE INSERT ON purchase_orders FOR EACH ROW EXECUTE FUNCTION fn_assign_doc_number('purchase_order', 'po_number');

CREATE TRIGGER trg_audit_employees    AFTER INSERT OR UPDATE OR DELETE ON employees        FOR EACH ROW EXECUTE FUNCTION fn_audit('employee_id');
CREATE TRIGGER trg_audit_compensation AFTER INSERT OR UPDATE OR DELETE ON employee_compensation FOR EACH ROW EXECUTE FUNCTION fn_audit('compensation_id');
CREATE TRIGGER trg_audit_clients      AFTER INSERT OR UPDATE OR DELETE ON clients          FOR EACH ROW EXECUTE FUNCTION fn_audit('client_id');
CREATE TRIGGER trg_audit_contracts    AFTER INSERT OR UPDATE OR DELETE ON contracts        FOR EACH ROW EXECUTE FUNCTION fn_audit('contract_id');
CREATE TRIGGER trg_audit_projects     AFTER INSERT OR UPDATE OR DELETE ON projects         FOR EACH ROW EXECUTE FUNCTION fn_audit('project_id');
CREATE TRIGGER trg_audit_invoices     AFTER INSERT OR UPDATE OR DELETE ON invoices         FOR EACH ROW EXECUTE FUNCTION fn_audit('invoice_id');
CREATE TRIGGER trg_audit_payments     AFTER INSERT OR UPDATE OR DELETE ON payments         FOR EACH ROW EXECUTE FUNCTION fn_audit('payment_id');
CREATE TRIGGER trg_audit_journals     AFTER INSERT OR UPDATE OR DELETE ON journal_entries  FOR EACH ROW EXECUTE FUNCTION fn_audit('journal_entry_id');
CREATE TRIGGER trg_audit_timesheets   AFTER UPDATE OF status ON timesheets                 FOR EACH ROW EXECUTE FUNCTION fn_audit('timesheet_id');
CREATE TRIGGER trg_audit_user_roles   AFTER INSERT OR DELETE ON user_roles                 FOR EACH ROW EXECUTE FUNCTION fn_audit('user_id');
CREATE TRIGGER trg_audit_app_users    AFTER INSERT OR DELETE OR UPDATE OF is_active, locked_until, must_change_password ON app_users
                                                                                            FOR EACH ROW EXECUTE FUNCTION fn_audit('user_id');
CREATE TRIGGER trg_audit_role_perms   AFTER INSERT OR DELETE ON role_permissions           FOR EACH ROW EXECUTE FUNCTION fn_audit('role_id');
CREATE TRIGGER trg_audit_vendor_bills AFTER INSERT OR UPDATE OR DELETE ON vendor_bills     FOR EACH ROW EXECUTE FUNCTION fn_audit('vendor_bill_id');
CREATE TRIGGER trg_audit_vendor_pays  AFTER INSERT OR UPDATE OR DELETE ON vendor_payments  FOR EACH ROW EXECUTE FUNCTION fn_audit('vendor_payment_id');
CREATE TRIGGER trg_audit_payroll_runs AFTER INSERT OR UPDATE OR DELETE ON payroll_runs     FOR EACH ROW EXECUTE FUNCTION fn_audit('payroll_run_id');
CREATE TRIGGER trg_audit_fixed_assets AFTER INSERT OR UPDATE OR DELETE ON fixed_assets     FOR EACH ROW EXECUTE FUNCTION fn_audit('asset_id');
CREATE TRIGGER trg_audit_leases       AFTER INSERT OR UPDATE OR DELETE ON leases           FOR EACH ROW EXECUTE FUNCTION fn_audit('lease_id');
CREATE TRIGGER trg_audit_tax_returns  AFTER INSERT OR UPDATE OR DELETE ON tax_returns      FOR EACH ROW EXECUTE FUNCTION fn_audit('tax_return_id');
CREATE TRIGGER trg_audit_bank_accounts AFTER INSERT OR UPDATE OR DELETE ON bank_accounts   FOR EACH ROW EXECUTE FUNCTION fn_audit('bank_account_id');

/* ---------- 15.10 ZIMRA fiscalisation (FDMS) ----------
   When an invoice is issued it receives a fiscal invoice number and a verification code
   (in production these come back from the ZIMRA FDMS API / fiscal device). */
CREATE OR REPLACE FUNCTION fn_invoice_fiscalise() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status <> 'draft' AND OLD.status = 'draft' AND NEW.fiscal_invoice_number IS NULL THEN
        NEW.fiscal_invoice_number := 'FDMS-' || COALESCE((SELECT fiscal_device_serial FROM firm_settings), 'VD') || '-'
                                     || lpad(NEW.invoice_id::TEXT, 7, '0');
        NEW.fiscal_verification_code := upper(substr(md5(NEW.invoice_number || NEW.total_amount::TEXT || NEW.invoice_date::TEXT), 1, 16));
        NEW.fiscalised_at := COALESCE(NEW.issued_at, now());
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_invoices_fiscalise BEFORE UPDATE OF status ON invoices
    FOR EACH ROW EXECUTE FUNCTION fn_invoice_fiscalise();

-- Pin search_path on every routine so they work regardless of the caller's search_path
-- (search_path pinning for all functions is done at the end of module 24)


