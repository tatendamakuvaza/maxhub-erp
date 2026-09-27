
/* =====================================================================================
   01. REFERENCE DATA & FIRM SETTINGS
   ===================================================================================== */

CREATE TABLE currencies (
    currency_code   CHAR(3)      PRIMARY KEY,
    name            VARCHAR(60)  NOT NULL,
    symbol          VARCHAR(8),
    decimal_places  SMALLINT     NOT NULL DEFAULT 2,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE exchange_rates (
    exchange_rate_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    from_currency    CHAR(3)       NOT NULL REFERENCES currencies,
    to_currency      CHAR(3)       NOT NULL REFERENCES currencies,
    rate_date        DATE          NOT NULL,
    rate             NUMERIC(18,8) NOT NULL CHECK (rate > 0),
    source           VARCHAR(60),
    UNIQUE (from_currency, to_currency, rate_date),
    CHECK (from_currency <> to_currency)
);

CREATE TABLE countries (
    country_code     CHAR(2)     PRIMARY KEY,
    name             VARCHAR(80) NOT NULL,
    default_currency CHAR(3)     REFERENCES currencies
);

CREATE TABLE tax_rates (
    tax_rate_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code          VARCHAR(20)  NOT NULL UNIQUE,
    name          VARCHAR(80)  NOT NULL,
    rate_percent  NUMERIC(6,3) NOT NULL CHECK (rate_percent >= 0),
    country_code  CHAR(2)      REFERENCES countries,
    valid_from    DATE         NOT NULL DEFAULT CURRENT_DATE,
    valid_to      DATE,
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE,
    tax_kind      VARCHAR(20)  NOT NULL DEFAULT 'vat' CHECK (tax_kind IN ('vat','sales_tax','withholding','other')),
    gl_account_code VARCHAR(20) NOT NULL DEFAULT '2200',   -- output-tax liability account for this rate
    CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE fiscal_years (
    fiscal_year_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name           VARCHAR(20) NOT NULL UNIQUE,
    start_date     DATE        NOT NULL,
    end_date       DATE        NOT NULL,
    is_closed      BOOLEAN     NOT NULL DEFAULT FALSE,
    CHECK (end_date > start_date)
);

CREATE TABLE fiscal_periods (
    fiscal_period_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fiscal_year_id   BIGINT   NOT NULL REFERENCES fiscal_years ON DELETE CASCADE,
    period_no        SMALLINT NOT NULL CHECK (period_no BETWEEN 1 AND 13),
    start_date       DATE     NOT NULL,
    end_date         DATE     NOT NULL,
    is_closed        BOOLEAN  NOT NULL DEFAULT FALSE,
    UNIQUE (fiscal_year_id, period_no),
    CHECK (end_date >= start_date)
);

CREATE TABLE firm_settings (
    setting_id                 SMALLINT PRIMARY KEY DEFAULT 1 CHECK (setting_id = 1),  -- single row
    legal_name                 VARCHAR(150) NOT NULL,
    trading_name               VARCHAR(150),
    registration_number        VARCHAR(50),
    tax_number                 VARCHAR(50),
    vat_number                 VARCHAR(50),
    base_currency              CHAR(3)      NOT NULL REFERENCES currencies,
    country_code               CHAR(2)      NOT NULL REFERENCES countries,
    address                    TEXT,
    phone                      VARCHAR(40),
    email                      VARCHAR(150),
    website                    VARCHAR(150),
    default_payment_terms_days SMALLINT     NOT NULL DEFAULT 30,
    default_tax_code           VARCHAR(20),
    logo_url                   TEXT,
    -- statutory registrations (Zimbabwe)
    zimra_tin                  VARCHAR(30),          -- ZIMRA Taxpayer Identification Number
    zimra_bp_number            VARCHAR(30),          -- ZIMRA Business Partner number
    nssa_employer_number       VARCHAR(30),
    zimdef_number              VARCHAR(30),
    praz_number                VARCHAR(30),          -- Procurement Regulatory Authority supplier no.
    fiscal_device_serial       VARCHAR(40),          -- ZIMRA FDMS fiscal device / virtual device id
    date_of_incorporation      DATE,
    -- financial reporting
    reporting_framework        VARCHAR(80)  NOT NULL DEFAULT 'IFRS Accounting Standards',
    functional_currency        CHAR(3)      REFERENCES currencies,
    presentation_currency      CHAR(3)      REFERENCES currencies,
    ifrs18_adopted_from        DATE,                 -- IFRS 18 mandatory 1 Jan 2027; early adoption allowed
    expense_presentation       VARCHAR(10)  NOT NULL DEFAULT 'nature' CHECK (expense_presentation IN ('nature','function','mixed')),
    year_end_month             SMALLINT     NOT NULL DEFAULT 12 CHECK (year_end_month BETWEEN 1 AND 12),
    auditor_name               VARCHAR(150),
    company_secretary          VARCHAR(150),
    email_domain               VARCHAR(80)  NOT NULL DEFAULT 'maxhub.co.zw'
);

-- Auto-numbering for business documents (invoices, payments, journals ...)
CREATE TABLE document_sequences (
    doc_type      VARCHAR(30) PRIMARY KEY,
    prefix        VARCHAR(10) NOT NULL,
    next_value    BIGINT      NOT NULL DEFAULT 1,
    padding       SMALLINT    NOT NULL DEFAULT 5,
    include_year  BOOLEAN     NOT NULL DEFAULT TRUE
);

