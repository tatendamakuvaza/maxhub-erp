
/* =====================================================================================
   06. CRM - CLIENTS, CONTACTS, LEADS, OPPORTUNITIES
   ===================================================================================== */

CREATE TABLE industries (
    industry_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        VARCHAR(80) NOT NULL UNIQUE
);

CREATE TABLE clients (
    client_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    client_code        VARCHAR(20)   NOT NULL UNIQUE,
    legal_name         VARCHAR(150)  NOT NULL,
    trading_name       VARCHAR(150),
    industry_id        BIGINT        REFERENCES industries,
    status             client_status NOT NULL DEFAULT 'prospect',
    registration_number VARCHAR(50),
    tax_number         VARCHAR(50),
    vat_number         VARCHAR(50),
    website            VARCHAR(150),
    billing_email      VARCHAR(150),
    phone              VARCHAR(40),
    address_line1      VARCHAR(150),
    address_line2      VARCHAR(150),
    city               VARCHAR(80),
    country_code       CHAR(2)       REFERENCES countries,
    currency_code      CHAR(3)       NOT NULL DEFAULT 'USD' REFERENCES currencies,
    payment_terms_days SMALLINT      NOT NULL DEFAULT 30 CHECK (payment_terms_days >= 0),
    credit_limit       NUMERIC(18,2),
    account_manager_id BIGINT        REFERENCES employees,
    lead_source        VARCHAR(60),
    notes              TEXT,
    created_at         TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE client_contacts (
    contact_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    client_id          BIGINT       NOT NULL REFERENCES clients ON DELETE CASCADE,
    first_name         VARCHAR(60)  NOT NULL,
    last_name          VARCHAR(60)  NOT NULL,
    job_title          VARCHAR(100),
    email              VARCHAR(150),
    phone              VARCHAR(40),
    is_primary         BOOLEAN      NOT NULL DEFAULT FALSE,
    is_billing_contact BOOLEAN      NOT NULL DEFAULT FALSE,
    is_decision_maker  BOOLEAN      NOT NULL DEFAULT FALSE,
    notes              TEXT,
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now()
);
-- only one primary contact per client
CREATE UNIQUE INDEX ux_client_primary_contact ON client_contacts (client_id) WHERE is_primary;

CREATE TABLE leads (
    lead_id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_name        VARCHAR(150) NOT NULL,
    contact_name        VARCHAR(120),
    email               VARCHAR(150),
    phone               VARCHAR(40),
    industry_id         BIGINT       REFERENCES industries,
    source              VARCHAR(60),   -- referral, website, event, tender, cold call
    estimated_value     NUMERIC(18,2),
    status              VARCHAR(20)  NOT NULL DEFAULT 'new'
                        CHECK (status IN ('new','contacted','qualified','disqualified','converted')),
    owner_id            BIGINT       REFERENCES employees,
    converted_client_id BIGINT       REFERENCES clients,
    notes               TEXT,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE opportunities (
    opportunity_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    opportunity_code    VARCHAR(20)       NOT NULL UNIQUE,
    client_id           BIGINT            NOT NULL REFERENCES clients,
    lead_id             BIGINT            REFERENCES leads,
    name                VARCHAR(150)      NOT NULL,
    description         TEXT,
    service_line_id     BIGINT            REFERENCES service_lines,
    stage               opportunity_stage NOT NULL DEFAULT 'qualification',
    probability_pct     NUMERIC(5,2)      NOT NULL DEFAULT 10 CHECK (probability_pct BETWEEN 0 AND 100),
    estimated_value     NUMERIC(18,2)     NOT NULL DEFAULT 0,
    weighted_value      NUMERIC(18,2)     GENERATED ALWAYS AS (round(estimated_value * probability_pct / 100, 2)) STORED,
    currency_code       CHAR(3)           NOT NULL DEFAULT 'USD' REFERENCES currencies,
    expected_close_date DATE,
    actual_close_date   DATE,
    owner_id            BIGINT            REFERENCES employees,
    competitor          VARCHAR(150),
    lost_reason         TEXT,
    created_at          TIMESTAMPTZ       NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ       NOT NULL DEFAULT now(),
    CHECK (stage <> 'lost' OR lost_reason IS NOT NULL)
);

CREATE TABLE crm_activities (
    activity_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    activity_type  VARCHAR(20)  NOT NULL CHECK (activity_type IN ('call','email','meeting','presentation','note','task')),
    subject        VARCHAR(200) NOT NULL,
    details        TEXT,
    activity_date  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    client_id      BIGINT       REFERENCES clients,
    contact_id     BIGINT       REFERENCES client_contacts,
    lead_id        BIGINT       REFERENCES leads,
    opportunity_id BIGINT       REFERENCES opportunities,
    employee_id    BIGINT       NOT NULL REFERENCES employees,
    follow_up_date DATE,
    is_completed   BOOLEAN      NOT NULL DEFAULT FALSE,
    CHECK (client_id IS NOT NULL OR lead_id IS NOT NULL OR opportunity_id IS NOT NULL)
);

