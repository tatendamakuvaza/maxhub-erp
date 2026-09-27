
/* =====================================================================================
   04. HUMAN RESOURCES & PAYROLL
   ===================================================================================== */

CREATE TABLE job_grades (
    job_grade_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code              VARCHAR(10)   NOT NULL UNIQUE,
    name              VARCHAR(60)   NOT NULL,
    level             SMALLINT      NOT NULL UNIQUE,
    min_salary        NUMERIC(14,2),
    max_salary        NUMERIC(14,2),
    currency_code     CHAR(3)       NOT NULL REFERENCES currencies,
    default_cost_rate NUMERIC(10,2) NOT NULL DEFAULT 0,   -- fully loaded cost / hour
    default_bill_rate NUMERIC(10,2) NOT NULL DEFAULT 0,   -- standard sell rate / hour
    target_utilization_pct NUMERIC(5,2) NOT NULL DEFAULT 75,
    CHECK (max_salary IS NULL OR min_salary IS NULL OR max_salary >= min_salary)
);

CREATE TABLE employees (
    employee_id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_number         VARCHAR(20)  NOT NULL UNIQUE,
    first_name              VARCHAR(60)  NOT NULL,
    last_name               VARCHAR(60)  NOT NULL,
    preferred_name          VARCHAR(60),
    email                   VARCHAR(150) NOT NULL,
    phone                   VARCHAR(40),
    national_id             VARCHAR(40),
    date_of_birth           DATE,
    gender                  VARCHAR(20),
    hire_date               DATE         NOT NULL,
    termination_date        DATE,
    employment_type         employment_type NOT NULL DEFAULT 'full_time',
    status                  employee_status NOT NULL DEFAULT 'active',
    job_grade_id            BIGINT       REFERENCES job_grades,
    job_title               VARCHAR(100),
    department_id           BIGINT       REFERENCES departments,
    office_id               BIGINT       REFERENCES offices,
    service_line_id         BIGINT       REFERENCES service_lines,
    manager_id              BIGINT       REFERENCES employees,
    is_billable             BOOLEAN      NOT NULL DEFAULT TRUE,
    standard_hours_per_week NUMERIC(5,2) NOT NULL DEFAULT 40 CHECK (standard_hours_per_week BETWEEN 0 AND 80),
    target_utilization_pct  NUMERIC(5,2) NOT NULL DEFAULT 75 CHECK (target_utilization_pct BETWEEN 0 AND 100),
    cost_rate_hourly        NUMERIC(10,2),
    default_bill_rate       NUMERIC(10,2),
    currency_code           CHAR(3)      NOT NULL DEFAULT 'USD' REFERENCES currencies,
    bank_name               VARCHAR(100),
    bank_account_number     VARCHAR(50),
    emergency_contact_name  VARCHAR(100),
    emergency_contact_phone VARCHAR(40),
    -- company communication details
    work_phone_ext          VARCHAR(10),
    mobile_phone            VARCHAR(40),
    personal_email          VARCHAR(150),
    -- statutory & personal details
    nationality             VARCHAR(60),
    tax_number              VARCHAR(40),       -- ZIMRA TIN / SARS / KRA PIN / UK NI number
    social_security_number  VARCHAR(40),       -- NSSA / UIF / NSSF number
    work_permit_expiry      DATE,
    pension_member          BOOLEAN      NOT NULL DEFAULT TRUE,
    medical_aid_member      BOOLEAN      NOT NULL DEFAULT TRUE,
    medical_aid_scheme      VARCHAR(80),
    created_at              TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CHECK (termination_date IS NULL OR termination_date >= hire_date),
    CHECK (manager_id IS NULL OR manager_id <> employee_id)
);
CREATE UNIQUE INDEX ux_employees_email ON employees (lower(email));

ALTER TABLE departments   ADD CONSTRAINT fk_departments_head   FOREIGN KEY (head_employee_id) REFERENCES employees;
ALTER TABLE offices       ADD CONSTRAINT fk_offices_manager    FOREIGN KEY (manager_employee_id) REFERENCES employees;
ALTER TABLE service_lines ADD CONSTRAINT fk_service_lines_lead FOREIGN KEY (lead_employee_id) REFERENCES employees;

CREATE TABLE employee_compensation (
    compensation_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id       BIGINT        NOT NULL REFERENCES employees ON DELETE CASCADE,
    effective_date    DATE          NOT NULL,
    base_salary_annual NUMERIC(14,2) NOT NULL CHECK (base_salary_annual >= 0),
    monthly_allowances NUMERIC(12,2) NOT NULL DEFAULT 0,
    bonus_target_pct  NUMERIC(5,2)  NOT NULL DEFAULT 0,
    currency_code     CHAR(3)       NOT NULL REFERENCES currencies,
    change_reason     VARCHAR(150),
    approved_by       BIGINT        REFERENCES employees,
    UNIQUE (employee_id, effective_date)
);

