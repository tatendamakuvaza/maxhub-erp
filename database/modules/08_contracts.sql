
/* =====================================================================================
   08. CONTRACTS / ENGAGEMENT LETTERS & MILESTONES
   ===================================================================================== */

CREATE TABLE contracts (
    contract_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_number    VARCHAR(30)   NOT NULL UNIQUE,
    client_id          BIGINT        NOT NULL REFERENCES clients,
    proposal_id        BIGINT        REFERENCES proposals,
    title              VARCHAR(200)  NOT NULL,
    contract_type      contract_type NOT NULL,
    status             VARCHAR(20)   NOT NULL DEFAULT 'draft'
                       CHECK (status IN ('draft','active','suspended','completed','terminated')),
    start_date         DATE          NOT NULL,
    end_date           DATE,
    currency_code      CHAR(3)       NOT NULL REFERENCES currencies,
    contract_value     NUMERIC(18,2),                 -- cap / fixed fee / retainer total
    rate_card_id       BIGINT        REFERENCES rate_cards,
    payment_terms_days SMALLINT      NOT NULL DEFAULT 30,
    billing_frequency  VARCHAR(20)   NOT NULL DEFAULT 'monthly'
                       CHECK (billing_frequency IN ('weekly','fortnightly','monthly','milestone','on_completion')),
    retainer_hours_per_month NUMERIC(8,2),
    retainer_fee_per_month   NUMERIC(14,2),
    signed_date        DATE,
    client_signatory   VARCHAR(120),
    firm_signatory_id  BIGINT        REFERENCES employees,
    document_url       TEXT,
    created_at         TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE TABLE contract_milestones (
    milestone_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_id      BIGINT        NOT NULL REFERENCES contracts ON DELETE CASCADE,
    seq              SMALLINT      NOT NULL,
    name             VARCHAR(150)  NOT NULL,
    due_date         DATE,
    amount           NUMERIC(18,2) NOT NULL CHECK (amount >= 0),
    status           VARCHAR(20)   NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending','achieved','invoiced','cancelled')),
    achieved_date    DATE,
    invoice_id       BIGINT,                          -- FK added after invoices
    UNIQUE (contract_id, seq)
);

