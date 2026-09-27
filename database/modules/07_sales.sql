
/* =====================================================================================
   07. SALES - SERVICE CATALOGUE, RATE CARDS, PROPOSALS
   ===================================================================================== */

CREATE TABLE services (
    service_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    service_line_id BIGINT       NOT NULL REFERENCES service_lines,
    code            VARCHAR(20)  NOT NULL UNIQUE,
    name            VARCHAR(120) NOT NULL,
    description     TEXT,
    default_unit    VARCHAR(10)  NOT NULL DEFAULT 'hour' CHECK (default_unit IN ('hour','day','fixed','month')),
    default_price   NUMERIC(14,2),
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE rate_cards (
    rate_card_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          VARCHAR(100) NOT NULL,
    currency_code CHAR(3)      NOT NULL REFERENCES currencies,
    client_id     BIGINT       REFERENCES clients,    -- NULL = standard firm rate card
    valid_from    DATE         NOT NULL,
    valid_to      DATE,
    is_default    BOOLEAN      NOT NULL DEFAULT FALSE,
    CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE TABLE rate_card_lines (
    rate_card_line_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rate_card_id      BIGINT        NOT NULL REFERENCES rate_cards ON DELETE CASCADE,
    job_grade_id      BIGINT        NOT NULL REFERENCES job_grades,
    hourly_rate       NUMERIC(10,2) NOT NULL CHECK (hourly_rate >= 0),
    daily_rate        NUMERIC(10,2),
    UNIQUE (rate_card_id, job_grade_id)
);

CREATE TABLE proposals (
    proposal_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    proposal_number VARCHAR(30)   NOT NULL UNIQUE,
    opportunity_id  BIGINT        REFERENCES opportunities,
    client_id       BIGINT        NOT NULL REFERENCES clients,
    title           VARCHAR(200)  NOT NULL,
    version_no      SMALLINT      NOT NULL DEFAULT 1,
    status          VARCHAR(20)   NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft','in_review','sent','accepted','rejected','expired')),
    issue_date      DATE,
    valid_until     DATE,
    currency_code   CHAR(3)       NOT NULL REFERENCES currencies,
    proposed_contract_type contract_type NOT NULL DEFAULT 'time_and_materials',
    discount_amount NUMERIC(18,2) NOT NULL DEFAULT 0,
    subtotal        NUMERIC(18,2) NOT NULL DEFAULT 0,
    total_amount    NUMERIC(18,2) NOT NULL DEFAULT 0,
    executive_summary TEXT,
    scope_of_work   TEXT,
    assumptions     TEXT,
    prepared_by     BIGINT        REFERENCES employees,
    reviewed_by     BIGINT        REFERENCES employees,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE proposal_lines (
    proposal_line_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    proposal_id      BIGINT        NOT NULL REFERENCES proposals ON DELETE CASCADE,
    line_no          SMALLINT      NOT NULL,
    service_id       BIGINT        REFERENCES services,
    job_grade_id     BIGINT        REFERENCES job_grades,
    description      VARCHAR(300)  NOT NULL,
    quantity         NUMERIC(12,2) NOT NULL CHECK (quantity > 0),
    unit             VARCHAR(10)   NOT NULL DEFAULT 'hour',
    unit_price       NUMERIC(14,2) NOT NULL CHECK (unit_price >= 0),
    line_total       NUMERIC(18,2) GENERATED ALWAYS AS (round(quantity * unit_price, 2)) STORED,
    UNIQUE (proposal_id, line_no)
);