CREATE TABLE skills (
    skill_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name      VARCHAR(80) NOT NULL UNIQUE,
    category  VARCHAR(60)
);

CREATE TABLE employee_skills (
    employee_id      BIGINT       NOT NULL REFERENCES employees ON DELETE CASCADE,
    skill_id         BIGINT       NOT NULL REFERENCES skills ON DELETE CASCADE,
    proficiency      SMALLINT     NOT NULL CHECK (proficiency BETWEEN 1 AND 5),
    years_experience NUMERIC(4,1),
    PRIMARY KEY (employee_id, skill_id)
);

CREATE TABLE certifications (
    certification_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id      BIGINT       NOT NULL REFERENCES employees ON DELETE CASCADE,
    name             VARCHAR(120) NOT NULL,
    issuing_body     VARCHAR(120),
    credential_id    VARCHAR(80),
    issue_date       DATE,
    expiry_date      DATE,
    CHECK (expiry_date IS NULL OR issue_date IS NULL OR expiry_date >= issue_date)
);

CREATE TABLE public_holidays (
    holiday_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    country_code CHAR(2)      NOT NULL REFERENCES countries,
    holiday_date DATE         NOT NULL,
    name         VARCHAR(100) NOT NULL,
    UNIQUE (country_code, holiday_date)
);

CREATE TABLE leave_types (
    leave_type_id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code                    VARCHAR(10)  NOT NULL UNIQUE,
    name                    VARCHAR(60)  NOT NULL,
    annual_entitlement_days NUMERIC(5,2) NOT NULL DEFAULT 0,
    is_paid                 BOOLEAN      NOT NULL DEFAULT TRUE,
    carry_forward_max_days  NUMERIC(5,2) NOT NULL DEFAULT 0,
    requires_document       BOOLEAN      NOT NULL DEFAULT FALSE
);

CREATE TABLE leave_balances (
    employee_id          BIGINT       NOT NULL REFERENCES employees ON DELETE CASCADE,
    leave_type_id        BIGINT       NOT NULL REFERENCES leave_types,
    leave_year           SMALLINT     NOT NULL,
    entitled_days        NUMERIC(5,2) NOT NULL DEFAULT 0,
    carried_forward_days NUMERIC(5,2) NOT NULL DEFAULT 0,
    taken_days           NUMERIC(5,2) NOT NULL DEFAULT 0,
    remaining_days       NUMERIC(6,2) GENERATED ALWAYS AS (entitled_days + carried_forward_days - taken_days) STORED,
    PRIMARY KEY (employee_id, leave_type_id, leave_year)
);

CREATE TABLE leave_requests (
    leave_request_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id      BIGINT          NOT NULL REFERENCES employees,
    leave_type_id    BIGINT          NOT NULL REFERENCES leave_types,
    start_date       DATE            NOT NULL,
    end_date         DATE            NOT NULL,
    days_requested   NUMERIC(5,2)    NOT NULL CHECK (days_requested > 0),
    reason           TEXT,
    status           approval_status NOT NULL DEFAULT 'draft',
    approver_id      BIGINT          REFERENCES employees,
    decided_at       TIMESTAMPTZ,
    decision_comment TEXT,
    created_at       TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ     NOT NULL DEFAULT now(),
    CHECK (end_date >= start_date)
);

CREATE TABLE performance_reviews (
    review_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id    BIGINT   NOT NULL REFERENCES employees,
    reviewer_id    BIGINT   NOT NULL REFERENCES employees,
    period_start   DATE     NOT NULL,
    period_end     DATE     NOT NULL,
    overall_rating SMALLINT CHECK (overall_rating BETWEEN 1 AND 5),
    strengths      TEXT,
    development_areas TEXT,
    goals_next_period TEXT,
    status         VARCHAR(20) NOT NULL DEFAULT 'draft'
                   CHECK (status IN ('draft','self_review','manager_review','completed')),
    completed_at   TIMESTAMPTZ,
    CHECK (period_end > period_start),
    CHECK (employee_id <> reviewer_id)
);

