
/* =====================================================================================
   13. GENERAL LEDGER, BANK RECONCILIATION & BUDGETS
   ===================================================================================== */

CREATE TABLE journal_entries (
    journal_entry_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    entry_number     VARCHAR(30)  UNIQUE,                  -- auto-assigned
    entry_date       DATE         NOT NULL,
    fiscal_period_id BIGINT       REFERENCES fiscal_periods,  -- derived by trigger
    description      VARCHAR(300) NOT NULL,
    source_type      VARCHAR(20)  NOT NULL DEFAULT 'manual'
                     CHECK (source_type IN ('manual','invoice','payment','credit_note','expense','payroll',
                                            'payroll_payment','vendor_bill','vendor_payment','adjustment','opening',
                                            'depreciation','asset_disposal','revaluation','lease','lease_payment',
                                            'loan','tax','tax_payment','fx_revaluation','dividend','ecl','transfer',
                                            'rental_income','interest','accrual','legacy','fair_value')),
    source_id        BIGINT,
    status           VARCHAR(10)  NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','posted','reversed')),
    reversal_of_id   BIGINT       REFERENCES journal_entries,
    posted_at        TIMESTAMPTZ,
    created_by       BIGINT       REFERENCES app_users,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE journal_lines (
    journal_line_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    journal_entry_id BIGINT        NOT NULL REFERENCES journal_entries ON DELETE CASCADE,
    line_no          SMALLINT      NOT NULL,
    account_id       BIGINT        NOT NULL REFERENCES chart_of_accounts,
    debit            NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (debit  >= 0),
    credit           NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
    description      VARCHAR(300),
    client_id        BIGINT        REFERENCES clients,
    vendor_id        BIGINT        REFERENCES vendors,
    project_id       BIGINT        REFERENCES projects,
    department_id    BIGINT        REFERENCES departments,
    employee_id      BIGINT        REFERENCES employees,
    office_id        BIGINT        REFERENCES offices,     -- branch dimension (IFRS 8 segments)
    UNIQUE (journal_entry_id, line_no),
    CHECK ((debit = 0) <> (credit = 0))            -- exactly one side populated
);

ALTER TABLE invoices        ADD CONSTRAINT fk_invoice_je  FOREIGN KEY (journal_entry_id) REFERENCES journal_entries;
ALTER TABLE payments        ADD CONSTRAINT fk_payment_je  FOREIGN KEY (journal_entry_id) REFERENCES journal_entries;
ALTER TABLE expense_reports ADD CONSTRAINT fk_expense_je  FOREIGN KEY (journal_entry_id) REFERENCES journal_entries;
ALTER TABLE vendor_bills    ADD CONSTRAINT fk_vbill_je    FOREIGN KEY (journal_entry_id) REFERENCES journal_entries;
ALTER TABLE vendor_payments ADD CONSTRAINT fk_vpay_je     FOREIGN KEY (journal_entry_id) REFERENCES journal_entries;
ALTER TABLE payroll_runs    ADD CONSTRAINT fk_payroll_je  FOREIGN KEY (journal_entry_id) REFERENCES journal_entries;
ALTER TABLE payroll_runs    ADD CONSTRAINT fk_payroll_pay_je FOREIGN KEY (payment_journal_id) REFERENCES journal_entries;

CREATE TABLE bank_transactions (
    bank_txn_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bank_account_id   BIGINT        NOT NULL REFERENCES bank_accounts,
    txn_date          DATE          NOT NULL,
    description       VARCHAR(300),
    amount            NUMERIC(18,2) NOT NULL,           -- +ve money in, -ve money out
    reference         VARCHAR(80),
    is_reconciled     BOOLEAN       NOT NULL DEFAULT FALSE,
    payment_id        BIGINT        REFERENCES payments,
    vendor_payment_id BIGINT        REFERENCES vendor_payments,
    journal_entry_id  BIGINT        REFERENCES journal_entries,
    imported_at       TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE budgets (
    budget_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fiscal_year_id BIGINT        NOT NULL REFERENCES fiscal_years,
    period_no      SMALLINT      NOT NULL CHECK (period_no BETWEEN 1 AND 13),
    account_id     BIGINT        NOT NULL REFERENCES chart_of_accounts,
    department_id  BIGINT        REFERENCES departments,
    amount         NUMERIC(18,2) NOT NULL,
    UNIQUE NULLS NOT DISTINCT (fiscal_year_id, period_no, account_id, department_id)
);

