
/* =====================================================================================
   12. PROCUREMENT & ACCOUNTS PAYABLE (suppliers, subcontractors, freelancers)
   ===================================================================================== */

CREATE TABLE vendors (
    vendor_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vendor_code        VARCHAR(20)  NOT NULL UNIQUE,
    name               VARCHAR(150) NOT NULL,
    vendor_type        VARCHAR(20)  NOT NULL DEFAULT 'supplier'
                       CHECK (vendor_type IN ('supplier','subcontractor','freelancer','landlord','utility','government','insurer','professional')),
    tax_number         VARCHAR(50),
    vat_number         VARCHAR(50),
    is_resident        BOOLEAN      NOT NULL DEFAULT TRUE,   -- non-residents: non-resident tax on fees
    tax_clearance_expiry DATE,                               -- ZIMRA ITF263; no valid ITF263 => 30% WHT
    praz_registered    BOOLEAN      NOT NULL DEFAULT FALSE,
    email              VARCHAR(150),
    phone              VARCHAR(40),
    address            TEXT,
    country_code       CHAR(2)      REFERENCES countries,
    currency_code      CHAR(3)      NOT NULL DEFAULT 'USD' REFERENCES currencies,
    payment_terms_days SMALLINT     NOT NULL DEFAULT 30,
    bank_name          VARCHAR(100),
    bank_account_number VARCHAR(50),
    default_expense_account_id BIGINT REFERENCES chart_of_accounts,
    is_active          BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE purchase_orders (
    po_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    po_number     VARCHAR(30)   UNIQUE,                    -- auto-assigned
    vendor_id     BIGINT        NOT NULL REFERENCES vendors,
    project_id    BIGINT        REFERENCES projects,
    order_date    DATE          NOT NULL DEFAULT CURRENT_DATE,
    expected_date DATE,
    status        VARCHAR(20)   NOT NULL DEFAULT 'draft'
                  CHECK (status IN ('draft','approved','sent','partially_received','received','closed','cancelled')),
    currency_code CHAR(3)       NOT NULL REFERENCES currencies,
    total_amount  NUMERIC(18,2) NOT NULL DEFAULT 0,
    requested_by  BIGINT        REFERENCES employees,
    approved_by   BIGINT        REFERENCES employees,
    notes         TEXT,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE purchase_order_lines (
    po_line_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    po_id        BIGINT        NOT NULL REFERENCES purchase_orders ON DELETE CASCADE,
    line_no      SMALLINT      NOT NULL,
    description  VARCHAR(300)  NOT NULL,
    quantity     NUMERIC(12,2) NOT NULL CHECK (quantity > 0),
    unit_price   NUMERIC(14,2) NOT NULL CHECK (unit_price >= 0),
    line_total   NUMERIC(18,2) GENERATED ALWAYS AS (round(quantity * unit_price, 2)) STORED,
    received_qty NUMERIC(12,2) NOT NULL DEFAULT 0,
    UNIQUE (po_id, line_no)
);

CREATE TABLE vendor_bills (
    vendor_bill_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vendor_id      BIGINT        NOT NULL REFERENCES vendors,
    po_id          BIGINT        REFERENCES purchase_orders,
    project_id     BIGINT        REFERENCES projects,
    bill_number    VARCHAR(50)   NOT NULL,                 -- vendor's own invoice number
    bill_date      DATE          NOT NULL,
    due_date       DATE          NOT NULL,
    currency_code  CHAR(3)       NOT NULL REFERENCES currencies,
    subtotal       NUMERIC(18,2) NOT NULL DEFAULT 0,
    tax_amount     NUMERIC(18,2) NOT NULL DEFAULT 0,
    total_amount   NUMERIC(18,2) GENERATED ALWAYS AS (subtotal + tax_amount) STORED,
    amount_paid    NUMERIC(18,2) NOT NULL DEFAULT 0,
    expense_account_id BIGINT    REFERENCES chart_of_accounts,
    exchange_rate  NUMERIC(18,8) NOT NULL DEFAULT 1,       -- bill currency -> USD on bill date
    office_id      BIGINT        REFERENCES offices,
    department_id  BIGINT        REFERENCES departments,
    description    VARCHAR(300),
    is_rebillable  BOOLEAN       NOT NULL DEFAULT FALSE,
    journal_entry_id BIGINT,                               -- FK added in module 13
    status         VARCHAR(20)   NOT NULL DEFAULT 'draft'
                   CHECK (status IN ('draft','approved','partially_paid','paid','void')),
    approved_by    BIGINT        REFERENCES employees,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    UNIQUE (vendor_id, bill_number),
    CHECK (due_date >= bill_date)
);

CREATE TABLE vendor_payments (
    vendor_payment_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vendor_bill_id    BIGINT         NOT NULL REFERENCES vendor_bills,
    payment_date      DATE           NOT NULL DEFAULT CURRENT_DATE,
    amount            NUMERIC(18,2)  NOT NULL CHECK (amount > 0),
    method            payment_method NOT NULL DEFAULT 'bank_transfer',
    reference         VARCHAR(80),
    bank_account_id   BIGINT         REFERENCES bank_accounts,
    withholding_tax   NUMERIC(18,2)  NOT NULL DEFAULT 0,  -- WHT kept back and paid to ZIMRA
    imtt_amount       NUMERIC(18,2)  NOT NULL DEFAULT 0,  -- 2% Intermediated Money Transfer Tax charged by bank
    journal_entry_id  BIGINT,
    created_at        TIMESTAMPTZ    NOT NULL DEFAULT now()
);

