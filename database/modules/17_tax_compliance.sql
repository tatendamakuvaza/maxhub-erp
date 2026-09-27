
/* =====================================================================================
   17. TAX COMPLIANCE - ZIMRA, NSSA, ZIMDEF & FOREIGN BRANCH TAXES
   -------------------------------------------------------------------------------------
   Zimbabwe obligations modelled (rates are DATA - update when the law changes):
     VAT 15.5% ............... monthly VAT7 return, due 25th of the following month
     PAYE + AIDS levy 3% ..... monthly P2 return, due 10th of the following month
     NSSA POBS 4.5% + 4.5% ... monthly (P4), capped at USD 700 insurable earnings
     NSSA WCIF ............... employer only, industry rate
     ZIMDEF 1% ............... employer levy on the wage bill
     Corporate income tax .... 24% + AIDS levy 3% of tax = 24.72%; Quarterly Payment
                               Dates (QPDs) 25 Mar 10%, 25 Jun 25%, 25 Sep 30%, 20 Dec 35%;
                               ITF12C annual return
     Withholding taxes ....... 30% on payments to suppliers without a valid ITF263 tax
                               clearance; 15% non-residents' tax on fees
     IMTT 2% ................. charged by banks on electronic transfers
     Fiscalisation ........... every VAT invoice fiscalised through ZIMRA FDMS
   Branches: SARS (ZA), KRA (KE), HMRC (GB), Federal Tax Authority (AE).
   ===================================================================================== */

CREATE TABLE tax_authorities (
    authority_code VARCHAR(12)  PRIMARY KEY,            -- ZIMRA, NSSA, ZIMDEF, SARS ...
    name           VARCHAR(150) NOT NULL,
    country_code   CHAR(2)      NOT NULL REFERENCES countries,
    website        VARCHAR(150),
    portal_name    VARCHAR(80),                         -- e.g. ZIMRA TaRMS, NSSA self-service
    vendor_id      BIGINT       REFERENCES vendors      -- payee used for remittances
);

CREATE TABLE tax_registrations (
    registration_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    authority_code    VARCHAR(12)  NOT NULL REFERENCES tax_authorities,
    office_id         BIGINT       REFERENCES offices,
    registration_type VARCHAR(40)  NOT NULL,            -- TIN, VAT, PAYE, NSSA employer, ZIMDEF ...
    registration_no   VARCHAR(40)  NOT NULL,
    registered_on     DATE,
    tax_office        VARCHAR(80),                      -- e.g. ZIMRA Large Client Office, Harare
    UNIQUE (authority_code, registration_type, registration_no)
);

-- Every tax / levy the company files or pays
CREATE TABLE tax_types (
    tax_code          VARCHAR(20)  PRIMARY KEY,         -- VAT, PAYE, NSSA, ZIMDEF, CIT_QPD ...
    name              VARCHAR(120) NOT NULL,
    authority_code    VARCHAR(12)  NOT NULL REFERENCES tax_authorities,
    return_form       VARCHAR(30),                      -- VAT7, P2, P4, ITF12C, EMP201 ...
    frequency         VARCHAR(16)  NOT NULL CHECK (frequency IN ('monthly','bi_monthly','quarterly','qpd','annual','per_transaction')),
    due_day           SMALLINT,                         -- day of the following month the return/payment is due
    liability_account_code VARCHAR(20),                 -- GL account the liability sits in
    offset_account_code    VARCHAR(20),                 -- e.g. VAT input account (netted on VAT return)
    description       TEXT
);

-- Flat statutory rates and ceilings (Zimbabwe + simplified branch rates)
CREATE TABLE statutory_rates (
    rate_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    country_code   CHAR(2)       NOT NULL REFERENCES countries,
    rate_code      VARCHAR(30)   NOT NULL,              -- e.g. NSSA_EE, NSSA_CEILING, CIT, AIDS_LEVY
    description    VARCHAR(200)  NOT NULL,
    rate_pct       NUMERIC(7,3),
    amount         NUMERIC(16,2),                       -- ceilings / thresholds (in currency_code)
    currency_code  CHAR(3)       REFERENCES currencies,
    effective_from DATE          NOT NULL,
    effective_to   DATE,
    source_note    VARCHAR(200),
    UNIQUE (country_code, rate_code, effective_from)
);

-- Progressive PAYE tables (monthly), e.g. ZIMRA USD bands
CREATE TABLE paye_tax_bands (
    band_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    country_code   CHAR(2)       NOT NULL REFERENCES countries,
    currency_code  CHAR(3)       NOT NULL REFERENCES currencies,
    effective_from DATE          NOT NULL,
    lower_limit    NUMERIC(16,2) NOT NULL,              -- monthly taxable income from
    upper_limit    NUMERIC(16,2),                       -- NULL = and above
    rate_pct       NUMERIC(6,2)  NOT NULL,
    deduct_amount  NUMERIC(16,2) NOT NULL DEFAULT 0,    -- "less" column of the ZIMRA table
    UNIQUE (country_code, currency_code, effective_from, lower_limit)
);