CREATE TABLE payroll_runs (
    payroll_run_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_number       VARCHAR(30) UNIQUE,                 -- e.g. PAY-ZW-2026-09
    country_code     CHAR(2)     NOT NULL REFERENCES countries,
    period_start     DATE        NOT NULL,
    period_end       DATE        NOT NULL,
    pay_date         DATE        NOT NULL,
    currency_code    CHAR(3)     NOT NULL REFERENCES currencies,
    exchange_rate    NUMERIC(18,8) NOT NULL DEFAULT 1,    -- payroll currency -> USD
    status           VARCHAR(20) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','approved','paid','cancelled')),
    employee_count   INTEGER     NOT NULL DEFAULT 0,
    total_gross      NUMERIC(16,2) NOT NULL DEFAULT 0,
    total_net        NUMERIC(16,2) NOT NULL DEFAULT 0,
    total_employer_cost NUMERIC(16,2) NOT NULL DEFAULT 0,
    approved_by      BIGINT      REFERENCES employees,
    approved_at      TIMESTAMPTZ,
    journal_entry_id BIGINT,                             -- accrual journal (FK added in module 13)
    payment_journal_id BIGINT,                           -- net-pay journal
    notes            TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (country_code, period_start, period_end, currency_code),
    CHECK (period_end >= period_start)
);

-- One payslip per employee per run. Statutory fields follow Zimbabwe payroll
-- (PAYE + AIDS levy, NSSA POBS & WCIF, ZIMDEF); branches reuse the same columns for
-- their local income tax and social-security equivalents.
CREATE TABLE payslips (
    payslip_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payroll_run_id    BIGINT        NOT NULL REFERENCES payroll_runs ON DELETE CASCADE,
    employee_id       BIGINT        NOT NULL REFERENCES employees,
    currency_code     CHAR(3)       NOT NULL REFERENCES currencies,
    -- earnings
    basic_pay         NUMERIC(14,2) NOT NULL DEFAULT 0,
    allowances        NUMERIC(14,2) NOT NULL DEFAULT 0,   -- housing, transport, cell phone
    overtime          NUMERIC(14,2) NOT NULL DEFAULT 0,
    bonus             NUMERIC(14,2) NOT NULL DEFAULT 0,
    -- employee deductions
    nssa_employee     NUMERIC(14,2) NOT NULL DEFAULT 0,   -- NSSA POBS 4.5% (capped) / UIF / NSSF / NI
    pension           NUMERIC(14,2) NOT NULL DEFAULT 0,   -- approved pension fund (employee)
    taxable_income    NUMERIC(14,2) NOT NULL DEFAULT 0,
    paye_tax          NUMERIC(14,2) NOT NULL DEFAULT 0,   -- income tax after credits
    medical_aid_credit NUMERIC(14,2) NOT NULL DEFAULT 0,  -- ZIMRA 50% medical-aid credit (already netted in paye_tax)
    aids_levy         NUMERIC(14,2) NOT NULL DEFAULT 0,   -- 3% of PAYE (Zimbabwe)
    medical_aid       NUMERIC(14,2) NOT NULL DEFAULT 0,   -- employee medical aid contribution
    other_deductions  NUMERIC(14,2) NOT NULL DEFAULT 0,   -- loans, union dues, funeral cover
    -- employer contributions (cost to company, not deducted from pay)
    employer_nssa     NUMERIC(14,2) NOT NULL DEFAULT 0,   -- NSSA POBS 4.5% / UIF / NSSF / employer NI
    employer_wcif     NUMERIC(14,2) NOT NULL DEFAULT 0,   -- NSSA Workers Compensation / SDL / gratuity accrual
    employer_zimdef   NUMERIC(14,2) NOT NULL DEFAULT 0,   -- ZIMDEF 1% manpower development levy
    employer_pension  NUMERIC(14,2) NOT NULL DEFAULT 0,
    employer_medical  NUMERIC(14,2) NOT NULL DEFAULT 0,
    gross_pay         NUMERIC(14,2) GENERATED ALWAYS AS (basic_pay + allowances + overtime + bonus) STORED,
    total_deductions  NUMERIC(14,2) GENERATED ALWAYS AS
                      (nssa_employee + pension + paye_tax + aids_levy + medical_aid + other_deductions) STORED,
    net_pay           NUMERIC(14,2) GENERATED ALWAYS AS
                      (basic_pay + allowances + overtime + bonus
                       - nssa_employee - pension - paye_tax - aids_levy - medical_aid - other_deductions) STORED,
    employer_cost     NUMERIC(14,2) GENERATED ALWAYS AS
                      (basic_pay + allowances + overtime + bonus
                       + employer_nssa + employer_wcif + employer_zimdef + employer_pension + employer_medical) STORED,
    UNIQUE (payroll_run_id, employee_id)
);
