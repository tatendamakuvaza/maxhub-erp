
/* =====================================================================================
   10. BILLING & ACCOUNTS RECEIVABLE
   ===================================================================================== */

CREATE TABLE invoices (
    invoice_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_number VARCHAR(30)    UNIQUE,                 -- auto-assigned by trigger
    client_id      BIGINT         NOT NULL REFERENCES clients,
    project_id     BIGINT         REFERENCES projects,
    contract_id    BIGINT         REFERENCES contracts,
    invoice_date   DATE           NOT NULL DEFAULT CURRENT_DATE,
    due_date       DATE           NOT NULL,
    currency_code  CHAR(3)        NOT NULL REFERENCES currencies,
    exchange_rate  NUMERIC(18,8)  NOT NULL DEFAULT 1,     -- to base currency
    status         invoice_status NOT NULL DEFAULT 'draft',
    subtotal       NUMERIC(18,2)  NOT NULL DEFAULT 0,
    tax_amount     NUMERIC(18,2)  NOT NULL DEFAULT 0,
    total_amount   NUMERIC(18,2)  NOT NULL DEFAULT 0,
    amount_paid    NUMERIC(18,2)  NOT NULL DEFAULT 0,
    balance_due    NUMERIC(18,2)  GENERATED ALWAYS AS (total_amount - amount_paid) STORED,
    po_reference   VARCHAR(60),
    notes          TEXT,
    issued_at      TIMESTAMPTZ,
    -- ZIMRA Fiscalisation Data Management System (FDMS): every VAT invoice must be fiscalised
    fiscal_invoice_number VARCHAR(40),
    fiscal_verification_code VARCHAR(40),
    fiscalised_at  TIMESTAMPTZ,
    journal_entry_id BIGINT,                              -- FK added after journal_entries
    created_by     BIGINT         REFERENCES app_users,
    created_at     TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CHECK (due_date >= invoice_date),
    CHECK (amount_paid >= 0)
);

ALTER TABLE contract_milestones ADD CONSTRAINT fk_milestone_invoice FOREIGN KEY (invoice_id) REFERENCES invoices;

CREATE TABLE invoice_lines (
    invoice_line_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_id         BIGINT        NOT NULL REFERENCES invoices ON DELETE CASCADE,
    line_no            SMALLINT      NOT NULL,
    line_type          VARCHAR(20)   NOT NULL DEFAULT 'time'
                       CHECK (line_type IN ('time','expense','fixed_fee','milestone','retainer','subcontractor','other')),
    description        VARCHAR(400)  NOT NULL,
    quantity           NUMERIC(12,2) NOT NULL DEFAULT 1,
    unit               VARCHAR(10)   NOT NULL DEFAULT 'hour',
    unit_price         NUMERIC(14,2) NOT NULL DEFAULT 0,
    discount_pct       NUMERIC(5,2)  NOT NULL DEFAULT 0 CHECK (discount_pct BETWEEN 0 AND 100),
    line_net           NUMERIC(18,2) GENERATED ALWAYS AS (round(quantity * unit_price * (1 - discount_pct / 100), 2)) STORED,
    tax_rate_id        BIGINT        REFERENCES tax_rates,
    tax_amount         NUMERIC(18,2) NOT NULL DEFAULT 0,   -- computed by trigger
    project_id         BIGINT        REFERENCES projects,
    milestone_id       BIGINT        REFERENCES contract_milestones,
    revenue_account_id BIGINT        REFERENCES chart_of_accounts,
    UNIQUE (invoice_id, line_no)
);

CREATE TABLE payments (
    payment_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_number  VARCHAR(30)    UNIQUE,                -- auto-assigned by trigger
    client_id       BIGINT         NOT NULL REFERENCES clients,
    payment_date    DATE           NOT NULL DEFAULT CURRENT_DATE,
    amount          NUMERIC(18,2)  NOT NULL CHECK (amount > 0),
    currency_code   CHAR(3)        NOT NULL REFERENCES currencies,
    exchange_rate   NUMERIC(18,8)  NOT NULL DEFAULT 1,
    method          payment_method NOT NULL DEFAULT 'bank_transfer',
    reference       VARCHAR(80),
    bank_account_id BIGINT         REFERENCES bank_accounts,
    withholding_tax NUMERIC(18,2)  NOT NULL DEFAULT 0,
    notes           TEXT,
    journal_entry_id BIGINT,
    created_at      TIMESTAMPTZ    NOT NULL DEFAULT now()
);

CREATE TABLE payment_allocations (
    payment_id   BIGINT        NOT NULL REFERENCES payments ON DELETE CASCADE,
    invoice_id   BIGINT        NOT NULL REFERENCES invoices,
    amount       NUMERIC(18,2) NOT NULL CHECK (amount > 0),
    allocated_at TIMESTAMPTZ   NOT NULL DEFAULT now(),
    PRIMARY KEY (payment_id, invoice_id)
);

CREATE TABLE credit_notes (
    credit_note_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    credit_note_number VARCHAR(30)   NOT NULL UNIQUE,
    invoice_id         BIGINT        NOT NULL REFERENCES invoices,
    client_id          BIGINT        NOT NULL REFERENCES clients,
    issue_date         DATE          NOT NULL DEFAULT CURRENT_DATE,
    reason             TEXT          NOT NULL,
    net_amount         NUMERIC(18,2) NOT NULL CHECK (net_amount > 0),
    tax_amount         NUMERIC(18,2) NOT NULL DEFAULT 0,
    status             VARCHAR(20)   NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','issued','applied','void')),
    created_at         TIMESTAMPTZ   NOT NULL DEFAULT now()
);

