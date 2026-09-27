
/* =====================================================================================
   03. ORGANISATION STRUCTURE - offices/branches, departments, service lines
   ===================================================================================== */

CREATE TABLE offices (
    office_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code                VARCHAR(10)  NOT NULL UNIQUE,
    name                VARCHAR(100) NOT NULL,
    office_type         VARCHAR(20)  NOT NULL DEFAULT 'branch'
                        CHECK (office_type IN ('head_office','branch','representative','lab')),
    occupancy           VARCHAR(10)  NOT NULL DEFAULT 'leased' CHECK (occupancy IN ('owned','leased')),
    address_line1       VARCHAR(150),
    address_line2       VARCHAR(150),
    city                VARCHAR(80),
    country_code        CHAR(2)      NOT NULL REFERENCES countries,
    functional_currency CHAR(3)      NOT NULL DEFAULT 'USD' REFERENCES currencies,  -- IAS 21 currency of the branch
    tax_jurisdiction    VARCHAR(20),                     -- ZIMRA, SARS, KRA, HMRC, UAE-FTA
    phone               VARCHAR(40),
    email               VARCHAR(150),                    -- branch mailbox, e.g. harare@maxhub.co.zw
    timezone            VARCHAR(50)  NOT NULL DEFAULT 'Africa/Harare',
    opened_date         DATE,
    manager_employee_id BIGINT,                          -- FK added after employees
    is_head_office      BOOLEAN      NOT NULL DEFAULT FALSE,
    is_active           BOOLEAN      NOT NULL DEFAULT TRUE
);
CREATE UNIQUE INDEX ux_offices_one_head_office ON offices (is_head_office) WHERE is_head_office;

ALTER TABLE bank_accounts ADD CONSTRAINT fk_bank_accounts_office FOREIGN KEY (office_id) REFERENCES offices;

CREATE TABLE departments (
    department_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code                  VARCHAR(10)  NOT NULL UNIQUE,
    name                  VARCHAR(100) NOT NULL,
    division              VARCHAR(30)  NOT NULL DEFAULT 'Client Service'
                          CHECK (division IN ('Leadership','Client Service','Business Support','Governance')),
    parent_department_id  BIGINT       REFERENCES departments,
    office_id             BIGINT       REFERENCES offices,   -- where the department is based
    head_employee_id      BIGINT,                          -- FK added after employees
    cost_center_code      VARCHAR(20),
    email                 VARCHAR(150),                    -- shared mailbox, e.g. finance@maxhub.co.zw
    phone_extension       VARCHAR(10),
    description           TEXT,
    is_revenue_generating BOOLEAN      NOT NULL DEFAULT TRUE,
    is_active             BOOLEAN      NOT NULL DEFAULT TRUE
);

-- Practices / service lines (each run by a client-service department)
CREATE TABLE service_lines (
    service_line_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code             VARCHAR(10)  NOT NULL UNIQUE,
    name             VARCHAR(100) NOT NULL,
    description      TEXT,
    department_id    BIGINT       REFERENCES departments,
    lead_employee_id BIGINT,                             -- FK added after employees
    revenue_target   NUMERIC(18,2),
    is_active        BOOLEAN      NOT NULL DEFAULT TRUE
);
