
/* =====================================================================================
   11. TIME & EXPENSE
   ===================================================================================== */

CREATE TABLE activity_codes (
    activity_code VARCHAR(20) PRIMARY KEY,         -- CLIENT, BD, ADMIN, TRAINING, LEAVE ...
    name          VARCHAR(80) NOT NULL,
    is_chargeable BOOLEAN     NOT NULL DEFAULT FALSE,
    counts_as_capacity_reduction BOOLEAN NOT NULL DEFAULT FALSE   -- e.g. leave, public holiday
);

CREATE TABLE timesheets (
    timesheet_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id      BIGINT          NOT NULL REFERENCES employees,
    week_start_date  DATE            NOT NULL CHECK (extract(isodow FROM week_start_date) = 1),  -- Monday
    status           approval_status NOT NULL DEFAULT 'draft',
    total_hours      NUMERIC(6,2)    NOT NULL DEFAULT 0,          -- maintained by trigger
    submitted_at     TIMESTAMPTZ,
    approved_by      BIGINT          REFERENCES employees,
    approved_at      TIMESTAMPTZ,
    rejection_reason TEXT,
    created_at       TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ     NOT NULL DEFAULT now(),
    UNIQUE (employee_id, week_start_date)
);

CREATE TABLE time_entries (
    time_entry_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    timesheet_id    BIGINT        NOT NULL REFERENCES timesheets ON DELETE CASCADE,
    employee_id     BIGINT        NOT NULL REFERENCES employees,
    project_id      BIGINT        REFERENCES projects,     -- NULL => internal / non-project time
    task_id         BIGINT        REFERENCES tasks,
    activity_code   VARCHAR(20)   NOT NULL DEFAULT 'CLIENT' REFERENCES activity_codes,
    work_date       DATE          NOT NULL,
    hours           NUMERIC(5,2)  NOT NULL CHECK (hours > 0 AND hours <= 24),
    is_billable     BOOLEAN       NOT NULL DEFAULT TRUE,
    bill_rate       NUMERIC(10,2),                          -- defaulted by trigger
    cost_rate       NUMERIC(10,2),                          -- defaulted by trigger
    billable_amount NUMERIC(14,2) GENERATED ALWAYS AS
                    (CASE WHEN is_billable THEN round(hours * COALESCE(bill_rate,0), 2) ELSE 0 END) STORED,
    cost_amount     NUMERIC(14,2) GENERATED ALWAYS AS (round(hours * COALESCE(cost_rate,0), 2)) STORED,
    description     TEXT,
    invoice_line_id BIGINT        REFERENCES invoice_lines ON DELETE SET NULL,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE expense_categories (
    expense_category_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code                 VARCHAR(20)  NOT NULL UNIQUE,
    name                 VARCHAR(80)  NOT NULL,
    gl_account_id        BIGINT       NOT NULL REFERENCES chart_of_accounts,
    is_billable_default  BOOLEAN      NOT NULL DEFAULT TRUE,
    requires_receipt     BOOLEAN      NOT NULL DEFAULT TRUE,
    max_amount_per_item  NUMERIC(12,2)
);

CREATE TABLE expense_reports (
    expense_report_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    report_number     VARCHAR(30)     UNIQUE,              -- auto-assigned
    employee_id       BIGINT          NOT NULL REFERENCES employees,
    title             VARCHAR(150)    NOT NULL,
    status            approval_status NOT NULL DEFAULT 'draft',
    currency_code     CHAR(3)         NOT NULL DEFAULT 'USD' REFERENCES currencies,
    total_amount      NUMERIC(14,2)   NOT NULL DEFAULT 0,  -- maintained by trigger
    submitted_at      TIMESTAMPTZ,
    approved_by       BIGINT          REFERENCES employees,
    approved_at       TIMESTAMPTZ,
    reimbursed_at     TIMESTAMPTZ,
    rejection_reason  TEXT,
    journal_entry_id  BIGINT,
    created_at        TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE TABLE expense_items (
    expense_item_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    expense_report_id   BIGINT        NOT NULL REFERENCES expense_reports ON DELETE CASCADE,
    expense_date        DATE          NOT NULL,
    expense_category_id BIGINT        NOT NULL REFERENCES expense_categories,
    project_id          BIGINT        REFERENCES projects,
    description         VARCHAR(300)  NOT NULL,
    merchant            VARCHAR(120),
    amount              NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    currency_code       CHAR(3)       NOT NULL DEFAULT 'USD' REFERENCES currencies,
    exchange_rate       NUMERIC(18,8) NOT NULL DEFAULT 1,
    amount_base         NUMERIC(14,2) GENERATED ALWAYS AS (round(amount * exchange_rate, 2)) STORED,
    is_billable         BOOLEAN       NOT NULL DEFAULT TRUE,
    markup_pct          NUMERIC(5,2)  NOT NULL DEFAULT 0,
    receipt_url         TEXT,
    invoice_line_id     BIGINT        REFERENCES invoice_lines ON DELETE SET NULL,
    CHECK (NOT is_billable OR project_id IS NOT NULL)
);