-- Returns filed / payments made to tax authorities
CREATE TABLE tax_returns (
    tax_return_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    return_number    VARCHAR(40)   UNIQUE,              -- e.g. VAT-2026-08
    tax_code         VARCHAR(20)   NOT NULL REFERENCES tax_types,
    office_id        BIGINT        REFERENCES offices,
    period_start     DATE          NOT NULL,
    period_end       DATE          NOT NULL,
    due_date         DATE          NOT NULL,
    currency_code    CHAR(3)       NOT NULL DEFAULT 'USD' REFERENCES currencies,
    gross_amount     NUMERIC(18,2) NOT NULL DEFAULT 0,  -- e.g. output VAT, gross PAYE
    credits_amount   NUMERIC(18,2) NOT NULL DEFAULT 0,  -- e.g. input VAT
    amount_due       NUMERIC(18,2) GENERATED ALWAYS AS (gross_amount - credits_amount) STORED,
    penalty_amount   NUMERIC(18,2) NOT NULL DEFAULT 0,
    interest_amount  NUMERIC(18,2) NOT NULL DEFAULT 0,
    amount_paid      NUMERIC(18,2) NOT NULL DEFAULT 0,
    status           tax_return_status NOT NULL DEFAULT 'draft',
    filed_date       DATE,
    paid_date        DATE,
    acknowledgement_ref VARCHAR(60),                    -- receipt from ZIMRA TaRMS / NSSA
    prepared_by      BIGINT        REFERENCES employees,
    bank_account_id  BIGINT        REFERENCES bank_accounts,
    journal_entry_id BIGINT        REFERENCES journal_entries,
    notes            TEXT,
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    UNIQUE (tax_code, office_id, period_start, period_end),
    CHECK (period_end >= period_start)
);

CREATE TABLE tax_return_lines (
    tax_return_id  BIGINT        NOT NULL REFERENCES tax_returns ON DELETE CASCADE,
    line_no        SMALLINT      NOT NULL,
    box_code       VARCHAR(20),                         -- form box, e.g. VAT7 box 1
    description    VARCHAR(200)  NOT NULL,
    amount         NUMERIC(18,2) NOT NULL,
    PRIMARY KEY (tax_return_id, line_no)
);

-- ITF263 tax clearance certificates (ours and our suppliers')
CREATE TABLE tax_clearance_certificates (
    certificate_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    holder_type     VARCHAR(10)  NOT NULL CHECK (holder_type IN ('company','vendor')),
    vendor_id       BIGINT       REFERENCES vendors,
    certificate_no  VARCHAR(40)  NOT NULL,
    issue_date      DATE         NOT NULL,
    expiry_date     DATE         NOT NULL,
    CHECK (holder_type = 'company' OR vendor_id IS NOT NULL),
    CHECK (expiry_date > issue_date)
);

-- Withholding tax deducted from supplier payments (paid over to ZIMRA)
CREATE TABLE withholding_tax_deductions (
    wht_id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vendor_payment_id BIGINT        REFERENCES vendor_payments ON DELETE CASCADE,
    vendor_id         BIGINT        NOT NULL REFERENCES vendors,
    wht_type          VARCHAR(20)   NOT NULL CHECK (wht_type IN ('tender_30','non_resident_fees','interest','dividends','royalties')),
    gross_amount      NUMERIC(18,2) NOT NULL,
    rate_pct          NUMERIC(6,2)  NOT NULL,
    wht_amount        NUMERIC(18,2) NOT NULL,
    deduction_date    DATE          NOT NULL,
    tax_return_id     BIGINT        REFERENCES tax_returns,
    certificate_ref   VARCHAR(40)
);

-- Annual corporate income tax computation (ITF12C) - IAS 12 current tax
CREATE TABLE income_tax_computations (
    computation_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fiscal_year_id        BIGINT        NOT NULL UNIQUE REFERENCES fiscal_years,
    profit_before_tax     NUMERIC(18,2) NOT NULL,
    add_backs             NUMERIC(18,2) NOT NULL DEFAULT 0,    -- depreciation, fines, disallowed entertainment ...
    capital_allowances    NUMERIC(18,2) NOT NULL DEFAULT 0,    -- wear & tear / SIA
    exempt_income         NUMERIC(18,2) NOT NULL DEFAULT 0,
    foreign_branch_profit NUMERIC(18,2) NOT NULL DEFAULT 0,    -- taxed abroad, credit relief
    taxable_income        NUMERIC(18,2) NOT NULL,
    tax_rate_pct          NUMERIC(6,3)  NOT NULL,
    income_tax            NUMERIC(18,2) NOT NULL,
    aids_levy             NUMERIC(18,2) NOT NULL,
    foreign_tax_credit    NUMERIC(18,2) NOT NULL DEFAULT 0,
    total_tax             NUMERIC(18,2) NOT NULL,
    qpds_paid             NUMERIC(18,2) NOT NULL DEFAULT 0,
    balance_due           NUMERIC(18,2) GENERATED ALWAYS AS (total_tax - qpds_paid) STORED,
    status                VARCHAR(12)   NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','final','filed','assessed')),
    filed_date            DATE,
    notes                 TEXT
);
