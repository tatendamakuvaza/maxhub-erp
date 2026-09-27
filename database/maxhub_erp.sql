-- =====================================================================================
-- GENERATED FILE - built by database/build.py on 24 Sep 2026 from database/modules/*.sql
-- Edit the module files, then run:  python database/build.py
-- =====================================================================================

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  00_setup.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
/* =====================================================================================
   MAXHUB PVT LTD (t/a MAXHUB FORENSIC DATA ANALYTICS)  -  ENTERPRISE ERP DATABASE
   ------------------------------------------------------------------------------------
   Target      : PostgreSQL 15+ (tested on PostgreSQL 17)          Schema : erp
   Company     : Forensic audit, data analytics, cyber, risk, tax & financial advisory
                 consultancy. HQ Harare (owned), Bulawayo (owned), rented branches in
                 Johannesburg, Nairobi, London and Dubai.
   Reporting   : IFRS Accounting Standards, IFRS 18 "Presentation and Disclosure in
                 Financial Statements" (early adopted for FY2026), IAS 16, IAS 38, IAS 40,
                 IFRS 16, IFRS 15, IFRS 9 (ECL), IAS 12, IAS 19, IAS 21, IFRS 8.
   Tax         : ZIMRA (VAT, PAYE + AIDS levy, Corporate Income Tax + QPDs, WHT, IMTT,
                 fiscalised invoices), NSSA (POBS + WCIF), ZIMDEF, plus branch taxes
                 (SARS, KRA, HMRC, UAE FTA).  All rates live in tables - update them when
                 ZIMRA/NSSA publish changes.
   Security    : Log-in with bcrypt-hashed passwords (pgcrypto), account lock-out,
                 password policy & history, sessions, login audit, role-based access
                 that follows each employee's department and grade.

   MODULES (this file is built from the files in database/modules)
     00 Setup & types            10 Billing & receivables      20 Core business logic
     01 Reference & settings     11 Time & expense             21 Authentication logic
     02 Chart of accounts/banks  12 Procurement & payables     22 Finance, payroll, tax logic
     03 Organisation (6 offices) 13 General ledger & budgets   23 Reporting views & IFRS
     04 HR & payroll             14 Documents                     financial statements
     05 Security & access        15 Fixed assets (IAS 16/38/40) 24 Indexes & hardening
     06 CRM                      16 Leases & borrowings (IFRS16) 30-36 Seed / demo data
     07 Sales                    17 Tax compliance (ZIMRA/NSSA)
     08 Contracts                18 Communications (mail, notices)
     09 Projects                 19 IFRS reporting structure

   Run with    : psql -U postgres -d maxhub_erp -f maxhub_erp.sql
   WARNING     : This script DROPS and recreates schema "erp" (all ERP data is replaced).
   ===================================================================================== */

-- pgcrypto gives us bcrypt password hashing (crypt / gen_salt). It is a "trusted"
-- extension, so the database owner can install it (it ships with PostgreSQL on Windows).
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;

DROP SCHEMA IF EXISTS erp CASCADE;
CREATE SCHEMA erp;
SET search_path TO erp, public;

/* ---------- Enumerated types ---------- */
CREATE TYPE employment_type   AS ENUM ('full_time','part_time','contractor','intern');
CREATE TYPE employee_status   AS ENUM ('active','on_leave','suspended','terminated');
CREATE TYPE client_status     AS ENUM ('prospect','active','inactive','blacklisted');
CREATE TYPE opportunity_stage AS ENUM ('qualification','needs_analysis','proposal','negotiation','won','lost');
CREATE TYPE contract_type     AS ENUM ('time_and_materials','fixed_fee','retainer','milestone');
CREATE TYPE project_status    AS ENUM ('planned','active','on_hold','completed','cancelled');
CREATE TYPE task_status       AS ENUM ('todo','in_progress','review','done','blocked');
CREATE TYPE approval_status   AS ENUM ('draft','submitted','approved','rejected');
CREATE TYPE invoice_status    AS ENUM ('draft','issued','partially_paid','paid','overdue','void');
CREATE TYPE priority_level    AS ENUM ('low','medium','high','critical');
CREATE TYPE account_type      AS ENUM ('asset','liability','equity','revenue','expense');
CREATE TYPE payment_method    AS ENUM ('bank_transfer','cash','card','mobile_money','cheque','rtgs');

CREATE TYPE asset_status      AS ENUM ('under_construction','in_use','idle','held_for_sale','disposed','written_off');
CREATE TYPE tax_return_status AS ENUM ('not_started','draft','filed','paid','overdue','cancelled');

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  01_reference.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

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


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  02_accounts_banking.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   02. CHART OF ACCOUNTS, IFRS MAPPING & BANKING
   -------------------------------------------------------------------------------------
   Every postable account is mapped to
     * an IFRS line item  (which line of which primary statement it rolls into), and
     * a cash-flow line    (used to build the statement of cash flows, direct method).
   The IFRS line item carries the IFRS 18 category: operating / investing / financing /
   income_taxes / discontinued (profit or loss) - so the income statement subtotals
   "Operating profit" and "Profit before financing and income taxes" come straight
   from the data.
   ===================================================================================== */

CREATE TABLE ifrs_line_items (
    line_code        VARCHAR(20)  PRIMARY KEY,           -- e.g. PL_REV, SFP_PPE
    statement        VARCHAR(4)   NOT NULL CHECK (statement IN ('PL','OCI','SFP')),
    section          VARCHAR(60)  NOT NULL,              -- heading the line sits under
    name             VARCHAR(150) NOT NULL,              -- caption shown in the statements
    ifrs18_category  VARCHAR(15)  CHECK (ifrs18_category IN ('operating','investing','financing','income_taxes','discontinued')),
    sort_order       SMALLINT     NOT NULL,
    sign             SMALLINT     NOT NULL DEFAULT 1 CHECK (sign IN (1,-1)),  -- 1 = credit-positive (income), -1 = debit-positive
    standard_ref     VARCHAR(60),                        -- e.g. 'IFRS 18.75', 'IAS 16'
    nature_disclosure VARCHAR(40),                       -- IFRS 18 specified expense by nature (depreciation, employee benefits...)
    CHECK (statement <> 'PL' OR ifrs18_category IS NOT NULL)
);

CREATE TABLE cash_flow_lines (
    cf_code      VARCHAR(20)  PRIMARY KEY,               -- e.g. CF_OP_RECEIPTS
    category     VARCHAR(15)  NOT NULL CHECK (category IN ('operating','investing','financing','fx')),
    name         VARCHAR(150) NOT NULL,
    sort_order   SMALLINT     NOT NULL
);

CREATE TABLE chart_of_accounts (
    account_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_code      VARCHAR(20)  NOT NULL UNIQUE,
    name              VARCHAR(120) NOT NULL,
    account_type      account_type NOT NULL,
    parent_account_id BIGINT       REFERENCES chart_of_accounts,
    is_postable       BOOLEAN      NOT NULL DEFAULT TRUE,   -- FALSE = header / roll-up account
    is_active         BOOLEAN      NOT NULL DEFAULT TRUE,
    ifrs_line_code    VARCHAR(20)  REFERENCES ifrs_line_items,
    cash_flow_code    VARCHAR(20)  REFERENCES cash_flow_lines,
    is_cash           BOOLEAN      NOT NULL DEFAULT FALSE,  -- cash & cash equivalents (IAS 7)
    is_control        BOOLEAN      NOT NULL DEFAULT FALSE,  -- AR/AP/asset control accounts: post via sub-ledgers
    description       TEXT,
    CHECK (NOT is_postable OR ifrs_line_code IS NOT NULL)
);

CREATE TABLE bank_accounts (
    bank_account_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    bank_name       VARCHAR(100) NOT NULL,
    branch          VARCHAR(100),
    account_number  VARCHAR(50)  NOT NULL,
    swift_code      VARCHAR(20),
    account_type    VARCHAR(20)  NOT NULL DEFAULT 'current'
                    CHECK (account_type IN ('current','savings','money_market','fca','petty_cash')),
    currency_code   CHAR(3)      NOT NULL REFERENCES currencies,
    gl_account_id   BIGINT       NOT NULL REFERENCES chart_of_accounts,
    office_id       BIGINT,                                -- FK added after offices
    opening_balance NUMERIC(18,2) NOT NULL DEFAULT 0,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    UNIQUE (bank_name, account_number)
);

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  03_organisation.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

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

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  04_hr_payroll.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

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

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  05_security.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   05. SECURITY - USERS, LOG-IN, ROLES, PERMISSIONS & AUDIT
   -------------------------------------------------------------------------------------
   How access works
     * Every employee gets ONE user account (username = firstname.lastname, e-mail =
       firstname.lastname@maxhub.co.zw).  Passwords are stored as bcrypt hashes
       (pgcrypto) - never as plain text.
     * People must log in first.  fn_login() checks the password, counts failures,
       locks the account for 15 minutes after 5 wrong attempts and writes every
       attempt to login_attempts.
     * Roles are given automatically from the employee's DEPARTMENT and GRADE
       (department_role_rules), e.g. Finance staff -> ACCOUNTANT, Finance managers ->
       FINANCE_MANAGER, every employee -> EMPLOYEE (self-service).
     * Roles carry permissions such as 'page.finance' or 'payroll.run'.  The dashboard
       only shows the pages the user's permissions allow.
   ===================================================================================== */

CREATE TABLE roles (
    role_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code        VARCHAR(30)  NOT NULL UNIQUE,
    name        VARCHAR(80)  NOT NULL,
    description TEXT,
    is_system   BOOLEAN      NOT NULL DEFAULT FALSE     -- cannot be deleted from the UI
);

CREATE TABLE permissions (
    permission_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code          VARCHAR(60) NOT NULL UNIQUE,     -- e.g. 'page.finance', 'invoice.issue'
    module        VARCHAR(30) NOT NULL,
    description   TEXT
);

CREATE TABLE role_permissions (
    role_id       BIGINT NOT NULL REFERENCES roles ON DELETE CASCADE,
    permission_id BIGINT NOT NULL REFERENCES permissions ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE app_users (
    user_id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id          BIGINT       UNIQUE REFERENCES employees,
    username             VARCHAR(60)  NOT NULL UNIQUE,
    email                VARCHAR(150) NOT NULL,
    password_hash        TEXT         NOT NULL,          -- bcrypt hash, e.g. $2a$10$...
    is_active            BOOLEAN      NOT NULL DEFAULT TRUE,
    must_change_password BOOLEAN      NOT NULL DEFAULT FALSE,
    password_changed_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    failed_logins        SMALLINT     NOT NULL DEFAULT 0,
    locked_until         TIMESTAMPTZ,
    last_login_at        TIMESTAMPTZ,
    last_login_ip        VARCHAR(60),
    mfa_enabled          BOOLEAN      NOT NULL DEFAULT FALSE,
    mfa_secret           TEXT,                           -- TOTP secret (encrypted) if MFA switched on
    is_service_account   BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CHECK (username = lower(username)),
    CHECK (password_hash LIKE '$2%')                     -- only bcrypt hashes accepted
);
CREATE UNIQUE INDEX ux_app_users_email ON app_users (lower(email));

CREATE TABLE user_roles (
    user_id    BIGINT NOT NULL REFERENCES app_users ON DELETE CASCADE,
    role_id    BIGINT NOT NULL REFERENCES roles ON DELETE CASCADE,
    source     VARCHAR(10) NOT NULL DEFAULT 'manual' CHECK (source IN ('auto','manual')),  -- auto = from department rules
    granted_by BIGINT REFERENCES app_users,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, role_id)
);

-- Department + grade -> role rules (drives automatic role assignment)
CREATE TABLE department_role_rules (
    rule_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    department_id   BIGINT   REFERENCES departments ON DELETE CASCADE,  -- NULL = every department
    min_grade_level SMALLINT NOT NULL DEFAULT 0,                       -- job_grades.level
    max_grade_level SMALLINT NOT NULL DEFAULT 99,
    role_id         BIGINT   NOT NULL REFERENCES roles ON DELETE CASCADE,
    description     VARCHAR(200),
    UNIQUE NULLS NOT DISTINCT (department_id, min_grade_level, max_grade_level, role_id)
);

-- Every log-in attempt (successful or not)
CREATE TABLE login_attempts (
    attempt_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username_tried VARCHAR(150) NOT NULL,
    user_id        BIGINT       REFERENCES app_users ON DELETE SET NULL,
    success        BOOLEAN      NOT NULL,
    failure_reason VARCHAR(60),               -- wrong_password, locked, inactive, unknown_user
    ip_address     VARCHAR(60),
    user_agent     VARCHAR(300),
    attempted_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Server-side sessions (only a SHA-256 hash of the token is stored)
CREATE TABLE user_sessions (
    session_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id       BIGINT       NOT NULL REFERENCES app_users ON DELETE CASCADE,
    token_hash    TEXT         NOT NULL UNIQUE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    last_seen_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    expires_at    TIMESTAMPTZ  NOT NULL,
    ip_address    VARCHAR(60),
    revoked_at    TIMESTAMPTZ,
    revoke_reason VARCHAR(60)
);

-- Last N password hashes, to stop people re-using old passwords
CREATE TABLE password_history (
    user_id       BIGINT      NOT NULL REFERENCES app_users ON DELETE CASCADE,
    password_hash TEXT        NOT NULL,
    changed_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, changed_at)
);

-- Security settings (single row)
CREATE TABLE security_policy (
    policy_id              SMALLINT PRIMARY KEY DEFAULT 1 CHECK (policy_id = 1),
    min_password_length    SMALLINT NOT NULL DEFAULT 8,
    require_upper          BOOLEAN  NOT NULL DEFAULT TRUE,
    require_lower          BOOLEAN  NOT NULL DEFAULT TRUE,
    require_digit          BOOLEAN  NOT NULL DEFAULT TRUE,
    require_symbol         BOOLEAN  NOT NULL DEFAULT TRUE,
    password_history_count SMALLINT NOT NULL DEFAULT 5,
    max_failed_logins      SMALLINT NOT NULL DEFAULT 5,
    lockout_minutes        SMALLINT NOT NULL DEFAULT 15,
    session_hours          SMALLINT NOT NULL DEFAULT 8,
    password_max_age_days  SMALLINT NOT NULL DEFAULT 90,
    bcrypt_cost            SMALLINT NOT NULL DEFAULT 10 CHECK (bcrypt_cost BETWEEN 6 AND 14)
);

CREATE TABLE audit_log (
    audit_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name  VARCHAR(60) NOT NULL,
    record_pk   TEXT,
    action      VARCHAR(10) NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
    old_data    JSONB,
    new_data    JSONB,
    changed_by  BIGINT,                 -- app user id, taken from setting erp.current_user_id
    db_user     TEXT        NOT NULL DEFAULT current_user,
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  06_crm.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

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


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  07_sales.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

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


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  08_contracts.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

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


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  09_projects.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   09. PROJECTS, PHASES, TASKS, RESOURCING, DELIVERY GOVERNANCE
   ===================================================================================== */

CREATE TABLE projects (
    project_id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_code          VARCHAR(20)    NOT NULL UNIQUE,
    name                  VARCHAR(200)   NOT NULL,
    description           TEXT,
    client_id             BIGINT         REFERENCES clients,   -- NULL for internal projects
    contract_id           BIGINT         REFERENCES contracts,
    service_line_id       BIGINT         REFERENCES service_lines,
    project_manager_id    BIGINT         REFERENCES employees,
    engagement_partner_id BIGINT         REFERENCES employees,
    office_id             BIGINT         REFERENCES offices,   -- delivering office / branch (segment reporting)
    status                project_status NOT NULL DEFAULT 'planned',
    billing_type          contract_type  NOT NULL DEFAULT 'time_and_materials',
    is_internal           BOOLEAN        NOT NULL DEFAULT FALSE,
    start_date            DATE           NOT NULL,
    planned_end_date      DATE,
    actual_end_date       DATE,
    currency_code         CHAR(3)        NOT NULL DEFAULT 'USD' REFERENCES currencies,
    budget_hours          NUMERIC(10,2)  NOT NULL DEFAULT 0,
    budget_fees           NUMERIC(18,2)  NOT NULL DEFAULT 0,
    budget_expenses       NUMERIC(18,2)  NOT NULL DEFAULT 0,
    budget_cost           NUMERIC(18,2)  NOT NULL DEFAULT 0,
    completion_pct        NUMERIC(5,2)   NOT NULL DEFAULT 0 CHECK (completion_pct BETWEEN 0 AND 100),
    priority              priority_level NOT NULL DEFAULT 'medium',
    created_at            TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CHECK (planned_end_date IS NULL OR planned_end_date >= start_date),
    CHECK (is_internal OR client_id IS NOT NULL)
);

CREATE TABLE project_phases (
    phase_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_id   BIGINT        NOT NULL REFERENCES projects ON DELETE CASCADE,
    seq          SMALLINT      NOT NULL,
    name         VARCHAR(150)  NOT NULL,
    start_date   DATE,
    end_date     DATE,
    budget_hours NUMERIC(10,2) NOT NULL DEFAULT 0,
    budget_fees  NUMERIC(18,2) NOT NULL DEFAULT 0,
    status       project_status NOT NULL DEFAULT 'planned',
    UNIQUE (project_id, seq)
);

CREATE TABLE tasks (
    task_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_id      BIGINT         NOT NULL REFERENCES projects ON DELETE CASCADE,
    phase_id        BIGINT         REFERENCES project_phases ON DELETE SET NULL,
    parent_task_id  BIGINT         REFERENCES tasks ON DELETE CASCADE,
    name            VARCHAR(200)   NOT NULL,
    description     TEXT,
    assignee_id     BIGINT         REFERENCES employees,
    status          task_status    NOT NULL DEFAULT 'todo',
    priority        priority_level NOT NULL DEFAULT 'medium',
    estimated_hours NUMERIC(8,2),
    start_date      DATE,
    due_date        DATE,
    completed_at    TIMESTAMPTZ,
    is_billable     BOOLEAN        NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ    NOT NULL DEFAULT now()
);

-- Who is staffed on which engagement, and at what sell / cost rate
CREATE TABLE project_members (
    project_member_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_id        BIGINT        NOT NULL REFERENCES projects ON DELETE CASCADE,
    employee_id       BIGINT        NOT NULL REFERENCES employees,
    project_role      VARCHAR(60)   NOT NULL DEFAULT 'Consultant',
    bill_rate         NUMERIC(10,2),         -- NULL => rate card / employee default
    cost_rate         NUMERIC(10,2),         -- NULL => employee cost rate
    start_date        DATE          NOT NULL,
    end_date          DATE,
    allocation_pct    NUMERIC(5,2)  NOT NULL DEFAULT 100 CHECK (allocation_pct BETWEEN 0 AND 100),
    UNIQUE (project_id, employee_id, start_date),
    CHECK (end_date IS NULL OR end_date >= start_date)
);

-- Weekly resource plan / forecast
CREATE TABLE resource_allocations (
    allocation_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id     BIGINT       NOT NULL REFERENCES employees,
    project_id      BIGINT       NOT NULL REFERENCES projects ON DELETE CASCADE,
    week_start_date DATE         NOT NULL CHECK (extract(isodow FROM week_start_date) = 1),
    planned_hours   NUMERIC(5,2) NOT NULL CHECK (planned_hours BETWEEN 0 AND 80),
    is_tentative    BOOLEAN      NOT NULL DEFAULT FALSE,
    UNIQUE (employee_id, project_id, week_start_date)
);

CREATE TABLE deliverables (
    deliverable_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_id        BIGINT       NOT NULL REFERENCES projects ON DELETE CASCADE,
    phase_id          BIGINT       REFERENCES project_phases ON DELETE SET NULL,
    milestone_id      BIGINT       REFERENCES contract_milestones,
    name              VARCHAR(200) NOT NULL,
    description       TEXT,
    owner_id          BIGINT       REFERENCES employees,
    due_date          DATE,
    delivered_date    DATE,
    status            VARCHAR(20)  NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending','in_progress','submitted','accepted','rejected')),
    client_signoff_by VARCHAR(120),
    signoff_date      DATE
);

CREATE TABLE project_risks (
    risk_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_id  BIGINT       NOT NULL REFERENCES projects ON DELETE CASCADE,
    title       VARCHAR(200) NOT NULL,
    description TEXT,
    probability SMALLINT     NOT NULL CHECK (probability BETWEEN 1 AND 5),
    impact      SMALLINT     NOT NULL CHECK (impact BETWEEN 1 AND 5),
    risk_score  SMALLINT     GENERATED ALWAYS AS (probability * impact) STORED,
    mitigation  TEXT,
    owner_id    BIGINT       REFERENCES employees,
    status      VARCHAR(20)  NOT NULL DEFAULT 'open' CHECK (status IN ('open','mitigating','closed','occurred')),
    raised_date DATE         NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE project_issues (
    issue_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_id    BIGINT         NOT NULL REFERENCES projects ON DELETE CASCADE,
    title         VARCHAR(200)   NOT NULL,
    description   TEXT,
    priority      priority_level NOT NULL DEFAULT 'medium',
    status        VARCHAR(20)    NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_progress','resolved','closed')),
    raised_by     BIGINT         REFERENCES employees,
    assigned_to   BIGINT         REFERENCES employees,
    raised_date   DATE           NOT NULL DEFAULT CURRENT_DATE,
    resolved_date DATE,
    resolution    TEXT
);

CREATE TABLE project_status_reports (
    status_report_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project_id       BIGINT  NOT NULL REFERENCES projects ON DELETE CASCADE,
    report_date      DATE    NOT NULL,
    overall_rag      CHAR(1) NOT NULL CHECK (overall_rag  IN ('R','A','G')),
    schedule_rag     CHAR(1) NOT NULL CHECK (schedule_rag IN ('R','A','G')),
    budget_rag       CHAR(1) NOT NULL CHECK (budget_rag   IN ('R','A','G')),
    scope_rag        CHAR(1) NOT NULL CHECK (scope_rag    IN ('R','A','G')),
    summary          TEXT,
    accomplishments  TEXT,
    next_steps       TEXT,
    author_id        BIGINT  REFERENCES employees,
    UNIQUE (project_id, report_date)
);


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  10_billing.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

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


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  11_time_expense.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   11. TIME & EXPENSE
   ===================================================================================== */

CREATE TABLE activity_codes (
    activity_code VARCHAR(20) PRIMARY KEY,         -- CLIENT, BD, ADMIN, TRAINING, LEAVE ...
    name          VARCHAR(80) NOT NULL,
    is_chargeable BOOLEAN     NOT NULL DEFAULT FALSE,
    counts_as_capacity_reduction BOOLEAN NOT NULL DEFAULT FALSE   -- e.g. leave, public holiday
);

CREATE TABLE timesheets (
    timesheet_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    employee_id      BIGINT          NOT NULL REFERENCES employees,
    week_start_date  DATE            NOT NULL CHECK (extract(isodow FROM week_start_date) = 1),  -- Monday
    status           approval_status NOT NULL DEFAULT 'draft',
    total_hours      NUMERIC(6,2)    NOT NULL DEFAULT 0,          -- maintained by trigger
    submitted_at     TIMESTAMPTZ,
    approved_by      BIGINT          REFERENCES employees,
    approved_at      TIMESTAMPTZ,
    rejection_reason TEXT,
    created_at       TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ     NOT NULL DEFAULT now(),
    UNIQUE (employee_id, week_start_date)
);

CREATE TABLE time_entries (
    time_entry_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    timesheet_id    BIGINT        NOT NULL REFERENCES timesheets ON DELETE CASCADE,
    employee_id     BIGINT        NOT NULL REFERENCES employees,
    project_id      BIGINT        REFERENCES projects,     -- NULL => internal / non-project time
    task_id         BIGINT        REFERENCES tasks,
    activity_code   VARCHAR(20)   NOT NULL DEFAULT 'CLIENT' REFERENCES activity_codes,
    work_date       DATE          NOT NULL,
    hours           NUMERIC(5,2)  NOT NULL CHECK (hours > 0 AND hours <= 24),
    is_billable     BOOLEAN       NOT NULL DEFAULT TRUE,
    bill_rate       NUMERIC(10,2),                          -- defaulted by trigger
    cost_rate       NUMERIC(10,2),                          -- defaulted by trigger
    billable_amount NUMERIC(14,2) GENERATED ALWAYS AS
                    (CASE WHEN is_billable THEN round(hours * COALESCE(bill_rate,0), 2) ELSE 0 END) STORED,
    cost_amount     NUMERIC(14,2) GENERATED ALWAYS AS (round(hours * COALESCE(cost_rate,0), 2)) STORED,
    description     TEXT,
    invoice_line_id BIGINT        REFERENCES invoice_lines ON DELETE SET NULL,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE expense_categories (
    expense_category_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code                 VARCHAR(20)  NOT NULL UNIQUE,
    name                 VARCHAR(80)  NOT NULL,
    gl_account_id        BIGINT       NOT NULL REFERENCES chart_of_accounts,
    is_billable_default  BOOLEAN      NOT NULL DEFAULT TRUE,
    requires_receipt     BOOLEAN      NOT NULL DEFAULT TRUE,
    max_amount_per_item  NUMERIC(12,2)
);

CREATE TABLE expense_reports (
    expense_report_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    report_number     VARCHAR(30)     UNIQUE,              -- auto-assigned
    employee_id       BIGINT          NOT NULL REFERENCES employees,
    title             VARCHAR(150)    NOT NULL,
    status            approval_status NOT NULL DEFAULT 'draft',
    currency_code     CHAR(3)         NOT NULL DEFAULT 'USD' REFERENCES currencies,
    total_amount      NUMERIC(14,2)   NOT NULL DEFAULT 0,  -- maintained by trigger
    submitted_at      TIMESTAMPTZ,
    approved_by       BIGINT          REFERENCES employees,
    approved_at       TIMESTAMPTZ,
    reimbursed_at     TIMESTAMPTZ,
    rejection_reason  TEXT,
    journal_entry_id  BIGINT,
    created_at        TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE TABLE expense_items (
    expense_item_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    expense_report_id   BIGINT        NOT NULL REFERENCES expense_reports ON DELETE CASCADE,
    expense_date        DATE          NOT NULL,
    expense_category_id BIGINT        NOT NULL REFERENCES expense_categories,
    project_id          BIGINT        REFERENCES projects,
    description         VARCHAR(300)  NOT NULL,
    merchant            VARCHAR(120),
    amount              NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    currency_code       CHAR(3)       NOT NULL DEFAULT 'USD' REFERENCES currencies,
    exchange_rate       NUMERIC(18,8) NOT NULL DEFAULT 1,
    amount_base         NUMERIC(14,2) GENERATED ALWAYS AS (round(amount * exchange_rate, 2)) STORED,
    is_billable         BOOLEAN       NOT NULL DEFAULT TRUE,
    markup_pct          NUMERIC(5,2)  NOT NULL DEFAULT 0,
    receipt_url         TEXT,
    invoice_line_id     BIGINT        REFERENCES invoice_lines ON DELETE SET NULL,
    CHECK (NOT is_billable OR project_id IS NOT NULL)
);


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  12_procurement.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

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


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  13_general_ledger.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

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


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  14_documents.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   14. DOCUMENTS, COMMENTS & NOTIFICATIONS  (polymorphic: entity_type + entity_id)
   ===================================================================================== */

CREATE TABLE documents (
    document_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    entity_type     VARCHAR(40)  NOT NULL,   -- 'project','client','contract','employee','invoice' ...
    entity_id       BIGINT       NOT NULL,
    file_name       VARCHAR(255) NOT NULL,
    file_url        TEXT         NOT NULL,
    mime_type       VARCHAR(100),
    size_bytes      BIGINT,
    version_no      SMALLINT     NOT NULL DEFAULT 1,
    confidentiality VARCHAR(20)  NOT NULL DEFAULT 'internal'
                    CHECK (confidentiality IN ('public','internal','confidential','restricted')),
    uploaded_by     BIGINT       REFERENCES app_users,
    uploaded_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE comments (
    comment_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    entity_type VARCHAR(40) NOT NULL,
    entity_id   BIGINT      NOT NULL,
    author_id   BIGINT      NOT NULL REFERENCES app_users,
    body        TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE notifications (
    notification_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id         BIGINT       NOT NULL REFERENCES app_users ON DELETE CASCADE,
    title           VARCHAR(150) NOT NULL,
    message         TEXT,
    link            TEXT,
    is_read         BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  15_fixed_assets.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   15. FIXED ASSETS - PROPERTY, PLANT & EQUIPMENT (IAS 16), INTANGIBLES (IAS 38),
       INVESTMENT PROPERTY (IAS 40)
   -------------------------------------------------------------------------------------
   * asset_categories holds the accounting policy per class: measurement model, method,
     useful life, GL accounts and the ZIMRA wear-and-tear (capital allowance) rate used
     for the tax base / deferred tax (IAS 12).
   * Land & buildings use the REVALUATION model (surplus to OCI / revaluation reserve).
   * Investment property (floors of Maxhub House let to tenants) uses the FAIR VALUE
     model - no depreciation, fair-value changes go to profit or loss (investing).
   * Depreciation is posted monthly by sp_run_depreciation().
   ===================================================================================== */

CREATE TABLE asset_categories (
    asset_category_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code                VARCHAR(10)  NOT NULL UNIQUE,
    name                VARCHAR(80)  NOT NULL,
    asset_class         VARCHAR(30)  NOT NULL CHECK (asset_class IN
                        ('land','buildings','motor_vehicles','computer_equipment','furniture','office_equipment',
                         'leasehold_improvements','forensic_lab_equipment','software','investment_property','cwip')),
    standard            VARCHAR(10)  NOT NULL DEFAULT 'IAS 16' CHECK (standard IN ('IAS 16','IAS 38','IAS 40')),
    measurement_model   VARCHAR(12)  NOT NULL DEFAULT 'cost' CHECK (measurement_model IN ('cost','revaluation','fair_value')),
    depreciation_method VARCHAR(20)  NOT NULL DEFAULT 'straight_line'
                        CHECK (depreciation_method IN ('straight_line','reducing_balance','none')),
    useful_life_months  SMALLINT,                        -- NULL for land / investment property / CWIP
    reducing_balance_rate NUMERIC(6,3),                  -- annual % if reducing balance
    residual_value_pct  NUMERIC(5,2) NOT NULL DEFAULT 0,
    cost_account_id     BIGINT       NOT NULL REFERENCES chart_of_accounts,
    acc_dep_account_id  BIGINT       REFERENCES chart_of_accounts,
    dep_expense_account_id BIGINT    REFERENCES chart_of_accounts,
    reval_reserve_account_id BIGINT  REFERENCES chart_of_accounts,
    tax_wear_tear_rate_pct NUMERIC(6,2) NOT NULL DEFAULT 0,   -- ZIMRA capital allowance, % of cost per year
    capitalisation_threshold NUMERIC(12,2) NOT NULL DEFAULT 500,
    CHECK (depreciation_method = 'none' OR useful_life_months > 0 OR reducing_balance_rate > 0)
);

-- Land & buildings details (title deeds, stand numbers, valuations)
CREATE TABLE properties (
    property_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    property_code     VARCHAR(20)  NOT NULL UNIQUE,
    name              VARCHAR(150) NOT NULL,
    address           TEXT         NOT NULL,
    city              VARCHAR(80)  NOT NULL,
    country_code      CHAR(2)      NOT NULL REFERENCES countries,
    stand_number      VARCHAR(60),
    title_deed_number VARCHAR(60),
    land_size_sqm     NUMERIC(12,2),
    building_size_sqm NUMERIC(12,2),
    use_type          VARCHAR(20)  NOT NULL CHECK (use_type IN ('owner_occupied','investment','mixed','vacant_land')),
    lettable_area_sqm NUMERIC(12,2),                    -- area let to tenants (investment part)
    office_id         BIGINT       REFERENCES offices,
    council           VARCHAR(80),                       -- rates authority, e.g. City of Harare
    notes             TEXT
);

CREATE TABLE fixed_assets (
    asset_id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    asset_tag             VARCHAR(30)  NOT NULL UNIQUE,       -- barcode label, e.g. MXH-IT-00042
    name                  VARCHAR(150) NOT NULL,
    asset_category_id     BIGINT       NOT NULL REFERENCES asset_categories,
    property_id           BIGINT       REFERENCES properties,
    status                asset_status NOT NULL DEFAULT 'in_use',
    office_id             BIGINT       REFERENCES offices,
    department_id         BIGINT       REFERENCES departments,
    custodian_employee_id BIGINT       REFERENCES employees,
    vendor_id             BIGINT       REFERENCES vendors,
    vendor_bill_id        BIGINT       REFERENCES vendor_bills,
    serial_number         VARCHAR(80),
    registration_number   VARCHAR(30),                         -- vehicles
    make_model            VARCHAR(100),
    acquisition_date      DATE         NOT NULL,
    available_for_use_date DATE        NOT NULL,               -- depreciation starts here (IAS 16.55)
    cost                  NUMERIC(18,2) NOT NULL CHECK (cost >= 0),        -- USD
    residual_value        NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (residual_value >= 0),
    useful_life_months    SMALLINT,                            -- overrides category if set
    -- migration / opening position (assets bought before the ERP went live)
    opening_date          DATE,                                -- date of the opening balance
    opening_acc_depreciation NUMERIC(18,2) NOT NULL DEFAULT 0,
    -- revaluation / fair-value model: latest carrying amount basis
    revalued_amount       NUMERIC(18,2),                       -- last fair value (IAS 16 reval / IAS 40)
    last_revaluation_date DATE,
    tax_value_opening     NUMERIC(18,2),                       -- ZIMRA income tax value at opening_date
    insured_value         NUMERIC(18,2),
    insurance_policy_id   BIGINT,                              -- FK added below
    warranty_expiry       DATE,
    disposal_date         DATE,
    location_note         VARCHAR(150),
    notes                 TEXT,
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CHECK (available_for_use_date >= acquisition_date),
    CHECK (residual_value <= cost OR revalued_amount IS NOT NULL)
);

CREATE TABLE asset_depreciation (
    depreciation_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    asset_id         BIGINT        NOT NULL REFERENCES fixed_assets ON DELETE CASCADE,
    period_end       DATE          NOT NULL,
    amount           NUMERIC(18,2) NOT NULL CHECK (amount >= 0),
    carrying_after   NUMERIC(18,2) NOT NULL,
    journal_entry_id BIGINT        REFERENCES journal_entries,
    UNIQUE (asset_id, period_end)
);

CREATE TABLE asset_revaluations (
    revaluation_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    asset_id          BIGINT        NOT NULL REFERENCES fixed_assets,
    valuation_date    DATE          NOT NULL,
    valuation_type    VARCHAR(12)   NOT NULL DEFAULT 'revaluation' CHECK (valuation_type IN ('revaluation','fair_value','impairment')),
    valuer            VARCHAR(150)  NOT NULL,             -- independent valuer (IFRS 13 level 2/3)
    fair_value        NUMERIC(18,2) NOT NULL CHECK (fair_value >= 0),
    carrying_before   NUMERIC(18,2) NOT NULL,
    surplus_deficit   NUMERIC(18,2) NOT NULL,             -- +ve surplus
    to_oci            NUMERIC(18,2) NOT NULL DEFAULT 0,
    to_profit_or_loss NUMERIC(18,2) NOT NULL DEFAULT 0,
    deferred_tax      NUMERIC(18,2) NOT NULL DEFAULT 0,
    fair_value_level  SMALLINT      CHECK (fair_value_level BETWEEN 1 AND 3),
    journal_entry_id  BIGINT        REFERENCES journal_entries,
    UNIQUE (asset_id, valuation_date)
);

CREATE TABLE asset_disposals (
    disposal_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    asset_id         BIGINT        NOT NULL UNIQUE REFERENCES fixed_assets,
    disposal_date    DATE          NOT NULL,
    disposal_type    VARCHAR(12)   NOT NULL DEFAULT 'sale' CHECK (disposal_type IN ('sale','scrap','donation','theft','trade_in')),
    proceeds         NUMERIC(18,2) NOT NULL DEFAULT 0,
    carrying_amount  NUMERIC(18,2) NOT NULL,
    gain_loss        NUMERIC(18,2) NOT NULL,             -- +ve gain
    buyer            VARCHAR(150),
    bank_account_id  BIGINT        REFERENCES bank_accounts,
    approved_by      BIGINT        REFERENCES employees,
    journal_entry_id BIGINT        REFERENCES journal_entries
);

CREATE TABLE asset_maintenance (
    maintenance_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    asset_id         BIGINT        NOT NULL REFERENCES fixed_assets ON DELETE CASCADE,
    service_date     DATE          NOT NULL,
    maintenance_type VARCHAR(20)   NOT NULL DEFAULT 'service' CHECK (maintenance_type IN ('service','repair','inspection','upgrade','licence_renewal')),
    description      VARCHAR(300)  NOT NULL,
    vendor_id        BIGINT        REFERENCES vendors,
    cost             NUMERIC(14,2) NOT NULL DEFAULT 0,
    odometer_km      INTEGER,
    next_due_date    DATE
);

-- Who has which laptop / phone / vehicle
CREATE TABLE asset_assignments (
    assignment_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    asset_id       BIGINT       NOT NULL REFERENCES fixed_assets ON DELETE CASCADE,
    employee_id    BIGINT       NOT NULL REFERENCES employees,
    assigned_date  DATE         NOT NULL,
    returned_date  DATE,
    condition_out  VARCHAR(100),
    condition_in   VARCHAR(100),
    CHECK (returned_date IS NULL OR returned_date >= assigned_date)
);
CREATE UNIQUE INDEX ux_asset_one_open_assignment ON asset_assignments (asset_id) WHERE returned_date IS NULL;

CREATE TABLE insurance_policies (
    policy_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    policy_number  VARCHAR(40)   NOT NULL UNIQUE,
    insurer_vendor_id BIGINT     REFERENCES vendors,
    cover_type     VARCHAR(80)   NOT NULL,           -- property, motor fleet, professional indemnity, cyber, GIT
    sum_insured    NUMERIC(18,2) NOT NULL,
    annual_premium NUMERIC(14,2) NOT NULL,
    currency_code  CHAR(3)       NOT NULL DEFAULT 'USD' REFERENCES currencies,
    start_date     DATE          NOT NULL,
    end_date       DATE          NOT NULL,
    excess_amount  NUMERIC(14,2),
    notes          TEXT,
    CHECK (end_date > start_date)
);
ALTER TABLE fixed_assets ADD CONSTRAINT fk_asset_policy FOREIGN KEY (insurance_policy_id) REFERENCES insurance_policies;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  16_leases_borrowings.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   16. LEASES (IFRS 16) & BORROWINGS
   -------------------------------------------------------------------------------------
   Lessee leases (Johannesburg, Nairobi, London, Dubai offices, Harare cyber lab ...):
     at commencement  Dr Right-of-use asset / Cr Lease liability (PV of payments at the
                      incremental borrowing rate)
     every month      Dr Interest on lease liabilities (financing) / Cr Lease interest payable
                      Dr Lease interest payable + Lease liability / Cr Bank  (payment)
                      Dr Depreciation of ROU assets / Cr Accumulated depreciation - ROU
   Short-term (<= 12 months) and low-value leases use the IFRS 16.6 exemption (expensed).
   Lessor leases (tenants in Maxhub House) are operating leases -> rental income.
   ===================================================================================== */

CREATE TABLE leases (
    lease_id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lease_number          VARCHAR(30)   NOT NULL UNIQUE,
    role                  VARCHAR(8)    NOT NULL DEFAULT 'lessee' CHECK (role IN ('lessee','lessor')),
    description           VARCHAR(200)  NOT NULL,
    asset_class           VARCHAR(20)   NOT NULL DEFAULT 'property' CHECK (asset_class IN ('property','vehicles','equipment','parking')),
    office_id             BIGINT        REFERENCES offices,
    property_id           BIGINT        REFERENCES properties,        -- lessor leases: which building
    vendor_id             BIGINT        REFERENCES vendors,           -- landlord (lessee leases)
    tenant_name           VARCHAR(150),                               -- lessor leases
    currency_code         CHAR(3)       NOT NULL REFERENCES currencies,
    commencement_date     DATE          NOT NULL,
    end_date              DATE          NOT NULL,
    term_months           SMALLINT      NOT NULL CHECK (term_months > 0),
    payment_amount        NUMERIC(16,2) NOT NULL CHECK (payment_amount >= 0),  -- per period, lease currency
    payment_frequency     VARCHAR(10)   NOT NULL DEFAULT 'monthly' CHECK (payment_frequency IN ('monthly','quarterly','annual')),
    payment_timing        VARCHAR(8)    NOT NULL DEFAULT 'advance' CHECK (payment_timing IN ('advance','arrears')),
    annual_escalation_pct NUMERIC(5,2)  NOT NULL DEFAULT 0,
    discount_rate_pct     NUMERIC(6,3)  NOT NULL DEFAULT 0,          -- incremental borrowing rate (annual)
    initial_direct_costs  NUMERIC(16,2) NOT NULL DEFAULT 0,
    lease_incentives      NUMERIC(16,2) NOT NULL DEFAULT 0,
    deposit_paid          NUMERIC(16,2) NOT NULL DEFAULT 0,
    extension_option      TEXT,                                       -- "reasonably certain" assessment note
    exemption             VARCHAR(12)   CHECK (exemption IN ('short_term','low_value')),  -- IFRS 16.5-8
    rou_account_code      VARCHAR(20)   NOT NULL DEFAULT '1600',
    rou_acc_dep_account_code VARCHAR(20) NOT NULL DEFAULT '1601',
    initial_liability     NUMERIC(18,2),                              -- lease currency
    initial_rou_asset     NUMERIC(18,2),                              -- USD (non-monetary, historical rate)
    commencement_fx_rate  NUMERIC(18,8) NOT NULL DEFAULT 1,           -- lease currency -> USD
    liability_usd_balance NUMERIC(18,2) NOT NULL DEFAULT 0,           -- maintained by posting routines
    last_fx_rate          NUMERIC(18,8),
    status                VARCHAR(12)   NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','terminated','expired')),
    recognised_journal_id BIGINT        REFERENCES journal_entries,
    notes                 TEXT,
    CHECK (end_date > commencement_date)
);

-- Amortisation schedule (lease currency). Generated by fn_generate_lease_schedule().
CREATE TABLE lease_schedule (
    lease_id          BIGINT        NOT NULL REFERENCES leases ON DELETE CASCADE,
    period_no         SMALLINT      NOT NULL,
    period_date       DATE          NOT NULL,          -- first day of the month
    opening_liability NUMERIC(18,2) NOT NULL,
    payment           NUMERIC(18,2) NOT NULL,
    interest          NUMERIC(18,2) NOT NULL,
    principal         NUMERIC(18,2) NOT NULL,
    closing_liability NUMERIC(18,2) NOT NULL,
    rou_depreciation  NUMERIC(18,2) NOT NULL,          -- USD
    is_posted         BOOLEAN       NOT NULL DEFAULT FALSE,
    journal_entry_id  BIGINT        REFERENCES journal_entries,
    PRIMARY KEY (lease_id, period_no)
);

CREATE TABLE borrowings (
    loan_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    loan_number      VARCHAR(30)   NOT NULL UNIQUE,
    lender           VARCHAR(150)  NOT NULL,
    purpose          VARCHAR(200),
    currency_code    CHAR(3)       NOT NULL DEFAULT 'USD' REFERENCES currencies,
    principal        NUMERIC(18,2) NOT NULL CHECK (principal > 0),
    interest_rate_pct NUMERIC(6,3) NOT NULL,
    drawdown_date    DATE          NOT NULL,
    term_months      SMALLINT      NOT NULL,
    monthly_instalment NUMERIC(16,2),                  -- level instalment (annuity)
    security         VARCHAR(200),                     -- e.g. mortgage bond over Maxhub House
    bank_account_id  BIGINT        REFERENCES bank_accounts,
    status           VARCHAR(10)   NOT NULL DEFAULT 'active' CHECK (status IN ('active','repaid','default'))
);

CREATE TABLE loan_schedule (
    loan_id          BIGINT        NOT NULL REFERENCES borrowings ON DELETE CASCADE,
    period_no        SMALLINT      NOT NULL,
    due_date         DATE          NOT NULL,
    opening_balance  NUMERIC(18,2) NOT NULL,
    instalment       NUMERIC(18,2) NOT NULL,
    interest         NUMERIC(18,2) NOT NULL,
    principal        NUMERIC(18,2) NOT NULL,
    closing_balance  NUMERIC(18,2) NOT NULL,
    is_posted        BOOLEAN       NOT NULL DEFAULT FALSE,
    journal_entry_id BIGINT        REFERENCES journal_entries,
    PRIMARY KEY (loan_id, period_no)
);

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  17_tax_compliance.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

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

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  18_communications.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   18. COMMUNICATIONS - COMPANY E-MAIL DIRECTORY, INTERNAL MESSAGES, NOTICES
   -------------------------------------------------------------------------------------
   * Every employee has a company mailbox firstname.lastname@maxhub.co.zw
     (employees.email).  Shared mailboxes & distribution lists (finance@, hr@,
     all-staff@, harare@ ...) live in mailing_lists.
   * internal_messages / message_recipients = the in-system inbox.
   * announcements = company notices targeted at everyone, a department or an office.
   * email_outbox = e-mails the system wants to send (approvals, payslips, reminders);
     an SMTP worker (e.g. Microsoft 365) would pick them up.
   ===================================================================================== */

CREATE TABLE mailing_lists (
    list_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    address        VARCHAR(150) NOT NULL UNIQUE,         -- finance@maxhub.co.zw
    display_name   VARCHAR(100) NOT NULL,
    list_type      VARCHAR(12)  NOT NULL DEFAULT 'distribution' CHECK (list_type IN ('distribution','shared','alias')),
    department_id  BIGINT       REFERENCES departments,  -- auto-membership by department
    office_id      BIGINT       REFERENCES offices,      -- auto-membership by office
    is_all_staff   BOOLEAN      NOT NULL DEFAULT FALSE,
    owner_employee_id BIGINT    REFERENCES employees,
    description    VARCHAR(200)
);

CREATE TABLE mailing_list_members (      -- extra (manual) members on top of the automatic ones
    list_id     BIGINT NOT NULL REFERENCES mailing_lists ON DELETE CASCADE,
    employee_id BIGINT NOT NULL REFERENCES employees ON DELETE CASCADE,
    PRIMARY KEY (list_id, employee_id)
);

CREATE TABLE internal_messages (
    message_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    thread_id      BIGINT       REFERENCES internal_messages,   -- first message of the conversation
    sender_id      BIGINT       NOT NULL REFERENCES employees,
    subject        VARCHAR(200) NOT NULL,
    body           TEXT         NOT NULL,
    priority       VARCHAR(8)   NOT NULL DEFAULT 'normal' CHECK (priority IN ('low','normal','high')),
    sent_to_list_id BIGINT      REFERENCES mailing_lists,
    related_entity VARCHAR(40),                                -- e.g. 'invoice', 'project'
    related_id     BIGINT,
    sent_at        TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE message_recipients (
    message_id   BIGINT      NOT NULL REFERENCES internal_messages ON DELETE CASCADE,
    recipient_id BIGINT      NOT NULL REFERENCES employees,
    recipient_type VARCHAR(3) NOT NULL DEFAULT 'to' CHECK (recipient_type IN ('to','cc','bcc')),
    read_at      TIMESTAMPTZ,
    is_starred   BOOLEAN     NOT NULL DEFAULT FALSE,
    is_archived  BOOLEAN     NOT NULL DEFAULT FALSE,
    PRIMARY KEY (message_id, recipient_id)
);

CREATE TABLE announcements (
    announcement_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title          VARCHAR(200) NOT NULL,
    body           TEXT         NOT NULL,
    category       VARCHAR(20)  NOT NULL DEFAULT 'general'
                   CHECK (category IN ('general','hr','it','finance','compliance','event','health_safety')),
    audience       VARCHAR(12)  NOT NULL DEFAULT 'all' CHECK (audience IN ('all','department','office')),
    department_id  BIGINT       REFERENCES departments,
    office_id      BIGINT       REFERENCES offices,
    author_id      BIGINT       NOT NULL REFERENCES employees,
    is_pinned      BOOLEAN      NOT NULL DEFAULT FALSE,
    publish_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    expires_at     TIMESTAMPTZ,
    CHECK (audience <> 'department' OR department_id IS NOT NULL),
    CHECK (audience <> 'office' OR office_id IS NOT NULL)
);

CREATE TABLE announcement_reads (
    announcement_id BIGINT      NOT NULL REFERENCES announcements ON DELETE CASCADE,
    employee_id     BIGINT      NOT NULL REFERENCES employees ON DELETE CASCADE,
    read_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (announcement_id, employee_id)
);

CREATE TABLE email_outbox (
    email_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    to_address    VARCHAR(300) NOT NULL,
    cc_address    VARCHAR(300),
    subject       VARCHAR(200) NOT NULL,
    body          TEXT         NOT NULL,
    template_code VARCHAR(40),                 -- timesheet_reminder, payslip, invoice, password_reset
    related_entity VARCHAR(40),
    related_id    BIGINT,
    status        VARCHAR(10)  NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','sent','failed','cancelled')),
    attempts      SMALLINT     NOT NULL DEFAULT 0,
    last_error    TEXT,
    queued_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    sent_at       TIMESTAMPTZ
);

-- Company events calendar (board meetings, town halls, training, ZIMRA deadlines)
CREATE TABLE calendar_events (
    event_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title         VARCHAR(200) NOT NULL,
    event_type    VARCHAR(20)  NOT NULL DEFAULT 'meeting' CHECK (event_type IN ('meeting','training','deadline','social','board','holiday')),
    starts_at     TIMESTAMPTZ  NOT NULL,
    ends_at       TIMESTAMPTZ,
    location      VARCHAR(150),
    office_id     BIGINT       REFERENCES offices,
    organiser_id  BIGINT       REFERENCES employees,
    description   TEXT
);

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  19_ifrs_reporting.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   19. IFRS REPORTING STRUCTURE - IFRS 18 MPMs, IFRS 9 ECL MATRIX, CASH-FLOW OVERRIDES
   -------------------------------------------------------------------------------------
   IFRS 18 (Presentation and Disclosure in Financial Statements) key requirements built in:
     * income & expenses classified into OPERATING, INVESTING, FINANCING, INCOME TAXES
       and DISCONTINUED categories                         (ifrs_line_items.ifrs18_category)
     * two new required subtotals: OPERATING PROFIT and PROFIT BEFORE FINANCING AND
       INCOME TAXES                                        (fn_ifrs_profit_or_loss)
     * Management-defined Performance Measures (MPMs) disclosed in one note with a
       reconciliation to the closest IFRS subtotal and the tax effect of each item
                                                           (mpm_definitions / fn_ifrs_mpm_note)
     * aggregation / disaggregation - expenses presented by NATURE here
     * cash-flow statement: interest paid = financing, interest & dividends received =
       investing (for a company whose main business is not investing/financing)
   ===================================================================================== */

CREATE TABLE mpm_definitions (
    mpm_code          VARCHAR(20)  PRIMARY KEY,
    name              VARCHAR(120) NOT NULL,
    description       TEXT         NOT NULL,            -- how it is calculated
    why_useful        TEXT         NOT NULL,            -- why management thinks it is useful (IFRS 18.123)
    base_subtotal     VARCHAR(40)  NOT NULL,            -- IFRS subtotal it is reconciled to
    sort_order        SMALLINT     NOT NULL DEFAULT 1,
    is_active         BOOLEAN      NOT NULL DEFAULT TRUE
);

-- Which accounts are adjusted out of the IFRS subtotal to arrive at the MPM
CREATE TABLE mpm_adjustments (
    mpm_code      VARCHAR(20)  NOT NULL REFERENCES mpm_definitions ON DELETE CASCADE,
    account_id    BIGINT       NOT NULL REFERENCES chart_of_accounts,
    caption       VARCHAR(150) NOT NULL,                -- reconciling item description
    tax_rate_pct  NUMERIC(6,3) NOT NULL DEFAULT 24.72,  -- for the tax-effect disclosure
    PRIMARY KEY (mpm_code, account_id)
);

-- IFRS 9 simplified approach: lifetime expected credit loss provision matrix
CREATE TABLE ecl_provision_matrix (
    bucket        VARCHAR(20)  PRIMARY KEY,             -- matches v_ar_aging buckets
    min_days      INTEGER      NOT NULL,
    max_days      INTEGER,
    loss_rate_pct NUMERIC(6,3) NOT NULL CHECK (loss_rate_pct BETWEEN 0 AND 100),
    sort_order    SMALLINT     NOT NULL
);

-- Journal sources whose non-cash lines must go to a specific cash-flow line
-- (e.g. an asset disposal: proceeds belong to "Proceeds from disposal of PPE")
CREATE TABLE cash_flow_source_overrides (
    source_type VARCHAR(20) PRIMARY KEY,
    cf_code     VARCHAR(20) NOT NULL REFERENCES cash_flow_lines
);

-- Period close checklist (month-end / year-end)
CREATE TABLE period_close_tasks (
    task_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fiscal_period_id BIGINT       NOT NULL REFERENCES fiscal_periods ON DELETE CASCADE,
    task_name        VARCHAR(150) NOT NULL,
    owner_role       VARCHAR(30),
    due_date         DATE,
    completed_by     BIGINT       REFERENCES employees,
    completed_at     TIMESTAMPTZ,
    UNIQUE (fiscal_period_id, task_name)
);

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  20_logic_core.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   15. BUSINESS LOGIC - FUNCTIONS, TRIGGERS & PROCEDURES
   ===================================================================================== */

/* ---------- 15.1 Generic helpers ---------- */

-- Keep updated_at current
CREATE OR REPLACE FUNCTION fn_set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END $$;

-- Generic audit trail. TG_ARGV[0] = name of primary-key column
CREATE OR REPLACE FUNCTION fn_audit() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_user BIGINT := NULLIF(current_setting('erp.current_user_id', true), '')::BIGINT;
    v_row  JSONB  := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
BEGIN
    -- bulk data loads (seed/migration) can switch auditing off for their session only
    IF current_setting('erp.skip_audit', true) = 'on' THEN RETURN NULL; END IF;
    INSERT INTO audit_log (table_name, record_pk, action, old_data, new_data, changed_by)
    VALUES (TG_TABLE_NAME,
            v_row ->> TG_ARGV[0],
            TG_OP,
            CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) END,
            CASE WHEN TG_OP IN ('UPDATE','INSERT') THEN to_jsonb(NEW) END,
            v_user);
    RETURN NULL;
END $$;

-- Next formatted document number, e.g. INV-2026-00001
CREATE OR REPLACE FUNCTION fn_next_doc_number(p_doc_type TEXT, p_date DATE DEFAULT CURRENT_DATE)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
    r document_sequences%ROWTYPE;
BEGIN
    UPDATE document_sequences
       SET next_value = next_value + 1
     WHERE doc_type = p_doc_type
    RETURNING * INTO r;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No document sequence configured for "%"', p_doc_type;
    END IF;
    RETURN r.prefix
        || CASE WHEN r.include_year THEN to_char(p_date, 'YYYY') || '-' ELSE '' END
        || lpad((r.next_value - 1)::TEXT, r.padding, '0');
END $$;

-- Trigger wrapper: TG_ARGV[0] = doc_type, TG_ARGV[1] = column to fill
CREATE OR REPLACE FUNCTION fn_assign_doc_number() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE j JSONB := to_jsonb(NEW); v_date DATE;
BEGIN
    IF j ->> TG_ARGV[1] IS NULL THEN
        -- number the document in the year of its own date (invoice_date, payment_date, entry_date ...)
        v_date := COALESCE((j->>'invoice_date')::DATE, (j->>'payment_date')::DATE, (j->>'entry_date')::DATE,
                           (j->>'order_date')::DATE, CURRENT_DATE);
        NEW := jsonb_populate_record(NEW, jsonb_build_object(TG_ARGV[1], fn_next_doc_number(TG_ARGV[0], v_date)));
    END IF;
    RETURN NEW;
END $$;

-- Look up a GL account id by code (raises if missing)
CREATE OR REPLACE FUNCTION fn_account_id(p_code TEXT) RETURNS BIGINT LANGUAGE plpgsql STABLE AS $$
DECLARE v_id BIGINT;
BEGIN
    SELECT account_id INTO v_id FROM chart_of_accounts WHERE account_code = p_code AND is_active;
    IF v_id IS NULL THEN
        RAISE EXCEPTION 'GL account % not found or inactive', p_code;
    END IF;
    RETURN v_id;
END $$;

-- Working days (Mon-Fri, excluding public holidays) between two dates inclusive
CREATE OR REPLACE FUNCTION fn_working_days(p_from DATE, p_to DATE, p_country CHAR(2) DEFAULT 'ZW')
RETURNS INTEGER LANGUAGE sql STABLE AS $$
    SELECT count(*)::INT
      FROM generate_series(p_from, p_to, INTERVAL '1 day') AS g(d)
     WHERE extract(isodow FROM g.d) < 6
       AND NOT EXISTS (SELECT 1 FROM public_holidays h
                        WHERE h.country_code = p_country AND h.holiday_date = g.d::DATE);
$$;


/* ---------- 15.2 Time entry rules ---------- */

CREATE OR REPLACE FUNCTION fn_time_entry_validate() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_ts        timesheets%ROWTYPE;
    v_member    project_members%ROWTYPE;
    v_emp       employees%ROWTYPE;
    v_proj      projects%ROWTYPE;
    v_card_rate NUMERIC;
    v_day_total NUMERIC;
BEGIN
    -- Allow the billing process to stamp invoice_line_id on locked entries
    IF TG_OP = 'UPDATE'
       AND (NEW.hours, NEW.work_date, NEW.project_id, NEW.task_id, NEW.is_billable, NEW.bill_rate,
            NEW.cost_rate, NEW.employee_id, NEW.timesheet_id)
           IS NOT DISTINCT FROM
           (OLD.hours, OLD.work_date, OLD.project_id, OLD.task_id, OLD.is_billable, OLD.bill_rate,
            OLD.cost_rate, OLD.employee_id, OLD.timesheet_id) THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' AND OLD.invoice_line_id IS NOT NULL THEN
        RAISE EXCEPTION 'Time entry % has already been invoiced and cannot be changed', OLD.time_entry_id;
    END IF;

    SELECT * INTO v_ts FROM timesheets WHERE timesheet_id = NEW.timesheet_id;
    IF v_ts.status NOT IN ('draft','rejected') THEN
        RAISE EXCEPTION 'Timesheet % is % - entries are locked', v_ts.timesheet_id, v_ts.status;
    END IF;
    IF NEW.employee_id IS NULL THEN
        NEW.employee_id := v_ts.employee_id;
    ELSIF NEW.employee_id <> v_ts.employee_id THEN
        RAISE EXCEPTION 'Time entry employee does not match timesheet owner';
    END IF;
    IF NEW.work_date NOT BETWEEN v_ts.week_start_date AND v_ts.week_start_date + 6 THEN
        RAISE EXCEPTION 'Work date % is outside timesheet week starting %', NEW.work_date, v_ts.week_start_date;
    END IF;

    -- Max 24h per person per day
    SELECT COALESCE(SUM(hours), 0) INTO v_day_total
      FROM time_entries
     WHERE employee_id = NEW.employee_id AND work_date = NEW.work_date
       AND time_entry_id <> NEW.time_entry_id;
    IF v_day_total + NEW.hours > 24 THEN
        RAISE EXCEPTION 'Total hours for % on % would exceed 24', NEW.employee_id, NEW.work_date;
    END IF;

    SELECT * INTO v_emp FROM employees WHERE employee_id = NEW.employee_id;

    IF NEW.project_id IS NULL THEN
        -- internal time is never billable
        NEW.is_billable := FALSE;
        NEW.bill_rate   := 0;
        NEW.cost_rate   := COALESCE(NEW.cost_rate, v_emp.cost_rate_hourly, 0);
        IF NEW.activity_code = 'CLIENT' THEN NEW.activity_code := 'ADMIN'; END IF;
        RETURN NEW;
    END IF;

    SELECT * INTO v_proj FROM projects WHERE project_id = NEW.project_id;
    IF v_proj.status NOT IN ('active','planned') THEN
        RAISE EXCEPTION 'Project % is % - time cannot be booked', v_proj.project_code, v_proj.status;
    END IF;
    IF v_proj.is_internal THEN
        NEW.is_billable := FALSE;
    END IF;

    -- Must be staffed on the project on that date
    SELECT * INTO v_member
      FROM project_members
     WHERE project_id = NEW.project_id AND employee_id = NEW.employee_id
       AND NEW.work_date BETWEEN start_date AND COALESCE(end_date, 'infinity'::DATE)
     ORDER BY start_date DESC
     LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Employee % is not assigned to project % on %',
              v_emp.employee_number, v_proj.project_code, NEW.work_date;
    END IF;

    -- Task must belong to the project
    IF NEW.task_id IS NOT NULL AND NOT EXISTS
       (SELECT 1 FROM tasks WHERE task_id = NEW.task_id AND project_id = NEW.project_id) THEN
        RAISE EXCEPTION 'Task % does not belong to project %', NEW.task_id, v_proj.project_code;
    END IF;

    -- Rate defaulting: project member -> contract rate card -> employee default -> grade default
    IF NEW.bill_rate IS NULL THEN
        SELECT rcl.hourly_rate INTO v_card_rate
          FROM contracts c
          JOIN rate_card_lines rcl ON rcl.rate_card_id = c.rate_card_id
         WHERE c.contract_id = v_proj.contract_id
           AND rcl.job_grade_id = v_emp.job_grade_id;

        NEW.bill_rate := COALESCE(v_member.bill_rate, v_card_rate, v_emp.default_bill_rate,
                                  (SELECT default_bill_rate FROM job_grades WHERE job_grade_id = v_emp.job_grade_id), 0);
    END IF;
    IF NEW.cost_rate IS NULL THEN
        NEW.cost_rate := COALESCE(v_member.cost_rate, v_emp.cost_rate_hourly,
                                  (SELECT default_cost_rate FROM job_grades WHERE job_grade_id = v_emp.job_grade_id), 0);
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_time_entries_validate
    BEFORE INSERT OR UPDATE ON time_entries
    FOR EACH ROW EXECUTE FUNCTION fn_time_entry_validate();

CREATE OR REPLACE FUNCTION fn_time_entry_lock_delete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.invoice_line_id IS NOT NULL THEN
        RAISE EXCEPTION 'Invoiced time entry % cannot be deleted', OLD.time_entry_id;
    END IF;
    IF EXISTS (SELECT 1 FROM timesheets WHERE timesheet_id = OLD.timesheet_id AND status IN ('submitted','approved')) THEN
        RAISE EXCEPTION 'Entries on a submitted/approved timesheet cannot be deleted';
    END IF;
    RETURN OLD;
END $$;

CREATE TRIGGER trg_time_entries_lock_delete
    BEFORE DELETE ON time_entries
    FOR EACH ROW EXECUTE FUNCTION fn_time_entry_lock_delete();

-- Keep timesheets.total_hours in sync
CREATE OR REPLACE FUNCTION fn_timesheet_total() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_ids BIGINT[];
BEGIN
    v_ids := CASE TG_OP
               WHEN 'INSERT' THEN ARRAY[NEW.timesheet_id]
               WHEN 'DELETE' THEN ARRAY[OLD.timesheet_id]
               ELSE ARRAY[NEW.timesheet_id, OLD.timesheet_id] END;
    UPDATE timesheets t
       SET total_hours = COALESCE((SELECT SUM(hours) FROM time_entries e WHERE e.timesheet_id = t.timesheet_id), 0)
     WHERE t.timesheet_id = ANY (v_ids);
    RETURN NULL;
END $$;

CREATE TRIGGER trg_time_entries_total
    AFTER INSERT OR UPDATE OF hours, timesheet_id OR DELETE ON time_entries
    FOR EACH ROW EXECUTE FUNCTION fn_timesheet_total();

-- Timesheet workflow
CREATE OR REPLACE PROCEDURE sp_submit_timesheet(p_timesheet_id BIGINT)
LANGUAGE plpgsql AS $$
DECLARE v_status approval_status; v_hours NUMERIC;
BEGIN
    SELECT status, total_hours INTO v_status, v_hours FROM timesheets WHERE timesheet_id = p_timesheet_id FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Timesheet % not found', p_timesheet_id; END IF;
    IF v_status NOT IN ('draft','rejected') THEN
        RAISE EXCEPTION 'Only draft/rejected timesheets can be submitted (current: %)', v_status;
    END IF;
    IF v_hours <= 0 THEN RAISE EXCEPTION 'Cannot submit an empty timesheet'; END IF;
    UPDATE timesheets SET status = 'submitted', submitted_at = now(), rejection_reason = NULL
     WHERE timesheet_id = p_timesheet_id;
END $$;

CREATE OR REPLACE PROCEDURE sp_approve_timesheet(p_timesheet_id BIGINT, p_approver_id BIGINT)
LANGUAGE plpgsql AS $$
DECLARE v_ts timesheets%ROWTYPE;
BEGIN
    SELECT * INTO v_ts FROM timesheets WHERE timesheet_id = p_timesheet_id FOR UPDATE;
    IF v_ts.status <> 'submitted' THEN
        RAISE EXCEPTION 'Timesheet % is not submitted (current: %)', p_timesheet_id, v_ts.status;
    END IF;
    IF v_ts.employee_id = p_approver_id THEN
        RAISE EXCEPTION 'Employees cannot approve their own timesheets';
    END IF;
    UPDATE timesheets SET status = 'approved', approved_by = p_approver_id, approved_at = now()
     WHERE timesheet_id = p_timesheet_id;
END $$;

CREATE OR REPLACE PROCEDURE sp_reject_timesheet(p_timesheet_id BIGINT, p_approver_id BIGINT, p_reason TEXT)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE timesheets SET status = 'rejected', approved_by = p_approver_id, approved_at = NULL,
                          rejection_reason = p_reason
     WHERE timesheet_id = p_timesheet_id AND status = 'submitted';
    IF NOT FOUND THEN RAISE EXCEPTION 'Timesheet % is not in submitted state', p_timesheet_id; END IF;
END $$;


/* ---------- 15.3 Leave management ---------- */

CREATE OR REPLACE FUNCTION fn_leave_balance_sync() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_year SMALLINT := extract(year FROM NEW.start_date);
    v_remaining NUMERIC;
BEGIN
    IF NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved' THEN
        INSERT INTO leave_balances (employee_id, leave_type_id, leave_year, entitled_days)
        SELECT NEW.employee_id, NEW.leave_type_id, v_year, lt.annual_entitlement_days
          FROM leave_types lt WHERE lt.leave_type_id = NEW.leave_type_id
        ON CONFLICT DO NOTHING;

        SELECT remaining_days INTO v_remaining FROM leave_balances
         WHERE employee_id = NEW.employee_id AND leave_type_id = NEW.leave_type_id AND leave_year = v_year
         FOR UPDATE;
        IF v_remaining < NEW.days_requested THEN
            RAISE EXCEPTION 'Insufficient leave balance: % day(s) remaining, % requested', v_remaining, NEW.days_requested;
        END IF;

        UPDATE leave_balances SET taken_days = taken_days + NEW.days_requested
         WHERE employee_id = NEW.employee_id AND leave_type_id = NEW.leave_type_id AND leave_year = v_year;
        NEW.decided_at := now();

    ELSIF OLD.status = 'approved' AND NEW.status <> 'approved' THEN
        UPDATE leave_balances SET taken_days = taken_days - OLD.days_requested
         WHERE employee_id = OLD.employee_id AND leave_type_id = OLD.leave_type_id
           AND leave_year = extract(year FROM OLD.start_date);
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_leave_balance_sync
    BEFORE UPDATE OF status ON leave_requests
    FOR EACH ROW EXECUTE FUNCTION fn_leave_balance_sync();


/* ---------- 15.4 Invoicing ---------- */

-- Tax + default revenue account on each invoice line; lines locked once invoice issued
CREATE OR REPLACE FUNCTION fn_invoice_line_before() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status invoice_status; v_rate NUMERIC;
BEGIN
    SELECT status INTO v_status FROM invoices
     WHERE invoice_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.invoice_id ELSE NEW.invoice_id END;
    IF v_status <> 'draft' THEN
        RAISE EXCEPTION 'Invoice is % - lines can only be changed while draft', v_status;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;

    SELECT rate_percent INTO v_rate FROM tax_rates WHERE tax_rate_id = NEW.tax_rate_id;
    NEW.tax_amount := round(round(NEW.quantity * NEW.unit_price * (1 - NEW.discount_pct / 100), 2)
                            * COALESCE(v_rate, 0) / 100, 2);

    IF NEW.revenue_account_id IS NULL THEN
        NEW.revenue_account_id := fn_account_id(CASE NEW.line_type
                                    WHEN 'time'          THEN '4000'
                                    WHEN 'fixed_fee'     THEN '4010'
                                    WHEN 'milestone'     THEN '4010'
                                    WHEN 'retainer'      THEN '4020'
                                    WHEN 'expense'       THEN '4100'
                                    WHEN 'subcontractor' THEN '4100'
                                    ELSE '4900' END);
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_invoice_lines_before
    BEFORE INSERT OR UPDATE OR DELETE ON invoice_lines
    FOR EACH ROW EXECUTE FUNCTION fn_invoice_line_before();

-- Roll line totals up to invoice header
CREATE OR REPLACE FUNCTION fn_invoice_recalc() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT := CASE WHEN TG_OP = 'DELETE' THEN OLD.invoice_id ELSE NEW.invoice_id END;
BEGIN
    UPDATE invoices i
       SET subtotal     = s.net,
           tax_amount   = s.tax,
           total_amount = s.net + s.tax
      FROM (SELECT COALESCE(SUM(line_net),0) AS net, COALESCE(SUM(tax_amount),0) AS tax
              FROM invoice_lines WHERE invoice_id = v_id) s
     WHERE i.invoice_id = v_id;
    RETURN NULL;
END $$;

CREATE TRIGGER trg_invoice_lines_recalc
    AFTER INSERT OR UPDATE OR DELETE ON invoice_lines
    FOR EACH ROW EXECUTE FUNCTION fn_invoice_recalc();

-- Build a draft invoice from approved, unbilled billable time (+ optional rebillable expenses)
CREATE OR REPLACE FUNCTION fn_generate_invoice_from_time(
    p_project_id       BIGINT,
    p_period_from      DATE,
    p_period_to        DATE,
    p_invoice_date     DATE    DEFAULT CURRENT_DATE,
    p_tax_code         TEXT    DEFAULT 'ZW-VAT',
    p_include_expenses BOOLEAN DEFAULT TRUE,
    p_created_by       BIGINT  DEFAULT NULL
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    v_proj       projects%ROWTYPE;
    v_terms      SMALLINT;
    v_tax_id     BIGINT;
    v_invoice_id BIGINT;
    v_line_id    BIGINT;
    v_line_no    SMALLINT := 0;
    r            RECORD;
BEGIN
    SELECT * INTO v_proj FROM projects WHERE project_id = p_project_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Project % not found', p_project_id; END IF;
    IF v_proj.is_internal THEN RAISE EXCEPTION 'Internal projects cannot be invoiced'; END IF;
    IF v_proj.billing_type IN ('fixed_fee','milestone') THEN
        RAISE EXCEPTION 'Project % is % - use fn_invoice_milestone instead', v_proj.project_code, v_proj.billing_type;
    END IF;

    SELECT COALESCE(ct.payment_terms_days, c.payment_terms_days) INTO v_terms
      FROM clients c LEFT JOIN contracts ct ON ct.contract_id = v_proj.contract_id
     WHERE c.client_id = v_proj.client_id;

    SELECT tax_rate_id INTO v_tax_id FROM tax_rates WHERE code = p_tax_code AND is_active;

    INSERT INTO invoices (client_id, project_id, contract_id, invoice_date, due_date, currency_code, created_by, notes)
    VALUES (v_proj.client_id, v_proj.project_id, v_proj.contract_id, p_invoice_date, p_invoice_date + v_terms,
            v_proj.currency_code, p_created_by,
            format('Professional services for %s, period %s to %s', v_proj.name,
                   to_char(p_period_from, 'DD Mon YYYY'), to_char(p_period_to, 'DD Mon YYYY')))
    RETURNING invoice_id INTO v_invoice_id;

    -- Time: one line per consultant per rate
    FOR r IN
        SELECT te.employee_id,
               e.first_name || ' ' || e.last_name AS emp_name,
               COALESCE(jg.name, 'Consultant')    AS grade_name,
               te.bill_rate,
               SUM(te.hours)                      AS hours
          FROM time_entries te
          JOIN timesheets ts ON ts.timesheet_id = te.timesheet_id
          JOIN employees  e  ON e.employee_id   = te.employee_id
          LEFT JOIN job_grades jg ON jg.job_grade_id = e.job_grade_id
         WHERE te.project_id = p_project_id
           AND te.is_billable
           AND te.invoice_line_id IS NULL
           AND ts.status = 'approved'
           AND te.work_date BETWEEN p_period_from AND p_period_to
         GROUP BY te.employee_id, e.first_name, e.last_name, jg.name, jg.level, te.bill_rate
         ORDER BY jg.level DESC NULLS LAST, e.last_name
    LOOP
        v_line_no := v_line_no + 1;
        INSERT INTO invoice_lines (invoice_id, line_no, line_type, description, quantity, unit, unit_price,
                                   tax_rate_id, project_id)
        VALUES (v_invoice_id, v_line_no, 'time',
                format('%s (%s) - professional services', r.emp_name, r.grade_name),
                r.hours, 'hour', r.bill_rate, v_tax_id, p_project_id)
        RETURNING invoice_line_id INTO v_line_id;

        UPDATE time_entries te
           SET invoice_line_id = v_line_id
          FROM timesheets ts
         WHERE ts.timesheet_id = te.timesheet_id
           AND ts.status = 'approved'
           AND te.project_id = p_project_id
           AND te.employee_id = r.employee_id
           AND te.bill_rate = r.bill_rate
           AND te.is_billable
           AND te.invoice_line_id IS NULL
           AND te.work_date BETWEEN p_period_from AND p_period_to;
    END LOOP;

    -- Rebillable expenses from approved expense reports
    IF p_include_expenses THEN
        FOR r IN
            SELECT ei.expense_item_id, ei.description, ec.name AS category,
                   round(ei.amount_base * (1 + ei.markup_pct / 100), 2) AS amount
              FROM expense_items ei
              JOIN expense_reports er    ON er.expense_report_id = ei.expense_report_id
              JOIN expense_categories ec ON ec.expense_category_id = ei.expense_category_id
             WHERE ei.project_id = p_project_id
               AND ei.is_billable
               AND ei.invoice_line_id IS NULL
               AND er.status = 'approved'
               AND ei.expense_date BETWEEN p_period_from AND p_period_to
             ORDER BY ei.expense_date
        LOOP
            v_line_no := v_line_no + 1;
            INSERT INTO invoice_lines (invoice_id, line_no, line_type, description, quantity, unit, unit_price,
                                       tax_rate_id, project_id)
            VALUES (v_invoice_id, v_line_no, 'expense', format('Reimbursable expense - %s: %s', r.category, r.description),
                    1, 'each', r.amount, v_tax_id, p_project_id)
            RETURNING invoice_line_id INTO v_line_id;

            UPDATE expense_items SET invoice_line_id = v_line_id WHERE expense_item_id = r.expense_item_id;
        END LOOP;
    END IF;

    IF v_line_no = 0 THEN
        RAISE EXCEPTION 'Nothing to invoice for project % between % and %',
              v_proj.project_code, p_period_from, p_period_to;
    END IF;

    RETURN v_invoice_id;
END $$;

-- Draft invoice for a fixed-fee milestone
CREATE OR REPLACE FUNCTION fn_invoice_milestone(
    p_milestone_id BIGINT, p_invoice_date DATE DEFAULT CURRENT_DATE,
    p_tax_code TEXT DEFAULT 'ZW-VAT', p_created_by BIGINT DEFAULT NULL
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    v_ms   contract_milestones%ROWTYPE;
    v_ct   contracts%ROWTYPE;
    v_proj_id BIGINT;
    v_inv  BIGINT;
BEGIN
    SELECT * INTO v_ms FROM contract_milestones WHERE milestone_id = p_milestone_id FOR UPDATE;
    IF v_ms.status <> 'achieved' THEN
        RAISE EXCEPTION 'Milestone % must be achieved before invoicing (current: %)', p_milestone_id, v_ms.status;
    END IF;
    SELECT * INTO v_ct FROM contracts WHERE contract_id = v_ms.contract_id;
    SELECT project_id INTO v_proj_id FROM projects WHERE contract_id = v_ct.contract_id ORDER BY project_id LIMIT 1;

    INSERT INTO invoices (client_id, project_id, contract_id, invoice_date, due_date, currency_code, created_by, notes)
    VALUES (v_ct.client_id, v_proj_id, v_ct.contract_id, p_invoice_date, p_invoice_date + v_ct.payment_terms_days,
            v_ct.currency_code, p_created_by, format('%s - milestone %s', v_ct.title, v_ms.seq))
    RETURNING invoice_id INTO v_inv;

    INSERT INTO invoice_lines (invoice_id, line_no, line_type, description, quantity, unit, unit_price,
                               tax_rate_id, project_id, milestone_id)
    VALUES (v_inv, 1, 'milestone', format('Milestone %s: %s', v_ms.seq, v_ms.name), 1, 'fixed', v_ms.amount,
            (SELECT tax_rate_id FROM tax_rates WHERE code = p_tax_code), v_proj_id, v_ms.milestone_id);

    UPDATE contract_milestones SET invoice_id = v_inv WHERE milestone_id = p_milestone_id;
    RETURN v_inv;
END $$;


/* ---------- 15.5 General ledger integrity ---------- */

-- Derive fiscal period, block posting into closed periods
CREATE OR REPLACE FUNCTION fn_journal_entry_before() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_period fiscal_periods%ROWTYPE;
BEGIN
    SELECT * INTO v_period FROM fiscal_periods
     WHERE NEW.entry_date BETWEEN start_date AND end_date
     ORDER BY period_no LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No fiscal period defined for %', NEW.entry_date;
    END IF;
    IF v_period.is_closed AND (TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status) THEN
        RAISE EXCEPTION 'Fiscal period for % is closed', NEW.entry_date;
    END IF;
    NEW.fiscal_period_id := v_period.fiscal_period_id;

    IF TG_OP = 'UPDATE' AND OLD.status = 'posted' AND NEW.status = 'draft' THEN
        RAISE EXCEPTION 'Posted journals cannot be returned to draft - create a reversal instead';
    END IF;
    IF NEW.status = 'posted' AND NEW.posted_at IS NULL THEN
        NEW.posted_at := now();
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_journal_entries_before
    BEFORE INSERT OR UPDATE ON journal_entries
    FOR EACH ROW EXECUTE FUNCTION fn_journal_entry_before();

-- Lines of posted journals are immutable; only postable accounts allowed
CREATE OR REPLACE FUNCTION fn_journal_line_before() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status TEXT;
BEGIN
    SELECT status INTO v_status FROM journal_entries
     WHERE journal_entry_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.journal_entry_id ELSE NEW.journal_entry_id END;
    IF v_status IN ('posted','reversed') THEN
        RAISE EXCEPTION 'Journal is % - lines cannot be modified', v_status;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    IF NOT EXISTS (SELECT 1 FROM chart_of_accounts WHERE account_id = NEW.account_id AND is_postable AND is_active) THEN
        RAISE EXCEPTION 'Account % is not postable', NEW.account_id;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_journal_lines_before
    BEFORE INSERT OR UPDATE OR DELETE ON journal_lines
    FOR EACH ROW EXECUTE FUNCTION fn_journal_line_before();

-- Debits must equal credits for every posted journal (checked at commit)
CREATE OR REPLACE FUNCTION fn_journal_balanced() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT; v_status TEXT; v_dr NUMERIC; v_cr NUMERIC;
BEGIN
    IF TG_OP = 'DELETE' THEN v_id := OLD.journal_entry_id; ELSE v_id := NEW.journal_entry_id; END IF;
    SELECT status INTO v_status FROM journal_entries WHERE journal_entry_id = v_id;
    IF v_status = 'posted' THEN
        SELECT COALESCE(SUM(debit),0), COALESCE(SUM(credit),0) INTO v_dr, v_cr
          FROM journal_lines WHERE journal_entry_id = v_id;
        IF v_dr <> v_cr OR v_dr = 0 THEN
            RAISE EXCEPTION 'Journal % is unbalanced (DR % / CR %)', v_id, v_dr, v_cr;
        END IF;
    END IF;
    RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER trg_journal_entries_balanced
    AFTER INSERT OR UPDATE ON journal_entries
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_journal_balanced();

CREATE CONSTRAINT TRIGGER trg_journal_lines_balanced
    AFTER INSERT OR UPDATE OR DELETE ON journal_lines
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION fn_journal_balanced();

-- Reverse a posted journal
CREATE OR REPLACE FUNCTION fn_reverse_journal(p_journal_entry_id BIGINT, p_date DATE DEFAULT CURRENT_DATE)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_new BIGINT; v_je journal_entries%ROWTYPE;
BEGIN
    SELECT * INTO v_je FROM journal_entries WHERE journal_entry_id = p_journal_entry_id FOR UPDATE;
    IF v_je.status <> 'posted' THEN RAISE EXCEPTION 'Only posted journals can be reversed'; END IF;

    INSERT INTO journal_entries (entry_date, description, source_type, source_id, reversal_of_id)
    VALUES (p_date, 'REVERSAL: ' || v_je.description, 'adjustment', v_je.source_id, v_je.journal_entry_id)
    RETURNING journal_entry_id INTO v_new;

    INSERT INTO journal_lines (journal_entry_id, line_no, account_id, debit, credit, description,
                               client_id, vendor_id, project_id, department_id, employee_id)
    SELECT v_new, line_no, account_id, credit, debit, description, client_id, vendor_id, project_id, department_id, employee_id
      FROM journal_lines WHERE journal_entry_id = p_journal_entry_id;

    UPDATE journal_entries SET status = 'posted'   WHERE journal_entry_id = v_new;
    UPDATE journal_entries SET status = 'reversed' WHERE journal_entry_id = p_journal_entry_id;
    RETURN v_new;
END $$;


/* ---------- 15.6 Posting documents to the GL ---------- */

-- Issue an invoice: DR Accounts Receivable / CR Revenue (+ CR VAT output)
CREATE OR REPLACE FUNCTION fn_issue_invoice(p_invoice_id BIGINT, p_user_id BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    v_inv  invoices%ROWTYPE;
    v_je   BIGINT;
    v_line SMALLINT := 1;
    v_office BIGINT;
    r      RECORD;
BEGIN
    SELECT * INTO v_inv FROM invoices WHERE invoice_id = p_invoice_id FOR UPDATE;
    SELECT office_id INTO v_office FROM projects WHERE project_id = v_inv.project_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Invoice % not found', p_invoice_id; END IF;
    IF v_inv.status <> 'draft' THEN RAISE EXCEPTION 'Invoice % is already %', v_inv.invoice_number, v_inv.status; END IF;
    IF v_inv.total_amount <= 0 THEN RAISE EXCEPTION 'Invoice % has no value', v_inv.invoice_number; END IF;

    INSERT INTO journal_entries (entry_date, description, source_type, source_id, created_by)
    VALUES (v_inv.invoice_date, 'Invoice ' || v_inv.invoice_number, 'invoice', v_inv.invoice_id, p_user_id)
    RETURNING journal_entry_id INTO v_je;

    INSERT INTO journal_lines (journal_entry_id, line_no, account_id, debit, description, client_id, project_id, office_id)
    VALUES (v_je, v_line, fn_account_id('1100'), round(v_inv.total_amount * v_inv.exchange_rate, 2),
            'Accounts receivable', v_inv.client_id, v_inv.project_id, v_office);

    FOR r IN SELECT revenue_account_id, project_id, SUM(line_net) AS net
               FROM invoice_lines WHERE invoice_id = p_invoice_id
              GROUP BY revenue_account_id, project_id HAVING SUM(line_net) <> 0
    LOOP
        v_line := v_line + 1;
        INSERT INTO journal_lines (journal_entry_id, line_no, account_id, credit, description, client_id, project_id, office_id)
        VALUES (v_je, v_line, r.revenue_account_id, round(r.net * v_inv.exchange_rate, 2), 'Fee revenue',
                v_inv.client_id, r.project_id, v_office);
    END LOOP;

    -- output tax goes to the liability account of each tax rate (ZIMRA VAT, SARS VAT, HMRC VAT ...)
    FOR r IN SELECT COALESCE(tr.gl_account_code, '2200') AS acc, tr.name, SUM(il.tax_amount) AS tax
               FROM invoice_lines il LEFT JOIN tax_rates tr ON tr.tax_rate_id = il.tax_rate_id
              WHERE il.invoice_id = p_invoice_id
              GROUP BY 1, 2 HAVING SUM(il.tax_amount) <> 0
    LOOP
        v_line := v_line + 1;
        INSERT INTO journal_lines (journal_entry_id, line_no, account_id, credit, description, client_id, office_id)
        VALUES (v_je, v_line, fn_account_id(r.acc), round(r.tax * v_inv.exchange_rate, 2),
                'Output tax - ' || COALESCE(r.name, 'VAT'), v_inv.client_id, v_office);
    END LOOP;
    -- FX rounding: converting each line separately can leave a cent difference - put it on the revenue line
    UPDATE journal_lines jl SET credit = jl.credit + d.diff
      FROM (SELECT SUM(debit) - SUM(credit) AS diff FROM journal_lines WHERE journal_entry_id = v_je) d
     WHERE jl.journal_entry_id = v_je AND jl.line_no = 2 AND d.diff <> 0;

    UPDATE journal_entries SET status = 'posted' WHERE journal_entry_id = v_je;

    UPDATE invoices SET status = 'issued', issued_at = now(), journal_entry_id = v_je
     WHERE invoice_id = p_invoice_id;

    UPDATE contract_milestones SET status = 'invoiced'
     WHERE milestone_id IN (SELECT milestone_id FROM invoice_lines WHERE invoice_id = p_invoice_id AND milestone_id IS NOT NULL);

    RETURN v_je;
END $$;

-- Payment allocation rules
CREATE OR REPLACE FUNCTION fn_payment_allocation_before() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_pay payments%ROWTYPE; v_inv invoices%ROWTYPE; v_allocated NUMERIC;
BEGIN
    SELECT * INTO v_pay FROM payments WHERE payment_id = NEW.payment_id;
    SELECT * INTO v_inv FROM invoices WHERE invoice_id = NEW.invoice_id FOR UPDATE;

    IF v_pay.client_id <> v_inv.client_id THEN
        RAISE EXCEPTION 'Payment and invoice belong to different clients';
    END IF;
    IF v_pay.currency_code <> v_inv.currency_code THEN
        RAISE EXCEPTION 'Payment currency % differs from invoice currency %', v_pay.currency_code, v_inv.currency_code;
    END IF;
    IF v_inv.status NOT IN ('issued','partially_paid','overdue') THEN
        RAISE EXCEPTION 'Invoice % is % and cannot receive payments', v_inv.invoice_number, v_inv.status;
    END IF;

    SELECT COALESCE(SUM(amount),0) INTO v_allocated FROM payment_allocations
     WHERE payment_id = NEW.payment_id AND invoice_id <> NEW.invoice_id;
    IF v_allocated + NEW.amount > v_pay.amount + v_pay.withholding_tax THEN
        RAISE EXCEPTION 'Allocation exceeds payment amount';
    END IF;

    IF NEW.amount > v_inv.balance_due + COALESCE(CASE WHEN TG_OP = 'UPDATE' THEN OLD.amount END, 0) THEN
        RAISE EXCEPTION 'Allocation % exceeds invoice balance %', NEW.amount, v_inv.balance_due;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_payment_allocations_before
    BEFORE INSERT OR UPDATE ON payment_allocations
    FOR EACH ROW EXECUTE FUNCTION fn_payment_allocation_before();

-- Update invoice paid amount and status
CREATE OR REPLACE FUNCTION fn_payment_allocation_after() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT := CASE WHEN TG_OP = 'DELETE' THEN OLD.invoice_id ELSE NEW.invoice_id END;
BEGIN
    UPDATE invoices i
       SET amount_paid = p.paid,
           status = CASE
                      WHEN p.paid >= i.total_amount THEN 'paid'::invoice_status
                      WHEN p.paid > 0              THEN 'partially_paid'::invoice_status
                      WHEN i.due_date < CURRENT_DATE THEN 'overdue'::invoice_status
                      ELSE 'issued'::invoice_status
                    END
      FROM (SELECT COALESCE(SUM(amount),0) AS paid FROM payment_allocations WHERE invoice_id = v_id) p
     WHERE i.invoice_id = v_id;
    RETURN NULL;
END $$;

CREATE TRIGGER trg_payment_allocations_after
    AFTER INSERT OR UPDATE OR DELETE ON payment_allocations
    FOR EACH ROW EXECUTE FUNCTION fn_payment_allocation_after();

-- Record a client receipt, post DR Bank / CR AR and auto-allocate oldest invoices first (FIFO)
CREATE OR REPLACE FUNCTION fn_record_client_payment(
    p_client_id       BIGINT,
    p_amount          NUMERIC,
    p_bank_account_id BIGINT,
    p_payment_date    DATE           DEFAULT CURRENT_DATE,
    p_method          payment_method DEFAULT 'bank_transfer',
    p_reference       TEXT           DEFAULT NULL,
    p_auto_allocate   BOOLEAN        DEFAULT TRUE
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    v_bank      bank_accounts%ROWTYPE;
    v_pay_id    BIGINT;
    v_je        BIGINT;
    v_remaining NUMERIC := p_amount;
    v_alloc     NUMERIC;
    r           RECORD;
BEGIN
    SELECT * INTO v_bank FROM bank_accounts WHERE bank_account_id = p_bank_account_id AND is_active;
    IF NOT FOUND THEN RAISE EXCEPTION 'Bank account % not found/inactive', p_bank_account_id; END IF;

    INSERT INTO payments (client_id, payment_date, amount, currency_code, method, reference, bank_account_id)
    VALUES (p_client_id, p_payment_date, p_amount, v_bank.currency_code, p_method, p_reference, p_bank_account_id)
    RETURNING payment_id INTO v_pay_id;

    INSERT INTO journal_entries (entry_date, description, source_type, source_id)
    VALUES (p_payment_date, 'Client receipt ' || COALESCE(p_reference, ''), 'payment', v_pay_id)
    RETURNING journal_entry_id INTO v_je;

    INSERT INTO journal_lines (journal_entry_id, line_no, account_id, debit, description, client_id)
    VALUES (v_je, 1, v_bank.gl_account_id, p_amount, 'Receipt to ' || v_bank.name, p_client_id);
    INSERT INTO journal_lines (journal_entry_id, line_no, account_id, credit, description, client_id)
    VALUES (v_je, 2, fn_account_id('1100'), p_amount, 'Settle accounts receivable', p_client_id);
    UPDATE journal_entries SET status = 'posted' WHERE journal_entry_id = v_je;
    UPDATE payments SET journal_entry_id = v_je WHERE payment_id = v_pay_id;

    IF p_auto_allocate THEN
        FOR r IN SELECT invoice_id, balance_due FROM invoices
                  WHERE client_id = p_client_id AND currency_code = v_bank.currency_code
                    AND status IN ('issued','partially_paid','overdue') AND balance_due > 0
                  ORDER BY due_date, invoice_id
        LOOP
            EXIT WHEN v_remaining <= 0;
            v_alloc := LEAST(v_remaining, r.balance_due);
            INSERT INTO payment_allocations (payment_id, invoice_id, amount) VALUES (v_pay_id, r.invoice_id, v_alloc);
            v_remaining := v_remaining - v_alloc;
        END LOOP;
    END IF;
    RETURN v_pay_id;
END $$;

-- Nightly job: flag overdue invoices
CREATE OR REPLACE FUNCTION fn_mark_overdue_invoices() RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE v_count INTEGER;
BEGIN
    UPDATE invoices SET status = 'overdue'
     WHERE status IN ('issued') AND due_date < CURRENT_DATE AND balance_due > 0;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END $$;


/* ---------- 15.7 Expenses ---------- */

CREATE OR REPLACE FUNCTION fn_expense_item_before() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status approval_status; v_max NUMERIC;
BEGIN
    SELECT status INTO v_status FROM expense_reports
     WHERE expense_report_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.expense_report_id ELSE NEW.expense_report_id END;
    IF TG_OP = 'UPDATE'
       AND (NEW.amount, NEW.expense_date, NEW.project_id, NEW.is_billable, NEW.expense_category_id)
           IS NOT DISTINCT FROM (OLD.amount, OLD.expense_date, OLD.project_id, OLD.is_billable, OLD.expense_category_id) THEN
        RETURN NEW;   -- e.g. billing stamping invoice_line_id
    END IF;
    IF v_status NOT IN ('draft','rejected') THEN
        RAISE EXCEPTION 'Expense report is % - items are locked', v_status;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    SELECT max_amount_per_item INTO v_max FROM expense_categories WHERE expense_category_id = NEW.expense_category_id;
    IF v_max IS NOT NULL AND NEW.amount * NEW.exchange_rate > v_max THEN
        RAISE EXCEPTION 'Expense % exceeds category limit %', NEW.amount, v_max;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_expense_items_before
    BEFORE INSERT OR UPDATE OR DELETE ON expense_items
    FOR EACH ROW EXECUTE FUNCTION fn_expense_item_before();

CREATE OR REPLACE FUNCTION fn_expense_report_total() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT := CASE WHEN TG_OP = 'DELETE' THEN OLD.expense_report_id ELSE NEW.expense_report_id END;
BEGIN
    UPDATE expense_reports
       SET total_amount = COALESCE((SELECT SUM(amount_base) FROM expense_items WHERE expense_report_id = v_id), 0)
     WHERE expense_report_id = v_id;
    RETURN NULL;
END $$;

CREATE TRIGGER trg_expense_items_total
    AFTER INSERT OR UPDATE OR DELETE ON expense_items
    FOR EACH ROW EXECUTE FUNCTION fn_expense_report_total();

CREATE OR REPLACE PROCEDURE sp_submit_expense_report(p_report_id BIGINT)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE expense_reports SET status = 'submitted', submitted_at = now()
     WHERE expense_report_id = p_report_id AND status IN ('draft','rejected') AND total_amount > 0;
    IF NOT FOUND THEN RAISE EXCEPTION 'Expense report % cannot be submitted', p_report_id; END IF;
END $$;

-- Approve and post: DR expense accounts / CR Employee reimbursements payable
CREATE OR REPLACE PROCEDURE sp_approve_expense_report(p_report_id BIGINT, p_approver_id BIGINT, p_date DATE DEFAULT CURRENT_DATE)
LANGUAGE plpgsql AS $$
DECLARE v_er expense_reports%ROWTYPE; v_je BIGINT; v_line SMALLINT := 0; r RECORD;
BEGIN
    SELECT * INTO v_er FROM expense_reports WHERE expense_report_id = p_report_id FOR UPDATE;
    IF v_er.status <> 'submitted' THEN RAISE EXCEPTION 'Expense report % is not submitted', p_report_id; END IF;
    IF v_er.employee_id = p_approver_id THEN RAISE EXCEPTION 'Cannot approve own expense report'; END IF;

    INSERT INTO journal_entries (entry_date, description, source_type, source_id)
    VALUES (p_date, 'Expense claim ' || v_er.report_number, 'expense', p_report_id)
    RETURNING journal_entry_id INTO v_je;

    FOR r IN SELECT ec.gl_account_id, ei.project_id, SUM(ei.amount_base) AS amt
               FROM expense_items ei JOIN expense_categories ec USING (expense_category_id)
              WHERE ei.expense_report_id = p_report_id
              GROUP BY ec.gl_account_id, ei.project_id
    LOOP
        v_line := v_line + 1;
        INSERT INTO journal_lines (journal_entry_id, line_no, account_id, debit, project_id, employee_id, description)
        VALUES (v_je, v_line, r.gl_account_id, r.amt, r.project_id, v_er.employee_id, v_er.title);
    END LOOP;

    INSERT INTO journal_lines (journal_entry_id, line_no, account_id, credit, employee_id, description)
    VALUES (v_je, v_line + 1, fn_account_id('2300'), v_er.total_amount, v_er.employee_id, 'Reimbursement due to employee');

    UPDATE journal_entries SET status = 'posted' WHERE journal_entry_id = v_je;
    UPDATE expense_reports SET status = 'approved', approved_by = p_approver_id,
           approved_at = LEAST(now(), p_date + TIME '17:00'), journal_entry_id = v_je
     WHERE expense_report_id = p_report_id;
END $$;


/* ---------- 15.8 Procurement ---------- */

CREATE OR REPLACE FUNCTION fn_po_total() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT := CASE WHEN TG_OP = 'DELETE' THEN OLD.po_id ELSE NEW.po_id END;
BEGIN
    UPDATE purchase_orders
       SET total_amount = COALESCE((SELECT SUM(line_total) FROM purchase_order_lines WHERE po_id = v_id), 0)
     WHERE po_id = v_id;
    RETURN NULL;
END $$;

CREATE TRIGGER trg_po_lines_total
    AFTER INSERT OR UPDATE OR DELETE ON purchase_order_lines
    FOR EACH ROW EXECUTE FUNCTION fn_po_total();

CREATE OR REPLACE FUNCTION fn_vendor_payment_after() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT := CASE WHEN TG_OP = 'DELETE' THEN OLD.vendor_bill_id ELSE NEW.vendor_bill_id END;
BEGIN
    UPDATE vendor_bills b
       SET amount_paid = p.paid,
           status = CASE WHEN p.paid >= b.total_amount THEN 'paid'
                         WHEN p.paid > 0 THEN 'partially_paid'
                         ELSE 'approved' END
      FROM (SELECT COALESCE(SUM(amount),0) AS paid FROM vendor_payments WHERE vendor_bill_id = v_id) p
     WHERE b.vendor_bill_id = v_id;
    IF (SELECT amount_paid > total_amount FROM vendor_bills WHERE vendor_bill_id = v_id) THEN
        RAISE EXCEPTION 'Payments exceed vendor bill total';
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER trg_vendor_payments_after
    AFTER INSERT OR UPDATE OR DELETE ON vendor_payments
    FOR EACH ROW EXECUTE FUNCTION fn_vendor_payment_after();


/* ---------- 15.9 Attach generic triggers (updated_at, doc numbers, audit) ---------- */

DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT c.table_name
          FROM information_schema.columns c
          JOIN information_schema.tables t
            ON t.table_schema = c.table_schema AND t.table_name = c.table_name AND t.table_type = 'BASE TABLE'
         WHERE c.table_schema = 'erp' AND c.column_name = 'updated_at'
    LOOP
        EXECUTE format('CREATE TRIGGER trg_%s_updated_at BEFORE UPDATE ON erp.%I
                        FOR EACH ROW EXECUTE FUNCTION erp.fn_set_updated_at()', r.table_name, r.table_name);
    END LOOP;
END $$;

CREATE TRIGGER trg_invoices_number        BEFORE INSERT ON invoices        FOR EACH ROW EXECUTE FUNCTION fn_assign_doc_number('invoice',        'invoice_number');
CREATE TRIGGER trg_payments_number        BEFORE INSERT ON payments        FOR EACH ROW EXECUTE FUNCTION fn_assign_doc_number('payment',        'payment_number');
CREATE TRIGGER trg_journal_number         BEFORE INSERT ON journal_entries FOR EACH ROW EXECUTE FUNCTION fn_assign_doc_number('journal',        'entry_number');
CREATE TRIGGER trg_expense_reports_number BEFORE INSERT ON expense_reports FOR EACH ROW EXECUTE FUNCTION fn_assign_doc_number('expense_report', 'report_number');
CREATE TRIGGER trg_purchase_orders_number BEFORE INSERT ON purchase_orders FOR EACH ROW EXECUTE FUNCTION fn_assign_doc_number('purchase_order', 'po_number');

CREATE TRIGGER trg_audit_employees    AFTER INSERT OR UPDATE OR DELETE ON employees        FOR EACH ROW EXECUTE FUNCTION fn_audit('employee_id');
CREATE TRIGGER trg_audit_compensation AFTER INSERT OR UPDATE OR DELETE ON employee_compensation FOR EACH ROW EXECUTE FUNCTION fn_audit('compensation_id');
CREATE TRIGGER trg_audit_clients      AFTER INSERT OR UPDATE OR DELETE ON clients          FOR EACH ROW EXECUTE FUNCTION fn_audit('client_id');
CREATE TRIGGER trg_audit_contracts    AFTER INSERT OR UPDATE OR DELETE ON contracts        FOR EACH ROW EXECUTE FUNCTION fn_audit('contract_id');
CREATE TRIGGER trg_audit_projects     AFTER INSERT OR UPDATE OR DELETE ON projects         FOR EACH ROW EXECUTE FUNCTION fn_audit('project_id');
CREATE TRIGGER trg_audit_invoices     AFTER INSERT OR UPDATE OR DELETE ON invoices         FOR EACH ROW EXECUTE FUNCTION fn_audit('invoice_id');
CREATE TRIGGER trg_audit_payments     AFTER INSERT OR UPDATE OR DELETE ON payments         FOR EACH ROW EXECUTE FUNCTION fn_audit('payment_id');
CREATE TRIGGER trg_audit_journals     AFTER INSERT OR UPDATE OR DELETE ON journal_entries  FOR EACH ROW EXECUTE FUNCTION fn_audit('journal_entry_id');
CREATE TRIGGER trg_audit_timesheets   AFTER UPDATE OF status ON timesheets                 FOR EACH ROW EXECUTE FUNCTION fn_audit('timesheet_id');
CREATE TRIGGER trg_audit_user_roles   AFTER INSERT OR DELETE ON user_roles                 FOR EACH ROW EXECUTE FUNCTION fn_audit('user_id');
CREATE TRIGGER trg_audit_app_users    AFTER INSERT OR DELETE OR UPDATE OF is_active, locked_until, must_change_password ON app_users
                                                                                            FOR EACH ROW EXECUTE FUNCTION fn_audit('user_id');
CREATE TRIGGER trg_audit_role_perms   AFTER INSERT OR DELETE ON role_permissions           FOR EACH ROW EXECUTE FUNCTION fn_audit('role_id');
CREATE TRIGGER trg_audit_vendor_bills AFTER INSERT OR UPDATE OR DELETE ON vendor_bills     FOR EACH ROW EXECUTE FUNCTION fn_audit('vendor_bill_id');
CREATE TRIGGER trg_audit_vendor_pays  AFTER INSERT OR UPDATE OR DELETE ON vendor_payments  FOR EACH ROW EXECUTE FUNCTION fn_audit('vendor_payment_id');
CREATE TRIGGER trg_audit_payroll_runs AFTER INSERT OR UPDATE OR DELETE ON payroll_runs     FOR EACH ROW EXECUTE FUNCTION fn_audit('payroll_run_id');
CREATE TRIGGER trg_audit_fixed_assets AFTER INSERT OR UPDATE OR DELETE ON fixed_assets     FOR EACH ROW EXECUTE FUNCTION fn_audit('asset_id');
CREATE TRIGGER trg_audit_leases       AFTER INSERT OR UPDATE OR DELETE ON leases           FOR EACH ROW EXECUTE FUNCTION fn_audit('lease_id');
CREATE TRIGGER trg_audit_tax_returns  AFTER INSERT OR UPDATE OR DELETE ON tax_returns      FOR EACH ROW EXECUTE FUNCTION fn_audit('tax_return_id');
CREATE TRIGGER trg_audit_bank_accounts AFTER INSERT OR UPDATE OR DELETE ON bank_accounts   FOR EACH ROW EXECUTE FUNCTION fn_audit('bank_account_id');

/* ---------- 15.10 ZIMRA fiscalisation (FDMS) ----------
   When an invoice is issued it receives a fiscal invoice number and a verification code
   (in production these come back from the ZIMRA FDMS API / fiscal device). */
CREATE OR REPLACE FUNCTION fn_invoice_fiscalise() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status <> 'draft' AND OLD.status = 'draft' AND NEW.fiscal_invoice_number IS NULL THEN
        NEW.fiscal_invoice_number := 'FDMS-' || COALESCE((SELECT fiscal_device_serial FROM firm_settings), 'VD') || '-'
                                     || lpad(NEW.invoice_id::TEXT, 7, '0');
        NEW.fiscal_verification_code := upper(substr(md5(NEW.invoice_number || NEW.total_amount::TEXT || NEW.invoice_date::TEXT), 1, 16));
        NEW.fiscalised_at := COALESCE(NEW.issued_at, now());
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_invoices_fiscalise BEFORE UPDATE OF status ON invoices
    FOR EACH ROW EXECUTE FUNCTION fn_invoice_fiscalise();

-- Pin search_path on every routine so they work regardless of the caller's search_path
-- (search_path pinning for all functions is done at the end of module 24)



-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  21_logic_auth.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   21. AUTHENTICATION & AUTHORISATION LOGIC
   -------------------------------------------------------------------------------------
   fn_login(login, password, ip, agent)  -> ('ok' | 'invalid' | 'locked' | 'inactive', user_id, message)
   fn_create_session / fn_validate_session / fn_logout
   fn_set_password / fn_change_password / fn_admin_reset_password / fn_unlock_user
   fn_sync_user_roles  (department + grade -> roles)      fn_has_permission
   Passwords are hashed with bcrypt: crypt(password, gen_salt('bf', cost)).
   ===================================================================================== */

-- Returns NULL when the password is acceptable, otherwise the reason it is not
CREATE OR REPLACE FUNCTION fn_password_policy_error(p_password TEXT) RETURNS TEXT
LANGUAGE plpgsql STABLE AS $$
DECLARE pol security_policy%ROWTYPE;
BEGIN
    SELECT * INTO pol FROM security_policy WHERE policy_id = 1;
    IF p_password IS NULL OR length(p_password) < pol.min_password_length THEN
        RETURN format('Password must be at least %s characters long', pol.min_password_length);
    END IF;
    IF pol.require_upper  AND p_password !~ '[A-Z]'        THEN RETURN 'Password needs at least one capital letter'; END IF;
    IF pol.require_lower  AND p_password !~ '[a-z]'        THEN RETURN 'Password needs at least one small letter'; END IF;
    IF pol.require_digit  AND p_password !~ '[0-9]'        THEN RETURN 'Password needs at least one number'; END IF;
    IF pol.require_symbol AND p_password !~ '[^A-Za-z0-9]' THEN RETURN 'Password needs at least one symbol, e.g. ! @ # $'; END IF;
    RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION fn_hash_password(p_password TEXT) RETURNS TEXT
LANGUAGE sql VOLATILE AS $$
    SELECT crypt(p_password, gen_salt('bf', (SELECT bcrypt_cost FROM security_policy WHERE policy_id = 1)));
$$;

-- Set a new password (policy + history checks). p_must_change = TRUE for temporary passwords.
CREATE OR REPLACE FUNCTION fn_set_password(p_user_id BIGINT, p_new_password TEXT, p_must_change BOOLEAN DEFAULT FALSE)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_err TEXT; v_keep SMALLINT; v_hash TEXT;
BEGIN
    v_err := fn_password_policy_error(p_new_password);
    IF v_err IS NOT NULL THEN RAISE EXCEPTION '%', v_err; END IF;

    SELECT password_history_count INTO v_keep FROM security_policy WHERE policy_id = 1;
    IF EXISTS (SELECT 1 FROM (SELECT password_hash FROM password_history WHERE user_id = p_user_id
                              ORDER BY changed_at DESC LIMIT v_keep) h
                WHERE crypt(p_new_password, h.password_hash) = h.password_hash) THEN
        RAISE EXCEPTION 'You cannot re-use one of your last % passwords', v_keep;
    END IF;

    v_hash := fn_hash_password(p_new_password);
    UPDATE app_users SET password_hash = v_hash, password_changed_at = now(),
                         must_change_password = p_must_change, failed_logins = 0, locked_until = NULL
     WHERE user_id = p_user_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'User % not found', p_user_id; END IF;
    INSERT INTO password_history (user_id, password_hash, changed_at) VALUES (p_user_id, v_hash, clock_timestamp());
END $$;

-- Self-service change: the old password must be correct
CREATE OR REPLACE FUNCTION fn_change_password(p_user_id BIGINT, p_old_password TEXT, p_new_password TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_hash TEXT;
BEGIN
    SELECT password_hash INTO v_hash FROM app_users WHERE user_id = p_user_id AND is_active;
    IF v_hash IS NULL OR crypt(p_old_password, v_hash) <> v_hash THEN
        RAISE EXCEPTION 'Your current password is not correct';
    END IF;
    IF p_old_password = p_new_password THEN
        RAISE EXCEPTION 'The new password must be different from the current one';
    END IF;
    PERFORM fn_set_password(p_user_id, p_new_password, FALSE);
END $$;

-- Log-in. Never raises for bad credentials (so the attempt is always logged); returns a status.
CREATE OR REPLACE FUNCTION fn_login(p_login TEXT, p_password TEXT, p_ip TEXT DEFAULT NULL, p_agent TEXT DEFAULT NULL)
RETURNS TABLE (status TEXT, user_id BIGINT, message TEXT)
LANGUAGE plpgsql AS $$
DECLARE
    u   app_users%ROWTYPE;
    pol security_policy%ROWTYPE;
    v_ok BOOLEAN;
BEGIN
    SELECT * INTO pol FROM security_policy WHERE policy_id = 1;
    SELECT * INTO u FROM app_users a
     WHERE lower(a.username) = lower(trim(p_login)) OR lower(a.email) = lower(trim(p_login))
     LIMIT 1;

    IF NOT FOUND THEN
        PERFORM crypt(COALESCE(p_password, ''), gen_salt('bf', pol.bcrypt_cost));   -- same delay as a real check
        INSERT INTO login_attempts (username_tried, success, failure_reason, ip_address, user_agent)
        VALUES (left(COALESCE(p_login, ''), 150), FALSE, 'unknown_user', p_ip, left(p_agent, 300));
        RETURN QUERY SELECT 'invalid'::TEXT, NULL::BIGINT, 'Incorrect username or password.'::TEXT;
        RETURN;
    END IF;

    IF NOT u.is_active THEN
        INSERT INTO login_attempts (username_tried, user_id, success, failure_reason, ip_address, user_agent)
        VALUES (p_login, u.user_id, FALSE, 'inactive', p_ip, left(p_agent, 300));
        RETURN QUERY SELECT 'inactive'::TEXT, u.user_id, 'This account has been disabled. Please contact IT Support (itsupport@maxhub.co.zw).'::TEXT;
        RETURN;
    END IF;

    IF u.locked_until IS NOT NULL AND u.locked_until > now() THEN
        INSERT INTO login_attempts (username_tried, user_id, success, failure_reason, ip_address, user_agent)
        VALUES (p_login, u.user_id, FALSE, 'locked', p_ip, left(p_agent, 300));
        RETURN QUERY SELECT 'locked'::TEXT, u.user_id,
            format('Account locked after too many wrong passwords. Try again after %s or ask IT Support to unlock it.',
                   to_char(u.locked_until AT TIME ZONE 'Africa/Harare', 'HH24:MI'));
        RETURN;
    END IF;

    v_ok := crypt(COALESCE(p_password, ''), u.password_hash) = u.password_hash;

    IF v_ok THEN
        UPDATE app_users a SET failed_logins = 0, locked_until = NULL, last_login_at = now(), last_login_ip = p_ip
         WHERE a.user_id = u.user_id;
        INSERT INTO login_attempts (username_tried, user_id, success, ip_address, user_agent)
        VALUES (p_login, u.user_id, TRUE, p_ip, left(p_agent, 300));
        RETURN QUERY SELECT 'ok'::TEXT, u.user_id,
            CASE WHEN u.must_change_password THEN 'Please choose a new password.'
                 WHEN u.password_changed_at < now() - make_interval(days => pol.password_max_age_days)
                      THEN 'Your password is older than ' || pol.password_max_age_days || ' days - please change it.'
                 ELSE 'Welcome back!' END;
        RETURN;
    END IF;

    UPDATE app_users a
       SET failed_logins = a.failed_logins + 1,
           locked_until  = CASE WHEN a.failed_logins + 1 >= pol.max_failed_logins
                                THEN now() + make_interval(mins => pol.lockout_minutes) END
     WHERE a.user_id = u.user_id
    RETURNING * INTO u;
    INSERT INTO login_attempts (username_tried, user_id, success, failure_reason, ip_address, user_agent)
    VALUES (p_login, u.user_id, FALSE, 'wrong_password', p_ip, left(p_agent, 300));

    IF u.locked_until IS NOT NULL THEN
        RETURN QUERY SELECT 'locked'::TEXT, u.user_id,
            format('Too many wrong passwords - the account is locked for %s minutes.', pol.lockout_minutes);
    ELSE
        RETURN QUERY SELECT 'invalid'::TEXT, NULL::BIGINT,
            format('Incorrect username or password. %s attempt(s) left before the account is locked.',
                   pol.max_failed_logins - u.failed_logins);
    END IF;
END $$;

-- Sessions: the app keeps the random token, the database only keeps its SHA-256 hash
CREATE OR REPLACE FUNCTION fn_create_session(p_user_id BIGINT, p_ip TEXT DEFAULT NULL) RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE v_token TEXT := encode(gen_random_bytes(32), 'hex');
BEGIN
    INSERT INTO user_sessions (user_id, token_hash, expires_at, ip_address)
    VALUES (p_user_id, encode(digest(v_token, 'sha256'), 'hex'),
            now() + make_interval(hours => (SELECT session_hours FROM security_policy WHERE policy_id = 1)), p_ip);
    RETURN v_token;
END $$;

CREATE OR REPLACE FUNCTION fn_validate_session(p_token TEXT) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE v_user BIGINT;
BEGIN
    UPDATE user_sessions s SET last_seen_at = now()
      FROM app_users u
     WHERE s.token_hash = encode(digest(p_token, 'sha256'), 'hex')
       AND s.revoked_at IS NULL AND s.expires_at > now()
       AND u.user_id = s.user_id AND u.is_active
    RETURNING s.user_id INTO v_user;
    RETURN v_user;                      -- NULL => session expired / revoked / user disabled
END $$;

CREATE OR REPLACE FUNCTION fn_logout(p_token TEXT) RETURNS VOID
LANGUAGE sql AS $$
    UPDATE user_sessions SET revoked_at = now(), revoke_reason = 'logout'
     WHERE token_hash = encode(digest(p_token, 'sha256'), 'hex') AND revoked_at IS NULL;
$$;

-- Administrator actions ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_admin_reset_password(p_admin_user_id BIGINT, p_target_user_id BIGINT, p_temp_password TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_email TEXT;
BEGIN
    IF NOT fn_has_permission(p_admin_user_id, 'user.manage') THEN
        RAISE EXCEPTION 'You do not have permission to reset passwords';
    END IF;
    PERFORM fn_set_password(p_target_user_id, p_temp_password, TRUE);
    UPDATE user_sessions SET revoked_at = now(), revoke_reason = 'password_reset'
     WHERE user_id = p_target_user_id AND revoked_at IS NULL;
    SELECT email INTO v_email FROM app_users WHERE user_id = p_target_user_id;
    INSERT INTO email_outbox (to_address, subject, body, template_code, related_entity, related_id)
    VALUES (v_email, 'Your Maxhub ERP password was reset',
            'IT Support has reset your password. Log in with the temporary password you were given and choose a new one.',
            'password_reset', 'app_user', p_target_user_id);
END $$;

CREATE OR REPLACE FUNCTION fn_unlock_user(p_admin_user_id BIGINT, p_target_user_id BIGINT) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT fn_has_permission(p_admin_user_id, 'user.manage') THEN
        RAISE EXCEPTION 'You do not have permission to unlock accounts';
    END IF;
    UPDATE app_users SET failed_logins = 0, locked_until = NULL WHERE user_id = p_target_user_id;
END $$;

-- Permissions ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_user_permissions(p_user_id BIGINT) RETURNS SETOF TEXT
LANGUAGE sql STABLE AS $$
    SELECT DISTINCT p.code
      FROM user_roles ur
      JOIN role_permissions rp ON rp.role_id = ur.role_id
      JOIN permissions p       ON p.permission_id = rp.permission_id
      JOIN app_users u         ON u.user_id = ur.user_id AND u.is_active
     WHERE ur.user_id = p_user_id;
$$;

CREATE OR REPLACE FUNCTION fn_has_permission(p_user_id BIGINT, p_permission TEXT) RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM fn_user_permissions(p_user_id) x WHERE x = p_permission);
$$;

-- Give a user the roles their department & grade call for (keeps manual roles)
CREATE OR REPLACE FUNCTION fn_sync_user_roles(p_user_id BIGINT) RETURNS INTEGER
LANGUAGE plpgsql AS $$
DECLARE v_count INTEGER;
BEGIN
    DELETE FROM user_roles WHERE user_id = p_user_id AND source = 'auto';
    INSERT INTO user_roles (user_id, role_id, source)
    SELECT DISTINCT u.user_id, r.role_id, 'auto'
      FROM app_users u
      JOIN employees e              ON e.employee_id = u.employee_id
      LEFT JOIN job_grades g        ON g.job_grade_id = e.job_grade_id
      JOIN department_role_rules r  ON (r.department_id IS NULL OR r.department_id = e.department_id)
                                   AND COALESCE(g.level, 0) BETWEEN r.min_grade_level AND r.max_grade_level
     WHERE u.user_id = p_user_id
    ON CONFLICT (user_id, role_id) DO NOTHING;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END $$;

CREATE OR REPLACE FUNCTION fn_app_user_after_insert() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM fn_sync_user_roles(NEW.user_id);
    RETURN NULL;
END $$;
CREATE TRIGGER trg_app_users_roles AFTER INSERT ON app_users
    FOR EACH ROW EXECUTE FUNCTION fn_app_user_after_insert();

-- Moving department / grade changes the automatic roles; leaving the firm disables the login
CREATE OR REPLACE FUNCTION fn_employee_access_sync() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_user BIGINT;
BEGIN
    SELECT user_id INTO v_user FROM app_users WHERE employee_id = NEW.employee_id;
    IF v_user IS NULL THEN RETURN NULL; END IF;
    IF NEW.status = 'terminated' AND OLD.status IS DISTINCT FROM 'terminated' THEN
        UPDATE app_users SET is_active = FALSE WHERE user_id = v_user;
        UPDATE user_sessions SET revoked_at = now(), revoke_reason = 'terminated'
         WHERE user_id = v_user AND revoked_at IS NULL;
    END IF;
    IF (NEW.department_id, NEW.job_grade_id) IS DISTINCT FROM (OLD.department_id, OLD.job_grade_id) THEN
        PERFORM fn_sync_user_roles(v_user);
    END IF;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_employees_access_sync AFTER UPDATE OF department_id, job_grade_id, status ON employees
    FOR EACH ROW EXECUTE FUNCTION fn_employee_access_sync();

-- HR onboarding: create a login for a new employee with a temporary password
CREATE OR REPLACE FUNCTION fn_create_user_for_employee(p_employee_id BIGINT, p_temp_password TEXT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_emp employees%ROWTYPE; v_user BIGINT; v_err TEXT;
BEGIN
    SELECT * INTO v_emp FROM employees WHERE employee_id = p_employee_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Employee % not found', p_employee_id; END IF;
    IF EXISTS (SELECT 1 FROM app_users WHERE employee_id = p_employee_id) THEN
        RAISE EXCEPTION '% already has a login', v_emp.first_name || ' ' || v_emp.last_name;
    END IF;
    v_err := fn_password_policy_error(p_temp_password);
    IF v_err IS NOT NULL THEN RAISE EXCEPTION '%', v_err; END IF;
    INSERT INTO app_users (employee_id, username, email, password_hash, must_change_password)
    VALUES (p_employee_id, lower(split_part(v_emp.email, '@', 1)), v_emp.email, fn_hash_password(p_temp_password), TRUE)
    RETURNING user_id INTO v_user;
    INSERT INTO email_outbox (to_address, subject, body, template_code, related_entity, related_id)
    VALUES (v_emp.email, 'Welcome to Maxhub - your ERP login',
            format('Hi %s, your Maxhub ERP username is %s. Use the temporary password from HR; you will be asked to change it.',
                   v_emp.first_name, lower(split_part(v_emp.email, '@', 1))),
            'welcome', 'app_user', v_user);
    RETURN v_user;
END $$;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  22_logic_finance.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   22. FINANCE, PAYROLL, ASSETS, LEASES & TAX LOGIC
   -------------------------------------------------------------------------------------
   22.1  Helpers ............ fn_fx_rate, fn_post_journal (JSON lines -> posted journal)
   22.2  Payroll ............ fn_calc_paye, fn_run_payroll, fn_approve_payroll, fn_pay_payroll
   22.3  Payables ........... fn_approve_vendor_bill, fn_pay_vendor_bill (WHT + IMTT)
   22.4  Fixed assets ....... fn_asset_nbv, fn_run_depreciation, fn_revalue_asset, fn_dispose_asset
   22.5  Leases & loans ..... fn_generate_lease_schedule, fn_recognise_lease, fn_post_lease_month,
                              fn_generate_loan_schedule, fn_post_loan_month
   22.6  Tax ................ fn_prepare_vat_return, fn_prepare_payroll_returns, fn_create_qpds,
                              fn_file_tax_return, fn_pay_tax_return, fn_accrue_income_tax,
                              fn_deferred_tax_schedule
   22.7  Other .............. fn_update_ecl_provision, fn_bank_transfer
   Keep cash journals "pure" (cash lines + their direct counterparts) so the direct-method
   cash-flow statement can classify every cash movement from the counter-accounts.
   ===================================================================================== */

/* ---------- 22.1 Helpers ---------- */

-- Units of USD per 1 unit of p_currency on (or before) p_date
CREATE OR REPLACE FUNCTION fn_fx_rate(p_currency CHAR(3), p_date DATE) RETURNS NUMERIC
LANGUAGE plpgsql STABLE AS $$
DECLARE v NUMERIC;
BEGIN
    IF p_currency = 'USD' THEN RETURN 1; END IF;
    SELECT rate INTO v FROM exchange_rates
     WHERE from_currency = p_currency AND to_currency = 'USD' AND rate_date <= p_date
     ORDER BY rate_date DESC LIMIT 1;
    IF v IS NULL THEN
        SELECT rate INTO v FROM exchange_rates
         WHERE from_currency = p_currency AND to_currency = 'USD' ORDER BY rate_date LIMIT 1;
    END IF;
    IF v IS NULL THEN RAISE EXCEPTION 'No exchange rate %->USD on or before %', p_currency, p_date; END IF;
    RETURN v;
END $$;

/* Create and post a journal in one call.
   p_lines = JSON array of objects: {"acc":"5100","dr":100.00,"cr":0,"desc":"...",
             "office":1,"dept":2,"project":3,"employee":4,"vendor":5,"client":6}
   Zero lines are skipped; a rounding difference of up to 0.05 is put on the last line. */
CREATE OR REPLACE FUNCTION fn_post_journal(p_date DATE, p_description TEXT, p_source TEXT, p_source_id BIGINT,
                                           p_lines JSONB, p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_je BIGINT; v_no SMALLINT := 0; l JSONB; v_dr NUMERIC; v_cr NUMERIC; v_diff NUMERIC;
BEGIN
    INSERT INTO journal_entries (entry_date, description, source_type, source_id, created_by)
    VALUES (p_date, left(p_description, 300), p_source, p_source_id, p_user)
    RETURNING journal_entry_id INTO v_je;

    FOR l IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
        v_dr := round(COALESCE((l->>'dr')::NUMERIC, 0), 2);
        v_cr := round(COALESCE((l->>'cr')::NUMERIC, 0), 2);
        IF v_dr < 0 THEN v_cr := v_cr - v_dr; v_dr := 0; END IF;     -- negative debit = credit
        IF v_cr < 0 THEN v_dr := v_dr - v_cr; v_cr := 0; END IF;
        IF v_dr > 0 AND v_cr > 0 THEN                                 -- net a two-sided line
            IF v_dr >= v_cr THEN v_dr := v_dr - v_cr; v_cr := 0; ELSE v_cr := v_cr - v_dr; v_dr := 0; END IF;
        END IF;
        CONTINUE WHEN v_dr = 0 AND v_cr = 0;
        v_no := v_no + 1;
        INSERT INTO journal_lines (journal_entry_id, line_no, account_id, debit, credit, description,
                                   office_id, department_id, project_id, employee_id, vendor_id, client_id)
        VALUES (v_je, v_no, fn_account_id(l->>'acc'), v_dr, v_cr, left(COALESCE(l->>'desc', p_description), 300),
                (l->>'office')::BIGINT, (l->>'dept')::BIGINT, (l->>'project')::BIGINT,
                (l->>'employee')::BIGINT, (l->>'vendor')::BIGINT, (l->>'client')::BIGINT);
    END LOOP;

    IF v_no = 0 THEN
        DELETE FROM journal_entries WHERE journal_entry_id = v_je;
        RETURN NULL;
    END IF;

    SELECT SUM(debit) - SUM(credit) INTO v_diff FROM journal_lines WHERE journal_entry_id = v_je;
    IF v_diff <> 0 THEN
        IF abs(v_diff) > 0.05 THEN
            RAISE EXCEPTION 'Journal "%" does not balance: difference %', p_description, v_diff;
        END IF;
        UPDATE journal_lines
           SET debit  = CASE WHEN debit  > 0 THEN debit  - v_diff ELSE debit END,
               credit = CASE WHEN credit > 0 THEN credit + v_diff ELSE credit END
         WHERE journal_entry_id = v_je AND line_no = v_no;
    END IF;

    UPDATE journal_entries SET status = 'posted' WHERE journal_entry_id = v_je;
    RETURN v_je;
END $$;

-- Current statutory rate / amount for a country (effective on p_date)
CREATE OR REPLACE FUNCTION fn_stat_rate(p_country CHAR(2), p_code TEXT, p_date DATE) RETURNS NUMERIC
LANGUAGE sql STABLE AS $$
    SELECT COALESCE((SELECT rate_pct FROM statutory_rates
                      WHERE country_code = p_country AND rate_code = p_code AND effective_from <= p_date
                        AND (effective_to IS NULL OR effective_to >= p_date)
                      ORDER BY effective_from DESC LIMIT 1), 0);
$$;

CREATE OR REPLACE FUNCTION fn_stat_amount(p_country CHAR(2), p_code TEXT, p_date DATE) RETURNS NUMERIC
LANGUAGE sql STABLE AS $$
    SELECT (SELECT amount FROM statutory_rates
             WHERE country_code = p_country AND rate_code = p_code AND effective_from <= p_date
               AND (effective_to IS NULL OR effective_to >= p_date)
             ORDER BY effective_from DESC LIMIT 1);
$$;


/* ---------- 22.2 Payroll ---------- */

-- Monthly PAYE from the progressive table: taxable x rate - "less" amount of the band
CREATE OR REPLACE FUNCTION fn_calc_paye(p_taxable NUMERIC, p_date DATE, p_country CHAR(2) DEFAULT 'ZW',
                                        p_currency CHAR(3) DEFAULT 'USD') RETURNS NUMERIC
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(round(GREATEST(p_taxable * b.rate_pct / 100 - b.deduct_amount, 0), 2), 0)
      FROM paye_tax_bands b
     WHERE b.country_code = p_country AND b.currency_code = p_currency
       AND b.effective_from = (SELECT max(effective_from) FROM paye_tax_bands
                                WHERE country_code = p_country AND currency_code = p_currency AND effective_from <= p_date)
       AND p_taxable >= b.lower_limit AND (b.upper_limit IS NULL OR p_taxable <= b.upper_limit)
     LIMIT 1;
$$;

/* Create a payroll run with payslips for every active employee based in p_country.
   Zimbabwe: NSSA 4.5% EE/ER on insurable earnings (USD 700 ceiling), WCIF, ZIMDEF 1%,
             pension (approved fund, deductible up to the cap), PAYE bands, 50% medical-aid
             credit, AIDS levy 3% of PAYE.
   Branches: simplified local rates from statutory_rates (effective income-tax rate,
             social security EE/ER, other employer levies). */
CREATE OR REPLACE FUNCTION fn_run_payroll(p_country CHAR(2), p_period_start DATE, p_pay_date DATE DEFAULT NULL,
                                          p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    v_end   DATE := (date_trunc('month', p_period_start) + INTERVAL '1 month - 1 day')::DATE;
    v_cur   CHAR(3);
    v_run   BIGINT;
    r       RECORD;
    v_gross NUMERIC; v_ins NUMERIC; v_nssa NUMERIC; v_pen NUMERIC; v_pen_er NUMERIC; v_med NUMERIC; v_med_er NUMERIC;
    v_taxable NUMERIC; v_tax NUMERIC; v_credit NUMERIC; v_aids NUMERIC; v_er_ss NUMERIC; v_er_other NUMERIC; v_zimdef NUMERIC;
    v_ceiling NUMERIC;
BEGIN
    SELECT default_currency INTO v_cur FROM countries WHERE country_code = p_country;
    INSERT INTO payroll_runs (run_number, country_code, period_start, period_end, pay_date, currency_code, exchange_rate, notes)
    VALUES ('PAY-' || p_country || '-' || to_char(p_period_start, 'YYYY-MM'), p_country, date_trunc('month', p_period_start)::DATE,
            v_end, COALESCE(p_pay_date, v_end - 2), v_cur, fn_fx_rate(v_cur, v_end),
            'Monthly payroll ' || to_char(p_period_start, 'FMMonth YYYY'))
    RETURNING payroll_run_id INTO v_run;

    FOR r IN
        SELECT e.employee_id, e.pension_member, e.medical_aid_member, c.base_salary_annual, c.monthly_allowances
          FROM employees e
          JOIN offices o ON o.office_id = e.office_id AND o.country_code = p_country
          JOIN LATERAL (SELECT * FROM employee_compensation ec
                         WHERE ec.employee_id = e.employee_id AND ec.effective_date <= v_end
                         ORDER BY ec.effective_date DESC LIMIT 1) c ON TRUE
         WHERE e.hire_date <= v_end
           AND (e.termination_date IS NULL OR e.termination_date >= p_period_start)
           AND e.employment_type IN ('full_time','part_time','intern')
    LOOP
        v_gross := round(r.base_salary_annual / 12, 2) + r.monthly_allowances;
        v_pen    := CASE WHEN r.pension_member THEN round(r.base_salary_annual / 12 * fn_stat_rate(p_country,'PENSION_EE',v_end) / 100, 2) ELSE 0 END;
        v_pen_er := CASE WHEN r.pension_member THEN round(r.base_salary_annual / 12 * fn_stat_rate(p_country,'PENSION_ER',v_end) / 100, 2) ELSE 0 END;

        IF p_country = 'ZW' THEN
            v_ceiling := COALESCE(fn_stat_amount('ZW','NSSA_CEILING',v_end), 700);
            v_ins    := LEAST(v_gross, v_ceiling);
            v_nssa   := round(v_ins * fn_stat_rate('ZW','NSSA_EE',v_end) / 100, 2);
            v_er_ss  := round(v_ins * fn_stat_rate('ZW','NSSA_ER',v_end) / 100, 2);
            v_er_other := round(v_ins * fn_stat_rate('ZW','NSSA_WCIF',v_end) / 100, 2);
            v_zimdef := round(v_gross * fn_stat_rate('ZW','ZIMDEF',v_end) / 100, 2);
            v_med    := CASE WHEN r.medical_aid_member THEN LEAST(round(v_gross * 0.04, 2), 180) ELSE 0 END;
            v_med_er := CASE WHEN r.medical_aid_member THEN round(v_med * 1.5, 2) ELSE 0 END;
            v_taxable := GREATEST(v_gross - v_nssa - LEAST(v_pen, COALESCE(fn_stat_amount('ZW','PENSION_CAP',v_end), 450)), 0);
            v_tax    := fn_calc_paye(v_taxable, v_end, 'ZW', 'USD');
            v_credit := LEAST(round(v_med * fn_stat_rate('ZW','MEDICAL_CREDIT',v_end) / 100, 2), v_tax);
            v_tax    := v_tax - v_credit;
            v_aids   := round(v_tax * fn_stat_rate('ZW','AIDS_LEVY',v_end) / 100, 2);
        ELSE
            v_ceiling := fn_stat_amount(p_country,'SOCIAL_CEILING',v_end);
            v_ins    := CASE WHEN v_ceiling IS NULL THEN v_gross ELSE LEAST(v_gross, v_ceiling) END;
            v_nssa   := round(v_ins * fn_stat_rate(p_country,'SOCIAL_EE',v_end) / 100, 2);
            v_er_ss  := round(v_ins * fn_stat_rate(p_country,'SOCIAL_ER',v_end) / 100, 2);
            v_er_other := round(v_gross * fn_stat_rate(p_country,'OTHER_ER',v_end) / 100, 2);
            v_zimdef := 0; v_med := 0; v_med_er := 0; v_credit := 0; v_aids := 0;
            v_taxable := GREATEST(v_gross - v_nssa - v_pen, 0);
            v_tax    := round(v_taxable * fn_stat_rate(p_country,'INCOME_TAX_EFFECTIVE',v_end) / 100, 2);
        END IF;

        INSERT INTO payslips (payroll_run_id, employee_id, currency_code, basic_pay, allowances,
                              nssa_employee, pension, taxable_income, paye_tax, medical_aid_credit, aids_levy, medical_aid,
                              employer_nssa, employer_wcif, employer_zimdef, employer_pension, employer_medical)
        VALUES (v_run, r.employee_id, v_cur, round(r.base_salary_annual / 12, 2), r.monthly_allowances,
                v_nssa, v_pen, v_taxable, v_tax, v_credit, v_aids, v_med,
                v_er_ss, v_er_other, v_zimdef, v_pen_er, v_med_er);
    END LOOP;

    UPDATE payroll_runs pr SET employee_count = s.n, total_gross = s.g, total_net = s.net, total_employer_cost = s.ec
      FROM (SELECT count(*) n, COALESCE(SUM(gross_pay),0) g, COALESCE(SUM(net_pay),0) net, COALESCE(SUM(employer_cost),0) ec
              FROM payslips WHERE payroll_run_id = v_run) s
     WHERE pr.payroll_run_id = v_run;
    RETURN v_run;
END $$;

-- Approve & post the payroll accrual (USD) - salaries by department/office, statutory liabilities
CREATE OR REPLACE FUNCTION fn_approve_payroll(p_run_id BIGINT, p_approver BIGINT, p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_run payroll_runs%ROWTYPE; v_lines JSONB := '[]'::JSONB; v_je BIGINT; x NUMERIC; r RECORD; t RECORD;
BEGIN
    SELECT * INTO v_run FROM payroll_runs WHERE payroll_run_id = p_run_id FOR UPDATE;
    IF v_run.status <> 'draft' THEN RAISE EXCEPTION 'Payroll run % is %', v_run.run_number, v_run.status; END IF;
    x := v_run.exchange_rate;

    -- gross pay and employer costs by department & office
    FOR r IN SELECT e.department_id, e.office_id, d.is_revenue_generating AS fee,
                    SUM(p.gross_pay) g, SUM(p.employer_nssa + p.employer_wcif) ss, SUM(p.employer_zimdef) zd,
                    SUM(p.employer_pension) pe, SUM(p.employer_medical) me
               FROM payslips p JOIN employees e USING (employee_id) JOIN departments d ON d.department_id = e.department_id
              WHERE p.payroll_run_id = p_run_id GROUP BY 1, 2, 3
    LOOP
        v_lines := v_lines
          || jsonb_build_object('acc', CASE WHEN r.fee THEN '5100' ELSE '5110' END, 'dr', r.g * x, 'dept', r.department_id, 'office', r.office_id, 'desc','Gross salaries')
          || jsonb_build_object('acc','5120','dr', r.ss * x, 'dept', r.department_id, 'office', r.office_id, 'desc','Employer social security & workers compensation')
          || jsonb_build_object('acc','5125','dr', r.zd * x, 'dept', r.department_id, 'office', r.office_id, 'desc','ZIMDEF levy')
          || jsonb_build_object('acc','5130','dr', r.pe * x, 'dept', r.department_id, 'office', r.office_id, 'desc','Employer pension')
          || jsonb_build_object('acc','5140','dr', r.me * x, 'dept', r.department_id, 'office', r.office_id, 'desc','Employer medical aid');
    END LOOP;

    SELECT SUM(paye_tax) paye, SUM(aids_levy) aids, SUM(nssa_employee) ss_ee, SUM(employer_nssa) ss_er, SUM(employer_wcif) oth,
           SUM(employer_zimdef) zd, SUM(pension + employer_pension) pen, SUM(medical_aid + employer_medical) med,
           SUM(other_deductions) oth_ded, SUM(net_pay) net
      INTO t FROM payslips WHERE payroll_run_id = p_run_id;

    IF v_run.country_code = 'ZW' THEN
        v_lines := v_lines
          || jsonb_build_object('acc','2400','cr', t.paye * x, 'desc','PAYE payable (ZIMRA)')
          || jsonb_build_object('acc','2405','cr', t.aids * x, 'desc','AIDS levy payable (ZIMRA)')
          || jsonb_build_object('acc','2410','cr', (t.ss_ee + t.ss_er + t.oth) * x, 'desc','NSSA POBS & WCIF payable')
          || jsonb_build_object('acc','2415','cr', t.zd * x, 'desc','ZIMDEF payable');
    ELSE
        v_lines := v_lines
          || jsonb_build_object('acc','2450','cr', (t.paye + t.ss_ee + t.ss_er + t.oth) * x,
                                'desc','Branch payroll taxes & social security payable - ' || v_run.country_code);
    END IF;
    v_lines := v_lines
      || jsonb_build_object('acc','2420','cr', t.pen * x, 'desc','Pension fund contributions payable')
      || jsonb_build_object('acc','2425','cr', t.med * x, 'desc','Medical aid contributions payable')
      || jsonb_build_object('acc','2500','cr', t.oth_ded * x, 'desc','Other payroll deductions payable')
      || jsonb_build_object('acc','2150','cr', t.net * x, 'desc','Net salaries payable');

    v_je := fn_post_journal(v_run.period_end, 'Payroll ' || v_run.run_number, 'payroll', p_run_id, v_lines, p_user);
    UPDATE payroll_runs SET status = 'approved', approved_by = p_approver, approved_at = now(), journal_entry_id = v_je
     WHERE payroll_run_id = p_run_id;
    RETURN v_je;
END $$;

CREATE OR REPLACE FUNCTION fn_pay_payroll(p_run_id BIGINT, p_bank_account_id BIGINT, p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_run payroll_runs%ROWTYPE; v_je BIGINT; v_amt NUMERIC; v_gl TEXT;
BEGIN
    SELECT * INTO v_run FROM payroll_runs WHERE payroll_run_id = p_run_id FOR UPDATE;
    IF v_run.status <> 'approved' THEN RAISE EXCEPTION 'Payroll run % must be approved before paying (current: %)', v_run.run_number, v_run.status; END IF;
    SELECT credit INTO v_amt FROM journal_lines
     WHERE journal_entry_id = v_run.journal_entry_id AND account_id = fn_account_id('2150');
    SELECT a.account_code INTO v_gl FROM bank_accounts b JOIN chart_of_accounts a ON a.account_id = b.gl_account_id
     WHERE b.bank_account_id = p_bank_account_id;
    v_je := fn_post_journal(v_run.pay_date, 'Net salaries paid ' || v_run.run_number, 'payroll_payment', p_run_id,
            jsonb_build_array(jsonb_build_object('acc','2150','dr', v_amt, 'desc','Net salaries'),
                              jsonb_build_object('acc', v_gl, 'cr', v_amt, 'desc','Salary transfer (IMTT exempt)')), p_user);
    UPDATE payroll_runs SET status = 'paid', payment_journal_id = v_je WHERE payroll_run_id = p_run_id;
    RETURN v_je;
END $$;


/* ---------- 22.3 Payables ---------- */

-- Approve a supplier bill: Dr expense / asset (+ recoverable ZIMRA input VAT) / Cr Accounts payable
CREATE OR REPLACE FUNCTION fn_approve_vendor_bill(p_bill_id BIGINT, p_approver BIGINT, p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE b vendor_bills%ROWTYPE; v vendors%ROWTYPE; v_je BIGINT; v_acc TEXT; v_ap TEXT; v_rate NUMERIC; v_vat_ok BOOLEAN;
BEGIN
    SELECT * INTO b FROM vendor_bills WHERE vendor_bill_id = p_bill_id FOR UPDATE;
    IF b.status <> 'draft' THEN RAISE EXCEPTION 'Bill % is already %', b.bill_number, b.status; END IF;
    SELECT * INTO v FROM vendors WHERE vendor_id = b.vendor_id;
    SELECT account_code INTO v_acc FROM chart_of_accounts
     WHERE account_id = COALESCE(b.expense_account_id, v.default_expense_account_id);
    IF v_acc IS NULL THEN RAISE EXCEPTION 'Bill % has no expense account', b.bill_number; END IF;
    -- capital purchases go to a separate payables account so their payment shows as INVESTING cash flow
    SELECT CASE WHEN ifrs_line_code IN ('SFP_PPE','SFP_INT','SFP_IP') THEN '2110' ELSE '2100' END INTO v_ap
      FROM chart_of_accounts WHERE account_code = v_acc;
    v_rate := CASE WHEN b.currency_code = 'USD' THEN 1 ELSE fn_fx_rate(b.currency_code, b.bill_date) END;
    -- input VAT is only claimable on Zimbabwean tax invoices from VAT-registered suppliers
    v_vat_ok := COALESCE(v.country_code, 'ZW') = 'ZW' AND v.vat_number IS NOT NULL;

    v_je := fn_post_journal(b.bill_date, format('Supplier bill %s - %s', b.bill_number, v.name), 'vendor_bill', p_bill_id,
        jsonb_build_array(
            jsonb_build_object('acc', v_acc, 'dr', (b.subtotal + CASE WHEN v_vat_ok THEN 0 ELSE b.tax_amount END) * v_rate,
                               'office', b.office_id, 'dept', b.department_id, 'project', b.project_id, 'vendor', b.vendor_id,
                               'desc', COALESCE(b.description, 'Supplier bill ' || b.bill_number)),
            jsonb_build_object('acc','2210','dr', CASE WHEN v_vat_ok THEN b.tax_amount * v_rate ELSE 0 END, 'vendor', b.vendor_id, 'desc','Input VAT'),
            jsonb_build_object('acc', v_ap, 'cr', (b.subtotal + b.tax_amount) * v_rate, 'vendor', b.vendor_id, 'desc','Accounts payable')),
        p_user);
    UPDATE vendor_bills SET status = 'approved', approved_by = p_approver, exchange_rate = v_rate, journal_entry_id = v_je
     WHERE vendor_bill_id = p_bill_id;
    RETURN v_je;
END $$;

/* Pay a supplier bill.
   * 30% withholding tax if a Zimbabwean supplier has no valid ITF263 tax clearance and the
     bill is at or above the threshold; 15% non-residents' tax on fees for foreign
     subcontractors/professionals.  WHT is paid over to ZIMRA later.
   * 2% IMTT charged by the bank on electronic transfers from Zimbabwean accounts.
   * AP is cleared at the bill's rate; the difference to today's rate is an FX gain/loss. */
CREATE OR REPLACE FUNCTION fn_pay_vendor_bill(p_bill_id BIGINT, p_amount NUMERIC, p_bank_account_id BIGINT,
                                              p_date DATE DEFAULT CURRENT_DATE, p_reference TEXT DEFAULT NULL,
                                              p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE
    b vendor_bills%ROWTYPE; v vendors%ROWTYPE; k bank_accounts%ROWTYPE;
    v_bank_gl TEXT; v_zw_bank BOOLEAN; v_rate NUMERIC; v_wht NUMERIC := 0; v_wht_rate NUMERIC := 0; v_wht_type TEXT;
    v_cash NUMERIC; v_imtt NUMERIC := 0; v_ap_usd NUMERIC; v_cash_usd NUMERIC; v_wht_usd NUMERIC; v_fx NUMERIC;
    v_pay BIGINT; v_je BIGINT; v_ap TEXT;
BEGIN
    SELECT * INTO b FROM vendor_bills WHERE vendor_bill_id = p_bill_id FOR UPDATE;
    IF b.status NOT IN ('approved','partially_paid') THEN
        RAISE EXCEPTION 'Bill % must be approved before payment (current: %)', b.bill_number, b.status;
    END IF;
    IF p_amount <= 0 OR p_amount > b.total_amount - b.amount_paid THEN
        RAISE EXCEPTION 'Payment % must be between 0 and the balance %', p_amount, b.total_amount - b.amount_paid;
    END IF;
    SELECT * INTO v FROM vendors WHERE vendor_id = b.vendor_id;
    SELECT * INTO k FROM bank_accounts WHERE bank_account_id = p_bank_account_id;
    IF k.currency_code <> b.currency_code THEN
        RAISE EXCEPTION 'Pay a % bill from a % account (selected account is %)', b.currency_code, b.currency_code, k.currency_code;
    END IF;
    SELECT a.account_code INTO v_bank_gl FROM chart_of_accounts a WHERE a.account_id = k.gl_account_id;
    SELECT o.country_code = 'ZW' INTO v_zw_bank FROM offices o WHERE o.office_id = k.office_id;
    SELECT CASE WHEN EXISTS (SELECT 1 FROM journal_lines jl WHERE jl.journal_entry_id = b.journal_entry_id
                              AND jl.account_id = fn_account_id('2110')) THEN '2110' ELSE '2100' END INTO v_ap;

    IF v.is_resident AND COALESCE(v.country_code,'ZW') = 'ZW' AND v.vendor_type NOT IN ('government','utility')
       AND (v.tax_clearance_expiry IS NULL OR v.tax_clearance_expiry < p_date)
       AND b.total_amount >= COALESCE(fn_stat_amount('ZW','WHT_TENDER_THRESHOLD', p_date), 1000) THEN
        v_wht_rate := fn_stat_rate('ZW','WHT_TENDER', p_date); v_wht_type := 'tender_30';
    ELSIF NOT v.is_resident AND v.vendor_type IN ('subcontractor','professional','freelancer') THEN
        v_wht_rate := fn_stat_rate('ZW','WHT_NONRES_FEES', p_date); v_wht_type := 'non_resident_fees';
    END IF;
    v_wht  := round(p_amount * v_wht_rate / 100, 2);
    v_cash := p_amount - v_wht;
    IF COALESCE(v_zw_bank, FALSE) AND v.vendor_type <> 'government' THEN
        v_imtt := round(v_cash * fn_stat_rate('ZW','IMTT', p_date) / 100, 2);
    END IF;

    v_rate     := fn_fx_rate(b.currency_code, p_date);
    v_ap_usd   := round(p_amount * b.exchange_rate, 2);
    v_cash_usd := round(v_cash * v_rate, 2);
    v_wht_usd  := round(v_wht * v_rate, 2);
    v_fx       := v_ap_usd - v_cash_usd - v_wht_usd;          -- +ve = gain

    INSERT INTO vendor_payments (vendor_bill_id, payment_date, amount, method, reference, bank_account_id, withholding_tax, imtt_amount)
    VALUES (p_bill_id, p_date, p_amount, 'bank_transfer', p_reference, p_bank_account_id, v_wht, v_imtt)
    RETURNING vendor_payment_id INTO v_pay;

    v_je := fn_post_journal(p_date, format('Payment to %s for %s', v.name, b.bill_number), 'vendor_payment', v_pay,
        jsonb_build_array(
            jsonb_build_object('acc', v_ap, 'dr', v_ap_usd, 'vendor', v.vendor_id, 'desc','Settle accounts payable'),
            jsonb_build_object('acc','2430','cr', v_wht_usd, 'vendor', v.vendor_id, 'desc','Withholding tax retained for ZIMRA'),
            jsonb_build_object('acc', CASE WHEN v_fx >= 0 THEN '4800' ELSE '7300' END, 'cr', v_fx, 'desc','Exchange difference on settlement'),
            jsonb_build_object('acc','6610','dr', round(v_imtt * v_rate, 2), 'office', k.office_id, 'desc','IMTT 2% on transfer'),
            jsonb_build_object('acc', v_bank_gl, 'cr', v_cash_usd + round(v_imtt * v_rate, 2), 'desc','Bank transfer')),
        p_user);
    UPDATE vendor_payments SET journal_entry_id = v_je WHERE vendor_payment_id = v_pay;

    IF v_wht > 0 THEN
        INSERT INTO withholding_tax_deductions (vendor_payment_id, vendor_id, wht_type, gross_amount, rate_pct, wht_amount, deduction_date)
        VALUES (v_pay, v.vendor_id, v_wht_type, p_amount, v_wht_rate, v_wht, p_date);
    END IF;
    RETURN v_pay;
END $$;


/* ---------- 22.4 Fixed assets ---------- */

-- Carrying amount (and its parts) of an asset at a date
CREATE OR REPLACE FUNCTION fn_asset_nbv(p_asset_id BIGINT, p_as_at DATE)
RETURNS TABLE (gross NUMERIC, accumulated_depreciation NUMERIC, carrying_amount NUMERIC)
LANGUAGE plpgsql STABLE AS $$
DECLARE a fixed_assets%ROWTYPE; v_rev asset_revaluations%ROWTYPE; v_g NUMERIC; v_ad NUMERIC;
BEGIN
    SELECT * INTO a FROM fixed_assets WHERE asset_id = p_asset_id;
    IF a.acquisition_date > p_as_at OR (a.disposal_date IS NOT NULL AND a.disposal_date <= p_as_at) THEN
        RETURN QUERY SELECT 0::NUMERIC, 0::NUMERIC, 0::NUMERIC; RETURN;
    END IF;
    SELECT * INTO v_rev FROM asset_revaluations
     WHERE asset_id = p_asset_id AND valuation_date <= p_as_at AND valuation_type IN ('revaluation','fair_value')
     ORDER BY valuation_date DESC LIMIT 1;
    IF FOUND THEN
        v_g  := v_rev.fair_value;                            -- elimination method: acc. dep. restarts at 0
        SELECT COALESCE(SUM(amount), 0) INTO v_ad FROM asset_depreciation
         WHERE asset_id = p_asset_id AND period_end > v_rev.valuation_date AND period_end <= p_as_at;
    ELSE
        v_g  := a.cost;
        SELECT a.opening_acc_depreciation + COALESCE(SUM(amount), 0) INTO v_ad FROM asset_depreciation
         WHERE asset_id = p_asset_id AND period_end <= p_as_at;
    END IF;
    RETURN QUERY SELECT v_g, v_ad, v_g - v_ad;
END $$;

-- Monthly depreciation for one asset (straight-line on cost / revalued amount over remaining life,
-- or reducing balance). Full month in the month the asset becomes available for use.
CREATE OR REPLACE FUNCTION fn_asset_monthly_depreciation(p_asset_id BIGINT, p_period_end DATE) RETURNS NUMERIC
LANGUAGE plpgsql STABLE AS $$
DECLARE a fixed_assets%ROWTYPE; c asset_categories%ROWTYPE; n RECORD; v_life INT; v_used INT; v_rev DATE; v_dep NUMERIC;
BEGIN
    SELECT * INTO a FROM fixed_assets WHERE asset_id = p_asset_id;
    SELECT * INTO c FROM asset_categories WHERE asset_category_id = a.asset_category_id;
    IF c.depreciation_method = 'none' OR a.status NOT IN ('in_use','idle') OR a.available_for_use_date > p_period_end THEN
        RETURN 0;
    END IF;
    IF a.acquisition_date > (date_trunc('month', p_period_end) - INTERVAL '1 day')::DATE THEN
        -- first month in service: nothing depreciated yet
        SELECT a.cost AS gross, 0::NUMERIC AS accumulated_depreciation, a.cost AS carrying_amount INTO n;
    ELSE
        SELECT * INTO n FROM fn_asset_nbv(p_asset_id, (date_trunc('month', p_period_end) - INTERVAL '1 day')::DATE);
    END IF;
    IF n.carrying_amount <= a.residual_value THEN RETURN 0; END IF;
    IF c.depreciation_method = 'reducing_balance' THEN
        v_dep := round(n.carrying_amount * c.reducing_balance_rate / 100 / 12, 2);
    ELSE
        v_life := COALESCE(a.useful_life_months, c.useful_life_months);
        SELECT max(valuation_date) INTO v_rev FROM asset_revaluations
         WHERE asset_id = p_asset_id AND valuation_date < p_period_end AND valuation_type = 'revaluation';
        IF v_rev IS NULL THEN
            v_dep := round((a.cost - a.residual_value) / v_life, 2);
        ELSE
            v_used := (extract(year FROM age(v_rev, a.available_for_use_date)) * 12
                       + extract(month FROM age(v_rev, a.available_for_use_date)))::INT;
            v_dep := round((n.gross - a.residual_value) / GREATEST(v_life - v_used, 12), 2);
        END IF;
    END IF;
    RETURN GREATEST(LEAST(v_dep, n.carrying_amount - a.residual_value), 0);
END $$;

-- Post depreciation for every asset for the month ending p_period_end
CREATE OR REPLACE FUNCTION fn_run_depreciation(p_period_end DATE, p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE r RECORD; v_dep NUMERIC; v_je BIGINT; v_lines JSONB := '[]'::JSONB; v_total NUMERIC := 0;
BEGIN
    p_period_end := (date_trunc('month', p_period_end) + INTERVAL '1 month - 1 day')::DATE;
    CREATE TEMP TABLE IF NOT EXISTS tmp_dep (asset_id BIGINT, amount NUMERIC) ON COMMIT DROP;
    DELETE FROM tmp_dep;
    FOR r IN SELECT fa.asset_id FROM fixed_assets fa
              WHERE fa.status IN ('in_use','idle') AND fa.available_for_use_date <= p_period_end
                AND NOT EXISTS (SELECT 1 FROM asset_depreciation d WHERE d.asset_id = fa.asset_id AND d.period_end = p_period_end)
    LOOP
        v_dep := fn_asset_monthly_depreciation(r.asset_id, p_period_end);
        IF v_dep > 0 THEN INSERT INTO tmp_dep VALUES (r.asset_id, v_dep); END IF;
    END LOOP;

    FOR r IN SELECT ex.account_code AS exp_acc, ad.account_code AS ad_acc, fa.office_id, fa.department_id, SUM(t.amount) amt
               FROM tmp_dep t JOIN fixed_assets fa USING (asset_id)
               JOIN asset_categories c ON c.asset_category_id = fa.asset_category_id
               JOIN chart_of_accounts ex ON ex.account_id = c.dep_expense_account_id
               JOIN chart_of_accounts ad ON ad.account_id = c.acc_dep_account_id
              GROUP BY 1, 2, 3, 4
    LOOP
        v_lines := v_lines
          || jsonb_build_object('acc', r.exp_acc, 'dr', r.amt, 'office', r.office_id, 'dept', r.department_id, 'desc','Depreciation / amortisation')
          || jsonb_build_object('acc', r.ad_acc,  'cr', r.amt, 'office', r.office_id, 'desc','Accumulated depreciation');
        v_total := v_total + r.amt;
    END LOOP;
    IF v_total = 0 THEN RETURN NULL; END IF;

    v_je := fn_post_journal(p_period_end, 'Depreciation & amortisation ' || to_char(p_period_end, 'Mon YYYY'),
                            'depreciation', NULL, v_lines, p_user);
    INSERT INTO asset_depreciation (asset_id, period_end, amount, carrying_after, journal_entry_id)
    SELECT t.asset_id, p_period_end, t.amount, (SELECT carrying_amount FROM fn_asset_nbv(t.asset_id, p_period_end - 1)) - t.amount, v_je
      FROM tmp_dep t;
    -- carrying_after was computed before this month's row existed -> recompute exactly
    UPDATE asset_depreciation d SET carrying_after = (SELECT carrying_amount FROM fn_asset_nbv(d.asset_id, p_period_end))
     WHERE d.journal_entry_id = v_je;
    RETURN v_je;
END $$;

-- IAS 16 revaluation (elimination method) or IAS 40 fair-value remeasurement
CREATE OR REPLACE FUNCTION fn_revalue_asset(p_asset_id BIGINT, p_date DATE, p_fair_value NUMERIC, p_valuer TEXT,
                                            p_level SMALLINT DEFAULT 2, p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE a fixed_assets%ROWTYPE; c asset_categories%ROWTYPE; n RECORD; v_cost TEXT; v_ad TEXT; v_res TEXT;
        v_surplus NUMERIC; v_tax NUMERIC; v_rate NUMERIC; v_je BIGINT; v_type TEXT;
BEGIN
    SELECT * INTO a FROM fixed_assets WHERE asset_id = p_asset_id FOR UPDATE;
    SELECT * INTO c FROM asset_categories WHERE asset_category_id = a.asset_category_id;
    IF c.measurement_model = 'cost' THEN RAISE EXCEPTION 'Asset % uses the cost model - it cannot be revalued', a.asset_tag; END IF;
    SELECT * INTO n FROM fn_asset_nbv(p_asset_id, p_date);
    v_surplus := p_fair_value - n.carrying_amount;
    v_rate := fn_stat_rate('ZW','CIT',p_date) * (1 + fn_stat_rate('ZW','AIDS_LEVY',p_date) / 100);   -- 24.72
    v_tax := round(v_surplus * v_rate / 100, 2);
    SELECT account_code INTO v_cost FROM chart_of_accounts WHERE account_id = c.cost_account_id;
    SELECT account_code INTO v_ad   FROM chart_of_accounts WHERE account_id = c.acc_dep_account_id;
    SELECT account_code INTO v_res  FROM chart_of_accounts WHERE account_id = c.reval_reserve_account_id;

    IF c.measurement_model = 'fair_value' THEN            -- IAS 40: gain/loss in profit or loss (investing)
        v_type := 'fair_value';
        v_je := fn_post_journal(p_date, 'Fair value remeasurement - ' || a.name, 'fair_value', p_asset_id, jsonb_build_array(
            jsonb_build_object('acc', v_cost, 'dr', v_surplus, 'office', a.office_id, 'desc','Investment property to fair value'),
            jsonb_build_object('acc','4510', 'cr', v_surplus, 'office', a.office_id, 'desc','Fair value gain on investment property'),
            jsonb_build_object('acc','9020', 'dr', v_tax, 'desc','Deferred tax on fair value gain'),
            jsonb_build_object('acc','2900', 'cr', v_tax, 'desc','Deferred tax liability')), p_user);
        INSERT INTO asset_revaluations (asset_id, valuation_date, valuation_type, valuer, fair_value, carrying_before,
                                        surplus_deficit, to_profit_or_loss, deferred_tax, fair_value_level, journal_entry_id)
        VALUES (p_asset_id, p_date, v_type, p_valuer, p_fair_value, n.carrying_amount, v_surplus, v_surplus, v_tax, p_level, v_je);
    ELSE                                                    -- IAS 16 revaluation model: surplus to OCI net of deferred tax
        v_type := 'revaluation';
        v_je := fn_post_journal(p_date, 'Revaluation - ' || a.name, 'revaluation', p_asset_id, jsonb_build_array(
            jsonb_build_object('acc', v_ad,   'dr', n.accumulated_depreciation, 'office', a.office_id, 'desc','Eliminate accumulated depreciation'),
            jsonb_build_object('acc', v_cost, 'cr', n.accumulated_depreciation, 'office', a.office_id, 'desc','Eliminate accumulated depreciation'),
            jsonb_build_object('acc', v_cost, 'dr', v_surplus, 'office', a.office_id, 'desc','Revaluation to fair value'),
            jsonb_build_object('acc', COALESCE(v_res,'3300'), 'cr', v_surplus - v_tax, 'desc','Revaluation surplus (OCI)'),
            jsonb_build_object('acc','2900', 'cr', v_tax, 'desc','Deferred tax on revaluation (OCI)')), p_user);
        INSERT INTO asset_revaluations (asset_id, valuation_date, valuation_type, valuer, fair_value, carrying_before,
                                        surplus_deficit, to_oci, deferred_tax, fair_value_level, journal_entry_id)
        VALUES (p_asset_id, p_date, v_type, p_valuer, p_fair_value, n.carrying_amount, v_surplus, v_surplus - v_tax, v_tax, p_level, v_je);
    END IF;
    UPDATE fixed_assets SET revalued_amount = p_fair_value, last_revaluation_date = p_date WHERE asset_id = p_asset_id;
    RETURN v_je;
END $$;

-- Sell / scrap an asset: remove cost & accumulated depreciation, book the gain or loss
CREATE OR REPLACE FUNCTION fn_dispose_asset(p_asset_id BIGINT, p_date DATE, p_proceeds NUMERIC, p_bank_account_id BIGINT,
                                            p_buyer TEXT DEFAULT NULL, p_type TEXT DEFAULT 'sale',
                                            p_approver BIGINT DEFAULT NULL, p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE a fixed_assets%ROWTYPE; c asset_categories%ROWTYPE; n RECORD; v_cost TEXT; v_ad TEXT; v_bank TEXT; v_gain NUMERIC; v_je BIGINT;
BEGIN
    SELECT * INTO a FROM fixed_assets WHERE asset_id = p_asset_id FOR UPDATE;
    IF a.status IN ('disposed','written_off') THEN RAISE EXCEPTION 'Asset % is already %', a.asset_tag, a.status; END IF;
    SELECT * INTO c FROM asset_categories WHERE asset_category_id = a.asset_category_id;
    SELECT * INTO n FROM fn_asset_nbv(p_asset_id, p_date);
    SELECT account_code INTO v_cost FROM chart_of_accounts WHERE account_id = c.cost_account_id;
    SELECT account_code INTO v_ad   FROM chart_of_accounts WHERE account_id = c.acc_dep_account_id;
    SELECT ca.account_code INTO v_bank FROM bank_accounts b JOIN chart_of_accounts ca ON ca.account_id = b.gl_account_id
     WHERE b.bank_account_id = p_bank_account_id;
    v_gain := p_proceeds - n.carrying_amount;

    v_je := fn_post_journal(p_date, 'Disposal of ' || a.asset_tag || ' ' || a.name, 'asset_disposal', p_asset_id, jsonb_build_array(
        jsonb_build_object('acc', COALESCE(v_bank,'1010'), 'dr', p_proceeds, 'desc','Disposal proceeds'),
        jsonb_build_object('acc', v_ad,   'dr', n.accumulated_depreciation, 'office', a.office_id, 'desc','Remove accumulated depreciation'),
        jsonb_build_object('acc', v_cost, 'cr', n.gross, 'office', a.office_id, 'desc','Remove cost'),
        jsonb_build_object('acc', CASE WHEN v_gain >= 0 THEN '4700' ELSE '7200' END, 'cr', v_gain, 'office', a.office_id,
                           'desc', CASE WHEN v_gain >= 0 THEN 'Gain on disposal' ELSE 'Loss on disposal' END)), p_user);
    INSERT INTO asset_disposals (asset_id, disposal_date, disposal_type, proceeds, carrying_amount, gain_loss, buyer,
                                 bank_account_id, approved_by, journal_entry_id)
    VALUES (p_asset_id, p_date, p_type, p_proceeds, n.carrying_amount, v_gain, p_buyer, p_bank_account_id, p_approver, v_je);
    UPDATE fixed_assets SET status = 'disposed', disposal_date = p_date WHERE asset_id = p_asset_id;
    UPDATE asset_assignments SET returned_date = p_date WHERE asset_id = p_asset_id AND returned_date IS NULL;
    RETURN v_je;
END $$;


/* ---------- 22.5 Leases (IFRS 16) & loans ---------- */

CREATE OR REPLACE FUNCTION fn_generate_lease_schedule(p_lease_id BIGINT) RETURNS NUMERIC
LANGUAGE plpgsql AS $$
DECLARE
    l leases%ROWTYPE; v_r NUMERIC; v_step INT; v_pv NUMERIC := 0; v_pay NUMERIC; k INT; v_bal NUMERIC;
    v_int NUMERIC; v_rou_usd NUMERIC; v_dep NUMERIC; v_pay_k NUMERIC;
BEGIN
    SELECT * INTO l FROM leases WHERE lease_id = p_lease_id;
    IF l.role <> 'lessee' OR l.exemption IS NOT NULL THEN RETURN 0; END IF;
    DELETE FROM lease_schedule WHERE lease_id = p_lease_id;
    v_r := l.discount_rate_pct / 100 / 12;
    v_step := CASE l.payment_frequency WHEN 'monthly' THEN 1 WHEN 'quarterly' THEN 3 ELSE 12 END;

    -- present value of all payments (escalating once a year)
    FOR k IN 0 .. l.term_months - 1 LOOP
        IF k % v_step = 0 THEN
            v_pay := l.payment_amount * power(1 + l.annual_escalation_pct / 100, k / 12);
            v_pv  := v_pv + v_pay / power(1 + v_r, CASE WHEN l.payment_timing = 'advance' THEN k ELSE k + v_step END);
        END IF;
    END LOOP;
    v_pv := round(v_pv, 2);
    v_rou_usd := round(v_pv * l.commencement_fx_rate + l.initial_direct_costs - l.lease_incentives, 2);
    v_dep := round(v_rou_usd / l.term_months, 2);

    v_bal := v_pv;
    FOR k IN 0 .. l.term_months - 1 LOOP
        v_pay_k := CASE WHEN k % v_step = 0 THEN round(l.payment_amount * power(1 + l.annual_escalation_pct / 100, k / 12), 2) ELSE 0 END;
        IF l.payment_timing = 'advance' THEN
            v_int := round((v_bal - v_pay_k) * v_r, 2);
        ELSE
            v_int := round(v_bal * v_r, 2);
        END IF;
        IF k = l.term_months - 1 THEN                        -- clear rounding in the last period
            v_int := v_pay_k - v_bal;
            IF v_int < 0 THEN v_int := 0; END IF;
        END IF;
        INSERT INTO lease_schedule (lease_id, period_no, period_date, opening_liability, payment, interest, principal,
                                    closing_liability, rou_depreciation)
        VALUES (p_lease_id, k + 1, (date_trunc('month', l.commencement_date) + make_interval(months => k))::DATE,
                v_bal, v_pay_k, v_int, v_pay_k - v_int,
                CASE WHEN k = l.term_months - 1 THEN 0 ELSE v_bal - v_pay_k + v_int END,
                CASE WHEN k = l.term_months - 1 THEN v_rou_usd - v_dep * (l.term_months - 1) ELSE v_dep END);
        v_bal := v_bal - v_pay_k + v_int;
    END LOOP;
    UPDATE leases SET initial_liability = v_pv, initial_rou_asset = v_rou_usd WHERE lease_id = p_lease_id;
    RETURN v_pv;
END $$;

-- Recognise a new lease at commencement: Dr ROU asset / Cr lease liability (non-cash)
CREATE OR REPLACE FUNCTION fn_recognise_lease(p_lease_id BIGINT, p_user BIGINT DEFAULT NULL) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE l leases%ROWTYPE; v_je BIGINT;
BEGIN
    SELECT * INTO l FROM leases WHERE lease_id = p_lease_id FOR UPDATE;
    IF l.status <> 'draft' THEN RAISE EXCEPTION 'Lease % is already %', l.lease_number, l.status; END IF;
    UPDATE leases SET commencement_fx_rate = fn_fx_rate(currency_code, commencement_date) WHERE lease_id = p_lease_id;
    PERFORM fn_generate_lease_schedule(p_lease_id);
    SELECT * INTO l FROM leases WHERE lease_id = p_lease_id;
    v_je := fn_post_journal(l.commencement_date, 'Lease commencement ' || l.lease_number || ' - ' || l.description, 'lease', p_lease_id,
        jsonb_build_array(
            jsonb_build_object('acc', l.rou_account_code, 'dr', l.initial_rou_asset, 'office', l.office_id, 'desc','Right-of-use asset'),
            jsonb_build_object('acc','2700', 'cr', round(l.initial_liability * l.commencement_fx_rate, 2), 'office', l.office_id, 'desc','Lease liability'),
            jsonb_build_object('acc','2100', 'cr', l.initial_direct_costs - l.lease_incentives, 'desc','Initial direct costs less incentives')),
        p_user);
    UPDATE leases SET status = 'active', recognised_journal_id = v_je,
                      liability_usd_balance = round(initial_liability * commencement_fx_rate, 2), last_fx_rate = commencement_fx_rate
     WHERE lease_id = p_lease_id;
    RETURN v_je;
END $$;

/* Monthly lease accounting for all active leases for the month containing p_month:
   (1) remeasure the foreign-currency liability to this month's rate (IAS 21, P&L)
   (2) interest & ROU depreciation (non-cash journal)
   (3) the cash payment (pure cash journal: interest part -> financing/interest paid,
       principal part -> financing/lease principal) */
CREATE OR REPLACE FUNCTION fn_post_lease_month(p_month DATE, p_user BIGINT DEFAULT NULL) RETURNS INTEGER
LANGUAGE plpgsql AS $$
DECLARE
    v_m DATE := date_trunc('month', p_month)::DATE; v_end DATE; l RECORD; s lease_schedule%ROWTYPE;
    v_rate NUMERIC; v_fx NUMERIC; v_int NUMERIC; v_pay NUMERIC; v_bank TEXT; v_count INT := 0; v_je BIGINT;
BEGIN
    v_end := (v_m + INTERVAL '1 month - 1 day')::DATE;
    FOR l IN SELECT * FROM leases WHERE role = 'lessee' AND status = 'active' AND exemption IS NULL ORDER BY lease_id LOOP
        SELECT * INTO s FROM lease_schedule WHERE lease_id = l.lease_id AND period_date = v_m AND NOT is_posted;
        CONTINUE WHEN NOT FOUND;
        v_rate := fn_fx_rate(l.currency_code, v_end);

        -- (1) FX remeasurement of the opening liability
        v_fx := round(s.opening_liability * v_rate, 2) - l.liability_usd_balance;
        IF v_fx <> 0 THEN
            PERFORM fn_post_journal(v_end, 'Lease liability FX remeasurement ' || l.lease_number, 'fx_revaluation', l.lease_id,
                jsonb_build_array(jsonb_build_object('acc', CASE WHEN v_fx > 0 THEN '7300' ELSE '4800' END, 'dr', v_fx, 'office', l.office_id,
                                                     'desc','Exchange difference on lease liability'),
                                  jsonb_build_object('acc','2700','cr', v_fx, 'office', l.office_id, 'desc','Lease liability remeasured')), p_user);
        END IF;

        -- (2) interest + depreciation
        v_int := round(s.interest * v_rate, 2);
        v_je := fn_post_journal(v_end, 'Lease interest & ROU depreciation ' || l.lease_number, 'lease', l.lease_id,
            jsonb_build_array(
                jsonb_build_object('acc','8000','dr', v_int, 'office', l.office_id, 'desc','Interest on lease liability'),
                jsonb_build_object('acc','2705','cr', v_int, 'office', l.office_id, 'desc','Lease interest payable'),
                jsonb_build_object('acc','7010','dr', s.rou_depreciation, 'office', l.office_id, 'desc','Depreciation of right-of-use asset'),
                jsonb_build_object('acc', l.rou_acc_dep_account_code, 'cr', s.rou_depreciation, 'office', l.office_id, 'desc','Accumulated depreciation - ROU')),
            p_user);

        -- (3) payment from the branch's own bank account (or head office USD)
        v_pay := round(s.payment * v_rate, 2);
        IF v_pay > 0 THEN
            SELECT a.account_code INTO v_bank
              FROM bank_accounts b JOIN chart_of_accounts a ON a.account_id = b.gl_account_id
             WHERE b.currency_code = l.currency_code AND b.is_active AND b.account_type IN ('current','fca')
             ORDER BY (b.office_id = l.office_id) DESC NULLS LAST, b.bank_account_id LIMIT 1;
            PERFORM fn_post_journal(CASE WHEN l.payment_timing = 'advance' THEN v_m ELSE v_end END,
                'Lease payment ' || l.lease_number || ' - ' || l.description, 'lease_payment', l.lease_id,
                jsonb_build_array(
                    jsonb_build_object('acc','2705','dr', v_int, 'office', l.office_id, 'vendor', l.vendor_id, 'desc','Lease interest paid'),
                    jsonb_build_object('acc','2700','dr', v_pay - v_int, 'office', l.office_id, 'vendor', l.vendor_id, 'desc','Lease principal paid'),
                    jsonb_build_object('acc', COALESCE(v_bank,'1010'), 'cr', v_pay, 'desc','Rent paid to landlord')), p_user);
        ELSIF v_int > 0 THEN
            -- rent-free month: interest stays in the liability
            PERFORM fn_post_journal(v_end, 'Lease interest capitalised ' || l.lease_number, 'lease', l.lease_id,
                jsonb_build_array(jsonb_build_object('acc','2705','dr', v_int), jsonb_build_object('acc','2700','cr', v_int)), p_user);
        END IF;

        UPDATE lease_schedule SET is_posted = TRUE, journal_entry_id = v_je WHERE lease_id = l.lease_id AND period_no = s.period_no;
        UPDATE leases SET liability_usd_balance = round(s.closing_liability * v_rate, 2), last_fx_rate = v_rate,
                          status = CASE WHEN s.period_no = term_months THEN 'expired' ELSE status END
         WHERE lease_id = l.lease_id;
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END $$;

CREATE OR REPLACE FUNCTION fn_generate_loan_schedule(p_loan_id BIGINT) RETURNS NUMERIC
LANGUAGE plpgsql AS $$
DECLARE b borrowings%ROWTYPE; v_r NUMERIC; v_inst NUMERIC; v_bal NUMERIC; k INT; v_int NUMERIC;
BEGIN
    SELECT * INTO b FROM borrowings WHERE loan_id = p_loan_id;
    DELETE FROM loan_schedule WHERE loan_id = p_loan_id;
    v_r := b.interest_rate_pct / 100 / 12;
    v_inst := round(b.principal * v_r / (1 - power(1 + v_r, -b.term_months)), 2);
    v_bal := b.principal;
    FOR k IN 1 .. b.term_months LOOP
        v_int := round(v_bal * v_r, 2);
        INSERT INTO loan_schedule (loan_id, period_no, due_date, opening_balance, instalment, interest, principal, closing_balance)
        VALUES (p_loan_id, k, (b.drawdown_date + make_interval(months => k))::DATE, v_bal,
                CASE WHEN k = b.term_months THEN v_bal + v_int ELSE v_inst END, v_int,
                CASE WHEN k = b.term_months THEN v_bal ELSE v_inst - v_int END,
                CASE WHEN k = b.term_months THEN 0 ELSE v_bal - (v_inst - v_int) END);
        v_bal := CASE WHEN k = b.term_months THEN 0 ELSE v_bal - (v_inst - v_int) END;
    END LOOP;
    UPDATE borrowings SET monthly_instalment = v_inst WHERE loan_id = p_loan_id;
    RETURN v_inst;
END $$;

-- Pay loan instalments due in the month: Dr interest (financing) + Dr loan / Cr bank
CREATE OR REPLACE FUNCTION fn_post_loan_month(p_month DATE, p_user BIGINT DEFAULT NULL) RETURNS INTEGER
LANGUAGE plpgsql AS $$
DECLARE r RECORD; v_bank TEXT; v_count INT := 0; v_je BIGINT;
BEGIN
    FOR r IN SELECT s.*, b.loan_number, b.lender, b.bank_account_id
               FROM loan_schedule s JOIN borrowings b USING (loan_id)
              WHERE b.status = 'active' AND NOT s.is_posted
                AND s.due_date BETWEEN date_trunc('month', p_month)::DATE AND (date_trunc('month', p_month) + INTERVAL '1 month - 1 day')::DATE
    LOOP
        SELECT a.account_code INTO v_bank FROM bank_accounts k JOIN chart_of_accounts a ON a.account_id = k.gl_account_id
         WHERE k.bank_account_id = r.bank_account_id;
        v_je := fn_post_journal(r.due_date, format('Loan instalment %s - %s', r.loan_number, r.lender), 'loan', r.loan_id,
            jsonb_build_array(jsonb_build_object('acc','8010','dr', r.interest, 'desc','Interest on borrowings'),
                              jsonb_build_object('acc','2800','dr', r.principal, 'desc','Loan principal repaid'),
                              jsonb_build_object('acc', COALESCE(v_bank,'1010'), 'cr', r.instalment, 'desc','Loan instalment')), p_user);
        UPDATE loan_schedule SET is_posted = TRUE, journal_entry_id = v_je WHERE loan_id = r.loan_id AND period_no = r.period_no;
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END $$;


/* ---------- 22.6 Tax compliance ---------- */

-- Balance movement of an account in a period (debit - credit), excluding given journal sources
CREATE OR REPLACE FUNCTION fn_account_movement(p_code TEXT, p_from DATE, p_to DATE, p_exclude_sources TEXT[] DEFAULT '{}')
RETURNS NUMERIC LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(jl.debit - jl.credit), 0)
      FROM journal_lines jl
      JOIN journal_entries je ON je.journal_entry_id = jl.journal_entry_id
      JOIN chart_of_accounts a ON a.account_id = jl.account_id
     WHERE a.account_code = p_code AND je.status IN ('posted','reversed')
       AND je.entry_date BETWEEN p_from AND p_to
       AND NOT (je.source_type = ANY (p_exclude_sources));
$$;

CREATE OR REPLACE FUNCTION fn_account_balance(p_code TEXT, p_as_at DATE) RETURNS NUMERIC
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(jl.debit - jl.credit), 0)
      FROM journal_lines jl
      JOIN journal_entries je ON je.journal_entry_id = jl.journal_entry_id
      JOIN chart_of_accounts a ON a.account_id = jl.account_id
     WHERE a.account_code = p_code AND je.status IN ('posted','reversed') AND je.entry_date <= p_as_at;
$$;

-- ZIMRA VAT7 return for a month (output tax on 2200, input tax on 2210)
CREATE OR REPLACE FUNCTION fn_prepare_vat_return(p_month DATE, p_prepared_by BIGINT DEFAULT NULL) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE v_from DATE := date_trunc('month', p_month)::DATE; v_to DATE; v_out NUMERIC; v_in NUMERIC; v_id BIGINT; v_sales NUMERIC;
BEGIN
    v_to := (v_from + INTERVAL '1 month - 1 day')::DATE;
    v_out := -fn_account_movement('2200', v_from, v_to, ARRAY['tax_payment']);
    v_in  :=  fn_account_movement('2210', v_from, v_to, ARRAY['tax_payment']);
    SELECT COALESCE(SUM(subtotal), 0) INTO v_sales FROM invoices WHERE invoice_date BETWEEN v_from AND v_to AND status <> 'void';
    INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, credits_amount,
                             status, prepared_by)
    VALUES ('VAT-' || to_char(v_from, 'YYYY-MM'), 'VAT', (SELECT office_id FROM offices WHERE is_head_office), v_from, v_to,
            (v_from + INTERVAL '1 month' + INTERVAL '24 days')::DATE, v_out, v_in, 'draft', p_prepared_by)
    RETURNING tax_return_id INTO v_id;
    INSERT INTO tax_return_lines VALUES
        (v_id, 1, 'VAT7-1', 'Value of taxable supplies (all invoices, excl. VAT)', v_sales),
        (v_id, 2, 'VAT7-2', 'Output tax (15.5%)', v_out),
        (v_id, 3, 'VAT7-3', 'Input tax claimable', v_in),
        (v_id, 4, 'VAT7-4', 'Net VAT payable / (refundable)', v_out - v_in);
    RETURN v_id;
END $$;

-- Monthly payroll returns from approved payroll runs: ZIMRA P2 (PAYE + AIDS levy), NSSA P4, ZIMDEF,
-- and the branch payroll-tax returns (SARS EMP201, KRA P10, HMRC RTI/FPS)
CREATE OR REPLACE FUNCTION fn_prepare_payroll_returns(p_month DATE, p_prepared_by BIGINT DEFAULT NULL) RETURNS INTEGER
LANGUAGE plpgsql AS $$
DECLARE v_from DATE := date_trunc('month', p_month)::DATE; v_to DATE; r RECORD; v_id BIGINT; v_n INT := 0;
BEGIN
    v_to := (v_from + INTERVAL '1 month - 1 day')::DATE;
    FOR r IN
        SELECT pr.country_code,
               SUM(p.paye_tax * pr.exchange_rate) paye, SUM(p.aids_levy * pr.exchange_rate) aids,
               SUM((p.nssa_employee + p.employer_nssa + p.employer_wcif) * pr.exchange_rate) nssa,
               SUM(p.employer_zimdef * pr.exchange_rate) zimdef,
               SUM((p.paye_tax + p.nssa_employee + p.employer_nssa + p.employer_wcif) * pr.exchange_rate) branch,
               SUM(p.gross_pay * pr.exchange_rate) gross
          FROM payroll_runs pr JOIN payslips p USING (payroll_run_id)
         WHERE pr.period_start = v_from AND pr.status IN ('approved','paid')
         GROUP BY pr.country_code
    LOOP
        IF r.country_code = 'ZW' THEN
            INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, status, prepared_by)
            VALUES ('P2-' || to_char(v_from,'YYYY-MM'), 'PAYE', (SELECT office_id FROM offices WHERE is_head_office), v_from, v_to,
                    (v_from + INTERVAL '1 month' + INTERVAL '9 days')::DATE, round(r.paye + r.aids, 2), 'draft', p_prepared_by)
            RETURNING tax_return_id INTO v_id;
            INSERT INTO tax_return_lines VALUES (v_id,1,'P2-A','Gross remuneration', round(r.gross,2)),
                                                (v_id,2,'P2-B','PAYE deducted', round(r.paye,2)),
                                                (v_id,3,'P2-C','AIDS levy (3% of PAYE)', round(r.aids,2));
            INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, status, prepared_by)
            VALUES ('P4-' || to_char(v_from,'YYYY-MM'), 'NSSA', (SELECT office_id FROM offices WHERE is_head_office), v_from, v_to,
                    (v_from + INTERVAL '1 month' + INTERVAL '9 days')::DATE, round(r.nssa, 2), 'draft', p_prepared_by);
            INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, status, prepared_by)
            VALUES ('ZIMDEF-' || to_char(v_from,'YYYY-MM'), 'ZIMDEF', (SELECT office_id FROM offices WHERE is_head_office), v_from, v_to,
                    (v_from + INTERVAL '1 month' + INTERVAL '9 days')::DATE, round(r.zimdef, 2), 'draft', p_prepared_by);
            v_n := v_n + 3;
        ELSE
            INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, status, prepared_by)
            SELECT tt.tax_code || '-' || to_char(v_from,'YYYY-MM'), tt.tax_code,
                   (SELECT office_id FROM offices o WHERE o.country_code = r.country_code ORDER BY o.office_id LIMIT 1),
                   v_from, v_to, (v_from + INTERVAL '1 month' + make_interval(days => COALESCE(tt.due_day, 7) - 1))::DATE,
                   round(r.branch, 2), 'draft', p_prepared_by
              FROM tax_types tt WHERE tt.tax_code = r.country_code || '_PAYE';
            v_n := v_n + 1;
        END IF;
    END LOOP;
    RETURN v_n;
END $$;

-- Branch VAT/GST return (SARS VAT201, KRA VAT3, HMRC VAT100, UAE VAT201): output tax on the branch account.
-- Branch input VAT is expensed in this model (see fn_approve_vendor_bill), so the return is output tax only.
CREATE OR REPLACE FUNCTION fn_prepare_branch_vat_return(p_tax_code TEXT, p_from DATE, p_to DATE, p_prepared_by BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE tt tax_types%ROWTYPE; v_out NUMERIC; v_id BIGINT;
BEGIN
    SELECT * INTO tt FROM tax_types WHERE tax_code = p_tax_code;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unknown tax type %', p_tax_code; END IF;
    v_out := -fn_account_movement(tt.liability_account_code, p_from, p_to, ARRAY['tax_payment']);
    IF v_out = 0 THEN RETURN NULL; END IF;
    INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, status, prepared_by)
    VALUES (p_tax_code || '-' || to_char(p_to, 'YYYY-MM'), p_tax_code,
            (SELECT o.office_id FROM offices o JOIN tax_authorities a ON a.country_code = o.country_code
              WHERE a.authority_code = tt.authority_code ORDER BY o.office_id LIMIT 1),
            p_from, p_to, (date_trunc('month', p_to) + INTERVAL '1 month' + make_interval(days => COALESCE(tt.due_day, 25) - 1))::DATE,
            v_out, 'draft', p_prepared_by)
    RETURNING tax_return_id INTO v_id;
    RETURN v_id;
END $$;

-- Four QPD instalments of estimated corporate income tax (10/25/30/35%)
CREATE OR REPLACE FUNCTION fn_create_qpds(p_year INT, p_estimated_tax NUMERIC, p_prepared_by BIGINT DEFAULT NULL) RETURNS INTEGER
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, status, prepared_by, notes)
    SELECT format('QPD%s-%s', q.n, p_year), 'CIT_QPD', (SELECT office_id FROM offices WHERE is_head_office),
           make_date(p_year, q.n * 3 - 2, 1), (make_date(p_year, q.n * 3, 1) + INTERVAL '1 month - 1 day')::DATE,
           q.due, round(p_estimated_tax * q.pct / 100, 2), 'draft', p_prepared_by,
           format('QPD %s: %s%% of estimated tax of USD %s', q.n, q.pct, to_char(p_estimated_tax, 'FM999,999,990.00'))
      FROM (VALUES (1, 10, make_date(p_year,3,25)), (2, 25, make_date(p_year,6,25)),
                   (3, 30, make_date(p_year,9,25)), (4, 35, make_date(p_year,12,20))) AS q(n, pct, due);
    RETURN 4;
END $$;

CREATE OR REPLACE FUNCTION fn_file_tax_return(p_return_id BIGINT, p_date DATE DEFAULT CURRENT_DATE, p_ack TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    UPDATE tax_returns SET status = 'filed', filed_date = p_date,
                           acknowledgement_ref = COALESCE(p_ack, 'ACK-' || upper(substr(md5(tax_return_id::TEXT || p_date::TEXT), 1, 10)))
     WHERE tax_return_id = p_return_id AND status IN ('draft','overdue','not_started');
    IF NOT FOUND THEN RAISE EXCEPTION 'Return % cannot be filed in its current status', p_return_id; END IF;
END $$;

-- Pay a return: clears the liability accounts of the tax type against the bank (pure cash journal)
CREATE OR REPLACE FUNCTION fn_pay_tax_return(p_return_id BIGINT, p_bank_account_id BIGINT, p_date DATE DEFAULT CURRENT_DATE,
                                             p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE t tax_returns%ROWTYPE; tt tax_types%ROWTYPE; v_bank TEXT; v_lines JSONB; v_je BIGINT; v_aids NUMERIC;
BEGIN
    SELECT * INTO t FROM tax_returns WHERE tax_return_id = p_return_id FOR UPDATE;
    IF t.status = 'paid' THEN RAISE EXCEPTION 'Return % is already paid', t.return_number; END IF;
    SELECT * INTO tt FROM tax_types WHERE tax_code = t.tax_code;
    SELECT a.account_code INTO v_bank FROM bank_accounts b JOIN chart_of_accounts a ON a.account_id = b.gl_account_id
     WHERE b.bank_account_id = p_bank_account_id;

    IF t.tax_code = 'VAT' THEN
        v_lines := jsonb_build_array(jsonb_build_object('acc','2200','dr', t.gross_amount, 'desc','Output VAT settled'),
                                     jsonb_build_object('acc','2210','cr', t.credits_amount, 'desc','Input VAT claimed'));
    ELSIF t.tax_code = 'PAYE' THEN
        SELECT amount INTO v_aids FROM tax_return_lines WHERE tax_return_id = p_return_id AND box_code = 'P2-C';
        v_lines := jsonb_build_array(jsonb_build_object('acc','2400','dr', t.gross_amount - COALESCE(v_aids,0), 'desc','PAYE remitted'),
                                     jsonb_build_object('acc','2405','dr', COALESCE(v_aids,0), 'desc','AIDS levy remitted'));
    ELSE
        v_lines := jsonb_build_array(jsonb_build_object('acc', tt.liability_account_code, 'dr', t.amount_due, 'desc', tt.name));
    END IF;
    v_lines := v_lines
      || jsonb_build_array(jsonb_build_object('acc','6900','dr', t.penalty_amount + t.interest_amount, 'desc','Tax penalties & interest (not deductible)'),
                           jsonb_build_object('acc', v_bank, 'cr', t.amount_due + t.penalty_amount + t.interest_amount,
                                              'desc','Payment to ' || tt.authority_code));
    v_je := fn_post_journal(p_date, format('%s payment %s', tt.authority_code, t.return_number), 'tax_payment', p_return_id, v_lines, p_user);
    UPDATE tax_returns SET status = 'paid', paid_date = p_date, amount_paid = amount_due + penalty_amount + interest_amount,
                           bank_account_id = p_bank_account_id, journal_entry_id = v_je,
                           filed_date = COALESCE(filed_date, p_date)
     WHERE tax_return_id = p_return_id;
    RETURN v_je;
END $$;

-- Current tax provision to date: (profit before tax YTD x 24.72%) - provision already booked (IAS 12)
CREATE OR REPLACE FUNCTION fn_accrue_income_tax(p_as_at DATE, p_user BIGINT DEFAULT NULL) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE v_from DATE := date_trunc('year', p_as_at)::DATE; v_pbt NUMERIC; v_rate NUMERIC; v_booked NUMERIC; v_need NUMERIC;
BEGIN
    SELECT COALESCE(SUM(jl.credit - jl.debit), 0) INTO v_pbt
      FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id)
      JOIN chart_of_accounts a ON a.account_id = jl.account_id
     WHERE je.status IN ('posted','reversed') AND je.entry_date BETWEEN v_from AND p_as_at
       AND a.account_type IN ('revenue','expense') AND a.account_code NOT LIKE '90%';
    v_rate := fn_stat_rate('ZW','CIT',p_as_at) * (1 + fn_stat_rate('ZW','AIDS_LEVY',p_as_at) / 100);
    v_booked := fn_account_movement('9000', v_from, p_as_at);
    v_need := round(GREATEST(v_pbt, 0) * v_rate / 100, 2) - v_booked;
    IF v_need = 0 THEN RETURN NULL; END IF;
    RETURN fn_post_journal(p_as_at, 'Current income tax provision to ' || to_char(p_as_at, 'DD Mon YYYY'), 'tax', NULL,
        jsonb_build_array(jsonb_build_object('acc','9000','dr', v_need, 'desc','Current tax - Zimbabwe (24% + 3% AIDS levy)'),
                          jsonb_build_object('acc','2260','cr', v_need, 'desc','Income tax payable (ZIMRA)')), p_user);
END $$;

-- Deferred tax working (IAS 12): temporary differences at a date
CREATE OR REPLACE FUNCTION fn_deferred_tax_schedule(p_as_at DATE)
RETURNS TABLE (item TEXT, carrying_amount NUMERIC, tax_base NUMERIC, temporary_difference NUMERIC, deferred_tax NUMERIC)
LANGUAGE sql STABLE AS $$
    WITH rate AS (SELECT fn_stat_rate('ZW','CIT',p_as_at) * (1 + fn_stat_rate('ZW','AIDS_LEVY',p_as_at)/100) / 100 AS r),
    ppe AS (
        SELECT c.name AS item, SUM(n.carrying_amount) AS ca,
               SUM(CASE WHEN c.asset_class IN ('land','investment_property') THEN fa.cost
                        ELSE GREATEST(COALESCE(fa.tax_value_opening, fa.cost)
                             - fa.cost * c.tax_wear_tear_rate_pct / 100
                               * GREATEST(extract(year FROM p_as_at) - extract(year FROM COALESCE(fa.opening_date, fa.acquisition_date))
                                          + CASE WHEN fa.opening_date IS NULL THEN 1 ELSE 0 END, 0), 0) END) AS tb
          FROM fixed_assets fa
          JOIN asset_categories c ON c.asset_category_id = fa.asset_category_id
          CROSS JOIN LATERAL fn_asset_nbv(fa.asset_id, p_as_at) n
         WHERE fa.acquisition_date <= p_as_at AND (fa.disposal_date IS NULL OR fa.disposal_date > p_as_at)
         GROUP BY c.name
    ),
    other AS (
        SELECT 'Right-of-use assets' AS item, fn_account_balance('1600', p_as_at) + fn_account_balance('1601', p_as_at)
                 + fn_account_balance('1610', p_as_at) + fn_account_balance('1611', p_as_at) AS ca, 0::NUMERIC AS tb
        UNION ALL
        SELECT 'Lease liabilities', fn_account_balance('2700', p_as_at) + fn_account_balance('2705', p_as_at), 0
        UNION ALL
        SELECT 'Expected credit loss allowance', fn_account_balance('1105', p_as_at), 0
        UNION ALL
        SELECT 'Leave pay & bonus accruals', fn_account_balance('2510', p_as_at) + fn_account_balance('2520', p_as_at), 0
    )
    SELECT item, round(ca, 2), round(tb, 2), round(ca - tb, 2), round((ca - tb) * (SELECT r FROM rate), 2)
      FROM (SELECT * FROM ppe UNION ALL SELECT * FROM other) x
     WHERE ca <> 0 OR tb <> 0
     ORDER BY 1;
$$;


/* ---------- 22.7 Other period-end routines ---------- */

-- IFRS 9 simplified approach: set the ECL allowance to the provision-matrix requirement
CREATE OR REPLACE FUNCTION fn_update_ecl_provision(p_as_at DATE, p_user BIGINT DEFAULT NULL) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE v_required NUMERIC; v_current NUMERIC; v_move NUMERIC;
BEGIN
    WITH open_items AS (
        SELECT i.invoice_id, i.due_date,
               i.total_amount * i.exchange_rate
                 - COALESCE((SELECT SUM(pa.amount) FROM payment_allocations pa JOIN payments p ON p.payment_id = pa.payment_id
                              WHERE pa.invoice_id = i.invoice_id AND p.payment_date <= p_as_at), 0) * i.exchange_rate AS bal
          FROM invoices i
         WHERE i.status <> 'draft' AND i.status <> 'void' AND i.invoice_date <= p_as_at
    )
    SELECT COALESCE(SUM(o.bal * m.loss_rate_pct / 100), 0) INTO v_required
      FROM open_items o
      JOIN ecl_provision_matrix m ON GREATEST(p_as_at - o.due_date, 0) >= m.min_days
                                 AND (m.max_days IS NULL OR GREATEST(p_as_at - o.due_date, 0) <= m.max_days)
     WHERE o.bal > 0.005;
    v_current := -fn_account_balance('1105', p_as_at);
    v_move := round(v_required - v_current, 2);
    IF v_move = 0 THEN RETURN NULL; END IF;
    RETURN fn_post_journal(p_as_at, 'Expected credit loss allowance update (IFRS 9)', 'ecl', NULL,
        jsonb_build_array(jsonb_build_object('acc','7100','dr', v_move, 'desc','Impairment loss on trade receivables'),
                          jsonb_build_object('acc','1105','cr', v_move, 'desc','Loss allowance')), p_user);
END $$;

-- Move money between two company bank accounts (USD value). Not a cash flow - both sides are cash.
CREATE OR REPLACE FUNCTION fn_bank_transfer(p_from_bank BIGINT, p_to_bank BIGINT, p_amount_usd NUMERIC, p_date DATE,
                                            p_description TEXT DEFAULT 'Inter-account transfer', p_user BIGINT DEFAULT NULL)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_from TEXT; v_to TEXT;
BEGIN
    SELECT a.account_code INTO v_from FROM bank_accounts b JOIN chart_of_accounts a ON a.account_id = b.gl_account_id WHERE b.bank_account_id = p_from_bank;
    SELECT a.account_code INTO v_to   FROM bank_accounts b JOIN chart_of_accounts a ON a.account_id = b.gl_account_id WHERE b.bank_account_id = p_to_bank;
    RETURN fn_post_journal(p_date, p_description, 'transfer', NULL,
        jsonb_build_array(jsonb_build_object('acc', v_to, 'dr', p_amount_usd), jsonb_build_object('acc', v_from, 'cr', p_amount_usd)), p_user);
END $$;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  23a_reporting_core.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   16. REPORTING VIEWS
   ===================================================================================== */

-- 16.1 Monthly utilisation per consultant (billable hours / available capacity)
CREATE OR REPLACE VIEW v_employee_utilization_monthly AS
WITH hrs AS (
    SELECT te.employee_id,
           date_trunc('month', te.work_date)::DATE                AS month_start,
           SUM(te.hours)                                          AS total_hours,
           COALESCE(SUM(te.hours) FILTER (WHERE te.is_billable),0) AS billable_hours,
           COALESCE(SUM(te.billable_amount),0)                    AS billable_value
      FROM time_entries te
      JOIN timesheets ts ON ts.timesheet_id = te.timesheet_id
     WHERE ts.status IN ('submitted','approved')
     GROUP BY te.employee_id, date_trunc('month', te.work_date)
)
SELECT e.employee_id,
       e.employee_number,
       e.first_name || ' ' || e.last_name                                   AS employee_name,
       jg.name                                                              AS grade,
       d.name                                                               AS department,
       h.month_start,
       cap.capacity_hours,
       h.total_hours,
       h.billable_hours,
       h.billable_value,
       round(100 * h.billable_hours / NULLIF(cap.capacity_hours, 0), 1)     AS utilization_pct,
       e.target_utilization_pct,
       round(100 * h.billable_hours / NULLIF(cap.capacity_hours, 0), 1) - e.target_utilization_pct AS variance_to_target_pct
  FROM hrs h
  JOIN employees e        ON e.employee_id = h.employee_id
  LEFT JOIN job_grades jg ON jg.job_grade_id = e.job_grade_id
  LEFT JOIN departments d ON d.department_id = e.department_id
  LEFT JOIN offices o     ON o.office_id = e.office_id
  CROSS JOIN LATERAL (
      SELECT fn_working_days(h.month_start, (h.month_start + INTERVAL '1 month - 1 day')::DATE,
                             COALESCE(o.country_code, 'ZW')) * round(e.standard_hours_per_week / 5, 2) AS capacity_hours
  ) cap;

-- 16.2 Project financials: budget vs actual, WIP, margin
CREATE OR REPLACE VIEW v_project_financials AS
WITH t AS (
    SELECT te.project_id,
           SUM(te.hours)                                                    AS actual_hours,
           SUM(te.cost_amount)                                              AS labour_cost,
           SUM(te.billable_amount)                                          AS billable_value,
           SUM(te.billable_amount) FILTER (WHERE te.invoice_line_id IS NULL AND ts.status = 'approved') AS unbilled_wip
      FROM time_entries te JOIN timesheets ts ON ts.timesheet_id = te.timesheet_id
     WHERE te.project_id IS NOT NULL AND ts.status IN ('submitted','approved')
     GROUP BY te.project_id
), x AS (
    SELECT ei.project_id, SUM(ei.amount_base) AS expense_cost
      FROM expense_items ei JOIN expense_reports er ON er.expense_report_id = ei.expense_report_id
     WHERE er.status = 'approved' AND ei.project_id IS NOT NULL
     GROUP BY ei.project_id
), s AS (
    SELECT project_id, SUM(subtotal) AS subcontractor_cost
      FROM vendor_bills WHERE status <> 'void' AND project_id IS NOT NULL
     GROUP BY project_id
), i AS (
    SELECT project_id, SUM(subtotal) AS invoiced_net, SUM(amount_paid) AS collected
      FROM invoices WHERE status NOT IN ('draft','void') AND project_id IS NOT NULL
     GROUP BY project_id
)
SELECT p.project_id,
       p.project_code,
       p.name                                   AS project_name,
       c.legal_name                             AS client,
       p.status,
       p.billing_type,
       p.currency_code,
       p.budget_hours,
       COALESCE(t.actual_hours, 0)              AS actual_hours,
       round(100 * COALESCE(t.actual_hours,0) / NULLIF(p.budget_hours, 0), 1) AS hours_burn_pct,
       p.budget_fees,
       COALESCE(t.billable_value, 0)            AS billable_value,
       COALESCE(i.invoiced_net, 0)              AS invoiced_net,
       COALESCE(i.collected, 0)                 AS collected,
       CASE WHEN p.billing_type IN ('fixed_fee','milestone')        -- earned but not yet invoiced (negative = billed in advance)
            THEN round(p.budget_fees * p.completion_pct / 100, 2) - COALESCE(i.invoiced_net, 0)
            WHEN p.billing_type = 'retainer' THEN 0                    -- retainer hours are covered by the monthly fee
            ELSE COALESCE(t.unbilled_wip, 0) END                              AS unbilled_wip,
       CASE WHEN p.billing_type IN ('fixed_fee','milestone')
            THEN round(p.budget_fees * p.completion_pct / 100, 2)
            WHEN p.billing_type = 'retainer' THEN COALESCE(i.invoiced_net, 0)
            ELSE COALESCE(t.billable_value, 0) END                            AS revenue_earned,
       COALESCE(t.labour_cost, 0)               AS labour_cost,
       COALESCE(x.expense_cost, 0)              AS expense_cost,
       COALESCE(s.subcontractor_cost, 0)        AS subcontractor_cost,
       CASE WHEN p.billing_type IN ('fixed_fee','milestone')
            THEN round(p.budget_fees * p.completion_pct / 100, 2)
            WHEN p.billing_type = 'retainer' THEN COALESCE(i.invoiced_net, 0)
            ELSE COALESCE(t.billable_value, 0) END
         - COALESCE(t.labour_cost, 0) - COALESCE(x.expense_cost, 0) - COALESCE(s.subcontractor_cost, 0) AS gross_margin,
       round(100 * (CASE WHEN p.billing_type IN ('fixed_fee','milestone')
                         THEN p.budget_fees * p.completion_pct / 100
                         WHEN p.billing_type = 'retainer' THEN COALESCE(i.invoiced_net, 0)
                         ELSE COALESCE(t.billable_value, 0) END
                    - COALESCE(t.labour_cost,0) - COALESCE(x.expense_cost,0) - COALESCE(s.subcontractor_cost,0))
             / NULLIF(CASE WHEN p.billing_type IN ('fixed_fee','milestone')
                           THEN p.budget_fees * p.completion_pct / 100
                           WHEN p.billing_type = 'retainer' THEN COALESCE(i.invoiced_net, 0)
                           ELSE COALESCE(t.billable_value, 0) END, 0), 1)      AS gross_margin_pct
  FROM projects p
  LEFT JOIN clients c ON c.client_id = p.client_id
  LEFT JOIN t ON t.project_id = p.project_id
  LEFT JOIN x ON x.project_id = p.project_id
  LEFT JOIN s ON s.project_id = p.project_id
  LEFT JOIN i ON i.project_id = p.project_id
 WHERE NOT p.is_internal;

-- 16.3 Unbilled work in progress (approved, billable, not yet invoiced)
CREATE OR REPLACE VIEW v_unbilled_wip AS
SELECT p.project_code, p.name AS project_name, c.legal_name AS client,
       e.first_name || ' ' || e.last_name AS employee_name,
       min(te.work_date) AS earliest_date, max(te.work_date) AS latest_date,
       SUM(te.hours) AS hours, SUM(te.billable_amount) AS wip_value,
       CURRENT_DATE - min(te.work_date) AS days_unbilled
  FROM time_entries te
  JOIN timesheets ts ON ts.timesheet_id = te.timesheet_id
  JOIN projects p    ON p.project_id = te.project_id
  JOIN clients c     ON c.client_id = p.client_id
  JOIN employees e   ON e.employee_id = te.employee_id
 WHERE ts.status = 'approved' AND te.is_billable AND te.invoice_line_id IS NULL
   AND p.billing_type = 'time_and_materials'
 GROUP BY p.project_code, p.name, c.legal_name, e.first_name, e.last_name;

-- 16.4 Accounts receivable ageing
CREATE OR REPLACE VIEW v_ar_aging AS
SELECT i.invoice_id, i.invoice_number, c.client_code, c.legal_name AS client,
       i.invoice_date, i.due_date, i.currency_code, i.total_amount, i.amount_paid, i.balance_due,
       GREATEST(CURRENT_DATE - i.due_date, 0) AS days_overdue,
       CASE WHEN CURRENT_DATE <= i.due_date          THEN i.balance_due ELSE 0 END AS current_due,
       CASE WHEN CURRENT_DATE - i.due_date BETWEEN 1  AND 30 THEN i.balance_due ELSE 0 END AS days_1_30,
       CASE WHEN CURRENT_DATE - i.due_date BETWEEN 31 AND 60 THEN i.balance_due ELSE 0 END AS days_31_60,
       CASE WHEN CURRENT_DATE - i.due_date BETWEEN 61 AND 90 THEN i.balance_due ELSE 0 END AS days_61_90,
       CASE WHEN CURRENT_DATE - i.due_date > 90              THEN i.balance_due ELSE 0 END AS days_over_90
  FROM invoices i JOIN clients c ON c.client_id = i.client_id
 WHERE i.status IN ('issued','partially_paid','overdue') AND i.balance_due > 0;

CREATE OR REPLACE VIEW v_client_ar_summary AS
SELECT client_code, client, currency_code,
       COUNT(*) AS open_invoices,
       SUM(balance_due)  AS total_outstanding,
       SUM(current_due)  AS current_due,
       SUM(days_1_30)    AS days_1_30,
       SUM(days_31_60)   AS days_31_60,
       SUM(days_61_90)   AS days_61_90,
       SUM(days_over_90) AS days_over_90
  FROM v_ar_aging
 GROUP BY client_code, client, currency_code;

-- 16.5 Sales pipeline
CREATE OR REPLACE VIEW v_sales_pipeline AS
SELECT o.stage,
       sl.name                     AS service_line,
       o.currency_code,
       COUNT(*)                    AS opportunities,
       SUM(o.estimated_value)      AS total_value,
       SUM(o.weighted_value)       AS weighted_value,
       min(o.expected_close_date)  AS next_expected_close
  FROM opportunities o
  LEFT JOIN service_lines sl ON sl.service_line_id = o.service_line_id
 GROUP BY o.stage, sl.name, o.currency_code;

-- 16.6 Timesheet compliance for the last 4 complete weeks
CREATE OR REPLACE VIEW v_timesheet_compliance AS
SELECT e.employee_number,
       e.first_name || ' ' || e.last_name AS employee_name,
       m.first_name || ' ' || m.last_name AS manager_name,
       w.week_start::DATE                 AS week_start_date,
       COALESCE(ts.status::TEXT, 'missing') AS timesheet_status,
       COALESCE(ts.total_hours, 0)        AS hours_logged,
       e.standard_hours_per_week          AS expected_hours
  FROM employees e
  LEFT JOIN employees m ON m.employee_id = e.manager_id
  CROSS JOIN generate_series(date_trunc('week', CURRENT_DATE) - INTERVAL '4 weeks',
                             date_trunc('week', CURRENT_DATE) - INTERVAL '1 week',
                             INTERVAL '1 week') AS w(week_start)
  LEFT JOIN timesheets ts ON ts.employee_id = e.employee_id AND ts.week_start_date = w.week_start::DATE
 WHERE e.status = 'active' AND e.hire_date <= w.week_start::DATE;

-- 16.7 Resource capacity vs plan (weekly)
CREATE OR REPLACE VIEW v_resource_capacity AS
SELECT e.employee_id,
       e.first_name || ' ' || e.last_name AS employee_name,
       jg.name                            AS grade,
       ra.week_start_date,
       e.standard_hours_per_week          AS capacity_hours,
       SUM(ra.planned_hours)              AS planned_hours,
       e.standard_hours_per_week - SUM(ra.planned_hours) AS available_hours,
       round(100 * SUM(ra.planned_hours) / NULLIF(e.standard_hours_per_week, 0), 1) AS planned_load_pct,
       string_agg(p.project_code || ':' || ra.planned_hours, ', ' ORDER BY p.project_code) AS breakdown
  FROM resource_allocations ra
  JOIN employees e        ON e.employee_id = ra.employee_id
  LEFT JOIN job_grades jg ON jg.job_grade_id = e.job_grade_id
  JOIN projects p         ON p.project_id = ra.project_id
 GROUP BY e.employee_id, e.first_name, e.last_name, jg.name, ra.week_start_date, e.standard_hours_per_week;

-- 16.8 Project health dashboard
CREATE OR REPLACE VIEW v_project_health AS
SELECT p.project_code, p.name AS project_name, p.status,
       pm.first_name || ' ' || pm.last_name AS project_manager,
       sr.report_date AS last_status_report, sr.overall_rag, sr.schedule_rag, sr.budget_rag,
       (SELECT COUNT(*) FROM project_risks r  WHERE r.project_id = p.project_id AND r.status IN ('open','mitigating'))    AS open_risks,
       (SELECT MAX(risk_score) FROM project_risks r WHERE r.project_id = p.project_id AND r.status IN ('open','mitigating')) AS top_risk_score,
       (SELECT COUNT(*) FROM project_issues i WHERE i.project_id = p.project_id AND i.status IN ('open','in_progress'))    AS open_issues,
       (SELECT COUNT(*) FROM deliverables d   WHERE d.project_id = p.project_id AND d.status NOT IN ('accepted')
                                               AND d.due_date < CURRENT_DATE)                                            AS overdue_deliverables,
       f.hours_burn_pct, p.completion_pct, f.gross_margin_pct
  FROM projects p
  LEFT JOIN employees pm ON pm.employee_id = p.project_manager_id
  LEFT JOIN LATERAL (SELECT * FROM project_status_reports s WHERE s.project_id = p.project_id
                     ORDER BY report_date DESC LIMIT 1) sr ON TRUE
  LEFT JOIN v_project_financials f ON f.project_id = p.project_id
 WHERE p.status IN ('planned','active','on_hold');

-- 16.9 Trial balance (posted journals only)
CREATE OR REPLACE VIEW v_trial_balance AS
SELECT a.account_code, a.name AS account_name, a.account_type,
       COALESCE(SUM(jl.debit), 0)  AS total_debit,
       COALESCE(SUM(jl.credit), 0) AS total_credit,
       CASE WHEN a.account_type IN ('asset','expense')
            THEN COALESCE(SUM(jl.debit),0) - COALESCE(SUM(jl.credit),0)
            ELSE COALESCE(SUM(jl.credit),0) - COALESCE(SUM(jl.debit),0) END AS balance
  FROM chart_of_accounts a
  LEFT JOIN journal_lines jl   ON jl.account_id = a.account_id
  LEFT JOIN journal_entries je ON je.journal_entry_id = jl.journal_entry_id
 WHERE a.is_postable AND (je.status IN ('posted','reversed') OR jl.journal_line_id IS NULL)
 GROUP BY a.account_code, a.name, a.account_type;

-- 16.10 Monthly income statement
CREATE OR REPLACE VIEW v_income_statement_monthly AS
SELECT date_trunc('month', je.entry_date)::DATE AS month_start,
       a.account_type, a.account_code, a.name AS account_name,
       SUM(CASE WHEN a.account_type = 'revenue' THEN jl.credit - jl.debit ELSE jl.debit - jl.credit END) AS amount
  FROM journal_lines jl
  JOIN journal_entries je  ON je.journal_entry_id = jl.journal_entry_id
  JOIN chart_of_accounts a ON a.account_id = jl.account_id
 WHERE je.status IN ('posted','reversed') AND a.account_type IN ('revenue','expense')
 GROUP BY 1, 2, 3, 4;

-- 16.11 Leave balances with names
CREATE OR REPLACE VIEW v_leave_balances AS
SELECT e.employee_number, e.first_name || ' ' || e.last_name AS employee_name,
       lt.name AS leave_type, lb.leave_year, lb.entitled_days, lb.carried_forward_days,
       lb.taken_days, lb.remaining_days
  FROM leave_balances lb
  JOIN employees e    ON e.employee_id = lb.employee_id
  JOIN leave_types lt ON lt.leave_type_id = lb.leave_type_id;

-- 16.12 Certifications expiring in the next 90 days
CREATE OR REPLACE VIEW v_expiring_certifications AS
SELECT e.employee_number, e.first_name || ' ' || e.last_name AS employee_name,
       c.name AS certification, c.issuing_body, c.expiry_date, c.expiry_date - CURRENT_DATE AS days_left
  FROM certifications c JOIN employees e ON e.employee_id = c.employee_id
 WHERE c.expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 90 AND e.status = 'active';


-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  23b_reporting_ifrs.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   23B. IFRS FINANCIAL STATEMENTS & MANAGEMENT REPORTING
   -------------------------------------------------------------------------------------
   SELECT * FROM erp.fn_ifrs_profit_or_loss('2026-01-01','2026-09-30');   -- IFRS 18 P&L + OCI
   SELECT * FROM erp.fn_ifrs_financial_position('2026-09-30');           -- balance sheet
   SELECT * FROM erp.fn_ifrs_cash_flows('2026-01-01','2026-09-30');      -- IAS 7 (direct method)
   SELECT * FROM erp.fn_ifrs_changes_in_equity('2026-01-01','2026-09-30');
   SELECT * FROM erp.fn_ifrs_mpm_note('2026-01-01','2026-09-30');        -- IFRS 18 MPM note
   SELECT * FROM erp.fn_ppe_movement('2026-01-01','2026-09-30');         -- IAS 16 note
   SELECT * FROM erp.fn_trial_balance('2026-09-30');
   ===================================================================================== */

-- Trial balance at a date
CREATE OR REPLACE FUNCTION fn_trial_balance(p_as_at DATE)
RETURNS TABLE (account_code VARCHAR, account_name VARCHAR, account_type account_type, ifrs_line VARCHAR,
               debit NUMERIC, credit NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT a.account_code, a.name, a.account_type, li.name,
           CASE WHEN SUM(jl.debit - jl.credit) > 0 THEN SUM(jl.debit - jl.credit) ELSE 0 END,
           CASE WHEN SUM(jl.debit - jl.credit) < 0 THEN -SUM(jl.debit - jl.credit) ELSE 0 END
      FROM chart_of_accounts a
      JOIN journal_lines jl    ON jl.account_id = a.account_id
      JOIN journal_entries je  ON je.journal_entry_id = jl.journal_entry_id
                              AND je.status IN ('posted','reversed') AND je.entry_date <= p_as_at
      LEFT JOIN ifrs_line_items li ON li.line_code = a.ifrs_line_code
     GROUP BY a.account_code, a.name, a.account_type, li.name
    HAVING SUM(jl.debit - jl.credit) <> 0
     ORDER BY a.account_code;
$$;

-- Amount per IFRS line item for a period (credit-positive) or at a date (balances)
CREATE OR REPLACE FUNCTION fn_ifrs_line_amounts(p_from DATE, p_to DATE)
RETURNS TABLE (line_code VARCHAR, amount NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT a.ifrs_line_code, SUM(jl.credit - jl.debit)
      FROM journal_lines jl
      JOIN journal_entries je  ON je.journal_entry_id = jl.journal_entry_id
      JOIN chart_of_accounts a ON a.account_id = jl.account_id
     WHERE je.status IN ('posted','reversed') AND je.entry_date BETWEEN p_from AND p_to
     GROUP BY a.ifrs_line_code;
$$;

/* Statement of profit or loss and other comprehensive income (IFRS 18)
   amount: income +, expense -.  Rows flagged is_subtotal are the IFRS 18 required
   subtotals / totals. */
CREATE OR REPLACE FUNCTION fn_ifrs_profit_or_loss(p_from DATE, p_to DATE)
RETURNS TABLE (sort_order INT, line_code VARCHAR, caption VARCHAR, category VARCHAR, amount NUMERIC, is_subtotal BOOLEAN)
LANGUAGE sql STABLE AS $$
    WITH amt AS (SELECT * FROM fn_ifrs_line_amounts(p_from, p_to)),
    pl AS (
        SELECT li.sort_order::INT * 10 AS so, li.line_code, li.name, li.ifrs18_category AS cat,
               COALESCE(amt.amount, 0) AS amount
          FROM ifrs_line_items li LEFT JOIN amt ON amt.line_code = li.line_code
         WHERE li.statement = 'PL'
    ),
    oci AS (
        SELECT li.sort_order::INT * 10 AS so, li.line_code, li.name, 'oci'::VARCHAR AS cat,
               COALESCE((SELECT SUM(jl.credit - jl.debit)
                           FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id)
                           JOIN chart_of_accounts a ON a.account_id = jl.account_id
                          WHERE a.ifrs_line_code IN ('SFP_REVAL','SFP_FXRES')
                            AND ((li.line_code = 'OCI_REVAL' AND a.ifrs_line_code = 'SFP_REVAL' AND je.source_type = 'revaluation')
                              OR (li.line_code = 'OCI_FX'    AND a.ifrs_line_code = 'SFP_FXRES'))
                            AND je.status IN ('posted','reversed') AND je.entry_date BETWEEN p_from AND p_to), 0) AS amount
          FROM ifrs_line_items li WHERE li.statement = 'OCI'
    ),
    sub AS (
        SELECT 1995 AS so, 'ST_OP'::VARCHAR AS code, 'Operating profit'::VARCHAR AS cap,
               (SELECT COALESCE(SUM(amount),0) FROM pl WHERE cat = 'operating') AS amount
        UNION ALL SELECT 2995, 'ST_PBFIT', 'Profit before financing and income taxes',
               (SELECT COALESCE(SUM(amount),0) FROM pl WHERE cat IN ('operating','investing'))
        UNION ALL SELECT 3995, 'ST_PBT', 'Profit before income taxes',
               (SELECT COALESCE(SUM(amount),0) FROM pl WHERE cat IN ('operating','investing','financing'))
        UNION ALL SELECT 4995, 'ST_PCONT', 'Profit from continuing operations',
               (SELECT COALESCE(SUM(amount),0) FROM pl WHERE cat <> 'discontinued')
        UNION ALL SELECT 5995, 'ST_PROFIT', 'PROFIT FOR THE PERIOD',
               (SELECT COALESCE(SUM(amount),0) FROM pl)
        UNION ALL SELECT 6995, 'ST_OCI', 'Other comprehensive income for the period, net of tax',
               (SELECT COALESCE(SUM(amount),0) FROM oci)
        UNION ALL SELECT 7995, 'ST_TCI', 'TOTAL COMPREHENSIVE INCOME FOR THE PERIOD',
               (SELECT COALESCE(SUM(amount),0) FROM pl) + (SELECT COALESCE(SUM(amount),0) FROM oci)
    )
    SELECT so, line_code, name, cat, round(amount, 2), FALSE FROM pl
    UNION ALL SELECT so, line_code, name, cat, round(amount, 2), FALSE FROM oci
    UNION ALL SELECT so, code, cap, 'subtotal', round(amount, 2), TRUE FROM sub
    ORDER BY 1;
$$;

/* Statement of financial position. amount is positive for assets and for equity/liabilities.
   Lease liabilities and borrowings are split into current / non-current from their schedules. */
CREATE OR REPLACE FUNCTION fn_ifrs_financial_position(p_as_at DATE)
RETURNS TABLE (sort_order INT, section VARCHAR, line_code VARCHAR, caption VARCHAR, amount NUMERIC, is_subtotal BOOLEAN)
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_lease NUMERIC; v_lease_cur NUMERIC; v_loan NUMERIC; v_loan_cur NUMERIC; v_tax NUMERIC; v_re NUMERIC;
BEGIN
    CREATE TEMP TABLE IF NOT EXISTS tmp_sfp (t_so INT, t_section VARCHAR, t_code VARCHAR, t_caption VARCHAR, t_amount NUMERIC, t_sub BOOLEAN) ON COMMIT DROP;
    DELETE FROM tmp_sfp;

    -- balances per line (debit-positive)
    INSERT INTO tmp_sfp
    SELECT li.sort_order, li.section, li.line_code, li.name,
           COALESCE(SUM(jl.debit - jl.credit), 0) * li.sign * -1, FALSE
      FROM ifrs_line_items li
      LEFT JOIN chart_of_accounts a ON a.ifrs_line_code = li.line_code
      LEFT JOIN journal_lines jl    ON jl.account_id = a.account_id
                                   AND EXISTS (SELECT 1 FROM journal_entries je WHERE je.journal_entry_id = jl.journal_entry_id
                                                  AND je.status IN ('posted','reversed') AND je.entry_date <= p_as_at)
     WHERE li.statement = 'SFP'
     GROUP BY li.sort_order, li.section, li.line_code, li.name, li.sign;

    -- retained earnings include all profit or loss to date
    SELECT COALESCE(SUM(jl.credit - jl.debit), 0) INTO v_re
      FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id)
      JOIN chart_of_accounts a ON a.account_id = jl.account_id
     WHERE a.account_type IN ('revenue','expense') AND je.status IN ('posted','reversed') AND je.entry_date <= p_as_at;
    UPDATE tmp_sfp SET t_amount = t_amount + v_re WHERE t_code = 'SFP_RE';

    -- lease liabilities: current portion = principal falling due in the next 12 months
    SELECT t_amount INTO v_lease FROM tmp_sfp WHERE t_code = 'SFP_LEASE';
    SELECT COALESCE(SUM(s.principal * fn_fx_rate(l.currency_code, p_as_at)), 0) INTO v_lease_cur
      FROM lease_schedule s JOIN leases l USING (lease_id)
     WHERE s.period_date > p_as_at AND s.period_date <= p_as_at + INTERVAL '12 months' AND l.recognised_journal_id IS NOT NULL
       AND l.commencement_date <= p_as_at;
    v_lease_cur := LEAST(round(v_lease_cur, 2), COALESCE(v_lease, 0));
    UPDATE tmp_sfp SET t_amount = COALESCE(v_lease,0) - v_lease_cur WHERE t_code = 'SFP_LEASE';
    UPDATE tmp_sfp SET t_amount = v_lease_cur WHERE t_code = 'SFP_LEASE_C';

    SELECT t_amount INTO v_loan FROM tmp_sfp WHERE t_code = 'SFP_BORR';
    SELECT COALESCE(SUM(s.principal), 0) INTO v_loan_cur FROM loan_schedule s JOIN borrowings b USING (loan_id)
     WHERE s.due_date > p_as_at AND s.due_date <= p_as_at + INTERVAL '12 months' AND b.drawdown_date <= p_as_at;
    v_loan_cur := LEAST(v_loan_cur, COALESCE(v_loan, 0));
    UPDATE tmp_sfp SET t_amount = COALESCE(v_loan,0) - v_loan_cur WHERE t_code = 'SFP_BORR';
    UPDATE tmp_sfp SET t_amount = v_loan_cur WHERE t_code = 'SFP_BORR_C';

    -- current tax: show as an asset if QPDs paid exceed the provision
    SELECT t_amount INTO v_tax FROM tmp_sfp WHERE t_code = 'SFP_TAX_L';
    IF v_tax < 0 THEN
        UPDATE tmp_sfp SET t_amount = -v_tax WHERE t_code = 'SFP_TAX_A';
        UPDATE tmp_sfp SET t_amount = 0 WHERE t_code = 'SFP_TAX_L';
    END IF;

    -- subtotals
    INSERT INTO tmp_sfp
    SELECT 1990, 'ASSETS', 'T_NCA', 'Total non-current assets', SUM(t_amount), TRUE FROM tmp_sfp WHERE t_section = 'Non-current assets' AND NOT t_sub
    UNION ALL SELECT 2990, 'ASSETS', 'T_CA', 'Total current assets', SUM(t_amount), TRUE FROM tmp_sfp WHERE t_section = 'Current assets' AND NOT t_sub
    UNION ALL SELECT 2999, 'ASSETS', 'T_A', 'TOTAL ASSETS', SUM(t_amount), TRUE FROM tmp_sfp WHERE t_section IN ('Non-current assets','Current assets') AND NOT t_sub
    UNION ALL SELECT 3990, 'EQUITY', 'T_E', 'Total equity', SUM(t_amount), TRUE FROM tmp_sfp WHERE t_section = 'Equity' AND NOT t_sub
    UNION ALL SELECT 4990, 'LIABILITIES', 'T_NCL', 'Total non-current liabilities', SUM(t_amount), TRUE FROM tmp_sfp WHERE t_section = 'Non-current liabilities' AND NOT t_sub
    UNION ALL SELECT 5990, 'LIABILITIES', 'T_CL', 'Total current liabilities', SUM(t_amount), TRUE FROM tmp_sfp WHERE t_section = 'Current liabilities' AND NOT t_sub
    UNION ALL SELECT 5995, 'LIABILITIES', 'T_L', 'Total liabilities', SUM(t_amount), TRUE FROM tmp_sfp WHERE t_section IN ('Non-current liabilities','Current liabilities') AND NOT t_sub
    UNION ALL SELECT 5999, 'LIABILITIES', 'T_EL', 'TOTAL EQUITY AND LIABILITIES', SUM(t_amount), TRUE FROM tmp_sfp WHERE t_section IN ('Equity','Non-current liabilities','Current liabilities') AND NOT t_sub;

    RETURN QUERY SELECT t.t_so, t.t_section, t.t_code, t.t_caption, round(t.t_amount, 2), t.t_sub FROM tmp_sfp t ORDER BY t.t_so;
END $$;

/* Statement of cash flows - direct method (IAS 7 as amended by IFRS 18).
   Every posted journal that touches a cash account is analysed: each non-cash line is
   classified by its account's cash-flow line (or the journal source override), and its
   cash effect is -(debit - credit).  Transfers between bank accounts net to nil.
   Interest paid -> financing; interest & dividends received -> investing. */
CREATE OR REPLACE FUNCTION fn_ifrs_cash_flows(p_from DATE, p_to DATE)
RETURNS TABLE (sort_order INT, category VARCHAR, cf_code VARCHAR, caption VARCHAR, amount NUMERIC, is_subtotal BOOLEAN)
LANGUAGE sql STABLE AS $$
    WITH cash_je AS (
        SELECT DISTINCT je.journal_entry_id, je.source_type
          FROM journal_entries je
          JOIN journal_lines jl    ON jl.journal_entry_id = je.journal_entry_id
          JOIN chart_of_accounts a ON a.account_id = jl.account_id AND a.is_cash
         WHERE je.status IN ('posted','reversed') AND je.entry_date BETWEEN p_from AND p_to
    ),
    flows AS (
        SELECT COALESCE(o.cf_code, a.cash_flow_code, 'CF_OP_SUPPLIERS') AS cf_code, SUM(jl.credit - jl.debit) AS amount
          FROM cash_je c
          JOIN journal_lines jl    ON jl.journal_entry_id = c.journal_entry_id
          JOIN chart_of_accounts a ON a.account_id = jl.account_id AND NOT a.is_cash
          LEFT JOIN cash_flow_source_overrides o ON o.source_type = c.source_type
         GROUP BY 1
    ),
    lines AS (
        SELECT cl.sort_order::INT * 10 AS so, cl.category, cl.cf_code, cl.name, COALESCE(f.amount, 0) AS amount
          FROM cash_flow_lines cl LEFT JOIN flows f ON f.cf_code = cl.cf_code
    ),
    cash_bal AS (
        SELECT COALESCE(SUM(CASE WHEN je.entry_date < p_from THEN jl.debit - jl.credit END), 0) AS opening,
               COALESCE(SUM(jl.debit - jl.credit), 0) AS closing
          FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id)
          JOIN chart_of_accounts a ON a.account_id = jl.account_id AND a.is_cash
         WHERE je.status IN ('posted','reversed') AND je.entry_date <= p_to
    )
    SELECT so, category, cf_code, name, round(amount, 2), FALSE FROM lines
    UNION ALL SELECT 1995, 'operating', 'T_OP', 'Net cash from operating activities', round((SELECT SUM(amount) FROM lines WHERE category = 'operating'), 2), TRUE
    UNION ALL SELECT 2995, 'investing', 'T_INV', 'Net cash used in investing activities', round((SELECT SUM(amount) FROM lines WHERE category = 'investing'), 2), TRUE
    UNION ALL SELECT 3995, 'financing', 'T_FIN', 'Net cash used in financing activities', round((SELECT SUM(amount) FROM lines WHERE category = 'financing'), 2), TRUE
    UNION ALL SELECT 4985, 'total', 'T_NET', 'Net increase / (decrease) in cash and cash equivalents', round((SELECT SUM(amount) FROM lines WHERE category <> 'fx'), 2), TRUE
    UNION ALL SELECT 4992, 'total', 'T_OPEN', 'Cash and cash equivalents at the beginning of the period', round((SELECT opening FROM cash_bal), 2), TRUE
    UNION ALL SELECT 4999, 'total', 'T_CLOSE', 'Cash and cash equivalents at the end of the period', round((SELECT closing FROM cash_bal), 2), TRUE
    ORDER BY 1;
$$;

-- Statement of changes in equity
CREATE OR REPLACE FUNCTION fn_ifrs_changes_in_equity(p_from DATE, p_to DATE)
RETURNS TABLE (sort_order INT, caption TEXT, share_capital NUMERIC, revaluation_reserve NUMERIC,
               translation_reserve NUMERIC, retained_earnings NUMERIC, total_equity NUMERIC)
LANGUAGE sql STABLE AS $$
    WITH mv AS (
        SELECT a.ifrs_line_code AS line, je.source_type AS src, je.entry_date < p_from AS before,
               a.account_type, SUM(jl.credit - jl.debit) AS amt
          FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id)
          JOIN chart_of_accounts a ON a.account_id = jl.account_id
         WHERE je.status IN ('posted','reversed') AND je.entry_date <= p_to
           AND (a.account_type IN ('equity','revenue','expense'))
         GROUP BY 1, 2, 3, 4
    ),
    r AS (
        SELECT
          COALESCE(SUM(amt) FILTER (WHERE before AND line = 'SFP_SC'), 0)     AS o_sc,
          COALESCE(SUM(amt) FILTER (WHERE before AND line = 'SFP_REVAL'), 0)  AS o_rr,
          COALESCE(SUM(amt) FILTER (WHERE before AND line = 'SFP_FXRES'), 0)  AS o_tr,
          COALESCE(SUM(amt) FILTER (WHERE before AND (line = 'SFP_RE' OR account_type IN ('revenue','expense'))), 0) AS o_re,
          COALESCE(SUM(amt) FILTER (WHERE NOT before AND account_type IN ('revenue','expense')), 0) AS profit,
          COALESCE(SUM(amt) FILTER (WHERE NOT before AND line = 'SFP_REVAL' AND src = 'revaluation'), 0) AS oci_rr,
          COALESCE(SUM(amt) FILTER (WHERE NOT before AND line = 'SFP_FXRES'), 0) AS oci_tr,
          COALESCE(SUM(amt) FILTER (WHERE NOT before AND line = 'SFP_RE' AND src = 'dividend'), 0) AS div,
          COALESCE(SUM(amt) FILTER (WHERE NOT before AND line = 'SFP_REVAL' AND src <> 'revaluation'), 0) AS tr_rr,
          COALESCE(SUM(amt) FILTER (WHERE NOT before AND line = 'SFP_RE' AND src <> 'dividend'), 0) AS tr_re,
          COALESCE(SUM(amt) FILTER (WHERE NOT before AND line = 'SFP_SC'), 0) AS sc_mv
          FROM mv
    )
    SELECT 1, 'Balance at ' || to_char(p_from - 1, 'DD Month YYYY'), o_sc, o_rr, o_tr, o_re, o_sc + o_rr + o_tr + o_re FROM r
    UNION ALL SELECT 2, 'Profit for the period', 0, 0, 0, profit, profit FROM r
    UNION ALL SELECT 3, 'Other comprehensive income (net of tax)', 0, oci_rr, oci_tr, 0, oci_rr + oci_tr FROM r
    UNION ALL SELECT 4, 'Total comprehensive income', 0, oci_rr, oci_tr, profit, profit + oci_rr + oci_tr FROM r
    UNION ALL SELECT 5, 'Dividends declared', 0, 0, 0, div, div FROM r
    UNION ALL SELECT 6, 'Shares issued / transfers between reserves', sc_mv, tr_rr, 0, tr_re, sc_mv + tr_rr + tr_re FROM r
    UNION ALL SELECT 7, 'Balance at ' || to_char(p_to, 'DD Month YYYY'), o_sc + sc_mv, o_rr + oci_rr + tr_rr, o_tr + oci_tr,
                     o_re + profit + div + tr_re, o_sc + sc_mv + o_rr + oci_rr + tr_rr + o_tr + oci_tr + o_re + profit + div + tr_re FROM r
    ORDER BY 1;
$$;

/* IFRS 18 note: Management-defined performance measures, reconciled to the closest
   IFRS subtotal with the income-tax effect of each reconciling item. */
CREATE OR REPLACE FUNCTION fn_ifrs_mpm_note(p_from DATE, p_to DATE)
RETURNS TABLE (mpm_code VARCHAR, mpm_name VARCHAR, sort_order INT, caption VARCHAR, amount NUMERIC, tax_effect NUMERIC)
LANGUAGE sql STABLE AS $$
    WITH base AS (SELECT amount FROM fn_ifrs_profit_or_loss(p_from, p_to) WHERE line_code = 'ST_OP'),
    adj AS (
        SELECT m.mpm_code, ma.caption, ma.tax_rate_pct,
               -COALESCE((SELECT SUM(jl.credit - jl.debit) FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id)
                           WHERE jl.account_id = ma.account_id AND je.status IN ('posted','reversed')
                             AND je.entry_date BETWEEN p_from AND p_to), 0) AS amount
          FROM mpm_definitions m JOIN mpm_adjustments ma ON ma.mpm_code = m.mpm_code
         WHERE m.is_active
    ),
    adj_grp AS (SELECT mpm_code, caption, SUM(amount) AS amount, SUM(amount * tax_rate_pct / 100) AS tax FROM adj GROUP BY 1, 2)
    SELECT m.mpm_code, m.name, 1, ('Operating profit (IFRS 18 subtotal)')::VARCHAR, round((SELECT amount FROM base), 2), NULL::NUMERIC
      FROM mpm_definitions m WHERE m.is_active
    UNION ALL
    SELECT g.mpm_code, m.name, 2, ('Add back: ' || g.caption)::VARCHAR, round(g.amount, 2), round(-g.tax, 2)
      FROM adj_grp g JOIN mpm_definitions m USING (mpm_code)
    UNION ALL
    SELECT m.mpm_code, m.name, 9, m.name, round((SELECT amount FROM base) + COALESCE((SELECT SUM(amount) FROM adj_grp g WHERE g.mpm_code = m.mpm_code), 0), 2),
           round(-COALESCE((SELECT SUM(tax) FROM adj_grp g WHERE g.mpm_code = m.mpm_code), 0), 2)
      FROM mpm_definitions m WHERE m.is_active
    ORDER BY 1, 3, 4;
$$;

-- IAS 16 / IAS 38 / IAS 40 movement schedule by asset category
CREATE OR REPLACE FUNCTION fn_ppe_movement(p_from DATE, p_to DATE)
RETURNS TABLE (category VARCHAR, standard VARCHAR, opening_nbv NUMERIC, additions NUMERIC, revaluations NUMERIC,
               disposals NUMERIC, depreciation NUMERIC, closing_nbv NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT c.name, c.standard,
           round(SUM((SELECT carrying_amount FROM fn_asset_nbv(fa.asset_id, p_from - 1))), 2),
           round(SUM(CASE WHEN fa.acquisition_date BETWEEN p_from AND p_to THEN fa.cost ELSE 0 END), 2),
           round(COALESCE(SUM((SELECT SUM(surplus_deficit) FROM asset_revaluations r WHERE r.asset_id = fa.asset_id
                                 AND r.valuation_date BETWEEN p_from AND p_to)), 0), 2),
           round(-COALESCE(SUM((SELECT carrying_amount FROM asset_disposals d WHERE d.asset_id = fa.asset_id
                                 AND d.disposal_date BETWEEN p_from AND p_to)), 0), 2),
           round(-COALESCE(SUM((SELECT SUM(amount) FROM asset_depreciation d WHERE d.asset_id = fa.asset_id
                                 AND d.period_end BETWEEN p_from AND p_to)), 0), 2),
           round(SUM((SELECT carrying_amount FROM fn_asset_nbv(fa.asset_id, p_to))), 2)
      FROM fixed_assets fa JOIN asset_categories c ON c.asset_category_id = fa.asset_category_id
     GROUP BY c.name, c.standard, c.code
     ORDER BY c.code;
$$;

-- Segment information (IFRS 8): revenue and direct costs by service line and by office
CREATE OR REPLACE VIEW v_segment_revenue AS
SELECT date_trunc('month', je.entry_date)::DATE AS month_start,
       COALESCE(sl.name, 'Other / unallocated') AS service_line,
       COALESCE(o.name, 'Head office') AS office,
       COALESCE(o.country_code, 'ZW') AS country_code,
       SUM(jl.credit - jl.debit) AS revenue
  FROM journal_lines jl
  JOIN journal_entries je  ON je.journal_entry_id = jl.journal_entry_id AND je.status IN ('posted','reversed')
  JOIN chart_of_accounts a ON a.account_id = jl.account_id AND a.ifrs_line_code = 'PL_REV'
  LEFT JOIN projects p     ON p.project_id = jl.project_id
  LEFT JOIN service_lines sl ON sl.service_line_id = p.service_line_id
  LEFT JOIN offices o      ON o.office_id = COALESCE(jl.office_id, p.office_id)
 GROUP BY 1, 2, 3, 4;

CREATE OR REPLACE VIEW v_fixed_asset_register AS
SELECT fa.asset_id, fa.asset_tag, fa.name, c.name AS category, c.asset_class, c.standard, c.measurement_model,
       fa.status, o.name AS office, d.name AS department,
       e.first_name || ' ' || e.last_name AS custodian,
       fa.make_model, fa.serial_number, fa.registration_number, fa.acquisition_date, fa.cost,
       n.gross, n.accumulated_depreciation, n.carrying_amount,
       CASE WHEN c.depreciation_method = 'none' THEN 0 ELSE fn_asset_monthly_depreciation(fa.asset_id, CURRENT_DATE) END AS monthly_depreciation,
       fa.insured_value, fa.warranty_expiry, fa.last_revaluation_date
  FROM fixed_assets fa
  JOIN asset_categories c ON c.asset_category_id = fa.asset_category_id
  LEFT JOIN offices o     ON o.office_id = fa.office_id
  LEFT JOIN departments d ON d.department_id = fa.department_id
  LEFT JOIN employees e   ON e.employee_id = fa.custodian_employee_id
  CROSS JOIN LATERAL fn_asset_nbv(fa.asset_id, CURRENT_DATE) n;

CREATE OR REPLACE VIEW v_lease_register AS
SELECT l.lease_id, l.lease_number, l.description, l.role, l.asset_class, o.name AS office, l.currency_code,
       l.commencement_date, l.end_date, l.term_months,
       GREATEST((extract(year FROM age(l.end_date, CURRENT_DATE)) * 12 + extract(month FROM age(l.end_date, CURRENT_DATE)))::INT, 0) AS months_remaining,
       l.payment_amount, l.payment_frequency, l.discount_rate_pct, l.exemption, l.status,
       l.initial_liability, l.initial_rou_asset,
       (SELECT s.closing_liability FROM lease_schedule s WHERE s.lease_id = l.lease_id AND s.is_posted
         ORDER BY s.period_no DESC LIMIT 1) AS liability_lease_ccy,
       l.liability_usd_balance AS liability_usd,
       l.initial_rou_asset - COALESCE((SELECT SUM(s.rou_depreciation) FROM lease_schedule s WHERE s.lease_id = l.lease_id AND s.is_posted), 0) AS rou_carrying_usd,
       v.name AS landlord, l.tenant_name
  FROM leases l
  LEFT JOIN offices o ON o.office_id = l.office_id
  LEFT JOIN vendors v ON v.vendor_id = l.vendor_id;

CREATE OR REPLACE VIEW v_tax_calendar AS
SELECT t.tax_return_id, t.return_number, t.tax_code, tt.name AS tax_name, tt.authority_code, tt.return_form,
       o.name AS office, t.period_start, t.period_end, t.due_date, t.amount_due, t.amount_paid,
       CASE WHEN t.status NOT IN ('paid','cancelled') AND t.due_date < CURRENT_DATE THEN 'overdue'::TEXT ELSE t.status::TEXT END AS status,
       t.due_date - CURRENT_DATE AS days_to_due, t.filed_date, t.paid_date, t.acknowledgement_ref
  FROM tax_returns t
  JOIN tax_types tt ON tt.tax_code = t.tax_code
  LEFT JOIN offices o ON o.office_id = t.office_id;

CREATE OR REPLACE VIEW v_payroll_summary AS
SELECT pr.payroll_run_id, pr.run_number, pr.country_code, pr.period_start, pr.pay_date, pr.currency_code, pr.status,
       pr.employee_count,
       round(SUM(p.gross_pay * pr.exchange_rate), 2)       AS gross_usd,
       round(SUM(p.paye_tax * pr.exchange_rate), 2)        AS income_tax_usd,
       round(SUM(p.aids_levy * pr.exchange_rate), 2)       AS aids_levy_usd,
       round(SUM((p.nssa_employee + p.employer_nssa) * pr.exchange_rate), 2) AS social_security_usd,
       round(SUM(p.employer_wcif * pr.exchange_rate), 2)   AS wcif_other_usd,
       round(SUM(p.employer_zimdef * pr.exchange_rate), 2) AS zimdef_usd,
       round(SUM(p.net_pay * pr.exchange_rate), 2)         AS net_pay_usd,
       round(SUM(p.employer_cost * pr.exchange_rate), 2)   AS employer_cost_usd
  FROM payroll_runs pr JOIN payslips p USING (payroll_run_id)
 GROUP BY pr.payroll_run_id;

CREATE OR REPLACE VIEW v_staff_directory AS
SELECT e.employee_id, e.employee_number, e.first_name || ' ' || e.last_name AS full_name, e.job_title,
       d.name AS department, o.name AS office, o.city, e.email, e.work_phone_ext, e.mobile_phone,
       m.first_name || ' ' || m.last_name AS manager, e.status
  FROM employees e
  LEFT JOIN departments d ON d.department_id = e.department_id
  LEFT JOIN offices o     ON o.office_id = e.office_id
  LEFT JOIN employees m   ON m.employee_id = e.manager_id
 WHERE e.status <> 'terminated';

CREATE OR REPLACE VIEW v_user_access AS
SELECT u.user_id, u.username, u.email, e.first_name || ' ' || e.last_name AS full_name, d.name AS department,
       g.name AS grade, u.is_active, (u.locked_until IS NOT NULL AND u.locked_until > now()) AS is_locked,
       u.must_change_password, u.last_login_at, u.failed_logins,
       (SELECT string_agg(r.code, ', ' ORDER BY r.code) FROM user_roles ur JOIN roles r USING (role_id) WHERE ur.user_id = u.user_id) AS roles
  FROM app_users u
  LEFT JOIN employees e   ON e.employee_id = u.employee_id
  LEFT JOIN departments d ON d.department_id = e.department_id
  LEFT JOIN job_grades g  ON g.job_grade_id = e.job_grade_id;

CREATE OR REPLACE VIEW v_inbox AS
SELECT r.recipient_id, m.message_id, m.thread_id, m.subject, m.body, m.priority, m.sent_at,
       s.first_name || ' ' || s.last_name AS sender, s.email AS sender_email,
       r.recipient_type, r.read_at, r.is_starred, r.is_archived, ml.address AS via_list
  FROM message_recipients r
  JOIN internal_messages m ON m.message_id = r.message_id
  JOIN employees s         ON s.employee_id = m.sender_id
  LEFT JOIN mailing_lists ml ON ml.list_id = m.sent_to_list_id;

-- Announcements visible to each employee (company-wide, their department, their office)
CREATE OR REPLACE VIEW v_employee_announcements AS
SELECT e.employee_id, a.announcement_id, a.title, a.body, a.category, a.audience, a.is_pinned, a.publish_at, a.expires_at,
       au.first_name || ' ' || au.last_name AS author,
       EXISTS (SELECT 1 FROM announcement_reads ar WHERE ar.announcement_id = a.announcement_id AND ar.employee_id = e.employee_id) AS is_read
  FROM employees e
  JOIN announcements a ON a.audience = 'all'
                       OR (a.audience = 'department' AND a.department_id = e.department_id)
                       OR (a.audience = 'office' AND a.office_id = e.office_id)
  JOIN employees au    ON au.employee_id = a.author_id
 WHERE a.publish_at <= now() AND (a.expires_at IS NULL OR a.expires_at > now());

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  24_indexes.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   17. INDEXES (foreign keys & frequent filters)
   ===================================================================================== */
CREATE INDEX ix_employees_manager        ON employees (manager_id);
CREATE INDEX ix_employees_department     ON employees (department_id);
CREATE INDEX ix_employees_status         ON employees (status);
CREATE INDEX ix_clients_account_manager  ON clients (account_manager_id);
CREATE INDEX ix_clients_status           ON clients (status);
CREATE INDEX ix_contacts_client          ON client_contacts (client_id);
CREATE INDEX ix_opportunities_client     ON opportunities (client_id);
CREATE INDEX ix_opportunities_stage      ON opportunities (stage, expected_close_date);
CREATE INDEX ix_crm_activities_client    ON crm_activities (client_id, activity_date DESC);
CREATE INDEX ix_contracts_client         ON contracts (client_id);
CREATE INDEX ix_projects_client          ON projects (client_id);
CREATE INDEX ix_projects_status          ON projects (status);
CREATE INDEX ix_projects_pm              ON projects (project_manager_id);
CREATE INDEX ix_tasks_project            ON tasks (project_id, status);
CREATE INDEX ix_tasks_assignee           ON tasks (assignee_id) WHERE status <> 'done';
CREATE INDEX ix_project_members_emp      ON project_members (employee_id);
CREATE INDEX ix_alloc_week               ON resource_allocations (week_start_date);
CREATE INDEX ix_timesheets_status        ON timesheets (status, week_start_date);
CREATE INDEX ix_time_entries_timesheet   ON time_entries (timesheet_id);
CREATE INDEX ix_time_entries_emp_date    ON time_entries (employee_id, work_date);
CREATE INDEX ix_time_entries_project     ON time_entries (project_id, work_date);
CREATE INDEX ix_time_entries_unbilled    ON time_entries (project_id) WHERE invoice_line_id IS NULL AND is_billable;
CREATE INDEX ix_expense_items_report     ON expense_items (expense_report_id);
CREATE INDEX ix_expense_items_project    ON expense_items (project_id);
CREATE INDEX ix_invoices_client          ON invoices (client_id, status);
CREATE INDEX ix_invoices_project         ON invoices (project_id);
CREATE INDEX ix_invoices_open_due        ON invoices (due_date) WHERE status IN ('issued','partially_paid','overdue');
CREATE INDEX ix_invoice_lines_invoice    ON invoice_lines (invoice_id);
CREATE INDEX ix_payments_client          ON payments (client_id, payment_date);
CREATE INDEX ix_payment_alloc_invoice    ON payment_allocations (invoice_id);
CREATE INDEX ix_journal_entries_date     ON journal_entries (entry_date);
CREATE INDEX ix_journal_lines_account    ON journal_lines (account_id);
CREATE INDEX ix_journal_lines_project    ON journal_lines (project_id);
CREATE INDEX ix_leave_requests_emp       ON leave_requests (employee_id, start_date);
CREATE INDEX ix_documents_entity         ON documents (entity_type, entity_id);
CREATE INDEX ix_comments_entity          ON comments (entity_type, entity_id);
CREATE INDEX ix_notifications_user       ON notifications (user_id) WHERE NOT is_read;
CREATE INDEX ix_audit_log_table_pk       ON audit_log (table_name, record_pk);
CREATE INDEX ix_audit_log_changed_at     ON audit_log (changed_at);


-- indexes for the new modules
CREATE INDEX ix_journal_lines_office     ON journal_lines (office_id);
CREATE INDEX ix_payslips_employee        ON payslips (employee_id);
CREATE INDEX ix_fixed_assets_category    ON fixed_assets (asset_category_id);
CREATE INDEX ix_fixed_assets_custodian   ON fixed_assets (custodian_employee_id);
CREATE INDEX ix_asset_dep_period         ON asset_depreciation (period_end);
CREATE INDEX ix_lease_schedule_period    ON lease_schedule (period_date);
CREATE INDEX ix_tax_returns_due          ON tax_returns (due_date, status);
CREATE INDEX ix_msg_recipients_inbox     ON message_recipients (recipient_id, read_at);
CREATE INDEX ix_login_attempts_time      ON login_attempts (attempted_at);
CREATE INDEX ix_login_attempts_user      ON login_attempts (user_id);
CREATE INDEX ix_user_sessions_user       ON user_sessions (user_id);
CREATE INDEX ix_invoices_date            ON invoices (invoice_date);


/* =====================================================================================
   HARDENING
   ===================================================================================== */

-- The audit log is append-only: block UPDATE / DELETE from any application session
CREATE OR REPLACE FUNCTION fn_audit_log_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'audit_log is append-only';
END $$;
CREATE TRIGGER trg_audit_log_immutable BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION fn_audit_log_immutable();

-- Pin search_path on every routine so they work regardless of the caller's search_path
-- (and cannot be hijacked by objects in other schemas).
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT p.oid::regprocedure AS sig, p.prokind
               FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'erp'
    LOOP
        EXECUTE format('ALTER %s %s SET search_path = erp, public',
                       CASE r.prokind WHEN 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END, r.sig);
    END LOOP;
END $$;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  30_seed_reference.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   30. SEED - REFERENCE DATA, IFRS STRUCTURE, CHART OF ACCOUNTS, TAX TABLES, ACCESS
   -------------------------------------------------------------------------------------
   Demo data for Maxhub Pvt Ltd. People, clients and suppliers are fictional.
   Tax rates reflect published 2025/2026 Zimbabwe rates at the time of writing - VERIFY
   against current ZIMRA / NSSA public notices before relying on them.
   To install WITHOUT demo data run maxhub_erp_schema.sql instead (python database/build.py --schema).
   ===================================================================================== */

SET erp.skip_audit = 'on';      -- no audit rows for the bulk load (session only)

-- 30.1 Currencies, countries, FX ---------------------------------------------------------
INSERT INTO currencies (currency_code, name, symbol) VALUES
 ('USD','US Dollar','$'), ('ZWG','Zimbabwe Gold','ZiG'), ('ZAR','South African Rand','R'),
 ('KES','Kenyan Shilling','KSh'), ('GBP','Pound Sterling','£'), ('AED','UAE Dirham','AED'),
 ('EUR','Euro','€'), ('BWP','Botswana Pula','P'), ('ZMW','Zambian Kwacha','K');

INSERT INTO countries (country_code, name, default_currency) VALUES
 ('ZW','Zimbabwe','USD'), ('ZA','South Africa','ZAR'), ('KE','Kenya','KES'), ('GB','United Kingdom','GBP'),
 ('AE','United Arab Emirates','AED'), ('BW','Botswana','BWP'), ('ZM','Zambia','ZMW'), ('US','United States','USD'),
 ('MZ','Mozambique','USD');

-- Month-end rates (USD per 1 unit), Dec 2024 - Sep 2026. Gentle realistic drift.
INSERT INTO exchange_rates (from_currency, to_currency, rate_date, rate, source)
SELECT c.code, 'USD', (d + INTERVAL '1 month - 1 day')::DATE,
       round(c.base * (1 + c.drift * m.n + 0.012 * sin(m.n)::NUMERIC), 8), 'RBZ / central bank mid-rate (demo)'
  FROM (VALUES ('ZAR', 0.05450, -0.0010), ('KES', 0.00774, 0.0003), ('GBP', 1.27000, 0.0020),
               ('AED', 0.27229, 0.0000), ('EUR', 1.05000, 0.0030), ('ZWG', 0.03730, -0.0015),
               ('BWP', 0.07300, -0.0005), ('ZMW', 0.03600, -0.0008)) AS c(code, base, drift)
 CROSS JOIN LATERAL (SELECT g::DATE AS d, (row_number() OVER ()) - 1 AS n
                       FROM generate_series('2024-12-01'::DATE, '2026-09-01'::DATE, INTERVAL '1 month') g) m;
UPDATE exchange_rates SET rate = 0.27229 WHERE from_currency = 'AED';    -- dirham is pegged

INSERT INTO tax_rates (code, name, rate_percent, country_code, valid_from, tax_kind, gl_account_code) VALUES
 ('ZW-VAT', 'Zimbabwe VAT (standard, ZIMRA)', 15.500, 'ZW', '2023-01-01', 'vat', '2200'),
 ('ZA-VAT', 'South Africa VAT (SARS)',        15.000, 'ZA', '2018-04-01', 'vat', '2201'),
 ('KE-VAT', 'Kenya VAT (KRA)',                16.000, 'KE', '2013-09-02', 'vat', '2202'),
 ('GB-VAT', 'UK VAT (HMRC)',                  20.000, 'GB', '2011-01-04', 'vat', '2203'),
 ('AE-VAT', 'UAE VAT (FTA)',                   5.000, 'AE', '2018-01-01', 'vat', '2204'),
 ('ZERO',   'Zero-rated - exported services',  0.000, NULL, '2000-01-01', 'vat', '2200'),
 ('EXEMPT', 'Exempt',                          0.000, NULL, '2000-01-01', 'vat', '2200');

-- 30.2 Fiscal years (FY2024 holds only the opening balances) ------------------------------
INSERT INTO fiscal_years (name, start_date, end_date)
VALUES ('FY2024','2024-01-01','2024-12-31'), ('FY2025','2025-01-01','2025-12-31'), ('FY2026','2026-01-01','2026-12-31');
INSERT INTO fiscal_periods (fiscal_year_id, period_no, start_date, end_date)
SELECT fy.fiscal_year_id, m, make_date(extract(year FROM fy.start_date)::INT, m, 1),
       (make_date(extract(year FROM fy.start_date)::INT, m, 1) + INTERVAL '1 month - 1 day')::DATE
  FROM fiscal_years fy, generate_series(1, 12) AS m;

INSERT INTO firm_settings (legal_name, trading_name, registration_number, tax_number, vat_number, base_currency,
                           country_code, address, phone, email, website, default_payment_terms_days, default_tax_code,
                           zimra_tin, zimra_bp_number, nssa_employer_number, zimdef_number, praz_number, fiscal_device_serial,
                           date_of_incorporation, functional_currency, presentation_currency, ifrs18_adopted_from,
                           expense_presentation, auditor_name, company_secretary, email_domain)
VALUES ('Maxhub Pvt Ltd', 'Maxhub Forensic Data Analytics', '4521/2012', '2000451236', '220451236', 'USD', 'ZW',
        'Maxhub House, 45 Enterprise Road, Highlands, Harare, Zimbabwe', '+263 242 700 100', 'info@maxhub.co.zw',
        'www.maxhub.co.zw', 30, 'ZW-VAT', '2000451236', '0200451236', 'NSSA-EMP-0045123', 'ZDF-11873', 'PRAZ-SP-20931',
        'VD-MXH-0001', '2012-05-14', 'USD', 'USD', '2026-01-01', 'nature', 'Chartered Assurance Partners (Chartered Accountants Zimbabwe)',
        'Ruvimbo Zvobgo', 'maxhub.co.zw');

INSERT INTO document_sequences (doc_type, prefix, padding) VALUES
 ('invoice','INV-',5), ('payment','RCT-',5), ('journal','JE-',6),
 ('expense_report','EXP-',5), ('purchase_order','PO-',5), ('credit_note','CN-',5);

INSERT INTO activity_codes (activity_code, name, is_chargeable, counts_as_capacity_reduction) VALUES
 ('CLIENT','Client engagement work',TRUE,FALSE), ('BD','Business development & proposals',FALSE,FALSE),
 ('ADMIN','Firm administration',FALSE,FALSE), ('TRAINING','Training & CPD',FALSE,FALSE),
 ('KM','Knowledge management & methodology',FALSE,FALSE), ('LEAVE','Leave',FALSE,TRUE), ('HOLIDAY','Public holiday',FALSE,TRUE);

INSERT INTO public_holidays (country_code, holiday_date, name) VALUES
 ('ZW','2025-01-01','New Year''s Day'), ('ZW','2025-02-21','National Youth Day'), ('ZW','2025-04-18','Good Friday / Independence Day'),
 ('ZW','2025-04-21','Easter Monday'), ('ZW','2025-05-01','Workers'' Day'), ('ZW','2025-05-26','Africa Day (observed)'),
 ('ZW','2025-08-11','Heroes'' Day'), ('ZW','2025-08-12','Defence Forces Day'), ('ZW','2025-12-22','Unity Day'),
 ('ZW','2025-12-25','Christmas Day'), ('ZW','2025-12-26','Boxing Day'),
 ('ZW','2026-01-01','New Year''s Day'), ('ZW','2026-02-21','National Youth Day'), ('ZW','2026-04-03','Good Friday'),
 ('ZW','2026-04-06','Easter Monday'), ('ZW','2026-04-18','Independence Day'), ('ZW','2026-05-01','Workers'' Day'),
 ('ZW','2026-05-25','Africa Day'), ('ZW','2026-08-10','Heroes'' Day'), ('ZW','2026-08-11','Defence Forces Day'),
 ('ZW','2026-12-22','Unity Day'), ('ZW','2026-12-25','Christmas Day'), ('ZW','2026-12-26','Boxing Day'),
 ('ZA','2026-03-21','Human Rights Day'), ('ZA','2026-04-27','Freedom Day'), ('ZA','2026-06-16','Youth Day'),
 ('ZA','2026-08-10','National Women''s Day (observed)'), ('ZA','2026-09-24','Heritage Day'),
 ('KE','2026-06-01','Madaraka Day'), ('KE','2026-10-20','Mashujaa Day'),
 ('GB','2026-05-04','Early May bank holiday'), ('GB','2026-05-25','Spring bank holiday'), ('GB','2026-08-31','Summer bank holiday'),
 ('AE','2026-03-20','Eid al-Fitr'), ('AE','2026-05-27','Eid al-Adha'), ('AE','2026-12-02','National Day');

-- 30.3 IFRS structure ---------------------------------------------------------------------
INSERT INTO ifrs_line_items (line_code, statement, section, name, ifrs18_category, sort_order, sign, standard_ref, nature_disclosure) VALUES
 -- Statement of profit or loss (by nature), IFRS 18 categories
 ('PL_REV',      'PL', 'Operating', 'Revenue from contracts with customers', 'operating', 10, 1, 'IFRS 15', NULL),
 ('PL_OOI',      'PL', 'Operating', 'Other operating income (incl. FX & disposal gains)', 'operating', 20, 1, 'IFRS 18.47', NULL),
 ('PL_EMP',      'PL', 'Operating', 'Employee benefits expense', 'operating', 30, 1, 'IAS 19; IFRS 18.83', 'employee_benefits'),
 ('PL_SUB',      'PL', 'Operating', 'Subcontractors and direct engagement costs', 'operating', 40, 1, 'IFRS 18', NULL),
 ('PL_PREM',     'PL', 'Operating', 'Premises and occupancy costs', 'operating', 50, 1, 'IFRS 16.6', NULL),
 ('PL_TECH',     'PL', 'Operating', 'Technology and communication costs', 'operating', 60, 1, NULL, NULL),
 ('PL_DEP',      'PL', 'Operating', 'Depreciation and amortisation', 'operating', 70, 1, 'IAS 16; IAS 38; IFRS 16', 'depreciation_amortisation'),
 ('PL_ECL',      'PL', 'Operating', 'Impairment losses on trade receivables', 'operating', 80, 1, 'IFRS 9; IFRS 18.82', 'impairment'),
 ('PL_OPEX',     'PL', 'Operating', 'Other operating expenses (incl. FX & disposal losses)', 'operating', 90, 1, NULL, NULL),
 ('PL_INV_RENT', 'PL', 'Investing', 'Rental income from investment property', 'investing', 200, 1, 'IAS 40; IFRS 18.53', NULL),
 ('PL_INV_FV',   'PL', 'Investing', 'Fair value gain on investment property', 'investing', 210, 1, 'IAS 40.35', NULL),
 ('PL_INV_INT',  'PL', 'Investing', 'Interest and dividend income', 'investing', 220, 1, 'IFRS 18.53', NULL),
 ('PL_FIN_LEASE','PL', 'Financing', 'Interest expense on lease liabilities', 'financing', 300, 1, 'IFRS 16.49; IFRS 18.61', NULL),
 ('PL_FIN_BORR', 'PL', 'Financing', 'Interest expense on borrowings', 'financing', 310, 1, 'IFRS 18.59', NULL),
 ('PL_TAX',      'PL', 'Income taxes', 'Income tax expense', 'income_taxes', 400, 1, 'IAS 12', NULL),
 ('PL_DISC',     'PL', 'Discontinued', 'Profit from discontinued operations', 'discontinued', 500, 1, 'IFRS 5', NULL),
 -- Other comprehensive income
 ('OCI_REVAL',   'OCI','Items that will not be reclassified to profit or loss', 'Revaluation of land and buildings, net of tax', NULL, 600, 1, 'IAS 16.39', NULL),
 ('OCI_FX',      'OCI','Items that may be reclassified to profit or loss', 'Exchange differences on translating foreign operations', NULL, 610, 1, 'IAS 21.39', NULL),
 -- Statement of financial position (sign -1 = debit balance shown positive)
 ('SFP_PPE',     'SFP','Non-current assets', 'Property, plant and equipment', NULL, 1010, -1, 'IAS 16', NULL),
 ('SFP_ROU',     'SFP','Non-current assets', 'Right-of-use assets', NULL, 1020, -1, 'IFRS 16', NULL),
 ('SFP_IP',      'SFP','Non-current assets', 'Investment property', NULL, 1030, -1, 'IAS 40', NULL),
 ('SFP_INT',     'SFP','Non-current assets', 'Intangible assets', NULL, 1040, -1, 'IAS 38', NULL),
 ('SFP_DTA',     'SFP','Non-current assets', 'Deferred tax assets', NULL, 1050, -1, 'IAS 12', NULL),
 ('SFP_ONCA',    'SFP','Non-current assets', 'Other non-current assets (rental deposits)', NULL, 1060, -1, NULL, NULL),
 ('SFP_TR',      'SFP','Current assets', 'Trade and other receivables', NULL, 2010, -1, 'IFRS 9', NULL),
 ('SFP_CA15',    'SFP','Current assets', 'Contract assets (unbilled work)', NULL, 2020, -1, 'IFRS 15.105', NULL),
 ('SFP_PREP',    'SFP','Current assets', 'Prepayments', NULL, 2030, -1, NULL, NULL),
 ('SFP_TAX_A',   'SFP','Current assets', 'Current tax receivable', NULL, 2040, -1, 'IAS 12', NULL),
 ('SFP_CASH',    'SFP','Current assets', 'Cash and cash equivalents', NULL, 2050, -1, 'IAS 7', NULL),
 ('SFP_SC',      'SFP','Equity', 'Share capital', NULL, 3010, 1, NULL, NULL),
 ('SFP_REVAL',   'SFP','Equity', 'Revaluation reserve', NULL, 3020, 1, 'IAS 16.41', NULL),
 ('SFP_FXRES',   'SFP','Equity', 'Foreign currency translation reserve', NULL, 3030, 1, 'IAS 21', NULL),
 ('SFP_RE',      'SFP','Equity', 'Retained earnings', NULL, 3040, 1, NULL, NULL),
 ('SFP_BORR',    'SFP','Non-current liabilities', 'Borrowings', NULL, 4010, 1, 'IFRS 9', NULL),
 ('SFP_LEASE',   'SFP','Non-current liabilities', 'Lease liabilities', NULL, 4020, 1, 'IFRS 16', NULL),
 ('SFP_DTL',     'SFP','Non-current liabilities', 'Deferred tax liabilities', NULL, 4030, 1, 'IAS 12', NULL),
 ('SFP_PROV_NC', 'SFP','Non-current liabilities', 'Provisions', NULL, 4040, 1, 'IAS 37', NULL),
 ('SFP_TP',      'SFP','Current liabilities', 'Trade and other payables', NULL, 5010, 1, NULL, NULL),
 ('SFP_EMP',     'SFP','Current liabilities', 'Employee benefit obligations', NULL, 5020, 1, 'IAS 19', NULL),
 ('SFP_STAT',    'SFP','Current liabilities', 'VAT, PAYE, NSSA and other statutory liabilities', NULL, 5030, 1, NULL, NULL),
 ('SFP_TAX_L',   'SFP','Current liabilities', 'Current tax payable', NULL, 5040, 1, 'IAS 12', NULL),
 ('SFP_CL15',    'SFP','Current liabilities', 'Contract liabilities (client advances)', NULL, 5050, 1, 'IFRS 15.106', NULL),
 ('SFP_LEASE_C', 'SFP','Current liabilities', 'Lease liabilities - current portion', NULL, 5060, 1, 'IFRS 16', NULL),
 ('SFP_BORR_C',  'SFP','Current liabilities', 'Borrowings - current portion', NULL, 5070, 1, NULL, NULL);

INSERT INTO cash_flow_lines (cf_code, category, name, sort_order) VALUES
 ('CF_OP_RECEIPTS',   'operating', 'Cash receipts from clients', 10),
 ('CF_OP_OTHER_REC',  'operating', 'Other operating receipts', 20),
 ('CF_OP_SUPPLIERS',  'operating', 'Cash paid to suppliers', 30),
 ('CF_OP_EMPLOYEES',  'operating', 'Cash paid to and on behalf of employees (incl. PAYE & NSSA)', 40),
 ('CF_OP_TAXES',      'operating', 'VAT paid to tax authorities (net)', 50),
 ('CF_OP_INCOME_TAX', 'operating', 'Income taxes paid (QPDs and final)', 60),
 ('CF_INV_PPE',       'investing', 'Purchase of property, plant, equipment and intangibles', 200),
 ('CF_INV_DISPOSAL',  'investing', 'Proceeds from disposal of property, plant and equipment', 210),
 ('CF_INV_RENT',      'investing', 'Rental income received from investment property', 220),
 ('CF_INV_INTEREST',  'investing', 'Interest and dividends received', 230),
 ('CF_FIN_BORROW',    'financing', 'Repayment of borrowings', 300),
 ('CF_FIN_LEASE',     'financing', 'Principal elements of lease payments', 310),
 ('CF_FIN_INTEREST',  'financing', 'Interest paid (lease liabilities and borrowings)', 320),
 ('CF_FIN_DIVIDENDS', 'financing', 'Dividends paid to shareholders', 330),
 ('CF_FIN_SHARES',    'financing', 'Proceeds from issue of shares', 340),
 ('CF_FX',            'fx',        'Effect of exchange rate changes on cash and cash equivalents', 499);

-- 30.4 Chart of accounts ------------------------------------------------------------------
INSERT INTO chart_of_accounts (account_code, name, account_type, is_postable) VALUES
 ('1000','ASSETS','asset',FALSE), ('2000','LIABILITIES','liability',FALSE), ('3000','EQUITY','equity',FALSE),
 ('4000-H','REVENUE & OTHER INCOME','revenue',FALSE), ('5000-H','EMPLOYEE & ENGAGEMENT COSTS','expense',FALSE),
 ('6000-H','OPERATING EXPENSES','expense',FALSE), ('7000-H','DEPRECIATION, IMPAIRMENT & OTHER','expense',FALSE),
 ('8000-H','FINANCE COSTS','expense',FALSE), ('9000-H','INCOME TAX','expense',FALSE);

INSERT INTO chart_of_accounts (account_code, name, account_type, parent_account_id, ifrs_line_code, cash_flow_code, is_cash, is_control)
SELECT v.code, v.name, v.t::account_type, (SELECT account_id FROM chart_of_accounts WHERE account_code = v.parent),
       v.ifrs, v.cf, v.cash, v.ctrl
  FROM (VALUES
   -- cash & cash equivalents
   ('1010','Bank - CBZ USD Current (Harare HQ)',        'asset','1000','SFP_CASH',NULL,TRUE,FALSE),
   ('1011','Bank - Stanbic ZWG Current',                'asset','1000','SFP_CASH',NULL,TRUE,FALSE),
   ('1012','Bank - FNB ZAR (Johannesburg)',             'asset','1000','SFP_CASH',NULL,TRUE,FALSE),
   ('1013','Bank - Stanbic USD Nostro (client receipts)','asset','1000','SFP_CASH',NULL,TRUE,FALSE),
   ('1014','Bank - NCBA KES (Nairobi)',                 'asset','1000','SFP_CASH',NULL,TRUE,FALSE),
   ('1015','Bank - Barclays GBP (London)',              'asset','1000','SFP_CASH',NULL,TRUE,FALSE),
   ('1016','Bank - Emirates NBD AED (Dubai)',           'asset','1000','SFP_CASH',NULL,TRUE,FALSE),
   ('1017','Money market call deposit - USD',           'asset','1000','SFP_CASH',NULL,TRUE,FALSE),
   ('1018','Bank - CABS USD (Bulawayo)',                'asset','1000','SFP_CASH',NULL,TRUE,FALSE),
   ('1020','Petty cash',                                'asset','1000','SFP_CASH',NULL,TRUE,FALSE),
   -- receivables
   ('1100','Trade receivables',                         'asset','1000','SFP_TR','CF_OP_RECEIPTS',FALSE,TRUE),
   ('1105','Loss allowance - expected credit losses',   'asset','1000','SFP_TR','CF_OP_RECEIPTS',FALSE,FALSE),
   ('1150','Contract assets - unbilled revenue (WIP)',  'asset','1000','SFP_CA15','CF_OP_RECEIPTS',FALSE,FALSE),
   ('1200','Staff advances & loans',                    'asset','1000','SFP_TR','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('1210','Tenant & other receivables',                'asset','1000','SFP_TR','CF_INV_RENT',FALSE,FALSE),
   ('1300','Prepayments',                               'asset','1000','SFP_PREP','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('1310','Rental & utility deposits (current)',       'asset','1000','SFP_TR','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('1420','Withholding tax credits receivable',        'asset','1000','SFP_TR','CF_OP_RECEIPTS',FALSE,FALSE),
   -- PPE (IAS 16)
   ('1500','Land - at valuation',                       'asset','1000','SFP_PPE','CF_INV_PPE',FALSE,TRUE),
   ('1510','Buildings - at valuation',                  'asset','1000','SFP_PPE','CF_INV_PPE',FALSE,TRUE),
   ('1511','Buildings - accumulated depreciation',      'asset','1000','SFP_PPE','CF_INV_DISPOSAL',FALSE,TRUE),
   ('1520','Motor vehicles - cost',                     'asset','1000','SFP_PPE','CF_INV_PPE',FALSE,TRUE),
   ('1521','Motor vehicles - accumulated depreciation', 'asset','1000','SFP_PPE','CF_INV_DISPOSAL',FALSE,TRUE),
   ('1530','Computer equipment - cost',                 'asset','1000','SFP_PPE','CF_INV_PPE',FALSE,TRUE),
   ('1531','Computer equipment - accumulated depreciation','asset','1000','SFP_PPE','CF_INV_DISPOSAL',FALSE,TRUE),
   ('1540','Furniture & fittings - cost',               'asset','1000','SFP_PPE','CF_INV_PPE',FALSE,TRUE),
   ('1541','Furniture & fittings - accumulated depreciation','asset','1000','SFP_PPE','CF_INV_DISPOSAL',FALSE,TRUE),
   ('1550','Office equipment - cost',                   'asset','1000','SFP_PPE','CF_INV_PPE',FALSE,TRUE),
   ('1551','Office equipment - accumulated depreciation','asset','1000','SFP_PPE','CF_INV_DISPOSAL',FALSE,TRUE),
   ('1560','Leasehold improvements - cost',             'asset','1000','SFP_PPE','CF_INV_PPE',FALSE,TRUE),
   ('1561','Leasehold improvements - accumulated depreciation','asset','1000','SFP_PPE','CF_INV_DISPOSAL',FALSE,TRUE),
   ('1565','Forensic lab equipment - cost',             'asset','1000','SFP_PPE','CF_INV_PPE',FALSE,TRUE),
   ('1566','Forensic lab equipment - accumulated depreciation','asset','1000','SFP_PPE','CF_INV_DISPOSAL',FALSE,TRUE),
   ('1570','Capital work in progress',                  'asset','1000','SFP_PPE','CF_INV_PPE',FALSE,TRUE),
   -- ROU (IFRS 16), investment property (IAS 40), intangibles (IAS 38), other
   ('1600','Right-of-use assets - property',            'asset','1000','SFP_ROU','CF_INV_PPE',FALSE,TRUE),
   ('1601','Right-of-use property - accumulated depreciation','asset','1000','SFP_ROU','CF_INV_PPE',FALSE,TRUE),
   ('1610','Right-of-use assets - vehicles & equipment','asset','1000','SFP_ROU','CF_INV_PPE',FALSE,TRUE),
   ('1611','Right-of-use vehicles - accumulated depreciation','asset','1000','SFP_ROU','CF_INV_PPE',FALSE,TRUE),
   ('1700','Investment property - at fair value',       'asset','1000','SFP_IP','CF_INV_PPE',FALSE,TRUE),
   ('1800','Software & licences - cost',                'asset','1000','SFP_INT','CF_INV_PPE',FALSE,TRUE),
   ('1801','Software & licences - accumulated amortisation','asset','1000','SFP_INT','CF_INV_DISPOSAL',FALSE,TRUE),
   ('1900','Deferred tax asset',                        'asset','1000','SFP_DTA',NULL,FALSE,FALSE),
   ('1950','Long-term rental deposits',                 'asset','1000','SFP_ONCA','CF_OP_SUPPLIERS',FALSE,FALSE),
   -- liabilities
   ('2100','Trade payables',                            'liability','2000','SFP_TP','CF_OP_SUPPLIERS',FALSE,TRUE),
   ('2110','Payables - capital expenditure',            'liability','2000','SFP_TP','CF_INV_PPE',FALSE,TRUE),
   ('2150','Net salaries payable',                      'liability','2000','SFP_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2200','VAT output tax - ZIMRA',                    'liability','2000','SFP_STAT','CF_OP_TAXES',FALSE,FALSE),
   ('2201','VAT output tax - SARS (Johannesburg)',      'liability','2000','SFP_STAT','CF_OP_TAXES',FALSE,FALSE),
   ('2202','VAT output tax - KRA (Nairobi)',            'liability','2000','SFP_STAT','CF_OP_TAXES',FALSE,FALSE),
   ('2203','VAT output tax - HMRC (London)',            'liability','2000','SFP_STAT','CF_OP_TAXES',FALSE,FALSE),
   ('2204','VAT output tax - UAE FTA (Dubai)',          'liability','2000','SFP_STAT','CF_OP_TAXES',FALSE,FALSE),
   ('2210','VAT input tax - ZIMRA',                     'liability','2000','SFP_STAT','CF_OP_TAXES',FALSE,FALSE),
   ('2260','Income tax payable - ZIMRA',                'liability','2000','SFP_TAX_L','CF_OP_INCOME_TAX',FALSE,FALSE),
   ('2265','Income tax payable - branches',             'liability','2000','SFP_TAX_L','CF_OP_INCOME_TAX',FALSE,FALSE),
   ('2300','Employee reimbursements payable',           'liability','2000','SFP_TP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2400','PAYE payable - ZIMRA',                      'liability','2000','SFP_STAT','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2405','AIDS levy payable - ZIMRA',                 'liability','2000','SFP_STAT','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2410','NSSA payable (POBS & WCIF)',                'liability','2000','SFP_STAT','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2415','ZIMDEF levy payable',                       'liability','2000','SFP_STAT','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2420','Pension fund contributions payable',        'liability','2000','SFP_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2425','Medical aid contributions payable',         'liability','2000','SFP_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2430','Withholding tax payable - ZIMRA',           'liability','2000','SFP_STAT','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('2450','Branch payroll taxes & social security payable','liability','2000','SFP_STAT','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2500','Accrued expenses',                          'liability','2000','SFP_TP','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('2510','Leave pay accrual (IAS 19)',                'liability','2000','SFP_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2520','Bonus accrual (IAS 19)',                    'liability','2000','SFP_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('2550','Provisions - dilapidations & legal (IAS 37)','liability','2000','SFP_PROV_NC','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('2600','Contract liabilities - client advances',    'liability','2000','SFP_CL15','CF_OP_RECEIPTS',FALSE,FALSE),
   ('2650','Tenant deposits held',                      'liability','2000','SFP_TP','CF_INV_RENT',FALSE,FALSE),
   ('2700','Lease liabilities (IFRS 16)',               'liability','2000','SFP_LEASE','CF_FIN_LEASE',FALSE,TRUE),
   ('2705','Lease interest payable',                    'liability','2000','SFP_LEASE','CF_FIN_INTEREST',FALSE,FALSE),
   ('2800','Borrowings - CBZ mortgage loan',            'liability','2000','SFP_BORR','CF_FIN_BORROW',FALSE,TRUE),
   ('2900','Deferred tax liability',                    'liability','2000','SFP_DTL',NULL,FALSE,FALSE),
   ('2950','Dividends payable',                         'liability','2000','SFP_TP','CF_FIN_DIVIDENDS',FALSE,FALSE),
   -- equity
   ('3100','Share capital (ordinary shares)',           'equity','3000','SFP_SC','CF_FIN_SHARES',FALSE,FALSE),
   ('3200','Retained earnings',                         'equity','3000','SFP_RE','CF_FIN_DIVIDENDS',FALSE,FALSE),
   ('3300','Revaluation reserve (IAS 16)',              'equity','3000','SFP_REVAL',NULL,FALSE,FALSE),
   ('3400','Foreign currency translation reserve',      'equity','3000','SFP_FXRES',NULL,FALSE,FALSE),
   -- revenue & other income
   ('4000','Fees - time & materials',                   'revenue','4000-H','PL_REV','CF_OP_RECEIPTS',FALSE,FALSE),
   ('4010','Fees - fixed fee & milestones',             'revenue','4000-H','PL_REV','CF_OP_RECEIPTS',FALSE,FALSE),
   ('4020','Retainer fees',                             'revenue','4000-H','PL_REV','CF_OP_RECEIPTS',FALSE,FALSE),
   ('4100','Recoverable expenses billed',               'revenue','4000-H','PL_REV','CF_OP_RECEIPTS',FALSE,FALSE),
   ('4500','Rental income - investment property',       'revenue','4000-H','PL_INV_RENT','CF_INV_RENT',FALSE,FALSE),
   ('4510','Fair value gains - investment property',    'revenue','4000-H','PL_INV_FV',NULL,FALSE,FALSE),
   ('4600','Interest income',                           'revenue','4000-H','PL_INV_INT','CF_INV_INTEREST',FALSE,FALSE),
   ('4610','Dividend income',                           'revenue','4000-H','PL_INV_INT','CF_INV_INTEREST',FALSE,FALSE),
   ('4700','Gain on disposal of PPE',                   'revenue','4000-H','PL_OOI','CF_INV_DISPOSAL',FALSE,FALSE),
   ('4800','Foreign exchange gains',                    'revenue','4000-H','PL_OOI','CF_FX',FALSE,FALSE),
   ('4900','Other income',                              'revenue','4000-H','PL_OOI','CF_OP_OTHER_REC',FALSE,FALSE),
   -- employee benefits (by nature)
   ('5100','Salaries - fee earners',                    'expense','5000-H','PL_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('5110','Salaries - business support',               'expense','5000-H','PL_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('5120','Employer NSSA / social security & WCIF',    'expense','5000-H','PL_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('5125','ZIMDEF & training levies',                  'expense','5000-H','PL_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('5130','Employer pension contributions',            'expense','5000-H','PL_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('5140','Employer medical aid contributions',        'expense','5000-H','PL_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('5150','Staff bonuses',                             'expense','5000-H','PL_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('5160','Leave pay',                                 'expense','5000-H','PL_EMP','CF_OP_EMPLOYEES',FALSE,FALSE),
   ('5170','Staff welfare & recruitment',               'expense','5000-H','PL_EMP','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('5200','Subcontractor fees',                        'expense','5000-H','PL_SUB','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('5300','Project travel',                            'expense','5000-H','PL_SUB','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('5310','Project accommodation',                     'expense','5000-H','PL_SUB','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('5320','Project meals & subsistence',               'expense','5000-H','PL_SUB','CF_OP_SUPPLIERS',FALSE,FALSE),
   -- operating expenses
   ('6100','Short-term & low-value lease rentals',      'expense','6000-H','PL_PREM','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6110','Rates, electricity & water',                'expense','6000-H','PL_PREM','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6120','Repairs & maintenance',                     'expense','6000-H','PL_PREM','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6130','Security & cleaning',                       'expense','6000-H','PL_PREM','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6140','Insurance',                                 'expense','6000-H','PL_OPEX','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6200','Software licences & subscriptions',         'expense','6000-H','PL_TECH','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6210','Cloud hosting & data services',             'expense','6000-H','PL_TECH','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6300','Training & professional subscriptions',     'expense','6000-H','PL_OPEX','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6400','Marketing & business development',          'expense','6000-H','PL_OPEX','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6500','Telephone & internet',                      'expense','6000-H','PL_TECH','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6600','Bank charges',                              'expense','6000-H','PL_OPEX','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6610','IMTT (2% transfer tax)',                    'expense','6000-H','PL_OPEX','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6700','Audit, legal & professional fees',          'expense','6000-H','PL_OPEX','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6710','Non-executive directors'' fees',            'expense','6000-H','PL_OPEX','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6800','Motor vehicle running costs',               'expense','6000-H','PL_OPEX','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6900','General administration',                    'expense','6000-H','PL_OPEX','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('6950','Donations & corporate social responsibility','expense','6000-H','PL_OPEX','CF_OP_SUPPLIERS',FALSE,FALSE),
   ('7000','Depreciation - property, plant & equipment','expense','7000-H','PL_DEP',NULL,FALSE,FALSE),
   ('7010','Depreciation - right-of-use assets',        'expense','7000-H','PL_DEP',NULL,FALSE,FALSE),
   ('7020','Amortisation - intangible assets',          'expense','7000-H','PL_DEP',NULL,FALSE,FALSE),
   ('7100','Impairment losses on trade receivables (ECL)','expense','7000-H','PL_ECL','CF_OP_RECEIPTS',FALSE,FALSE),
   ('7200','Loss on disposal of PPE',                   'expense','7000-H','PL_OPEX','CF_INV_DISPOSAL',FALSE,FALSE),
   ('7300','Foreign exchange losses',                   'expense','7000-H','PL_OPEX','CF_FX',FALSE,FALSE),
   -- financing & tax
   ('8000','Interest on lease liabilities',             'expense','8000-H','PL_FIN_LEASE','CF_FIN_INTEREST',FALSE,FALSE),
   ('8010','Interest on borrowings',                    'expense','8000-H','PL_FIN_BORR','CF_FIN_INTEREST',FALSE,FALSE),
   ('9000','Current tax - Zimbabwe (CIT + AIDS levy)',  'expense','9000-H','PL_TAX','CF_OP_INCOME_TAX',FALSE,FALSE),
   ('9010','Current tax - foreign branches',            'expense','9000-H','PL_TAX','CF_OP_INCOME_TAX',FALSE,FALSE),
   ('9020','Deferred tax',                              'expense','9000-H','PL_TAX',NULL,FALSE,FALSE)
  ) AS v(code, name, t, parent, ifrs, cf, cash, ctrl);

INSERT INTO cash_flow_source_overrides (source_type, cf_code) VALUES
 ('asset_disposal','CF_INV_DISPOSAL'), ('payroll_payment','CF_OP_EMPLOYEES'), ('dividend','CF_FIN_DIVIDENDS');

-- IFRS 9 provision matrix (simplified approach, lifetime ECL)
INSERT INTO ecl_provision_matrix (bucket, min_days, max_days, loss_rate_pct, sort_order) VALUES
 ('Current', 0, 0, 0.50, 1), ('1-30', 1, 30, 1.50, 2), ('31-60', 31, 60, 4.00, 3),
 ('61-90', 61, 90, 10.00, 4), ('90+', 91, NULL, 35.00, 5);

-- IFRS 18 management-defined performance measures
INSERT INTO mpm_definitions (mpm_code, name, description, why_useful, base_subtotal, sort_order) VALUES
 ('ADJ_OP', 'Adjusted operating profit',
  'Operating profit excluding foreign exchange gains and losses and gains/losses on disposal of property, plant and equipment.',
  'Management uses it to assess the performance of the consulting business without currency movements and one-off asset sales, and it is the basis of the staff bonus pool.',
  'Operating profit', 1),
 ('ADJ_EBITDA', 'Adjusted EBITDA',
  'Operating profit before depreciation, amortisation, foreign exchange differences and gains/losses on disposal of PPE.',
  'Used by the Board and by CBZ Bank in the mortgage-loan covenant (net debt / adjusted EBITDA) to measure cash-generating capacity.',
  'Operating profit', 2);
INSERT INTO mpm_adjustments (mpm_code, account_id, caption)
SELECT m, fn_account_id(a), c FROM (VALUES
  ('ADJ_OP','4800','Foreign exchange differences'), ('ADJ_OP','7300','Foreign exchange differences'),
  ('ADJ_OP','4700','(Gain) / loss on disposal of PPE'), ('ADJ_OP','7200','(Gain) / loss on disposal of PPE'),
  ('ADJ_EBITDA','7000','Depreciation and amortisation'), ('ADJ_EBITDA','7010','Depreciation and amortisation'),
  ('ADJ_EBITDA','7020','Depreciation and amortisation'),
  ('ADJ_EBITDA','4800','Foreign exchange differences'), ('ADJ_EBITDA','7300','Foreign exchange differences'),
  ('ADJ_EBITDA','4700','(Gain) / loss on disposal of PPE'), ('ADJ_EBITDA','7200','(Gain) / loss on disposal of PPE')) AS x(m, a, c);

-- 30.5 Tax authorities, tax types, statutory rates, PAYE tables ---------------------------
INSERT INTO tax_authorities (authority_code, name, country_code, website, portal_name) VALUES
 ('ZIMRA',  'Zimbabwe Revenue Authority', 'ZW', 'www.zimra.co.zw', 'TaRMS'),
 ('NSSA',   'National Social Security Authority', 'ZW', 'www.nssa.org.zw', 'NSSA e-Services'),
 ('ZIMDEF', 'Zimbabwe Manpower Development Fund', 'ZW', 'www.zimdef.org.zw', 'ZIMDEF returns'),
 ('SARS',   'South African Revenue Service', 'ZA', 'www.sars.gov.za', 'eFiling'),
 ('KRA',    'Kenya Revenue Authority', 'KE', 'www.kra.go.ke', 'iTax'),
 ('HMRC',   'HM Revenue & Customs', 'GB', 'www.gov.uk/hmrc', 'PAYE Online / MTD'),
 ('UAEFTA', 'Federal Tax Authority (UAE)', 'AE', 'tax.gov.ae', 'EmaraTax');

INSERT INTO tax_types (tax_code, name, authority_code, return_form, frequency, due_day, liability_account_code, offset_account_code, description) VALUES
 ('VAT',      'Value Added Tax (15.5%)',                 'ZIMRA','VAT7',       'monthly', 25, '2200', '2210', 'Output tax less input tax; Category C monthly filer; fiscalised invoices (FDMS).'),
 ('PAYE',     'PAYE + AIDS levy',                        'ZIMRA','P2',         'monthly', 10, '2400', NULL,   'Employees tax per ZIMRA tables plus 3% AIDS levy on the tax; ITF16 annual reconciliation.'),
 ('NSSA',     'NSSA POBS & WCIF contributions',          'NSSA', 'P4',         'monthly', 10, '2410', NULL,   '4.5% employee + 4.5% employer on insurable earnings (ceiling USD 700) plus employer WCIF.'),
 ('ZIMDEF',   'ZIMDEF manpower development levy (1%)',   'ZIMDEF','ZIMDEF return','monthly', 10, '2415', NULL, '1% of the gross wage bill, employer only.'),
 ('WHT',      'Withholding taxes (30% tender / 15% non-resident fees)', 'ZIMRA','REV5','monthly', 10, '2430', NULL, 'Tax withheld from supplier payments and paid over to ZIMRA.'),
 ('CIT_QPD',  'Corporate income tax - QPD instalment',   'ZIMRA','ITF12B',     'qpd',     NULL, '2260', NULL, 'QPDs: 25 Mar 10%, 25 Jun 25%, 25 Sep 30%, 20 Dec 35% of estimated tax.'),
 ('CIT_FINAL','Corporate income tax - final return',     'ZIMRA','ITF12C',     'annual',  30,   '2260', NULL, 'Annual self-assessment return due 30 April; balance of tax payable.'),
 ('IMTT',     'Intermediated Money Transfer Tax (2%)',   'ZIMRA',NULL,         'per_transaction', NULL, NULL, NULL, 'Deducted by banks on electronic transfers; expensed in 6610.'),
 ('ZA_PAYE',  'SARS PAYE, UIF & SDL',                    'SARS', 'EMP201',     'monthly', 7,  '2450', NULL, 'Johannesburg branch payroll taxes.'),
 ('ZA_VAT',   'SARS VAT (15%)',                          'SARS', 'VAT201',     'bi_monthly', 25, '2201', NULL, 'Johannesburg branch VAT.'),
 ('ZA_CIT',   'SARS corporate income tax (27%)',         'SARS', 'ITR14',      'annual',  NULL, '2265', NULL, 'Tax on profits of the South African branch (permanent establishment).'),
 ('KE_PAYE',  'KRA PAYE, NSSF, SHIF & housing levy',     'KRA',  'P10',        'monthly', 9,  '2450', NULL, 'Nairobi branch payroll taxes.'),
 ('KE_VAT',   'KRA VAT (16%)',                           'KRA',  'VAT3',       'monthly', 20, '2202', NULL, 'Nairobi branch VAT.'),
 ('KE_CIT',   'KRA corporation tax - branch (30%)',      'KRA',  'IT2C',       'annual',  NULL, '2265', NULL, 'Kenyan branch profits.'),
 ('GB_PAYE',  'HMRC PAYE & National Insurance',          'HMRC', 'RTI FPS/EPS','monthly', 22, '2450', NULL, 'London branch payroll taxes.'),
 ('GB_VAT',   'HMRC VAT (20%)',                          'HMRC', 'VAT100 (MTD)','quarterly', 7, '2203', NULL, 'London branch VAT.'),
 ('GB_CT',    'HMRC corporation tax (25%)',              'HMRC', 'CT600',      'annual',  NULL, '2265', NULL, 'UK permanent establishment profits.'),
 ('AE_VAT',   'UAE VAT (5%)',                            'UAEFTA','VAT201',    'quarterly', 28, '2204', NULL, 'Dubai branch VAT.'),
 ('AE_CT',    'UAE corporate tax (9%)',                  'UAEFTA','CT return', 'annual',  NULL, '2265', NULL, '9% on taxable income above AED 375,000.');

INSERT INTO statutory_rates (country_code, rate_code, description, rate_pct, amount, currency_code, effective_from, source_note) VALUES
 ('ZW','CIT',                  'Corporate income tax rate', 24.000, NULL, NULL, '2023-01-01', 'Income Tax Act [Chapter 23:06]'),
 ('ZW','AIDS_LEVY',            'AIDS levy on income tax / PAYE', 3.000, NULL, NULL, '2000-01-01', 'Finance Act'),
 ('ZW','VAT',                  'VAT standard rate', 15.500, NULL, NULL, '2023-01-01', 'Finance Act 2023'),
 ('ZW','NSSA_EE',              'NSSA POBS - employee share', 4.500, NULL, NULL, '2019-01-01', 'SI 2019; verify NSSA notices'),
 ('ZW','NSSA_ER',              'NSSA POBS - employer share', 4.500, NULL, NULL, '2019-01-01', 'SI 2019; verify NSSA notices'),
 ('ZW','NSSA_CEILING',         'NSSA insurable earnings ceiling (per month)', NULL, 700.00, 'USD', '2024-01-01', 'NSSA; verify current ceiling'),
 ('ZW','NSSA_WCIF',            'Workers Compensation Insurance Fund - employer (industry rate)', 1.000, NULL, NULL, '2024-01-01', 'Rate depends on industry class'),
 ('ZW','ZIMDEF',               'ZIMDEF levy - employer, % of wage bill', 1.000, NULL, NULL, '1996-01-01', 'Manpower Planning & Development Act'),
 ('ZW','PENSION_EE',           'Company pension fund - employee contribution (% of basic)', 5.000, NULL, NULL, '2015-01-01', 'Maxhub Staff Pension Fund rules'),
 ('ZW','PENSION_ER',           'Company pension fund - employer contribution (% of basic)', 7.500, NULL, NULL, '2015-01-01', 'Maxhub Staff Pension Fund rules'),
 ('ZW','PENSION_CAP',          'Deductible pension contributions cap (per month)', NULL, 450.00, 'USD', '2023-01-01', 'USD 5,400 per year'),
 ('ZW','MEDICAL_CREDIT',       'Medical aid tax credit (% of contributions)', 50.000, NULL, NULL, '2020-01-01', 'Income Tax Act credits'),
 ('ZW','WHT_TENDER',           'Withholding on payments to suppliers without ITF263 tax clearance', 30.000, NULL, NULL, '2015-01-01', 'Section 80 Income Tax Act'),
 ('ZW','WHT_TENDER_THRESHOLD', 'Threshold for 30% withholding (per contract)', NULL, 1000.00, 'USD', '2019-01-01', 'Verify current ZIMRA threshold'),
 ('ZW','WHT_NONRES_FEES',      'Non-residents tax on fees', 15.000, NULL, NULL, '2019-01-01', 'Income Tax Act'),
 ('ZW','WHT_DIVIDENDS',        'Resident shareholders tax on dividends (unlisted)', 10.000, NULL, NULL, '2019-01-01', 'Income Tax Act'),
 ('ZW','IMTT',                 'Intermediated Money Transfer Tax', 2.000, NULL, NULL, '2018-10-01', 'Finance Act'),
 ('ZW','CGT',                  'Capital gains tax', 20.000, NULL, NULL, '2019-01-01', 'Capital Gains Tax Act'),
 ('ZA','CIT','SA corporate income tax', 27.000, NULL, NULL, '2022-04-01', 'SARS'),
 ('ZA','INCOME_TAX_EFFECTIVE','Branch payroll: effective PAYE rate (simplified)', 24.000, NULL, NULL, '2025-03-01', 'Simplified - use SARS tables in production'),
 ('ZA','SOCIAL_EE','UIF - employee', 1.000, NULL, NULL, '2021-06-01', 'UIF'),
 ('ZA','SOCIAL_ER','UIF - employer', 1.000, NULL, NULL, '2021-06-01', 'UIF'),
 ('ZA','SOCIAL_CEILING','UIF earnings ceiling (per month)', NULL, 17712.00, 'ZAR', '2021-06-01', 'UIF'),
 ('ZA','OTHER_ER','Skills Development Levy - employer', 1.000, NULL, NULL, '2001-01-01', 'SDL'),
 ('ZA','PENSION_EE','Provident fund - employee', 5.000, NULL, NULL, '2020-01-01', 'Company scheme'),
 ('ZA','PENSION_ER','Provident fund - employer', 5.000, NULL, NULL, '2020-01-01', 'Company scheme'),
 ('KE','CIT','Kenya corporation tax - branch', 30.000, NULL, NULL, '2023-07-01', 'KRA'),
 ('KE','INCOME_TAX_EFFECTIVE','Branch payroll: effective PAYE rate incl. SHIF & housing levy (simplified)', 28.000, NULL, NULL, '2025-01-01', 'Simplified'),
 ('KE','SOCIAL_EE','NSSF - employee', 6.000, NULL, NULL, '2025-02-01', 'NSSF Act 2013 phase 3'),
 ('KE','SOCIAL_ER','NSSF - employer', 6.000, NULL, NULL, '2025-02-01', 'NSSF Act 2013 phase 3'),
 ('KE','SOCIAL_CEILING','NSSF upper earnings limit (per month)', NULL, 72000.00, 'KES', '2025-02-01', 'NSSF'),
 ('KE','OTHER_ER','Affordable housing levy - employer', 1.500, NULL, NULL, '2024-03-19', 'Affordable Housing Act 2024'),
 ('GB','CIT','UK corporation tax (main rate)', 25.000, NULL, NULL, '2023-04-01', 'HMRC'),
 ('GB','INCOME_TAX_EFFECTIVE','Branch payroll: effective income tax rate (simplified)', 22.000, NULL, NULL, '2025-04-06', 'Simplified'),
 ('GB','SOCIAL_EE','Employee Class 1 NIC', 8.000, NULL, NULL, '2024-04-06', 'HMRC'),
 ('GB','SOCIAL_ER','Employer Class 1 NIC', 15.000, NULL, NULL, '2025-04-06', 'HMRC'),
 ('GB','PENSION_EE','Workplace pension - employee (auto-enrolment)', 5.000, NULL, NULL, '2019-04-06', 'The Pensions Regulator'),
 ('GB','PENSION_ER','Workplace pension - employer (auto-enrolment)', 3.000, NULL, NULL, '2019-04-06', 'The Pensions Regulator'),
 ('AE','CIT','UAE corporate tax (above AED 375,000)', 9.000, NULL, NULL, '2023-06-01', 'Federal Decree-Law 47/2022'),
 ('AE','INCOME_TAX_EFFECTIVE','No personal income tax', 0.000, NULL, NULL, '2000-01-01', 'UAE');

-- ZIMRA USD PAYE tables (monthly). Verify every January against the ZIMRA tax tables.
INSERT INTO paye_tax_bands (country_code, currency_code, effective_from, lower_limit, upper_limit, rate_pct, deduct_amount)
SELECT 'ZW', 'USD', y.d, b.lo, b.hi, b.rate, b.less
  FROM (VALUES ('2025-01-01'::DATE), ('2026-01-01'::DATE)) AS y(d)
 CROSS JOIN (VALUES (0.00, 100.00, 0, 0), (100.01, 300.00, 20, 20), (300.01, 1000.00, 25, 35),
                    (1000.01, 2000.00, 30, 85), (2000.01, 3000.00, 35, 185), (3000.01, NULL, 40, 335)) AS b(lo, hi, rate, less);

-- 30.6 Security: roles, permissions, policy ----------------------------------------------
INSERT INTO security_policy (policy_id) VALUES (1);

INSERT INTO roles (code, name, description, is_system) VALUES
 ('ADMIN',           'System Administrator',        'Full access to every module, users, roles and audit logs (ICT managers)', TRUE),
 ('EXECUTIVE',       'Executive / Partner',         'Partners, directors and the executive team - all business pages and approvals', TRUE),
 ('FINANCE_MANAGER', 'Finance Manager',             'CFO, financial controller & finance managers - GL, billing, tax, assets, leases, reporting', TRUE),
 ('ACCOUNTANT',      'Accountant',                  'Finance department staff - billing, receipts, journals, statements', TRUE),
 ('TAX_OFFICER',     'Tax Compliance Officer',      'Prepares and files ZIMRA / NSSA returns', TRUE),
 ('HR_MANAGER',      'HR Manager',                  'People records, leave, payroll approval, announcements', TRUE),
 ('PAYROLL_OFFICER', 'Payroll / HR Officer',        'Runs payroll and views payslips', TRUE),
 ('PROJECT_MANAGER', 'Engagement Manager',          'Manages engagements, approves team timesheets and expenses', TRUE),
 ('CONSULTANT',      'Consultant',                  'Client-service staff - projects, timesheets, expenses', TRUE),
 ('BD_MANAGER',      'Marketing & BD',              'CRM: clients, leads, opportunities', TRUE),
 ('FACILITIES',      'Facilities & Procurement',    'Fixed-asset register, maintenance, office leases', TRUE),
 ('IT_SUPPORT',      'IT Support',                  'IT equipment register, user accounts and password resets', TRUE),
 ('AUDITOR',         'Internal Audit / Compliance', 'Read-only access to finance, tax, assets and the audit trail', TRUE),
 ('EMPLOYEE',        'Employee self-service',       'Every staff member: home, timesheets, expenses, leave, messages', TRUE);

INSERT INTO permissions (code, module, description) VALUES
 ('page.home','pages','Home / my workspace'), ('page.dashboard','pages','Firm dashboard (KPIs)'),
 ('page.projects','pages','Projects'), ('page.timesheets','pages','Timesheets'), ('page.expenses','pages','Expense claims'),
 ('page.crm','pages','CRM'), ('page.billing','pages','Billing & receivables'), ('page.finance','pages','General ledger & budgets'),
 ('page.reports','pages','IFRS financial statements'), ('page.people','pages','People & leave'), ('page.payroll','pages','Payroll'),
 ('page.assets','pages','Fixed assets'), ('page.leases','pages','Leases & borrowings'), ('page.tax','pages','Tax compliance (ZIMRA/NSSA)'),
 ('page.comms','pages','Messages, announcements & directory'), ('page.admin','pages','Administration (users, roles, audit)'),
 ('timesheet.approve','time','Approve timesheets of direct reports'), ('timesheet.approve_all','time','Approve any timesheet'),
 ('expense.approve','expenses','Approve expense claims of direct reports'), ('expense.approve_all','expenses','Approve any expense claim'),
 ('project.manage','projects','Create/update projects, risks, issues, status reports'),
 ('client.manage','crm','Create clients, leads and opportunities'),
 ('invoice.issue','billing','Generate and issue invoices'), ('payment.record','billing','Record client receipts'),
 ('gl.post','finance','Post manual journals'), ('report.financial','finance','View financial statements & firm financial KPIs'),
 ('employee.manage','hr','Maintain employee records, onboard logins'), ('leave.approve_all','hr','Approve any leave request'),
 ('payroll.run','payroll','Run and approve payroll'), ('payroll.view_all','payroll','See every payslip'),
 ('asset.manage','assets','Maintain the asset register, assignments, maintenance'), ('depreciation.run','assets','Run monthly depreciation'),
 ('lease.manage','leases','Maintain leases and post monthly lease accounting'),
 ('tax.manage','tax','Prepare, file and pay tax returns'),
 ('announcement.publish','comms','Publish company announcements'), ('message.all_staff','comms','Message all-staff lists'),
 ('user.manage','admin','Create users, reset passwords, unlock accounts, change roles'), ('audit.view','admin','View audit trail & login history');

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
  FROM roles r JOIN permissions p ON
       r.code = 'ADMIN'
    OR (r.code = 'EMPLOYEE'        AND p.code IN ('page.home','page.timesheets','page.expenses','page.people','page.comms'))
    OR (r.code = 'CONSULTANT'      AND p.code IN ('page.projects'))
    OR (r.code = 'PROJECT_MANAGER' AND p.code IN ('page.projects','page.dashboard','page.crm','project.manage','timesheet.approve','expense.approve'))
    OR (r.code = 'EXECUTIVE'       AND (p.code LIKE 'page.%' AND p.code <> 'page.admin'
                                        OR p.code IN ('timesheet.approve','timesheet.approve_all','expense.approve','expense.approve_all',
                                                      'leave.approve_all','project.manage','client.manage','invoice.issue','report.financial',
                                                      'payroll.view_all','announcement.publish','message.all_staff','audit.view')))
    OR (r.code = 'FINANCE_MANAGER' AND p.code IN ('page.dashboard','page.billing','page.finance','page.reports','page.assets','page.leases',
                                                  'page.tax','page.payroll','page.crm','invoice.issue','payment.record','gl.post','report.financial',
                                                  'depreciation.run','asset.manage','lease.manage','tax.manage','expense.approve_all','payroll.view_all',
                                                  'announcement.publish'))
    OR (r.code = 'ACCOUNTANT'      AND p.code IN ('page.billing','page.finance','page.reports','page.assets','page.leases','page.tax',
                                                  'invoice.issue','payment.record','gl.post','report.financial'))
    OR (r.code = 'TAX_OFFICER'     AND p.code IN ('page.tax','page.finance','page.reports','page.payroll','tax.manage','report.financial','payroll.view_all'))
    OR (r.code = 'HR_MANAGER'      AND p.code IN ('page.people','page.payroll','employee.manage','leave.approve_all','payroll.run','payroll.view_all',
                                                  'announcement.publish','message.all_staff'))
    OR (r.code = 'PAYROLL_OFFICER' AND p.code IN ('page.payroll','payroll.run','payroll.view_all'))
    OR (r.code = 'BD_MANAGER'      AND p.code IN ('page.crm','page.dashboard','client.manage'))
    OR (r.code = 'FACILITIES'      AND p.code IN ('page.assets','page.leases','asset.manage'))
    OR (r.code = 'IT_SUPPORT'      AND p.code IN ('page.assets','page.admin','asset.manage','user.manage'))
    OR (r.code = 'AUDITOR'         AND p.code IN ('page.dashboard','page.billing','page.finance','page.reports','page.assets','page.leases',
                                                  'page.tax','page.payroll','report.financial','audit.view','payroll.view_all'));

-- 30.7 HR reference -----------------------------------------------------------------------
INSERT INTO leave_types (code, name, annual_entitlement_days, is_paid, carry_forward_max_days, requires_document) VALUES
 ('AL','Annual Leave',22,TRUE,10,FALSE), ('SL','Sick Leave',30,TRUE,0,TRUE),
 ('ML','Maternity Leave',98,TRUE,0,TRUE), ('SP','Study / Exam Leave',5,TRUE,0,FALSE),
 ('CL','Compassionate Leave',5,TRUE,0,FALSE), ('UL','Unpaid Leave',0,FALSE,0,FALSE);

INSERT INTO skills (name, category) VALUES
 ('Forensic Accounting','Forensic'), ('Fraud Investigation','Forensic'), ('Litigation Support & Expert Witness','Forensic'),
 ('eDiscovery (Relativity)','Forensic'), ('Data Analytics (Python)','Data'), ('SQL','Data'), ('Power BI','Data'),
 ('Machine Learning','Data'), ('Digital Forensics (EnCase / FTK)','Cyber'), ('Penetration Testing','Cyber'),
 ('ISO 27001','Cyber'), ('Internal Audit','Risk'), ('AML/CFT Compliance','Risk'), ('Enterprise Risk Management','Risk'),
 ('Zimbabwe Tax (ZIMRA)','Tax'), ('Transfer Pricing','Tax'), ('IFRS Reporting','Finance'), ('Business Valuation','Finance'),
 ('Financial Due Diligence','Finance'), ('Project Management','General');

INSERT INTO industries (name) VALUES
 ('Banking & Financial Services'), ('Insurance & Pensions'), ('Mining & Resources'), ('Telecommunications'),
 ('Government & Public Sector'), ('Retail & FMCG'), ('Agriculture & Agro-processing'), ('Energy & Utilities'),
 ('NGO & Development'), ('Manufacturing'), ('Healthcare'), ('Transport & Logistics'), ('Real Estate');

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  31_seed_organisation.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   31. SEED - OFFICES, DEPARTMENTS, ~170 EMPLOYEES, BANK ACCOUNTS, LOGINS
   -------------------------------------------------------------------------------------
   Every employee gets a company e-mail firstname.lastname@maxhub.co.zw and a login with
   the same username.  DEMO PASSWORD FOR EVERY USER:  Maxhub@2026
   (change it after the first login - Account page, or ask IT to force a reset).
   ===================================================================================== */

-- 31.1 Offices / branches ----------------------------------------------------------------
INSERT INTO offices (code, name, office_type, occupancy, address_line1, address_line2, city, country_code,
                     functional_currency, tax_jurisdiction, phone, email, timezone, opened_date, is_head_office) VALUES
 ('HRE','Harare Head Office','head_office','owned','Maxhub House, 45 Enterprise Road','Highlands','Harare','ZW','USD','ZIMRA','+263 242 700 100','harare@maxhub.co.zw','Africa/Harare','2012-06-01',TRUE),
 ('BYO','Bulawayo Office','branch','owned','Maxhub Centre, 88 Jason Moyo Street','City Centre','Bulawayo','ZW','USD','ZIMRA','+263 292 880 100','bulawayo@maxhub.co.zw','Africa/Harare','2015-02-01',FALSE),
 ('JNB','Johannesburg Branch','branch','leased','140 West Street, 9th Floor','Sandton','Johannesburg','ZA','ZAR','SARS','+27 10 500 4100','johannesburg@maxhub.co.zw','Africa/Johannesburg','2018-07-01',FALSE),
 ('NBO','Nairobi Branch','branch','leased','Westlands Square, 7th Floor, Ring Road','Westlands','Nairobi','KE','KES','KRA','+254 20 450 7100','nairobi@maxhub.co.zw','Africa/Nairobi','2021-03-01',FALSE),
 ('LON','London Branch','branch','leased','1 Minster Court, Mincing Lane, 4th Floor','City of London','London','GB','GBP','HMRC','+44 20 3900 4100','london@maxhub.co.zw','Europe/London','2023-01-09',FALSE),
 ('DXB','Dubai Branch','branch','leased','Gate Village 5, Level 3','DIFC','Dubai','AE','AED','UAEFTA','+971 4 500 4100','dubai@maxhub.co.zw','Asia/Dubai','2024-02-01',FALSE);

-- 31.2 Departments & service lines --------------------------------------------------------
INSERT INTO departments (code, name, division, office_id, cost_center_code, email, phone_extension, description, is_revenue_generating)
SELECT v.code, v.name, v.div, (SELECT office_id FROM offices WHERE code = 'HRE'), v.cc, v.email, v.ext, v.descr, v.rev
  FROM (VALUES
   ('EXE','Executive Office','Leadership','CC100','executive@maxhub.co.zw','100','CEO, COO and executive support',FALSE),
   ('FAI','Forensic Audit & Investigations','Client Service','CC200','forensics@maxhub.co.zw','200','Fraud investigations, forensic audits, litigation support, asset tracing',TRUE),
   ('DAA','Data Analytics & AI','Client Service','CC210','analytics@maxhub.co.zw','210','Fraud analytics, continuous monitoring, BI dashboards, machine learning',TRUE),
   ('CYB','Cybersecurity & Digital Forensics','Client Service','CC220','cyber@maxhub.co.zw','220','Digital forensics lab, incident response, penetration testing, ISO 27001',TRUE),
   ('RAS','Risk Advisory & Internal Audit','Client Service','CC230','risk@maxhub.co.zw','230','Outsourced internal audit, ERM, AML/CFT, governance reviews',TRUE),
   ('TAX','Tax Advisory','Client Service','CC240','tax@maxhub.co.zw','240','ZIMRA disputes, tax health checks, transfer pricing, tax compliance outsourcing',TRUE),
   ('FAV','Financial Advisory & Valuations','Client Service','CC250','advisory@maxhub.co.zw','250','Valuations, due diligence, IFRS advisory, restructuring',TRUE),
   ('FIN','Finance & Accounting','Business Support','CC300','finance@maxhub.co.zw','300','Financial reporting, billing, payables, treasury, tax compliance, payroll accounting',FALSE),
   ('HRM','Human Resources','Business Support','CC310','hr@maxhub.co.zw','310','Recruitment, payroll, performance, learning & development',FALSE),
   ('ICT','Information Technology','Business Support','CC320','itsupport@maxhub.co.zw','320','Infrastructure, service desk, ERP administration, information security',FALSE),
   ('MBD','Marketing & Business Development','Business Support','CC330','marketing@maxhub.co.zw','330','Brand, bids & proposals, client relationship programmes',FALSE),
   ('PRC','Procurement & Supply Chain','Business Support','CC340','procurement@maxhub.co.zw','340','Sourcing, supplier management, PRAZ compliance',FALSE),
   ('FAC','Facilities & Administration','Business Support','CC350','facilities@maxhub.co.zw','350','Buildings, fleet, reception, security, office services',FALSE),
   ('LEG','Legal & Company Secretarial','Governance','CC400','legal@maxhub.co.zw','400','Contracts, board secretariat, regulatory compliance',FALSE),
   ('QRM','Quality & Risk Management','Governance','CC410','quality@maxhub.co.zw','410','Engagement quality reviews, independence, ISQM 1',FALSE),
   ('IAU','Internal Audit','Governance','CC420','internalaudit@maxhub.co.zw','420','Independent assurance to the Audit Committee',FALSE)
  ) AS v(code, name, div, cc, email, ext, descr, rev);

INSERT INTO service_lines (code, name, description, department_id, revenue_target)
SELECT d.code, v.name, v.descr, d.department_id, v.target
  FROM (VALUES ('FAI','Forensic Audit & Investigations','Fraud & corruption investigations, forensic audits, expert witness', 5500000),
               ('DAA','Data Analytics & AI','Fraud analytics, data platforms, dashboards, AI models', 3800000),
               ('CYB','Cybersecurity & Digital Forensics','Digital evidence, incident response, cyber assurance', 2600000),
               ('RAS','Risk Advisory & Internal Audit','Internal audit co-sourcing, ERM, AML/CFT', 3200000),
               ('TAX','Tax Advisory','ZIMRA disputes, tax reviews, transfer pricing', 1900000),
               ('FAV','Financial Advisory & Valuations','Valuations, due diligence, IFRS advisory', 2000000)) AS v(code, name, descr, target)
  JOIN departments d ON d.code = v.code;

INSERT INTO job_grades (code, name, level, currency_code, min_salary, max_salary, default_cost_rate, default_bill_rate, target_utilization_pct) VALUES
 ('SUP','Business Support',    0, 'USD',   7000,  30000,  10,   0,  0),
 ('AN', 'Analyst',             1, 'USD',  10000,  15000,  11,  75, 85),
 ('CON','Consultant',          2, 'USD',  16000,  24000,  16, 110, 80),
 ('SC', 'Senior Consultant',   3, 'USD',  26000,  36000,  23, 145, 80),
 ('MGR','Manager',             4, 'USD',  40000,  52000,  34, 190, 70),
 ('SM', 'Senior Manager',      5, 'USD',  55000,  70000,  45, 240, 65),
 ('DIR','Director',            6, 'USD',  75000, 100000,  60, 300, 50),
 ('PTR','Partner',             7, 'USD', 110000, 170000,  90, 380, 40);

-- 31.3 Employees --------------------------------------------------------------------------
-- (a) named leadership team & key demo users
CREATE TEMP TABLE seed_people (num TEXT, fn TEXT, ln TEXT, gender TEXT, grade TEXT, title TEXT, dept TEXT, office TEXT, hire DATE);
INSERT INTO seed_people VALUES
 ('E001','Tendai','Moyo','Male','PTR','Managing Partner & Chief Executive Officer','EXE','HRE','2012-06-01'),
 ('E002','Rutendo','Chikore','Female','PTR','Partner - Forensic Audit & Investigations','FAI','HRE','2013-01-15'),
 ('E003','Farai','Ndlovu','Male','DIR','Director - Data Analytics & AI','DAA','HRE','2016-06-01'),
 ('E004','Nyasha','Mutasa','Female','MGR','Manager - Forensic Audit','FAI','HRE','2019-02-01'),
 ('E005','Kudakwashe','Banda','Male','CON','Consultant - Forensic Audit','FAI','HRE','2023-03-01'),
 ('E006','Blessing','Marufu','Female','DIR','Chief Financial Officer','FIN','HRE','2014-02-01'),
 ('E007','Chipo','Sibanda','Female','SM','Human Resources Director','HRM','HRE','2015-08-01'),
 ('E008','Tawanda','Gumbo','Male','MGR','IT Manager & ERP System Administrator','ICT','HRE','2017-05-02'),
 ('E009','Memory','Nkomo','Female','MGR','Tax Compliance Manager','FIN','HRE','2018-09-03'),
 ('E010','Simbarashe','Chiweshe','Male','PTR','Partner - Risk Advisory','RAS','HRE','2014-04-01'),
 ('E011','Thandiwe','Ncube','Female','PTR','Partner - Tax Advisory','TAX','HRE','2015-01-12'),
 ('E012','Tatenda','Mhlanga','Male','DIR','Director - Cybersecurity & Digital Forensics','CYB','HRE','2017-10-02'),
 ('E013','Rumbidzai','Makoni','Female','DIR','Director - Financial Advisory & Valuations','FAV','HRE','2016-03-01'),
 ('E014','Sipho','Mokoena','Male','DIR','Branch Director - Johannesburg','FAI','JNB','2018-07-01'),
 ('E015','Wanjiru','Kamau','Female','DIR','Branch Director - Nairobi','DAA','NBO','2021-03-01'),
 ('E016','Oliver','Thompson','Male','DIR','Branch Director - London','FAV','LON','2023-01-09'),
 ('E017','Omar','Haddad','Male','DIR','Branch Director - Dubai','FAI','DXB','2024-02-01'),
 ('E018','Mufaro','Chigumba','Male','PTR','Chief Operating Officer','EXE','HRE','2013-06-03'),
 ('E019','Ruvimbo','Zvobgo','Female','SM','Company Secretary & Head of Legal','LEG','HRE','2016-11-01'),
 ('E020','Tinashe','Mapfumo','Male','SM','Head of Marketing & Business Development','MBD','HRE','2017-02-06'),
 ('E021','Vimbai','Hove','Female','MGR','Procurement Manager','PRC','HRE','2019-06-03'),
 ('E022','Tapiwa','Mlambo','Male','MGR','Facilities & Administration Manager','FAC','HRE','2016-08-01'),
 ('E023','Fadzai','Madziva','Female','SM','Head of Quality & Risk Management','QRM','HRE','2018-01-08'),
 ('E024','Munyaradzi','Mandaza','Male','SM','Head of Internal Audit','IAU','HRE','2019-04-01'),
 ('E025','Chiedza','Mushonga','Female','SM','Financial Controller','FIN','HRE','2017-07-03'),
 ('E026','Nokuthula','Tshuma','Female','DIR','Office Head - Bulawayo','RAS','BYO','2015-02-01');

-- (b) the rest of the firm: department, office, grade, head-count
CREATE TEMP TABLE seed_headcount (dept TEXT, office TEXT, grade TEXT, n INT);
INSERT INTO seed_headcount VALUES
 ('FAI','HRE','SM',2), ('FAI','HRE','MGR',2), ('FAI','HRE','SC',4), ('FAI','HRE','CON',4), ('FAI','HRE','AN',4),
 ('DAA','HRE','SM',1), ('DAA','HRE','MGR',2), ('DAA','HRE','SC',4), ('DAA','HRE','CON',4), ('DAA','HRE','AN',4),
 ('CYB','HRE','SM',1), ('CYB','HRE','MGR',1), ('CYB','HRE','SC',3), ('CYB','HRE','CON',3), ('CYB','HRE','AN',2),
 ('RAS','HRE','SM',1), ('RAS','HRE','MGR',2), ('RAS','HRE','SC',3), ('RAS','HRE','CON',3), ('RAS','HRE','AN',3),
 ('TAX','HRE','SM',1), ('TAX','HRE','MGR',1), ('TAX','HRE','SC',2), ('TAX','HRE','CON',3), ('TAX','HRE','AN',2),
 ('FAV','HRE','MGR',1), ('FAV','HRE','SC',2), ('FAV','HRE','CON',2), ('FAV','HRE','AN',1),
 ('FIN','HRE','MGR',1), ('FIN','HRE','SUP',6), ('HRM','HRE','MGR',1), ('HRM','HRE','SUP',4),
 ('ICT','HRE','SUP',5), ('LEG','HRE','SUP',2), ('MBD','HRE','MGR',1), ('MBD','HRE','SUP',3),
 ('PRC','HRE','SUP',2), ('FAC','HRE','SUP',5), ('QRM','HRE','SUP',1), ('IAU','HRE','SUP',1), ('EXE','HRE','SUP',2),
 ('RAS','BYO','MGR',1), ('RAS','BYO','SC',2), ('RAS','BYO','CON',2), ('RAS','BYO','AN',1),
 ('FAI','BYO','SC',1), ('FAI','BYO','CON',2), ('FAI','BYO','AN',1), ('TAX','BYO','CON',1), ('FIN','BYO','SUP',1), ('FAC','BYO','SUP',1),
 ('FAI','JNB','MGR',1), ('FAI','JNB','SC',1), ('FAI','JNB','CON',2), ('FAI','JNB','AN',1),
 ('DAA','JNB','SC',1), ('DAA','JNB','CON',1), ('CYB','JNB','CON',1), ('FIN','JNB','SUP',1), ('FAC','JNB','SUP',1),
 ('DAA','NBO','MGR',1), ('DAA','NBO','SC',1), ('DAA','NBO','CON',2), ('DAA','NBO','AN',1),
 ('RAS','NBO','SC',1), ('RAS','NBO','CON',1), ('FIN','NBO','SUP',1),
 ('FAV','LON','MGR',1), ('FAV','LON','SC',1), ('FAV','LON','CON',1), ('FAI','LON','SC',1), ('MBD','LON','SUP',1),
 ('FAI','DXB','MGR',1), ('FAI','DXB','SC',1), ('FAI','DXB','CON',1), ('CYB','DXB','CON',1), ('FIN','DXB','SUP',1);

DO $$
DECLARE
    zw_f TEXT[] := ARRAY['Tatenda','Rudo','Farai','Chipo','Tafadzwa','Nyasha','Tinashe','Rumbidzai','Takudzwa','Tsitsi',
                         'Ruvimbo','Simba','Vimbai','Tapiwa','Fadzai','Munashe','Chiedza','Tawanda','Nokuthula','Sibusiso',
                         'Thandeka','Nkosana','Sipho','Lindiwe','Busisiwe','Themba','Shingai','Kundai','Panashe','Anesu',
                         'Ropafadzo','Tanaka','Tariro','Mufaro','Ngoni','Dudzai','Kudzai','Rutendo','Tendekai','Mazvita',
                         'Tonderai','Chengetai','Petronella','Gift','Precious','Brighton','Prudence','Admire','Loveness','Obert'];
    zw_l TEXT[] := ARRAY['Moyo','Ncube','Sibanda','Dube','Ndlovu','Mpofu','Chikore','Mutasa','Banda','Marufu',
                         'Chinembiri','Gumbo','Mhlanga','Nkomo','Chirwa','Mushonga','Makoni','Zvobgo','Chiweshe','Mukanya',
                         'Nyathi','Tshuma','Mlambo','Chigumba','Madziva','Mapfumo','Chidzikwe','Mandaza','Hove','Mutsvangwa',
                         'Chakanyuka','Matongo','Mazarura','Musonza','Chitando','Nyoni','Mangena','Dhliwayo','Kadenge','Makumbe'];
    za_f TEXT[] := ARRAY['Thabo','Lerato','Naledi','Pieter','Zanele','Johan','Ayanda','Kagiso','Refilwe','Bongani','Palesa','Riaan'];
    za_l TEXT[] := ARRAY['Nkosi','van der Merwe','Dlamini','Botha','Khumalo','Naidoo','Pillay','Mahlangu','Coetzee','Molefe'];
    ke_f TEXT[] := ARRAY['Achieng','Brian','Njeri','Kevin','Wambui','Dennis','Akinyi','Collins','Mercy','Kiprono'];
    ke_l TEXT[] := ARRAY['Otieno','Kariuki','Mutua','Njoroge','Kiptoo','Wafula','Odhiambo','Chege','Mwangi','Wekesa'];
    gb_f TEXT[] := ARRAY['Charlotte','James','Amelia','Harry','Sophie','Daniel','Priya','Thomas'];
    gb_l TEXT[] := ARRAY['Clarke','Hughes','Patel','Walker','Bennett','Evans','Morgan','Shaw'];
    ae_f TEXT[] := ARRAY['Fatima','Ahmed','Priya','Rahul','Layla','Yusuf','Aisha','Karim'];
    ae_l TEXT[] := ARRAY['Al Mansoori','Khan','Menon','Nair','Farouk','Saleh','Rahman','Qureshi'];
    sup_titles JSONB := '{"FIN":["Accountant","Accounts Payable Officer","Accounts Receivable & Billing Officer","Payroll Accountant","Treasury Officer","Assistant Accountant","Management Accountant"],
                          "HRM":["HR Officer","Payroll & Benefits Officer","Talent Acquisition Officer","Learning & Development Officer"],
                          "ICT":["Systems Administrator","Service Desk Analyst","Network Engineer","Database Administrator","Information Security Officer"],
                          "LEG":["Legal Officer","Compliance Officer"],
                          "MBD":["Marketing Officer","Bids & Proposals Coordinator","Digital Marketing Specialist","Business Development Executive"],
                          "PRC":["Procurement Officer","Stores & Asset Clerk"],
                          "FAC":["Facilities Officer","Receptionist","Driver","Office Assistant","Fleet Coordinator"],
                          "QRM":["Quality Reviewer"], "IAU":["Internal Auditor"], "EXE":["Executive Assistant","Executive Office Administrator"]}';
    dept_short JSONB := '{"FAI":"Forensic Audit","DAA":"Data Analytics","CYB":"Cybersecurity","RAS":"Risk Advisory","TAX":"Tax Advisory","FAV":"Financial Advisory",
                          "FIN":"Finance","HRM":"Human Resources","MBD":"Marketing","ICT":"IT","FAC":"Facilities","PRC":"Procurement"}';
    r RECORD; k INT; i INT := 26; v_fn TEXT; v_ln TEXT; v_email TEXT; v_try INT; v_country TEXT; v_title TEXT; v_hire DATE;
    v_grade job_grades%ROWTYPE; v_lvl INT; v_sup_i INT := 0;
BEGIN
    FOR r IN SELECT h.*, o.country_code FROM seed_headcount h JOIN offices o ON o.code = h.office ORDER BY h.office, h.dept, h.grade LOOP
        SELECT * INTO v_grade FROM job_grades WHERE code = r.grade;
        FOR k IN 1 .. r.n LOOP
            i := i + 1;
            v_try := 0;
            LOOP
                CASE r.country_code
                    WHEN 'ZA' THEN v_fn := za_f[1 + (i * 7 + v_try) % array_length(za_f,1)]; v_ln := za_l[1 + (i * 3 + v_try * 5) % array_length(za_l,1)];
                    WHEN 'KE' THEN v_fn := ke_f[1 + (i * 7 + v_try) % array_length(ke_f,1)]; v_ln := ke_l[1 + (i * 3 + v_try * 5) % array_length(ke_l,1)];
                    WHEN 'GB' THEN v_fn := gb_f[1 + (i * 5 + v_try) % array_length(gb_f,1)]; v_ln := gb_l[1 + (i * 3 + v_try * 3) % array_length(gb_l,1)];
                    WHEN 'AE' THEN v_fn := ae_f[1 + (i * 5 + v_try) % array_length(ae_f,1)]; v_ln := ae_l[1 + (i * 3 + v_try * 3) % array_length(ae_l,1)];
                    ELSE           v_fn := zw_f[1 + (i * 7 + v_try) % array_length(zw_f,1)]; v_ln := zw_l[1 + (i * 13 + v_try * 7) % array_length(zw_l,1)];
                END CASE;
                v_email := lower(regexp_replace(v_fn, '[^A-Za-z]', '', 'g') || '.' || regexp_replace(v_ln, '[^A-Za-z]', '', 'g')) || '@maxhub.co.zw';
                EXIT WHEN NOT EXISTS (SELECT 1 FROM seed_people WHERE lower(fn || '.' || regexp_replace(ln, '[^A-Za-z]', '', 'g')) || '@maxhub.co.zw' = v_email)
                      AND NOT EXISTS (SELECT 1 FROM employees WHERE email = v_email);
                v_try := v_try + 1;
            END LOOP;

            IF r.grade = 'SUP' THEN
                v_sup_i := v_sup_i + 1;
                v_title := sup_titles -> r.dept ->> ((v_sup_i + k) % jsonb_array_length(sup_titles -> r.dept));
            ELSIF (SELECT is_revenue_generating FROM departments WHERE code = r.dept) THEN
                v_title := v_grade.name || ' - ' || (dept_short ->> r.dept);
            ELSE
                v_title := COALESCE(dept_short ->> r.dept, r.dept) || ' ' || CASE r.grade WHEN 'MGR' THEN 'Manager' ELSE v_grade.name END;
            END IF;
            v_lvl := v_grade.level;
            v_hire := CASE v_lvl WHEN 5 THEN '2016-01-11'::DATE + (i * 47 % 1500) WHEN 4 THEN '2017-03-01'::DATE + (i * 53 % 1800)
                                 WHEN 3 THEN '2019-02-01'::DATE + (i * 41 % 1400) WHEN 2 THEN '2021-01-11'::DATE + (i * 37 % 1300)
                                 WHEN 1 THEN '2023-01-09'::DATE + (i * 29 % 1050) ELSE '2015-06-01'::DATE + (i * 61 % 3500) END;
            INSERT INTO seed_people VALUES ('E' || lpad(i::TEXT, 3, '0'), v_fn, v_ln, CASE WHEN i % 2 = 0 THEN 'Female' ELSE 'Male' END,
                                            r.grade, v_title, r.dept, r.office, LEAST(v_hire, '2026-02-02'::DATE));
            INSERT INTO employees (employee_number, first_name, last_name, email, hire_date)   -- placeholder row to reserve the e-mail
            VALUES ('TMP' || i, v_fn, v_ln, v_email, '2020-01-01');
        END LOOP;
    END LOOP;
    DELETE FROM employees WHERE employee_number LIKE 'TMP%';
    EXECUTE 'ALTER TABLE employees ALTER COLUMN employee_id RESTART WITH 1';
END $$;

INSERT INTO employees (employee_number, first_name, last_name, email, phone, mobile_phone, work_phone_ext, gender, date_of_birth,
                       national_id, hire_date, employment_type, status, job_grade_id, job_title, department_id, office_id, service_line_id,
                       is_billable, target_utilization_pct, cost_rate_hourly, default_bill_rate, currency_code, nationality,
                       tax_number, social_security_number, pension_member, medical_aid_member, medical_aid_scheme,
                       bank_name, bank_account_number, emergency_contact_name, emergency_contact_phone, work_permit_expiry)
SELECT p.num, p.fn, p.ln,
       lower(regexp_replace(p.fn, '[^A-Za-z]', '', 'g') || '.' || regexp_replace(p.ln, '[^A-Za-z]', '', 'g')) || '@maxhub.co.zw',
       o.phone, CASE o.country_code WHEN 'ZW' THEN '+263 77 ' ELSE '+' END || lpad((1000000 + n.rn * 7919 % 8999999)::TEXT, 7, '0'),
       d.phone_extension::INT + n.rn % 90 || '', p.gender,
       ('1968-01-01'::DATE + ((7 - g.level) * 1460 + n.rn * 97 % 1400)::INT),
       CASE o.country_code WHEN 'ZW' THEN lpad((10 + n.rn % 80)::TEXT, 2, '0') || '-' || lpad((200000 + n.rn * 3571 % 799999)::TEXT, 6, '0') || 'X' || lpad((n.rn % 90 + 10)::TEXT, 2, '0') END,
       p.hire, 'full_time', 'active', g.job_grade_id, p.title, d.department_id, o.office_id,
       (SELECT service_line_id FROM service_lines sl WHERE sl.code = p.dept),
       d.is_revenue_generating AND g.level > 0, g.target_utilization_pct,
       NULL, CASE WHEN d.is_revenue_generating AND g.level > 0
                  THEN round(g.default_bill_rate * CASE o.code WHEN 'LON' THEN 1.8 WHEN 'DXB' THEN 1.5 WHEN 'JNB' THEN 1.1 WHEN 'BYO' THEN 0.9 ELSE 1 END, 0) END,
       o.functional_currency,
       CASE o.country_code WHEN 'ZW' THEN 'Zimbabwean' WHEN 'ZA' THEN 'South African' WHEN 'KE' THEN 'Kenyan' WHEN 'GB' THEN 'British'
                           ELSE CASE WHEN n.rn % 2 = 0 THEN 'Zimbabwean' ELSE 'Indian' END END,
       CASE o.country_code WHEN 'ZW' THEN '2' || lpad((n.rn * 104729 % 999999999)::TEXT, 9, '0') WHEN 'KE' THEN 'A0' || lpad((n.rn * 7127)::TEXT, 8, '0') || 'K'
                           WHEN 'GB' THEN 'QQ' || lpad((n.rn * 123457 % 999999)::TEXT, 6, '0') || 'C' ELSE 'TX' || lpad((n.rn * 7919)::TEXT, 9, '0') END,
       CASE o.country_code WHEN 'ZW' THEN 'NSSA' || lpad((n.rn * 3083 % 9999999)::TEXT, 7, '0') ELSE NULL END,
       TRUE, o.country_code = 'ZW', CASE WHEN o.country_code = 'ZW' THEN CASE WHEN n.rn % 3 = 0 THEN 'First Mutual Health' ELSE 'CIMAS' END END,
       CASE o.country_code WHEN 'ZW' THEN CASE WHEN n.rn % 2 = 0 THEN 'CBZ Bank' ELSE 'Stanbic Bank' END WHEN 'ZA' THEN 'FNB' WHEN 'KE' THEN 'NCBA Bank'
                           WHEN 'GB' THEN 'Barclays' ELSE 'Emirates NBD' END,
       lpad((n.rn * 99991 % 9999999999)::TEXT, 10, '0'),
       'Next of kin', '+263 71 ' || lpad((n.rn * 4441 % 9999999)::TEXT, 7, '0'),
       CASE WHEN o.country_code = 'AE' THEN '2027-01-31'::DATE WHEN o.country_code = 'GB' THEN '2027-12-31'::DATE END
  FROM (SELECT sp.*, row_number() OVER (ORDER BY sp.num) AS rn FROM seed_people sp) n
  JOIN seed_people p ON p.num = n.num
  JOIN job_grades g  ON g.code = p.grade
  JOIN departments d ON d.code = p.dept
  JOIN offices o     ON o.code = p.office
 ORDER BY p.num;

-- Reporting lines: branch staff -> branch head; department staff -> next senior level; heads -> CEO/COO
UPDATE employees e SET manager_id = (SELECT employee_id FROM employees WHERE employee_number = CASE o.code
        WHEN 'BYO' THEN 'E026' WHEN 'JNB' THEN 'E014' WHEN 'NBO' THEN 'E015' WHEN 'LON' THEN 'E016' WHEN 'DXB' THEN 'E017' END)
  FROM offices o
 WHERE o.office_id = e.office_id AND o.code <> 'HRE' AND e.employee_number NOT IN ('E014','E015','E016','E017','E026');

UPDATE departments d SET head_employee_id = (SELECT employee_id FROM employees WHERE employee_number = v.num)
  FROM (VALUES ('EXE','E001'), ('FAI','E002'), ('DAA','E003'), ('CYB','E012'), ('RAS','E010'), ('TAX','E011'), ('FAV','E013'),
               ('FIN','E006'), ('HRM','E007'), ('ICT','E008'), ('MBD','E020'), ('PRC','E021'), ('FAC','E022'), ('LEG','E019'),
               ('QRM','E023'), ('IAU','E024')) AS v(code, num)
 WHERE d.code = v.code;

UPDATE employees e
   SET manager_id = COALESCE(
         (SELECT m.employee_id FROM employees m JOIN job_grades mg ON mg.job_grade_id = m.job_grade_id
           WHERE m.department_id = e.department_id AND m.office_id = e.office_id AND m.employee_id <> e.employee_id
             AND mg.level = (SELECT min(g2.level) FROM employees e2 JOIN job_grades g2 ON g2.job_grade_id = e2.job_grade_id
                              WHERE e2.department_id = e.department_id AND e2.office_id = e.office_id AND g2.level > g.level)
           ORDER BY (m.employee_id + e.employee_id) % 3, m.employee_id LIMIT 1),
         (SELECT head_employee_id FROM departments WHERE department_id = e.department_id))
  FROM job_grades g, offices o
 WHERE g.job_grade_id = e.job_grade_id AND o.office_id = e.office_id AND o.code = 'HRE' AND e.manager_id IS NULL
   AND e.employee_id NOT IN (SELECT head_employee_id FROM departments WHERE head_employee_id IS NOT NULL);

UPDATE employees SET manager_id = (SELECT employee_id FROM employees WHERE employee_number = 'E001')
 WHERE employee_id IN (SELECT head_employee_id FROM departments) AND employee_number <> 'E001';
UPDATE employees SET manager_id = (SELECT employee_id FROM employees WHERE employee_number = 'E018')
 WHERE employee_number IN ('E014','E015','E016','E017','E026');
UPDATE employees SET manager_id = NULL WHERE employee_number = 'E001';
UPDATE employees SET manager_id = (SELECT employee_id FROM employees WHERE employee_number = 'E006') WHERE employee_number IN ('E009','E025');
UPDATE employees SET manager_id = (SELECT employee_id FROM employees WHERE employee_number = 'E002') WHERE employee_number = 'E004';

UPDATE offices o SET manager_employee_id = (SELECT employee_id FROM employees WHERE employee_number = v.num)
  FROM (VALUES ('HRE','E018'), ('BYO','E026'), ('JNB','E014'), ('NBO','E015'), ('LON','E016'), ('DXB','E017')) AS v(code, num)
 WHERE o.code = v.code;
UPDATE service_lines sl SET lead_employee_id = d.head_employee_id FROM departments d WHERE d.department_id = sl.department_id;

-- 31.4 Compensation (local currency). 2026 increase of 7% from 1 January.
INSERT INTO employee_compensation (employee_id, effective_date, base_salary_annual, monthly_allowances, bonus_target_pct, currency_code, change_reason)
SELECT e.employee_id, GREATEST(e.hire_date, '2024-01-01'::DATE),
       round(x.usd * 0.93 * x.mult / x.fx, -2), round(x.usd * 0.93 * x.mult / x.fx / 12 * x.allow, -1),
       CASE WHEN g.level >= 5 THEN 20 WHEN g.level >= 3 THEN 12 ELSE 8 END, e.currency_code, 'Salary on appointment / 2024 review'
  FROM employees e JOIN job_grades g USING (job_grade_id) JOIN offices o ON o.office_id = e.office_id
  CROSS JOIN LATERAL (SELECT
        CASE WHEN g.code = 'SUP' THEN 7500 + (e.employee_id * 37 % 100) * 120
             ELSE g.min_salary + (g.max_salary - g.min_salary) * (e.employee_id * 37 % 100) / 100.0 END
          * CASE WHEN g.code = 'SUP' AND e.job_title ~ '(Receptionist|Driver|Office Assistant)' THEN 0.6 ELSE 1 END AS usd,
        CASE o.country_code WHEN 'ZA' THEN 1.2 WHEN 'KE' THEN 0.9 WHEN 'GB' THEN 1.9 WHEN 'AE' THEN 1.6 ELSE 1 END AS mult,
        fn_fx_rate(e.currency_code, '2025-12-31') AS fx,
        CASE o.country_code WHEN 'ZW' THEN 0.12 ELSE 0.05 END AS allow) x;

INSERT INTO employee_compensation (employee_id, effective_date, base_salary_annual, monthly_allowances, bonus_target_pct, currency_code, change_reason)
SELECT employee_id, '2026-01-01', round(base_salary_annual * 1.07, -2), round(monthly_allowances * 1.07, -1), bonus_target_pct, currency_code,
       'Annual review 2026 (+7%)'
  FROM employee_compensation WHERE effective_date < '2026-01-01';

UPDATE employees e SET cost_rate_hourly = round(c.base_salary_annual * fn_fx_rate(c.currency_code, '2025-12-31') * 1.35 / 1760, 2)
  FROM employee_compensation c WHERE c.employee_id = e.employee_id AND c.effective_date = '2026-01-01';

-- 31.5 Bank accounts ----------------------------------------------------------------------
INSERT INTO bank_accounts (name, bank_name, branch, account_number, swift_code, account_type, currency_code, gl_account_id, office_id)
SELECT v.name, v.bank, v.branch, v.acc, v.swift, v.t, v.cur, fn_account_id(v.gl), (SELECT office_id FROM offices WHERE code = v.office)
  FROM (VALUES
   ('Operating USD - Harare',       'CBZ Bank',              'Kwame Nkrumah Avenue', '01120456789012', 'COBZZWHA','current',     'USD','1010','HRE'),
   ('Client receipts USD Nostro',   'Stanbic Bank Zimbabwe', 'Harare Corporate',     '9140004512375',  'SBICZWHX','fca',         'USD','1013','HRE'),
   ('Operating ZWG',                'Stanbic Bank Zimbabwe', 'Harare Corporate',     '9140004512367',  'SBICZWHX','current',     'ZWG','1011','HRE'),
   ('Money market call account',    'CBZ Bank',              'Treasury',             '01120456789999', 'COBZZWHA','money_market','USD','1017','HRE'),
   ('Bulawayo operating USD',       'CABS',                  'Bulawayo Main',        '1003458712',     'CABSZWHX','current',     'USD','1018','BYO'),
   ('Johannesburg operating ZAR',   'FNB',                   'Sandton',              '62845120045',    'FIRNZAJJ','current',     'ZAR','1012','JNB'),
   ('Nairobi operating KES',        'NCBA Bank',             'Westlands',            '1004512078',     'CBAFKENX','current',     'KES','1014','NBO'),
   ('London operating GBP',         'Barclays Bank UK',      'Canary Wharf',         '43125698',       'BARCGB22','current',     'GBP','1015','LON'),
   ('Dubai operating AED',          'Emirates NBD',          'DIFC',                 '1015004512301',  'EBILAEAD','current',     'AED','1016','DXB'),
   ('Petty cash - Harare',          'Cash on hand',          'Maxhub House',         'PC-HRE-01',      NULL,      'petty_cash',  'USD','1020','HRE')
  ) AS v(name, bank, branch, acc, swift, t, cur, gl, office);

-- 31.6 Access: department + grade -> roles, then one login per employee -------------------
INSERT INTO department_role_rules (department_id, min_grade_level, max_grade_level, role_id, description)
SELECT (SELECT department_id FROM departments WHERE code = v.dept), v.lo, v.hi, (SELECT role_id FROM roles WHERE code = v.role), v.descr
  FROM (VALUES
   (NULL, 0, 99, 'EMPLOYEE',        'Every employee: self-service'),
   ('FAI',1, 3, 'CONSULTANT','Fee earners'), ('DAA',1,3,'CONSULTANT','Fee earners'), ('CYB',1,3,'CONSULTANT','Fee earners'),
   ('RAS',1, 3, 'CONSULTANT','Fee earners'), ('TAX',1,3,'CONSULTANT','Fee earners'), ('FAV',1,3,'CONSULTANT','Fee earners'),
   ('FAI',4, 5, 'PROJECT_MANAGER','Managers run engagements'), ('DAA',4,5,'PROJECT_MANAGER','Managers run engagements'),
   ('CYB',4, 5, 'PROJECT_MANAGER','Managers run engagements'), ('RAS',4,5,'PROJECT_MANAGER','Managers run engagements'),
   ('TAX',4, 5, 'PROJECT_MANAGER','Managers run engagements'), ('FAV',4,5,'PROJECT_MANAGER','Managers run engagements'),
   ('FAI',4, 5, 'CONSULTANT','Managers also deliver'), ('DAA',4,5,'CONSULTANT','Managers also deliver'),
   ('CYB',4, 5, 'CONSULTANT','Managers also deliver'), ('RAS',4,5,'CONSULTANT','Managers also deliver'),
   ('TAX',4, 5, 'CONSULTANT','Managers also deliver'), ('FAV',4,5,'CONSULTANT','Managers also deliver'),
   ('FAI',6, 7, 'EXECUTIVE','Partners & directors'), ('DAA',6,7,'EXECUTIVE','Partners & directors'),
   ('CYB',6, 7, 'EXECUTIVE','Partners & directors'), ('RAS',6,7,'EXECUTIVE','Partners & directors'),
   ('TAX',6, 7, 'EXECUTIVE','Partners & directors'), ('FAV',6,7,'EXECUTIVE','Partners & directors'),
   ('FAI',6, 7, 'PROJECT_MANAGER','Engagement partners'), ('DAA',6,7,'PROJECT_MANAGER','Engagement partners'),
   ('CYB',6, 7, 'PROJECT_MANAGER','Engagement partners'), ('RAS',6,7,'PROJECT_MANAGER','Engagement partners'),
   ('TAX',6, 7, 'PROJECT_MANAGER','Engagement partners'), ('FAV',6,7,'PROJECT_MANAGER','Engagement partners'),
   ('EXE',6, 7, 'EXECUTIVE','Executive team'),
   ('FIN',0, 3, 'ACCOUNTANT','Finance staff'), ('FIN',4, 7, 'FINANCE_MANAGER','Finance leadership'), ('FIN',4,7,'ACCOUNTANT','Finance leadership'),
   ('HRM',0, 3, 'PAYROLL_OFFICER','HR officers'), ('HRM',4, 7, 'HR_MANAGER','HR leadership'),
   ('ICT',0, 3, 'IT_SUPPORT','IT staff'), ('ICT',4, 7, 'ADMIN','IT manager = system administrator'), ('ICT',4,7,'IT_SUPPORT','IT manager'),
   ('MBD',0, 7, 'BD_MANAGER','Marketing & BD'),
   ('PRC',0, 7, 'FACILITIES','Procurement'), ('FAC',0, 7, 'FACILITIES','Facilities'),
   ('LEG',0, 7, 'AUDITOR','Legal & compliance (read-only oversight)'), ('QRM',0, 7, 'AUDITOR','Quality & risk'),
   ('IAU',0, 7, 'AUDITOR','Internal audit')
  ) AS v(dept, lo, hi, role, descr);

DO $$
DECLARE v_hash TEXT := crypt('Maxhub@2026', gen_salt('bf', 10));   -- one bcrypt hash for the demo password
BEGIN
    INSERT INTO app_users (employee_id, username, email, password_hash, must_change_password, password_changed_at, last_login_at)
    SELECT e.employee_id, split_part(e.email, '@', 1), e.email, v_hash, FALSE, '2026-08-01 08:00+02',
           '2026-09-24 08:00+02'::TIMESTAMPTZ - make_interval(mins => (e.employee_id * 37 % 900)::INT)
      FROM employees e ORDER BY e.employee_id;           -- roles are assigned by trigger from department rules
    INSERT INTO password_history (user_id, password_hash, changed_at) SELECT user_id, password_hash, password_changed_at FROM app_users;
END $$;

-- manual extra role: the tax compliance manager also files ZIMRA returns
INSERT INTO user_roles (user_id, role_id, source)
SELECT u.user_id, r.role_id, 'manual' FROM app_users u, roles r WHERE u.username = 'memory.nkomo' AND r.code = 'TAX_OFFICER';

-- a few realistic log-in records (including a lock-out)
INSERT INTO login_attempts (username_tried, user_id, success, failure_reason, ip_address, user_agent, attempted_at)
SELECT u.username, u.user_id, TRUE, NULL, '10.10.' || (u.user_id % 20) || '.' || (u.user_id % 250 + 1), 'Chrome on Windows 11', u.last_login_at
  FROM app_users u;
INSERT INTO login_attempts (username_tried, user_id, success, failure_reason, ip_address, user_agent, attempted_at) VALUES
 ('kudakwashe.banda', (SELECT user_id FROM app_users WHERE username = 'kudakwashe.banda'), FALSE, 'wrong_password', '10.10.4.51', 'Chrome on Windows 11', '2026-09-23 07:58+02'),
 ('admin', NULL, FALSE, 'unknown_user', '196.27.100.14', 'python-requests/2.31', '2026-09-22 02:14+02'),
 ('administrator', NULL, FALSE, 'unknown_user', '196.27.100.14', 'python-requests/2.31', '2026-09-22 02:14+02');

-- 31.7 Leave balances & skills ------------------------------------------------------------
INSERT INTO leave_balances (employee_id, leave_type_id, leave_year, entitled_days, carried_forward_days)
SELECT e.employee_id, lt.leave_type_id, y, lt.annual_entitlement_days, CASE WHEN lt.code = 'AL' THEN (e.employee_id % 6) ELSE 0 END
  FROM employees e CROSS JOIN leave_types lt CROSS JOIN (VALUES (2025), (2026)) AS yy(y)
 WHERE lt.code IN ('AL','SL','SP');

INSERT INTO employee_skills (employee_id, skill_id, proficiency, years_experience)
SELECT e.employee_id, s.skill_id, LEAST(5, 2 + g.level / 2), g.level * 2 + 1
  FROM employees e JOIN job_grades g USING (job_grade_id) JOIN departments d USING (department_id)
  JOIN skills s ON s.category = CASE d.code WHEN 'FAI' THEN 'Forensic' WHEN 'DAA' THEN 'Data' WHEN 'CYB' THEN 'Cyber'
                                            WHEN 'RAS' THEN 'Risk' WHEN 'TAX' THEN 'Tax' WHEN 'FAV' THEN 'Finance' END
 WHERE (e.employee_id + s.skill_id) % 2 = 0 OR g.level >= 5;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  32_seed_assets_leases.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   32. SEED - SUPPLIERS, PROPERTIES, FIXED ASSETS, INSURANCE, LEASES, LOAN,
       OPENING BALANCES (31 December 2024 - the ERP went live on 1 January 2025)
   ===================================================================================== */

-- 32.1 Suppliers --------------------------------------------------------------------------
INSERT INTO vendors (vendor_code, name, vendor_type, tax_number, vat_number, is_resident, tax_clearance_expiry, praz_registered,
                     email, phone, country_code, currency_code, payment_terms_days, bank_name, bank_account_number, default_expense_account_id)
SELECT v.code, v.name, v.t, v.tin, v.vat, v.res, v.itf::DATE, v.praz, v.email, v.phone, v.cc, v.cur, v.terms, v.bank, v.acc,
       CASE WHEN v.gl IS NOT NULL THEN fn_account_id(v.gl) END
  FROM (VALUES
   ('V001','ZESA Holdings - ZETDC','utility','2000100001','220100001',TRUE,NULL,FALSE,'accounts@zetdc.co.zw','+263 242 774 508','ZW','USD',14,'CBZ Bank','0100200300','6110'),
   ('V002','City of Harare','government','2000100002',NULL,TRUE,NULL,FALSE,'revenue@hararecity.co.zw','+263 242 752 577','ZW','USD',30,'CBZ Bank','0100200301','6110'),
   ('V003','City of Bulawayo','government','2000100003',NULL,TRUE,NULL,FALSE,'revenue@citybyo.co.zw','+263 292 75011','ZW','USD',30,'CABS','0100200302','6110'),
   ('V004','Zimlink Fibre (Pvt) Ltd','supplier','2000100004','220100004',TRUE,'2026-12-31',TRUE,'billing@zimlink.co.zw','+263 242 555 100','ZW','USD',30,'Stanbic Bank','9140000004','6500'),
   ('V005','Mobicel Zimbabwe (Pvt) Ltd','supplier','2000100005','220100005',TRUE,'2026-12-31',TRUE,'corporate@mobicel.co.zw','+263 77 200 2000','ZW','USD',30,'Stanbic Bank','9140000005','6500'),
   ('V006','Microsoft Ireland Operations Ltd','supplier','IE8256796U',NULL,FALSE,NULL,FALSE,'billing@microsoft.com','+353 1 706 3117','GB','USD',30,'Citibank','IE00CITI0001','6200'),
   ('V007','Amazon Web Services EMEA SARL','supplier','LU26888617',NULL,FALSE,NULL,FALSE,'aws-receivables@amazon.com','+352 2789 0057','GB','USD',30,'Citibank','LU00CITI0002','6210'),
   ('V008','Relativity ODA LLC','supplier','US36-4430178',NULL,FALSE,NULL,FALSE,'ar@relativity.com','+1 312 263 1177','US','USD',30,'JPMorgan','US00JPM0003','6200'),
   ('V009','Guardline Security Services (Pvt) Ltd','supplier','2000100009','220100009',TRUE,'2026-11-30',TRUE,'accounts@guardline.co.zw','+263 242 480 900','ZW','USD',30,'CBZ Bank','0100200309','6130'),
   ('V010','Sparkle Cleaning Services','supplier','2000100010',NULL,TRUE,'2025-06-30',FALSE,'sparkleclean@gmail.com','+263 77 410 1010','ZW','USD',30,'CABS','1000200310','6130'),
   ('V011','Harare General Insurance Ltd','insurer','2000100011','220100011',TRUE,'2026-12-31',TRUE,'corporate@hgi.co.zw','+263 242 700 800','ZW','USD',30,'CBZ Bank','0100200311','6140'),
   ('V012','Chartered Assurance Partners','professional','2000100012','220100012',TRUE,'2026-12-31',TRUE,'billing@capartners.co.zw','+263 242 303 700','ZW','USD',30,'Stanbic Bank','9140000012','6700'),
   ('V013','Mhlanga & Associates Legal Practitioners','professional','2000100013','220100013',TRUE,'2026-12-31',FALSE,'accounts@mhlangalaw.co.zw','+263 242 250 600','ZW','USD',30,'CBZ Bank','0100200313','6700'),
   ('V014','Brand Africa Media (Pvt) Ltd','supplier','2000100014','220100014',TRUE,'2026-09-30',TRUE,'finance@brandafrica.co.zw','+263 242 870 400','ZW','USD',30,'Stanbic Bank','9140000014','6400'),
   ('V015','Zambezi Travel & Tours','supplier','2000100015','220100015',TRUE,'2026-12-31',TRUE,'corporate@zambezitravel.co.zw','+263 242 704 200','ZW','USD',14,'CBZ Bank','0100200315','5300'),
   ('V016','Sibanda Forensic Accountants','subcontractor','2000100016',NULL,TRUE,NULL,FALSE,'sibandafa@outlook.com','+263 77 316 1616','ZW','USD',30,'CABS','1000200316','5200'),
   ('V017','DataPlus Analytics (Pty) Ltd','subcontractor','ZA9012345678',NULL,FALSE,NULL,FALSE,'accounts@dataplus.co.za','+27 11 450 1700','ZA','USD',30,'FNB','62000017','5200'),
   ('V018','Zuva Energy (Pvt) Ltd','supplier','2000100018','220100018',TRUE,'2026-12-31',TRUE,'fleet@zuvaenergy.co.zw','+263 242 790 180','ZW','USD',14,'CBZ Bank','0100200318','6800'),
   ('V019','Harare Motor Services','supplier','2000100019','220100019',TRUE,'2026-10-31',TRUE,'service@hms.co.zw','+263 242 486 190','ZW','USD',30,'CBZ Bank','0100200319','6800'),
   ('V020','Paperlink Office Supplies','supplier','2000100020','220100020',TRUE,'2026-12-31',TRUE,'orders@paperlink.co.zw','+263 242 771 200','ZW','USD',30,'Stanbic Bank','9140000020','6900'),
   ('V021','Institute of Chartered Accountants of Zimbabwe','professional','2000100021',NULL,TRUE,'2026-12-31',FALSE,'members@icaz.org.zw','+263 242 301 100','ZW','USD',30,'CBZ Bank','0100200321','6300'),
   ('V022','Association of Certified Fraud Examiners','supplier','US58-1624890',NULL,FALSE,NULL,FALSE,'memberservices@acfe.com','+1 512 478 9000','US','USD',30,'Frost Bank','US00FROST22','6300'),
   ('V023','Axis Computers Zimbabwe (Pvt) Ltd','supplier','2000100023','220100023',TRUE,'2026-12-31',TRUE,'sales@axiscomputers.co.zw','+263 242 336 230','ZW','USD',30,'Stanbic Bank','9140000023','1530'),
   ('V024','Zimbabwe Motor Distributors','supplier','2000100024','220100024',TRUE,'2026-12-31',TRUE,'fleet@zmd.co.zw','+263 242 621 240','ZW','USD',30,'CBZ Bank','0100200324','1520'),
   ('V025','Delta Office Furniture','supplier','2000100025','220100025',TRUE,'2026-12-31',TRUE,'sales@deltafurniture.co.zw','+263 242 667 250','ZW','USD',30,'CBZ Bank','0100200325','1540'),
   ('V026','Magnet Forensics Inc.','supplier','CA81234 5678',NULL,FALSE,NULL,FALSE,'ar@magnetforensics.com','+1 844 638 7884','US','USD',30,'RBC','CA00RBC26','1800'),
   ('V027','Sandton Central Properties (Pty) Ltd','landlord','ZA4270100027','4270100027',TRUE,NULL,FALSE,'leasing@sandtoncentral.co.za','+27 11 300 2700','ZA','ZAR',7,'Standard Bank','00270100027',NULL),
   ('V028','Westlands Square Ltd','landlord','P051100028Z','0110028X',TRUE,NULL,FALSE,'accounts@westlandssquare.co.ke','+254 20 280 2800','KE','KES',7,'KCB','1100280028',NULL),
   ('V029','Minster Court Estates Ltd','landlord','GB290029029','GB290029029',TRUE,NULL,FALSE,'rent@minstercourt.co.uk','+44 20 7290 2900','GB','GBP',7,'HSBC','40-29-00 29002900',NULL),
   ('V030','DIFC Investments LLC','landlord','100300030000003','100300030000003',TRUE,NULL,FALSE,'leasing@difcinvest.ae','+971 4 362 2222','AE','AED',7,'Emirates NBD','1030030030',NULL),
   ('V031','Arundel Office Park (Pvt) Ltd','landlord','2000100031','220100031',TRUE,'2026-12-31',FALSE,'rentals@arundelpark.co.zw','+263 242 339 310','ZW','USD',7,'CBZ Bank','0100200331',NULL),
   ('V032','Sandton Office Services (Pty) Ltd','supplier','ZA4270100032','4270100032',TRUE,NULL,FALSE,'billing@sos.co.za','+27 11 300 3200','ZA','ZAR',30,'FNB','62000032','6110'),
   ('V033','Westlands Business Services','supplier','P051100033Z','0110033X',TRUE,NULL,FALSE,'billing@wbs.co.ke','+254 20 280 3300','KE','KES',30,'NCBA Bank','1100330033','6110'),
   ('V034','City Facilities Management Ltd','supplier','GB290029034','GB290029034',TRUE,NULL,FALSE,'ar@cityfm.co.uk','+44 20 7290 3400','GB','GBP',30,'Barclays','20-45-77 34003400','6110'),
   ('V035','Gulf Facilities Management LLC','supplier','100300030000035','100300030000035',TRUE,NULL,FALSE,'billing@gulffm.ae','+971 4 362 3500','AE','AED',30,'Emirates NBD','1030030035','6110'),
   ('V036','Zimbabwe Revenue Authority (ZIMRA)','government','ZIMRA',NULL,TRUE,NULL,FALSE,'lco@zimra.co.zw','+263 242 758 891','ZW','USD',0,'RBZ','ZIMRA-USD',NULL),
   ('V037','National Social Security Authority (NSSA)','government','NSSA',NULL,TRUE,NULL,FALSE,'contributions@nssa.org.zw','+263 242 706 523','ZW','USD',0,'CBZ Bank','NSSA-USD',NULL),
   ('V038','Zimbabwe Manpower Development Fund (ZIMDEF)','government','ZIMDEF',NULL,TRUE,NULL,FALSE,'levies@zimdef.org.zw','+263 242 790 912','ZW','USD',0,'CBZ Bank','ZIMDEF-USD',NULL),
   ('V039','Borrowdale Conference Centre (Pvt) Ltd','landlord','2000100039','220100039',TRUE,'2026-12-31',FALSE,'bookings@borrowdalecc.co.zw','+263 242 870 390','ZW','USD',7,'Stanbic Bank','9140000039',NULL),
   ('V040','Bulawayo Storage Solutions','landlord','2000100040','220100040',TRUE,'2026-12-31',FALSE,'info@byostorage.co.zw','+263 292 880 400','ZW','USD',7,'CABS','1000200340',NULL),
   ('V041','Maxhub Staff Pension Fund','professional','2000100041',NULL,TRUE,'2026-12-31',FALSE,'trustees@maxhubpension.co.zw','+263 242 700 141','ZW','USD',7,'CBZ Bank','0100200341',NULL),
   ('V042','CIMAS Medical Aid Society','professional','2000100042',NULL,TRUE,'2026-12-31',FALSE,'corporate@cimas.co.zw','+263 242 773 000','ZW','USD',7,'CBZ Bank','0100200342',NULL),
   ('V043','Cummins Power Zimbabwe','supplier','2000100043','220100043',TRUE,'2026-12-31',TRUE,'service@cumminszw.co.zw','+263 242 486 430','ZW','USD',30,'Stanbic Bank','9140000043','6120'),
   ('V044','SolarTech Africa (Pvt) Ltd','supplier','2000100044','220100044',TRUE,'2026-12-31',TRUE,'projects@solartech.co.zw','+263 242 870 440','ZW','USD',30,'CBZ Bank','0100200344','1550')
  ) AS v(code, name, t, tin, vat, res, itf, praz, email, phone, cc, cur, terms, bank, acc, gl);

UPDATE tax_authorities a SET vendor_id = v.vendor_id FROM vendors v
 WHERE (a.authority_code, v.vendor_code) IN (('ZIMRA','V036'), ('NSSA','V037'), ('ZIMDEF','V038'));

INSERT INTO tax_clearance_certificates (holder_type, vendor_id, certificate_no, issue_date, expiry_date)
VALUES ('company', NULL, 'ITF263-2026-0451236', '2026-01-05', '2026-12-31');
INSERT INTO tax_clearance_certificates (holder_type, vendor_id, certificate_no, issue_date, expiry_date)
SELECT 'vendor', vendor_id, 'ITF263-' || right(tax_number, 6), make_date(extract(year FROM tax_clearance_expiry)::INT, 1, 5), tax_clearance_expiry
  FROM vendors WHERE tax_clearance_expiry IS NOT NULL;

INSERT INTO tax_registrations (authority_code, office_id, registration_type, registration_no, registered_on, tax_office)
SELECT v.a, (SELECT office_id FROM offices WHERE code = v.o), v.t, v.n, v.d::DATE, v.office
  FROM (VALUES ('ZIMRA','HRE','TIN / BP number','2000451236','2012-06-15','ZIMRA Large Client Office, Harare'),
               ('ZIMRA','HRE','VAT (Category C)','220451236','2012-08-01','ZIMRA Large Client Office, Harare'),
               ('ZIMRA','HRE','PAYE employer','2000451236-PAYE','2012-06-15','ZIMRA Large Client Office, Harare'),
               ('NSSA','HRE','Employer registration','NSSA-EMP-0045123','2012-06-20','NSSA Harare'),
               ('ZIMDEF','HRE','Levy registration','ZDF-11873','2012-07-01','ZIMDEF Harare'),
               ('SARS','JNB','Income tax (external company)','9451236181','2018-07-15','SARS Large Business Centre'),
               ('SARS','JNB','VAT vendor','4451236181','2018-08-01','SARS'),
               ('KRA','NBO','PIN','P052451236M','2021-03-10','KRA Westlands'),
               ('HMRC','LON','Corporation tax UTR','45123 61234','2023-01-20','HMRC'),
               ('HMRC','LON','PAYE reference','120/MA45123','2023-01-20','HMRC'),
               ('UAEFTA','DXB','Tax registration number (TRN)','100451236100003','2024-03-01','Federal Tax Authority')) AS v(a, o, t, n, d, office);

-- 32.2 Properties & insurance -------------------------------------------------------------
INSERT INTO properties (property_code, name, address, city, country_code, stand_number, title_deed_number, land_size_sqm,
                        building_size_sqm, use_type, lettable_area_sqm, office_id, council, notes)
VALUES ('PRP-HRE-01','Maxhub House','45 Enterprise Road, Highlands','Harare','ZW','Stand 4412 Highlands Township','DT 2014/3321',4200,6800,'mixed',2040,
        (SELECT office_id FROM offices WHERE code='HRE'),'City of Harare','6 floors. Floors 1-4 owner-occupied (IAS 16). Floors 5-6 (30%) let to tenants - investment property (IAS 40).'),
       ('PRP-BYO-01','Maxhub Centre','88 Jason Moyo Street','Bulawayo','ZW','Stand 1180 Bulawayo Township','DT 2015/0877',1500,1900,'owner_occupied',NULL,
        (SELECT office_id FROM offices WHERE code='BYO'),'City of Bulawayo','Owner-occupied regional office.'),
       ('PRP-HRE-02','Mount Pleasant Business Park - Stand 22','Stand 22, Mount Pleasant Business Park','Harare','ZW','Stand 22 MPBP','DT 2022/1954',8000,NULL,'vacant_land',NULL,
        (SELECT office_id FROM offices WHERE code='HRE'),'City of Harare','Held for the future Maxhub campus (owner-occupation intended - IAS 16 land).');

INSERT INTO insurance_policies (policy_number, insurer_vendor_id, cover_type, sum_insured, annual_premium, start_date, end_date, excess_amount, notes)
SELECT v.no, (SELECT vendor_id FROM vendors WHERE vendor_code='V011'), v.cover, v.sum, v.prem, '2026-01-01', '2026-12-31', v.xs, v.notes
  FROM (VALUES ('HGI-PROP-2026-114','Property - buildings & contents (fire & allied perils)', 7500000, 21500, 5000, 'Maxhub House, Maxhub Centre'),
               ('HGI-MOT-2026-115','Motor fleet - comprehensive', 1100000, 41000, 1000, 'All company vehicles'),
               ('HGI-PI-2026-116','Professional indemnity', 5000000, 64000, 25000, 'Forensic & advisory engagements, worldwide excl. USA'),
               ('HGI-CYB-2026-117','Cyber liability', 2000000, 18500, 10000, 'Data breach, business interruption, ransomware'),
               ('HGI-EEI-2026-118','Electronic equipment (all risks)', 1400000, 9800, 250, 'Laptops, servers, forensic lab equipment')) AS v(no, cover, sum, prem, xs, notes);

-- 32.3 Asset categories (accounting policies) ----------------------------------------------
INSERT INTO asset_categories (code, name, asset_class, standard, measurement_model, depreciation_method, useful_life_months,
                              residual_value_pct, cost_account_id, acc_dep_account_id, dep_expense_account_id, reval_reserve_account_id,
                              tax_wear_tear_rate_pct, capitalisation_threshold)
SELECT v.code, v.name, v.cls, v.std, v.model, v.meth, v.life, v.resid, fn_account_id(v.cost),
       CASE WHEN v.ad IS NOT NULL THEN fn_account_id(v.ad) END, CASE WHEN v.dep IS NOT NULL THEN fn_account_id(v.dep) END,
       CASE WHEN v.res IS NOT NULL THEN fn_account_id(v.res) END, v.wt, v.thr
  FROM (VALUES
   ('LND','Land (revaluation model)','land','IAS 16','revaluation','none',NULL,0,'1500',NULL,NULL,'3300',0,0),
   ('BLD','Buildings (revaluation model)','buildings','IAS 16','revaluation','straight_line',600,0,'1510','1511','7000','3300',2.5,0),
   ('MV','Motor vehicles','motor_vehicles','IAS 16','cost','straight_line',60,10,'1520','1521','7000',NULL,20,1000),
   ('IT','Computer equipment','computer_equipment','IAS 16','cost','straight_line',36,0,'1530','1531','7000',NULL,25,500),
   ('FF','Furniture & fittings','furniture','IAS 16','cost','straight_line',120,0,'1540','1541','7000',NULL,10,500),
   ('OE','Office equipment, generators & solar','office_equipment','IAS 16','cost','straight_line',96,0,'1550','1551','7000',NULL,10,500),
   ('LHI','Leasehold improvements','leasehold_improvements','IAS 16','cost','straight_line',60,0,'1560','1561','7000',NULL,5,1000),
   ('LAB','Forensic lab equipment','forensic_lab_equipment','IAS 16','cost','straight_line',60,0,'1565','1566','7000',NULL,25,1000),
   ('SW','Software & licences','software','IAS 38','cost','straight_line',60,0,'1800','1801','7020',NULL,25,1000),
   ('IP','Investment property (fair value model)','investment_property','IAS 40','fair_value','none',NULL,0,'1700',NULL,NULL,NULL,2.5,0)
  ) AS v(code, name, cls, std, model, meth, life, resid, cost, ad, dep, res, wt, thr);

-- 32.4 Fixed asset register (assets owned at go-live, 31 Dec 2024) --------------------------
CREATE TEMP TABLE seed_assets (tag TEXT, name TEXT, cat TEXT, office TEXT, dept TEXT, custodian TEXT, make TEXT, serial TEXT, reg TEXT,
                               acq DATE, cost NUMERIC, life INT, fv2024 NUMERIC, prop TEXT, policy TEXT, qty INT DEFAULT 1);
INSERT INTO seed_assets VALUES
 ('MXH-LND-001','Maxhub House - land','LND','HRE','FAC',NULL,NULL,NULL,NULL,'2014-03-01',650000,NULL,1150000,'PRP-HRE-01','HGI-PROP-2026-114',1),
 ('MXH-BLD-001','Maxhub House - building (owner-occupied floors 1-4)','BLD','HRE','FAC',NULL,NULL,NULL,NULL,'2015-06-01',2300000,600,3400000,'PRP-HRE-01','HGI-PROP-2026-114',1),
 ('MXH-IP-001','Maxhub House - floors 5-6 let to tenants','IP','HRE','FIN',NULL,NULL,NULL,NULL,'2015-06-01',900000,NULL,1450000,'PRP-HRE-01','HGI-PROP-2026-114',1),
 ('MXH-LND-002','Maxhub Centre Bulawayo - land','LND','BYO','FAC',NULL,NULL,NULL,NULL,'2015-02-01',180000,NULL,260000,'PRP-BYO-01','HGI-PROP-2026-114',1),
 ('MXH-BLD-002','Maxhub Centre Bulawayo - building','BLD','BYO','FAC',NULL,NULL,NULL,NULL,'2015-02-01',520000,600,780000,'PRP-BYO-01','HGI-PROP-2026-114',1),
 ('MXH-LND-003','Mount Pleasant Business Park - Stand 22 (future campus)','LND','HRE','FAC',NULL,NULL,NULL,NULL,'2022-08-15',400000,NULL,520000,'PRP-HRE-02',NULL,1),
 ('MXH-MV-001','Toyota Land Cruiser Prado VX','MV','HRE','EXE','E001','Toyota Land Cruiser Prado 2.8GD','JTEBR3FJ20K100001','AFG 4410','2022-03-10',78000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-002','Toyota Fortuner 2.8GD-6','MV','HRE','EXE','E018','Toyota Fortuner 2.8GD-6','AHTKB3FS20K200002','AFB 2210','2021-06-15',52000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-003','Toyota Fortuner 2.8GD-6','MV','HRE','FAI','E002','Toyota Fortuner 2.8GD-6','AHTKB3FS20K200003','AFB 2211','2021-06-15',52000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-004','Toyota Fortuner 2.8GD-6','MV','HRE','RAS','E010','Toyota Fortuner 2.8GD-6','AHTKB3FS20K200004','AFB 2212','2021-06-15',52000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-005','Toyota Hilux 2.4GD-6 double cab','MV','HRE','FAC','E022','Toyota Hilux 2.4GD-6 D/C','AHTJB3DD20K300005','AEZ 7781','2020-09-01',45000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-006','Toyota Hilux 2.4GD-6 double cab','MV','BYO','FAC','E026','Toyota Hilux 2.4GD-6 D/C','AHTJB3DD20K300006','AEZ 7782','2021-02-01',46000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-007','Toyota Hilux 2.8GD-6 double cab','MV','HRE','FAI',NULL,'Toyota Hilux 2.8GD-6 D/C','AHTJB3DD20K300007','AGA 1920','2023-04-01',52000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-008','Nissan Navara 2.5 dCi (pool vehicle)','MV','HRE','FAC',NULL,'Nissan Navara D40','VSKCVND40U0400008','ADX 3380','2019-01-15',36000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-009','Toyota Quantum 14-seater (staff transport)','MV','HRE','FAC',NULL,'Toyota HiAce Quantum','JTFSS22P90K500009','AEY 5501','2021-08-01',42000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-010','Honda Fit hybrid (pool car)','MV','HRE','FAC',NULL,'Honda Fit Hybrid GP5','GP5-3100010','AGC 8810','2023-07-01',14000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-011','Honda Fit hybrid (pool car)','MV','HRE','FAC',NULL,'Honda Fit Hybrid GP5','GP5-3100011','AGC 8811','2023-07-01',14000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-MV-012','Mazda BT-50 3.2 (Johannesburg)','MV','JNB','FAI','E014','Mazda BT-50 3.2 4x4','MM0UP0YF100600012','JHB 441 GP','2022-05-01',38000,NULL,NULL,NULL,'HGI-MOT-2026-115',1),
 ('MXH-IT-SRV-001','Dell PowerEdge R760 - forensic processing server','IT','HRE','CYB','E012','Dell PowerEdge R760','SRV-R760-0001',NULL,'2023-05-15',38000,48,NULL,NULL,'HGI-EEI-2026-118',1),
 ('MXH-IT-SRV-002','Dell PowerEdge R760 - analytics platform server','IT','HRE','DAA','E003','Dell PowerEdge R760','SRV-R760-0002',NULL,'2023-05-15',38000,48,NULL,NULL,'HGI-EEI-2026-118',1),
 ('MXH-IT-NAS-001','Synology evidence storage array 400TB','IT','HRE','CYB','E012','Synology FS6400','NAS-6400-0001',NULL,'2023-05-15',24000,48,NULL,NULL,'HGI-EEI-2026-118',1),
 ('MXH-IT-NET-001','Core network: firewalls, switches & Wi-Fi','IT','HRE','ICT','E008','Fortinet / Cisco','NET-CORE-0001',NULL,'2022-02-01',32000,60,NULL,NULL,'HGI-EEI-2026-118',1),
 ('MXH-LAB-001','Forensic recovery workstations (FRED) x6','LAB','HRE','CYB','E012','Digital Intelligence FRED','FRED-6PK-0001',NULL,'2022-09-01',75000,NULL,NULL,NULL,'HGI-EEI-2026-118',1),
 ('MXH-LAB-002','Mobile forensics kit (UFED) #1','LAB','HRE','CYB',NULL,'Mobile extraction kit','UFED-0002',NULL,'2023-08-01',28000,NULL,NULL,NULL,'HGI-EEI-2026-118',1),
 ('MXH-LAB-003','Mobile forensics kit (UFED) #2','LAB','DXB','CYB',NULL,'Mobile extraction kit','UFED-0003',NULL,'2024-03-01',28000,NULL,NULL,NULL,'HGI-EEI-2026-118',1),
 ('MXH-LAB-004','Write-blocker & imaging field kits','LAB','HRE','CYB',NULL,'Tableau TX1 kits','TX1-KIT-0004',NULL,'2023-08-01',9500,NULL,NULL,NULL,'HGI-EEI-2026-118',1),
 ('MXH-FF-001','Maxhub House office furniture','FF','HRE','FAC',NULL,NULL,NULL,NULL,'2015-07-01',180000,NULL,NULL,'PRP-HRE-01','HGI-PROP-2026-114',1),
 ('MXH-FF-002','Bulawayo office furniture','FF','BYO','FAC',NULL,NULL,NULL,NULL,'2016-03-01',45000,NULL,NULL,'PRP-BYO-01','HGI-PROP-2026-114',1),
 ('MXH-FF-003','Johannesburg office furniture','FF','JNB','FAC',NULL,NULL,NULL,NULL,'2018-07-01',60000,NULL,NULL,NULL,'HGI-PROP-2026-114',1),
 ('MXH-FF-004','Nairobi office furniture','FF','NBO','FAC',NULL,NULL,NULL,NULL,'2021-03-01',38000,NULL,NULL,NULL,'HGI-PROP-2026-114',1),
 ('MXH-FF-005','London office furniture','FF','LON','FAC',NULL,NULL,NULL,NULL,'2023-01-09',52000,NULL,NULL,NULL,'HGI-PROP-2026-114',1),
 ('MXH-FF-006','Dubai office furniture','FF','DXB','FAC',NULL,NULL,NULL,NULL,'2024-02-01',41000,NULL,NULL,NULL,'HGI-PROP-2026-114',1),
 ('MXH-OE-001','Cummins 150kVA standby generator - Maxhub House','OE','HRE','FAC','E022','Cummins C150D5','GEN-150-0001',NULL,'2019-05-01',48000,NULL,NULL,'PRP-HRE-01','HGI-PROP-2026-114',1),
 ('MXH-OE-002','Cummins 60kVA standby generator - Bulawayo','OE','BYO','FAC',NULL,'Cummins C60D5','GEN-060-0002',NULL,'2019-08-01',22000,NULL,NULL,'PRP-BYO-01','HGI-PROP-2026-114',1),
 ('MXH-OE-003','120kW rooftop solar & battery system - Maxhub House','OE','HRE','FAC','E022','Hybrid PV + Li-ion storage','SOL-120-0003',NULL,'2023-10-01',85000,NULL,NULL,'PRP-HRE-01','HGI-PROP-2026-114',1),
 ('MXH-OE-004','Multifunction printers (fleet of 6)','OE','HRE','ICT',NULL,'Konica Minolta bizhub','MFP-6PK-0004',NULL,'2022-06-01',39000,60,NULL,NULL,'HGI-EEI-2026-118',1),
 ('MXH-OE-005','Air conditioning - Maxhub House','OE','HRE','FAC',NULL,'Daikin VRV','HVAC-0005',NULL,'2020-02-01',40000,NULL,NULL,'PRP-HRE-01','HGI-PROP-2026-114',1),
 ('MXH-OE-006','CCTV & access control','OE','HRE','FAC',NULL,'Hikvision / ZKTeco','SEC-0006',NULL,'2021-04-01',18000,NULL,NULL,'PRP-HRE-01','HGI-PROP-2026-114',1),
 ('MXH-LHI-001','Johannesburg office fit-out','LHI','JNB','FAC',NULL,NULL,NULL,NULL,'2018-07-01',95000,120,NULL,NULL,'HGI-PROP-2026-114',1),
 ('MXH-LHI-002','London office fit-out','LHI','LON','FAC',NULL,NULL,NULL,NULL,'2023-01-09',140000,60,NULL,NULL,'HGI-PROP-2026-114',1),
 ('MXH-LHI-003','Dubai office fit-out','LHI','DXB','FAC',NULL,NULL,NULL,NULL,'2024-02-01',88000,36,NULL,NULL,'HGI-PROP-2026-114',1),
 ('MXH-LHI-004','Arundel cyber lab - Faraday room & secure evidence store','LHI','HRE','CYB','E012',NULL,NULL,NULL,'2024-06-01',35000,36,NULL,NULL,'HGI-PROP-2026-114',1),
 ('MXH-SW-001','Relativity eDiscovery perpetual licence','SW','HRE','FAI','E002','Relativity Server','REL-LIC-0001',NULL,'2023-01-15',120000,60,NULL,NULL,NULL,1),
 ('MXH-SW-002','Data analytics licences (IDEA / Arbutus)','SW','HRE','DAA','E003','CaseWare IDEA / Arbutus','ANL-LIC-0002',NULL,'2024-01-10',45000,36,NULL,NULL,NULL,1);

-- laptops and phones: one per employee, tagged and assigned
INSERT INTO seed_assets (tag, name, cat, office, dept, custodian, make, serial, acq, cost, life, policy)
SELECT 'MXH-IT-' || lpad(e.employee_id::TEXT, 5, '0'),
       CASE WHEN g.level >= 5 THEN 'Laptop - Dell Latitude 9450' WHEN d.code IN ('DAA','CYB') THEN 'Laptop - Dell Precision 5690 (analytics)'
            ELSE 'Laptop - Dell Latitude 7450' END,
       'IT', o.code, d.code, e.employee_number,
       CASE WHEN g.level >= 5 THEN 'Dell Latitude 9450' WHEN d.code IN ('DAA','CYB') THEN 'Dell Precision 5690' ELSE 'Dell Latitude 7450' END,
       'DL' || upper(substr(md5(e.employee_id::TEXT), 1, 7)),
       CASE (e.employee_id % 3) WHEN 0 THEN '2022-02-14'::DATE WHEN 1 THEN '2023-02-20'::DATE ELSE '2024-03-18'::DATE END,
       CASE WHEN g.level >= 5 THEN 2400 WHEN d.code IN ('DAA','CYB') THEN 2900 ELSE 1450 END, 36, 'HGI-EEI-2026-118'
  FROM employees e JOIN job_grades g USING (job_grade_id) JOIN departments d USING (department_id) JOIN offices o ON o.office_id = e.office_id
 WHERE e.hire_date <= '2024-06-30' AND NOT (d.code = 'FAC' AND e.job_title IN ('Driver','Office Assistant'));

INSERT INTO fixed_assets (asset_tag, name, asset_category_id, property_id, status, office_id, department_id, custodian_employee_id,
                          serial_number, registration_number, make_model, acquisition_date, available_for_use_date, cost, residual_value,
                          useful_life_months, opening_date, opening_acc_depreciation, tax_value_opening, insured_value, insurance_policy_id, location_note)
SELECT s.tag, s.name, c.asset_category_id, (SELECT property_id FROM properties WHERE property_code = s.prop), 'in_use',
       (SELECT office_id FROM offices WHERE code = s.office), (SELECT department_id FROM departments WHERE code = s.dept),
       (SELECT employee_id FROM employees WHERE employee_number = s.custodian),
       s.serial, s.reg, s.make, s.acq, s.acq, s.cost, round(s.cost * c.residual_value_pct / 100, 2), s.life, '2024-12-31',
       -- accumulated depreciation at go-live (straight line, capped at depreciable amount); revalued assets restart from valuation
       CASE WHEN c.depreciation_method = 'none' OR s.fv2024 IS NOT NULL THEN 0
            ELSE LEAST(round((s.cost - s.cost * c.residual_value_pct / 100) / COALESCE(s.life, c.useful_life_months)
                        * ((extract(year FROM age('2024-12-31'::DATE, s.acq)) * 12 + extract(month FROM age('2024-12-31'::DATE, s.acq)) + 1)), 2),
                       s.cost - s.cost * c.residual_value_pct / 100) END,
       CASE WHEN c.asset_class IN ('land','investment_property') THEN s.cost
            ELSE GREATEST(round(s.cost * (1 - c.tax_wear_tear_rate_pct / 100 * (2024 - extract(year FROM s.acq) + 1)), 2), 0) END,
       COALESCE(s.fv2024, s.cost), (SELECT policy_id FROM insurance_policies WHERE policy_number = s.policy),
       (SELECT name FROM offices WHERE code = s.office)
  FROM seed_assets s JOIN asset_categories c ON c.code = s.cat;

-- legacy valuations at 31 Dec 2024 (performed before go-live: carrying amount = fair value)
INSERT INTO asset_revaluations (asset_id, valuation_date, valuation_type, valuer, fair_value, carrying_before, surplus_deficit,
                                to_oci, to_profit_or_loss, deferred_tax, fair_value_level)
SELECT fa.asset_id, '2024-12-31', CASE WHEN c.measurement_model = 'fair_value' THEN 'fair_value' ELSE 'revaluation' END,
       'Knight Frank Zimbabwe (independent valuers) - legacy valuation', s.fv2024, s.fv2024, 0, 0, 0, 0, 3
  FROM fixed_assets fa JOIN seed_assets s ON s.tag = fa.asset_tag JOIN asset_categories c ON c.asset_category_id = fa.asset_category_id
 WHERE s.fv2024 IS NOT NULL;
UPDATE fixed_assets fa SET revalued_amount = s.fv2024, last_revaluation_date = '2024-12-31'
  FROM seed_assets s WHERE s.tag = fa.asset_tag AND s.fv2024 IS NOT NULL;

INSERT INTO asset_assignments (asset_id, employee_id, assigned_date, condition_out)
SELECT asset_id, custodian_employee_id, GREATEST(acquisition_date, (SELECT hire_date FROM employees WHERE employee_id = custodian_employee_id)), 'New'
  FROM fixed_assets WHERE custodian_employee_id IS NOT NULL;

INSERT INTO asset_maintenance (asset_id, service_date, maintenance_type, description, vendor_id, cost, odometer_km, next_due_date)
SELECT fa.asset_id, d, 'service', 'Scheduled service', (SELECT vendor_id FROM vendors WHERE vendor_code = 'V019'),
       350 + (fa.asset_id % 5) * 60, 20000 + (fa.asset_id % 7) * 9000 + row_number() OVER (PARTITION BY fa.asset_id ORDER BY d) * 10000, d + 180
  FROM fixed_assets fa JOIN asset_categories c USING (asset_category_id)
 CROSS JOIN (VALUES ('2025-03-12'::DATE), ('2025-09-10'::DATE), ('2026-03-11'::DATE), ('2026-09-09'::DATE)) AS s(d)
 WHERE c.code = 'MV';
INSERT INTO asset_maintenance (asset_id, service_date, maintenance_type, description, vendor_id, cost, next_due_date)
SELECT fa.asset_id, d, 'service', '500-hour generator service & load test', (SELECT vendor_id FROM vendors WHERE vendor_code = 'V043'), 780, d + 120
  FROM fixed_assets fa CROSS JOIN (VALUES ('2025-02-05'::DATE), ('2025-06-04'::DATE), ('2025-10-08'::DATE), ('2026-02-04'::DATE), ('2026-06-03'::DATE)) AS s(d)
 WHERE fa.asset_tag IN ('MXH-OE-001','MXH-OE-002');

-- 32.5 Leases (IFRS 16) --------------------------------------------------------------------
INSERT INTO leases (lease_number, role, description, asset_class, office_id, vendor_id, currency_code, commencement_date, end_date, term_months,
                    payment_amount, payment_frequency, payment_timing, annual_escalation_pct, discount_rate_pct, deposit_paid, extension_option,
                    rou_account_code, rou_acc_dep_account_code, notes)
SELECT v.no, 'lessee', v.descr, v.cls, (SELECT office_id FROM offices WHERE code = v.office), (SELECT vendor_id FROM vendors WHERE vendor_code = v.vendor),
       v.cur, v.start::DATE, (v.start::DATE + make_interval(months => v.term) - INTERVAL '1 day')::DATE, v.term, v.pay, 'monthly', 'advance',
       v.esc, v.ibr, v.dep, v.ext, '1600', '1601', v.notes
  FROM (VALUES
   ('LSE-JNB-001','Johannesburg office - 140 West Street, 9th floor (620 m2)','property','JNB','V027','ZAR','2023-07-01',60,248000,7.0,11.75,496000,'Option to renew for 3 years - not reasonably certain','Escalates 7% each July'),
   ('LSE-NBO-001','Nairobi office - Westlands Square, 7th floor (410 m2)','property','NBO','V028','KES','2024-03-01',60,780000,5.0,14.00,1560000,'5-year renewal option - not reasonably certain','Service charge billed separately'),
   ('LSE-LON-001','London office - 1 Minster Court, 4th floor (300 m2)','property','LON','V029','GBP','2023-01-01',60,23500,0.0,7.25,70500,'Break clause at month 36 - not expected to be exercised','Rent reviewed at year 5'),
   ('LSE-DXB-001','Dubai office - DIFC Gate Village 5, level 3 (260 m2)','property','DXB','V030','AED','2024-02-01',36,52000,3.0,6.50,104000,'Renewal on market terms','DIFC fit-out approved'),
   ('LSE-HRE-001','Arundel Office Park - cyber forensics lab (180 m2)','property','HRE','V031','USD','2024-06-01',36,5400,0.0,12.50,10800,NULL,'Secure lab, Faraday room'),
   ('LSE-BYO-001','Bulawayo archive & evidence storage warehouse (240 m2)','property','BYO','V040','USD','2025-04-01',36,1850,0.0,12.50,3700,NULL,'Commenced after go-live - recognised in FY2025'),
   ('LSE-HRE-002','Borrowdale Conference Centre - Maxhub Academy training suite','property','HRE','V039','USD','2026-03-01',48,7200,5.0,12.00,14400,'Option to extend 2 years','Commenced in FY2026')
  ) AS v(no, descr, cls, office, vendor, cur, start, term, pay, esc, ibr, dep, ext, notes);

-- short-term / low-value leases use the IFRS 16 exemption (expensed in 6100)
INSERT INTO leases (lease_number, role, description, asset_class, office_id, vendor_id, currency_code, commencement_date, end_date, term_months,
                    payment_amount, exemption, status, notes)
VALUES ('LSE-HRE-ST1','lessee','Victoria Falls project site office (6 months)','property',(SELECT office_id FROM offices WHERE code='HRE'),
        (SELECT vendor_id FROM vendors WHERE vendor_code='V031'),'USD','2026-05-01','2026-10-31',6,1200,'short_term','active','Short-term lease exemption (IFRS 16.6)'),
       ('LSE-HRE-LV1','lessee','Water dispensers & shredders (low value)','equipment',(SELECT office_id FROM offices WHERE code='HRE'),
        (SELECT vendor_id FROM vendors WHERE vendor_code='V020'),'USD','2025-01-01','2027-12-31',36,180,'low_value','active','Low-value asset exemption (IFRS 16.6)');

-- lessor leases: tenants on floors 5-6 of Maxhub House (operating leases, IFRS 16.81)
INSERT INTO leases (lease_number, role, description, asset_class, property_id, tenant_name, currency_code, commencement_date, end_date, term_months,
                    payment_amount, payment_timing, annual_escalation_pct, deposit_paid, status, notes)
SELECT v.no, 'lessor', v.descr, 'property', (SELECT property_id FROM properties WHERE property_code = 'PRP-HRE-01'), v.tenant, 'USD',
       v.start::DATE, (v.start::DATE + make_interval(months => v.term) - INTERVAL '1 day')::DATE, v.term, v.rent, 'advance', 5, v.rent * 2, 'active', 'Operating lease - rental income (investing category under IFRS 18)'
  FROM (VALUES ('TEN-HRE-001','Floor 5 east wing (680 m2)','Kalahari Reinsurance Brokers (Pvt) Ltd','2023-04-01',60,6200),
               ('TEN-HRE-002','Floor 5 west wing (520 m2)','Mosi Legal Chambers','2024-01-01',36,4700),
               ('TEN-HRE-003','Floor 6 (840 m2)','Great Dyke Mining Services Ltd','2022-10-01',60,7400)) AS v(no, descr, tenant, start, term, rent);

-- 32.6 Borrowings -------------------------------------------------------------------------
INSERT INTO borrowings (loan_number, lender, purpose, currency_code, principal, interest_rate_pct, drawdown_date, term_months, security, bank_account_id)
VALUES ('CBZ-ML-2021-07','CBZ Bank Limited','Refinance of Maxhub House construction & Bulawayo purchase','USD',2400000,11.5,'2021-07-01',120,
        'First mortgage bond over Maxhub House (Stand 4412 Highlands)', (SELECT bank_account_id FROM bank_accounts WHERE name = 'Operating USD - Harare'));
DO $$ BEGIN PERFORM fn_generate_loan_schedule(loan_id) FROM borrowings; END $$;
UPDATE loan_schedule SET is_posted = TRUE WHERE due_date <= '2024-12-31';

-- schedules for leases that started before go-live; rows before go-live are "legacy posted"
UPDATE leases SET commencement_fx_rate = fn_fx_rate(currency_code, '2024-12-31')
 WHERE role = 'lessee' AND exemption IS NULL AND commencement_date < '2025-01-01';
DO $$ BEGIN PERFORM fn_generate_lease_schedule(lease_id) FROM leases WHERE role = 'lessee' AND exemption IS NULL AND commencement_date < '2025-01-01'; END $$;
UPDATE lease_schedule SET is_posted = TRUE WHERE period_date <= '2024-12-01';

-- 32.7 Opening balances at 31 December 2024 ----------------------------------------------
DO $$
DECLARE v_lines JSONB := '[]'::JSONB; v_total_dr NUMERIC; v_total_cr NUMERIC; v_je BIGINT; r RECORD; v_rate NUMERIC := 24.72;
        v_reval NUMERIC := 0; v_dtl NUMERIC := 0; v_lease_usd NUMERIC; v_rou NUMERIC;
BEGIN
    -- PPE, investment property & intangibles at go-live carrying amounts, by account
    FOR r IN SELECT ca.account_code AS cost_acc, ad.account_code AS ad_acc, SUM(COALESCE(fa.revalued_amount, fa.cost)) AS gross,
                    SUM(fa.opening_acc_depreciation) AS accdep
               FROM fixed_assets fa JOIN asset_categories c USING (asset_category_id)
               JOIN chart_of_accounts ca ON ca.account_id = c.cost_account_id
               LEFT JOIN chart_of_accounts ad ON ad.account_id = c.acc_dep_account_id
              GROUP BY 1, 2
    LOOP
        v_lines := v_lines || jsonb_build_object('acc', r.cost_acc, 'dr', r.gross, 'desc','Opening balance - cost / valuation');
        IF r.accdep > 0 THEN v_lines := v_lines || jsonb_build_object('acc', r.ad_acc, 'cr', r.accdep, 'desc','Opening accumulated depreciation'); END IF;
    END LOOP;

    -- revaluation surpluses on land & buildings (net of deferred tax) and deferred tax on investment property gains
    SELECT COALESCE(SUM(fa.revalued_amount - (fa.cost - LEAST(fa.cost, CASE WHEN c.depreciation_method = 'none' THEN 0 ELSE
                 fa.cost / c.useful_life_months * ((extract(year FROM age('2024-12-31'::DATE, fa.acquisition_date)) * 12
                 + extract(month FROM age('2024-12-31'::DATE, fa.acquisition_date))) + 1) END))), 0)
      INTO v_reval
      FROM fixed_assets fa JOIN asset_categories c USING (asset_category_id) WHERE c.measurement_model = 'revaluation';
    SELECT COALESCE(SUM(fa.revalued_amount - fa.cost), 0) INTO v_dtl
      FROM fixed_assets fa JOIN asset_categories c USING (asset_category_id) WHERE c.measurement_model = 'fair_value';
    v_lines := v_lines
      || jsonb_build_object('acc','3300','cr', round(v_reval * (1 - v_rate / 100), 2), 'desc','Revaluation reserve (net of deferred tax)')
      || jsonb_build_object('acc','2900','cr', round((v_reval + v_dtl) * v_rate / 100, 2) + 185000, 'desc','Deferred tax (revaluations, IP gains, accelerated allowances)');

    -- leases: ROU assets and lease liabilities from the schedules
    FOR r IN SELECT l.lease_id, l.rou_account_code, l.rou_acc_dep_account_code, l.initial_rou_asset, l.currency_code,
                    (SELECT SUM(rou_depreciation) FROM lease_schedule s WHERE s.lease_id = l.lease_id AND s.is_posted) AS dep,
                    (SELECT closing_liability FROM lease_schedule s WHERE s.lease_id = l.lease_id AND s.is_posted ORDER BY period_no DESC LIMIT 1) AS liab
               FROM leases l WHERE l.role = 'lessee' AND l.exemption IS NULL AND l.commencement_date < '2025-01-01'
    LOOP
        v_lease_usd := round(r.liab * fn_fx_rate(r.currency_code, '2024-12-31'), 2);
        v_lines := v_lines
          || jsonb_build_object('acc', r.rou_account_code, 'dr', r.initial_rou_asset, 'desc','Opening ROU asset')
          || jsonb_build_object('acc', r.rou_acc_dep_account_code, 'cr', r.dep, 'desc','Opening ROU accumulated depreciation')
          || jsonb_build_object('acc','2700','cr', v_lease_usd, 'desc','Opening lease liability');
        UPDATE leases SET status = 'active', liability_usd_balance = v_lease_usd, last_fx_rate = fn_fx_rate(r.currency_code, '2024-12-31')
         WHERE lease_id = r.lease_id;
    END LOOP;

    v_lines := v_lines
      || jsonb_build_object('acc','2800','cr', (SELECT closing_balance FROM loan_schedule WHERE is_posted ORDER BY period_no DESC LIMIT 1), 'desc','CBZ mortgage loan')
      -- cash & cash equivalents
      || jsonb_build_object('acc','1010','dr', 1450000) || jsonb_build_object('acc','1013','dr', 1250000)
      || jsonb_build_object('acc','1011','dr', 38000)   || jsonb_build_object('acc','1017','dr', 1500000)
      || jsonb_build_object('acc','1018','dr', 140000)  || jsonb_build_object('acc','1012','dr', 160000)
      || jsonb_build_object('acc','1014','dr', 110000)  || jsonb_build_object('acc','1015','dr', 240000)
      || jsonb_build_object('acc','1016','dr', 130000)  || jsonb_build_object('acc','1020','dr', 2500)
      -- working capital (legacy system balances)
      || jsonb_build_object('acc','1100','dr', 2180000, 'desc','Trade receivables (legacy ledger)')
      || jsonb_build_object('acc','1105','cr', 42000,   'desc','ECL allowance')
      || jsonb_build_object('acc','1300','dr', 176000,  'desc','Prepaid insurance & licences')
      || jsonb_build_object('acc','1950','dr', 142000,  'desc','Rental deposits paid to landlords')
      || jsonb_build_object('acc','2100','cr', 418000,  'desc','Trade payables (legacy ledger)')
      || jsonb_build_object('acc','2500','cr', 152000,  'desc','Accruals')
      || jsonb_build_object('acc','2200','cr', 196500,  'desc','December 2024 output VAT')
      || jsonb_build_object('acc','2210','dr', 41200,   'desc','December 2024 input VAT')
      || jsonb_build_object('acc','2400','cr', 88400,   'desc','December 2024 PAYE')
      || jsonb_build_object('acc','2405','cr', 2650,    'desc','December 2024 AIDS levy')
      || jsonb_build_object('acc','2410','cr', 14800,   'desc','December 2024 NSSA')
      || jsonb_build_object('acc','2415','cr', 3700,    'desc','December 2024 ZIMDEF')
      || jsonb_build_object('acc','2420','cr', 52000,   'desc','December 2024 pension contributions')
      || jsonb_build_object('acc','2425','cr', 21500,   'desc','December 2024 medical aid')
      || jsonb_build_object('acc','2450','cr', 61000,   'desc','Branch payroll taxes')
      || jsonb_build_object('acc','2260','cr', 342000,  'desc','FY2024 income tax balance due 30 April 2025')
      || jsonb_build_object('acc','2510','cr', 214000,  'desc','Leave pay accrual')
      || jsonb_build_object('acc','2550','cr', 90000,   'desc','Dilapidations provision - branch leases')
      || jsonb_build_object('acc','2600','cr', 158000,  'desc','Client advances')
      || jsonb_build_object('acc','2650','cr', (SELECT SUM(deposit_paid) FROM leases WHERE role = 'lessor'), 'desc','Tenant deposits held')
      || jsonb_build_object('acc','3100','cr', 1000000, 'desc','Share capital - 1,000,000 ordinary shares of USD 1');

    -- retained earnings = balancing figure
    SELECT SUM(COALESCE((x->>'dr')::NUMERIC, 0)), SUM(COALESCE((x->>'cr')::NUMERIC, 0)) INTO v_total_dr, v_total_cr
      FROM jsonb_array_elements(v_lines) x;
    v_lines := v_lines || jsonb_build_object('acc','3200','cr', round(v_total_dr - v_total_cr, 2), 'desc','Retained earnings at 31 December 2024');

    v_je := fn_post_journal('2024-12-31', 'Opening balances at go-live (migrated from legacy system, audited FY2024)', 'opening', NULL, v_lines);
    UPDATE leases SET recognised_journal_id = v_je WHERE role = 'lessee' AND exemption IS NULL AND commencement_date < '2025-01-01';
END $$;

UPDATE fiscal_periods SET is_closed = TRUE WHERE fiscal_year_id = (SELECT fiscal_year_id FROM fiscal_years WHERE name = 'FY2024');

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  33_seed_clients_projects.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   33. SEED - CLIENTS, CONTACTS, SERVICES, RATE CARDS, CONTRACTS, PROJECTS & TEAMS, CRM
   ===================================================================================== */

-- 33.1 Clients (fictional) ----------------------------------------------------------------
CREATE TEMP TABLE seed_clients (code TEXT, name TEXT, industry TEXT, cc TEXT, city TEXT, terms INT, behaviour TEXT, manager TEXT);
INSERT INTO seed_clients VALUES
 ('C001','Zambezi Mining Holdings Ltd','Mining & Resources','ZW','Harare',30,'good','E002'),
 ('C002','Harare Metropolitan Bank Ltd','Banking & Financial Services','ZW','Harare',30,'good','E002'),
 ('C003','Kariba Agro Processors (Pvt) Ltd','Agriculture & Agro-processing','ZW','Chinhoyi',45,'slow','E010'),
 ('C004','Great Zimbabwe Insurance Company','Insurance & Pensions','ZW','Harare',30,'good','E010'),
 ('C005','Ministry of Finance - Public Accounts Unit','Government & Public Sector','ZW','Harare',60,'slow','E001'),
 ('C006','National Water & Sanitation Authority','Government & Public Sector','ZW','Harare',60,'bad','E010'),
 ('C007','Chimanimani Telecoms Ltd','Telecommunications','ZW','Harare',30,'good','E003'),
 ('C008','Victoria Retail Group Ltd','Retail & FMCG','ZW','Harare',30,'good','E003'),
 ('C009','Midlands Steel Works (Pvt) Ltd','Manufacturing','ZW','Kwekwe',45,'slow','E026'),
 ('C010','Matabeleland Breweries Ltd','Retail & FMCG','ZW','Bulawayo',30,'good','E026'),
 ('C011','Hwange Power & Energy Ltd','Energy & Utilities','ZW','Hwange',45,'slow','E012'),
 ('C012','Pension Fund of Zimbabwe Municipal Workers','Insurance & Pensions','ZW','Harare',30,'good','E011'),
 ('C013','Mutapa Microfinance Bank','Banking & Financial Services','ZW','Harare',30,'good','E012'),
 ('C014','Eastern Highlands Tea Estates','Agriculture & Agro-processing','ZW','Mutare',45,'good','E011'),
 ('C015','Sable Pharmaceuticals (Pvt) Ltd','Healthcare','ZW','Harare',30,'good','E013'),
 ('C016','Limpopo Logistics Ltd','Transport & Logistics','ZW','Beitbridge',30,'slow','E026'),
 ('C017','Zimbabwe Anti-Corruption Trust (NGO)','NGO & Development','ZW','Harare',30,'good','E002'),
 ('C018','Bindura Nickel & Gold Ltd','Mining & Resources','ZW','Bindura',30,'good','E013'),
 ('C019','Savanna Tobacco Merchants','Agriculture & Agro-processing','ZW','Harare',30,'good','E011'),
 ('C020','Harare Stock Brokers Association','Banking & Financial Services','ZW','Harare',30,'good','E003'),
 ('C021','Gauteng Provincial Treasury','Government & Public Sector','ZA','Johannesburg',30,'slow','E014'),
 ('C022','Rand Merchant Credit (Pty) Ltd','Banking & Financial Services','ZA','Johannesburg',30,'good','E014'),
 ('C023','Highveld Platinum Mines (Pty) Ltd','Mining & Resources','ZA','Rustenburg',30,'good','E014'),
 ('C024','Umoja Mobile Money Kenya Ltd','Telecommunications','KE','Nairobi',30,'good','E015'),
 ('C025','Rift Valley Horticulture Exporters','Agriculture & Agro-processing','KE','Naivasha',45,'slow','E015'),
 ('C026','East African Development Fund','NGO & Development','KE','Nairobi',30,'good','E015'),
 ('C027','Thames Commodity Traders Ltd','Mining & Resources','GB','London',30,'good','E016'),
 ('C028','Albion Private Equity LLP','Banking & Financial Services','GB','London',30,'good','E016'),
 ('C029','Gulf Horizon Trading LLC','Retail & FMCG','AE','Dubai',30,'good','E017'),
 ('C030','Emirates Frontier Bank PJSC','Banking & Financial Services','AE','Dubai',30,'good','E017'),
 ('C031','Copperbelt Energy Partners Plc','Energy & Utilities','ZM','Lusaka',45,'slow','E013'),
 ('C032','Kalahari Diamond Traders (Pty) Ltd','Mining & Resources','BW','Gaborone',30,'good','E002'),
 ('C033','Beira Corridor Port Services','Transport & Logistics','MZ','Beira',45,'bad','E010'),
 ('C034','Zimbabwe Electoral Support Programme (UN)','NGO & Development','ZW','Harare',30,'good','E003'),
 ('C035','Masvingo Sugar Estates Ltd','Agriculture & Agro-processing','ZW','Chiredzi',30,'good','E026'),
 ('C036','Hararians Property Fund','Real Estate','ZW','Harare',30,'good','E013'),
 ('C037','Nyanga Medical Group','Healthcare','ZW','Harare',30,'slow','E011'),
 ('C038','African Reinsurance Pool Ltd','Insurance & Pensions','KE','Nairobi',30,'good','E015'),
 ('C039','Sadc Clearing & Settlement House','Banking & Financial Services','ZA','Johannesburg',30,'good','E014'),
 ('C040','Chitungwiza Municipality','Government & Public Sector','ZW','Chitungwiza',60,'bad','E010');

INSERT INTO clients (client_code, legal_name, trading_name, industry_id, status, registration_number, tax_number, vat_number, website, billing_email,
                     phone, address_line1, city, country_code, currency_code, payment_terms_days, credit_limit, account_manager_id, lead_source, notes)
SELECT c.code, c.name, split_part(c.name, ' ', 1) || ' ' || split_part(c.name, ' ', 2), i.industry_id, 'active',
       lpad((row_number() OVER (ORDER BY c.code) * 137)::TEXT, 4, '0') || '/' || (2000 + row_number() OVER (ORDER BY c.code) % 24),
       CASE c.cc WHEN 'ZW' THEN '2000' || lpad((row_number() OVER (ORDER BY c.code) * 7919)::TEXT, 6, '0') END,
       CASE c.cc WHEN 'ZW' THEN '2200' || lpad((row_number() OVER (ORDER BY c.code) * 7919)::TEXT, 5, '0') END,
       'www.' || lower(regexp_replace(split_part(c.name, ' ', 1), '[^A-Za-z]', '', 'g')) || '.example',
       'accounts@' || lower(regexp_replace(split_part(c.name, ' ', 1), '[^A-Za-z]', '', 'g')) || '.example',
       '+000 ' || lpad((row_number() OVER (ORDER BY c.code) * 4441)::TEXT, 7, '0'), 'Head Office', c.city, c.cc, 'USD', c.terms,
       CASE c.behaviour WHEN 'bad' THEN 150000 ELSE 600000 END,
       (SELECT employee_id FROM employees WHERE employee_number = c.manager),
       (ARRAY['Referral','Tender','Existing relationship','Website','Conference'])[1 + (row_number() OVER (ORDER BY c.code))::INT % 5],
       'Payment behaviour: ' || c.behaviour
  FROM seed_clients c JOIN industries i ON i.name = c.industry;

INSERT INTO client_contacts (client_id, first_name, last_name, job_title, email, phone, is_primary, is_billing_contact, is_decision_maker)
SELECT cl.client_id, v.fn, v.ln, v.title, lower(v.fn || '.' || v.ln) || '@' || split_part(cl.billing_email, '@', 2), cl.phone, v.prim, v.bill, v.dm
  FROM clients cl
 CROSS JOIN LATERAL (VALUES
      ((ARRAY['Grace','Peter','Linda','Joseph','Ann','Brian','Esther','Martin'])[1 + cl.client_id::INT % 8],
       (ARRAY['Mutero','Phiri','Govender','Otieno','Hughes','Musariri','Nel','Kamara'])[1 + cl.client_id::INT % 8],
       (ARRAY['Chief Executive Officer','Chief Financial Officer','Head of Internal Audit','Chief Risk Officer'])[1 + cl.client_id::INT % 4], TRUE, FALSE, TRUE),
      ((ARRAY['Rose','Sam','Mary','David','Julia','Kenneth'])[1 + cl.client_id::INT % 6],
       (ARRAY['Chari','Mokoena','Wanjiku','Brown','Dlamini','Moyo'])[1 + (cl.client_id::INT + 3) % 6], 'Accounts Payable Manager', FALSE, TRUE, FALSE)
 ) AS v(fn, ln, title, prim, bill, dm);

-- 33.2 Service catalogue & rate cards -----------------------------------------------------
INSERT INTO services (service_line_id, code, name, default_unit, default_price)
SELECT (SELECT service_line_id FROM service_lines WHERE code = v.sl), v.code, v.name, v.unit, v.price
  FROM (VALUES ('FAI','FAI-INV','Fraud & corruption investigation','hour',NULL), ('FAI','FAI-AUD','Forensic audit','hour',NULL),
               ('FAI','FAI-LIT','Litigation support & expert witness','hour',NULL), ('FAI','FAI-AST','Asset tracing','fixed',25000),
               ('DAA','DAA-FRA','Fraud analytics & continuous monitoring','month',NULL), ('DAA','DAA-BI','BI dashboards & data platform','fixed',NULL),
               ('DAA','DAA-ML','Machine-learning risk scoring model','fixed',60000),
               ('CYB','CYB-DF','Digital forensics (device imaging & analysis)','hour',NULL), ('CYB','CYB-IR','Incident response retainer','month',NULL),
               ('CYB','CYB-PT','Penetration test','fixed',18000), ('CYB','CYB-ISO','ISO 27001 readiness','fixed',35000),
               ('RAS','RAS-IA','Outsourced internal audit','month',NULL), ('RAS','RAS-ERM','Enterprise risk management framework','fixed',30000),
               ('RAS','RAS-AML','AML/CFT compliance review','hour',NULL),
               ('TAX','TAX-DSP','ZIMRA dispute resolution','hour',NULL), ('TAX','TAX-HC','Tax health check','fixed',12000),
               ('TAX','TAX-TP','Transfer pricing documentation','fixed',28000),
               ('FAV','FAV-VAL','Business valuation','fixed',22000), ('FAV','FAV-FDD','Financial due diligence','hour',NULL),
               ('FAV','FAV-IFRS','IFRS 18 / IFRS 16 advisory','hour',NULL)) AS v(sl, code, name, unit, price);

INSERT INTO rate_cards (name, currency_code, valid_from, valid_to, is_default) VALUES
 ('Standard USD rates 2025','USD','2025-01-01','2025-12-31',FALSE), ('Standard USD rates 2026','USD','2026-01-01',NULL,TRUE);
INSERT INTO rate_card_lines (rate_card_id, job_grade_id, hourly_rate, daily_rate)
SELECT rc.rate_card_id, g.job_grade_id, round(g.default_bill_rate * CASE WHEN rc.name LIKE '%2025%' THEN 0.95 ELSE 1 END, 0),
       round(g.default_bill_rate * 8 * CASE WHEN rc.name LIKE '%2025%' THEN 0.95 ELSE 1 END, 0)
  FROM rate_cards rc CROSS JOIN job_grades g WHERE g.level > 0;

-- 33.3 Projects ---------------------------------------------------------------------------
CREATE TEMP TABLE seed_projects (code TEXT, name TEXT, client TEXT, sl TEXT, office TEXT, btype TEXT, start DATE, finish DATE,
                                 final_status TEXT, fees NUMERIC, team INT, tax TEXT, priority TEXT);
INSERT INTO seed_projects VALUES
 ('P25-001','Procurement fraud investigation - mine supply contracts','C001','FAI','HRE','time_and_materials','2025-10-06','2026-06-30','completed',420000,5,'ZW-VAT','high'),
 ('P25-002','Forensic audit of loan book write-offs','C002','FAI','HRE','time_and_materials','2025-11-03','2026-04-30','completed',260000,4,'ZW-VAT','high'),
 ('P25-003','Outsourced internal audit FY2026','C004','RAS','HRE','retainer','2025-11-01','2026-12-31','active',264000,3,'ZW-VAT','medium'),
 ('P25-004','Continuous transaction monitoring platform','C007','DAA','HRE','milestone','2025-09-15','2026-10-31','active',380000,5,'ZW-VAT','high'),
 ('P25-005','Public finance management forensic review','C005','FAI','HRE','time_and_materials','2025-10-13','2026-12-18','active',520000,5,'ZW-VAT','critical'),
 ('P25-006','Tax dispute - ZIMRA transfer pricing assessment','C014','TAX','HRE','time_and_materials','2025-11-10','2026-05-29','completed',145000,3,'ZW-VAT','high'),
 ('P25-007','Valuation for rights issue','C018','FAV','HRE','fixed_fee','2025-11-17','2026-02-27','completed',95000,3,'ZW-VAT','medium'),
 ('P25-008','Incident response retainer','C013','CYB','HRE','retainer','2025-10-01','2026-09-30','active',144000,2,'ZW-VAT','high'),
 ('P25-009','Payroll ghost-worker analytics','C040','DAA','HRE','time_and_materials','2025-11-24','2026-07-31','completed',150000,3,'ZW-VAT','medium'),
 ('P25-010','Internal audit co-source - Bulawayo operations','C010','RAS','BYO','retainer','2025-10-01','2026-12-31','active',168000,3,'ZW-VAT','medium'),
 ('P26-011','Asset tracing - misappropriated fuel stocks','C016','FAI','BYO','time_and_materials','2026-01-12','2026-08-28','completed',135000,3,'ZW-VAT','high'),
 ('P26-012','AML/CFT compliance review & RBZ remediation','C013','RAS','HRE','time_and_materials','2026-01-19','2026-06-26','completed',118000,3,'ZW-VAT','high'),
 ('P26-013','Digital forensics - executive email leak','C008','CYB','HRE','time_and_materials','2026-02-02','2026-04-30','completed',88000,3,'ZW-VAT','critical'),
 ('P26-014','Fraud risk scoring model (machine learning)','C002','DAA','HRE','milestone','2026-02-09','2026-11-30','active',240000,4,'ZW-VAT','high'),
 ('P26-015','Water billing revenue-leakage investigation','C006','FAI','HRE','time_and_materials','2026-02-16','2026-10-30','active',210000,4,'ZW-VAT','high'),
 ('P26-016','ISO 27001 readiness & penetration test','C020','CYB','HRE','fixed_fee','2026-03-02','2026-08-28','completed',72000,3,'ZW-VAT','medium'),
 ('P26-017','Tax health check & VAT recovery review','C019','TAX','HRE','fixed_fee','2026-03-09','2026-06-30','completed',42000,2,'ZW-VAT','medium'),
 ('P26-018','Enterprise risk management framework','C012','RAS','HRE','fixed_fee','2026-03-16','2026-09-30','active',68000,3,'ZW-VAT','medium'),
 ('P26-019','Financial due diligence - acquisition of distributor','C015','FAV','HRE','time_and_materials','2026-03-23','2026-06-19','completed',96000,3,'ZW-VAT','high'),
 ('P26-020','Donor-funds forensic audit','C017','FAI','HRE','time_and_materials','2026-04-06','2026-09-30','active',98000,3,'ZERO','medium'),
 ('P26-021','Procurement analytics dashboard (Power BI)','C011','DAA','HRE','fixed_fee','2026-04-13','2026-09-30','active',85000,3,'ZW-VAT','medium'),
 ('P26-022','Steel inventory shrinkage investigation','C009','FAI','BYO','time_and_materials','2026-04-20','2026-10-30','active',125000,3,'ZW-VAT','high'),
 ('P26-023','Transfer pricing documentation 2025','C001','TAX','HRE','fixed_fee','2026-05-04','2026-08-28','completed',56000,2,'ZW-VAT','medium'),
 ('P26-024','Revenue assurance review - mobile money','C007','RAS','HRE','time_and_materials','2026-05-11','2026-11-27','active',142000,3,'ZW-VAT','high'),
 ('P26-025','Cyber incident - ransomware recovery & forensics','C011','CYB','HRE','time_and_materials','2026-06-01','2026-09-30','active',112000,3,'ZW-VAT','critical'),
 ('P26-026','IFRS 18 transition advisory','C004','FAV','HRE','time_and_materials','2026-06-08','2026-12-18','active',84000,2,'ZW-VAT','medium'),
 ('P26-027','Sugar out-grower payments audit','C035','RAS','BYO','time_and_materials','2026-06-15','2026-10-30','active',76000,2,'ZW-VAT','medium'),
 ('P26-028','Election-support procurement review','C034','FAI','HRE','time_and_materials','2026-07-06','2026-12-18','active',115000,3,'ZERO','high'),
 ('P26-029','Property fund valuation (IFRS 13)','C036','FAV','HRE','fixed_fee','2026-07-13','2026-10-16','active',48000,2,'ZW-VAT','medium'),
 ('P26-030','Medical aid claims fraud analytics','C037','DAA','HRE','time_and_materials','2026-08-03','2026-12-18','active',92000,3,'ZW-VAT','medium'),
 ('P25-031','Provincial treasury forensic investigation','C021','FAI','JNB','time_and_materials','2025-11-03','2026-09-30','active',310000,4,'ZA-VAT','high'),
 ('P26-032','Credit-fraud analytics programme','C022','DAA','JNB','time_and_materials','2026-01-19','2026-10-30','active',190000,3,'ZA-VAT','high'),
 ('P26-033','Platinum royalty dispute - litigation support','C023','FAI','JNB','time_and_materials','2026-03-02','2026-09-30','active',145000,3,'ZA-VAT','high'),
 ('P26-034','Settlement-system cyber assessment','C039','CYB','JNB','fixed_fee','2026-05-04','2026-08-28','completed',65000,2,'ZA-VAT','medium'),
 ('P25-035','Mobile-money fraud detection models','C024','DAA','NBO','time_and_materials','2025-11-10','2026-10-30','active',230000,4,'KE-VAT','high'),
 ('P26-036','Grant compliance internal audit','C026','RAS','NBO','retainer','2026-01-01','2026-12-31','active',108000,2,'ZERO','medium'),
 ('P26-037','Export proceeds forensic review','C025','FAI','NBO','time_and_materials','2026-03-09','2026-07-31','completed',78000,2,'KE-VAT','medium'),
 ('P26-038','Reinsurance claims analytics','C038','DAA','NBO','time_and_materials','2026-06-01','2026-11-27','active',88000,2,'ZERO','medium'),
 ('P25-039','Commodity trade-finance fraud investigation','C027','FAI','LON','time_and_materials','2025-11-17','2026-08-28','completed',360000,3,'GB-VAT','critical'),
 ('P26-040','Buy-side due diligence - African fintech','C028','FAV','LON','time_and_materials','2026-02-02','2026-05-29','completed',210000,3,'GB-VAT','high'),
 ('P26-041','Portfolio company valuations Q2-Q4','C028','FAV','LON','milestone','2026-06-01','2026-12-18','active',150000,2,'GB-VAT','medium'),
 ('P26-042','Trade-based money laundering review','C029','FAI','DXB','time_and_materials','2026-01-12','2026-08-28','completed',185000,3,'AE-VAT','high'),
 ('P26-043','Bank cyber forensics & insider threat','C030','CYB','DXB','time_and_materials','2026-04-06','2026-12-18','active',160000,2,'AE-VAT','high'),
 ('P26-044','Hydro concession forensic audit (Zambia)','C031','FAI','HRE','time_and_materials','2026-02-23','2026-09-30','active',175000,3,'ZERO','high'),
 ('P26-045','Diamond sales-channel analytics (Botswana)','C032','DAA','HRE','time_and_materials','2026-03-16','2026-10-30','active',120000,3,'ZERO','medium'),
 ('P26-046','Port concession revenue audit (Mozambique)','C033','RAS','HRE','time_and_materials','2026-02-09','2026-07-31','completed',94000,2,'ZERO','medium'),
 ('P26-047','Tobacco auction floor tax review','C019','TAX','HRE','time_and_materials','2026-07-20','2026-11-27','active',46000,2,'ZW-VAT','low'),
 ('P26-048','Brewery excise & VAT dispute','C010','TAX','BYO','time_and_materials','2026-05-18','2026-10-30','active',38000,1,'ZW-VAT','medium');

INSERT INTO projects (project_code, name, description, client_id, service_line_id, project_manager_id, engagement_partner_id, office_id, status,
                      billing_type, is_internal, start_date, planned_end_date, currency_code, budget_hours, budget_fees, budget_expenses,
                      budget_cost, completion_pct, priority)
SELECT p.code, p.name, p.name || ' for ' || c.legal_name, c.client_id, sl.service_line_id,
       -- engagement manager: a manager/senior manager of the practice in the delivering office (or the branch head)
       COALESCE((SELECT e.employee_id FROM employees e JOIN job_grades g USING (job_grade_id)
                  WHERE e.department_id = sl.department_id AND e.office_id = o.office_id AND g.level IN (4,5)
                  ORDER BY (e.employee_id + length(p.code) + ascii(right(p.code,1))) % 5, e.employee_id LIMIT 1),
                o.manager_employee_id),
       CASE WHEN o.code = 'HRE' THEN (SELECT head_employee_id FROM departments WHERE department_id = sl.department_id) ELSE o.manager_employee_id END,
       o.office_id, 'active', p.btype::contract_type, FALSE, p.start, p.finish, 'USD',
       round(p.fees / 140, 0), p.fees, round(p.fees * 0.04, 0), round(p.fees * 0.45, 0), 0, p.priority::priority_level
  FROM seed_projects p JOIN clients c ON c.client_code = p.client JOIN service_lines sl ON sl.code = p.sl JOIN offices o ON o.code = p.office;

-- internal projects (non-billable)
INSERT INTO projects (project_code, name, client_id, service_line_id, project_manager_id, office_id, status, billing_type, is_internal, start_date, planned_end_date)
VALUES ('INT-26-BD','Business development & proposals 2026', NULL, NULL, (SELECT employee_id FROM employees WHERE employee_number='E020'),
        (SELECT office_id FROM offices WHERE code='HRE'), 'active', 'time_and_materials', TRUE, '2026-01-01', '2026-12-31'),
       ('INT-26-KM','Methodology, tools & knowledge management 2026', NULL, NULL, (SELECT employee_id FROM employees WHERE employee_number='E023'),
        (SELECT office_id FROM offices WHERE code='HRE'), 'active', 'time_and_materials', TRUE, '2026-01-01', '2026-12-31');

-- contracts for every client project
INSERT INTO contracts (contract_number, client_id, title, contract_type, status, start_date, end_date, currency_code, contract_value, rate_card_id,
                       payment_terms_days, billing_frequency, retainer_hours_per_month, retainer_fee_per_month, signed_date, client_signatory, firm_signatory_id)
SELECT 'ENG-' || p.project_code, p.client_id, p.name, p.billing_type, 'active', p.start_date, p.planned_end_date, 'USD', p.budget_fees,
       (SELECT rate_card_id FROM rate_cards WHERE is_default), c.payment_terms_days,
       CASE p.billing_type WHEN 'milestone' THEN 'milestone' WHEN 'fixed_fee' THEN 'milestone' ELSE 'monthly' END,
       CASE WHEN p.billing_type = 'retainer' THEN 80 END,
       CASE WHEN p.billing_type = 'retainer'
            THEN round(p.budget_fees / GREATEST((extract(year FROM age(p.planned_end_date, p.start_date)) * 12 + extract(month FROM age(p.planned_end_date, p.start_date)) + 1), 1), 0) END,
       p.start_date - 7, (SELECT first_name || ' ' || last_name FROM client_contacts WHERE client_id = p.client_id AND is_primary),
       p.engagement_partner_id
  FROM projects p JOIN clients c ON c.client_id = p.client_id WHERE NOT p.is_internal;
UPDATE projects p SET contract_id = ct.contract_id FROM contracts ct WHERE ct.contract_number = 'ENG-' || p.project_code;

-- milestones for fixed-fee / milestone engagements (evenly spread over the engagement)
INSERT INTO contract_milestones (contract_id, seq, name, due_date, amount)
SELECT ct.contract_id, m.seq, m.name,
       (ct.start_date + ((ct.end_date - ct.start_date) * m.pct_time)::INT)::DATE, round(ct.contract_value * m.pct_fee, 2)
  FROM contracts ct
 CROSS JOIN (VALUES (1, 'Mobilisation & inception report', 0.10, 0.25), (2, 'Fieldwork / build complete', 0.55, 0.40),
                    (3, 'Final report / go-live & sign-off', 1.00, 0.35)) AS m(seq, name, pct_time, pct_fee)
 WHERE ct.contract_type IN ('fixed_fee','milestone');

-- phases & tasks
INSERT INTO project_phases (project_id, seq, name, start_date, end_date, budget_hours, status)
SELECT p.project_id, ph.seq, ph.name, p.start_date + ((p.planned_end_date - p.start_date) * ph.s)::INT,
       p.start_date + ((p.planned_end_date - p.start_date) * ph.e)::INT, round(p.budget_hours * (ph.e - ph.s)), 'active'
  FROM projects p CROSS JOIN (VALUES (1,'Planning & scoping',0,0.15), (2,'Fieldwork & analysis',0.15,0.80), (3,'Reporting & close-out',0.80,1.0)) AS ph(seq, name, s, e)
 WHERE NOT p.is_internal;

INSERT INTO tasks (project_id, phase_id, name, status, priority, estimated_hours, start_date, due_date, is_billable)
SELECT ph.project_id, ph.phase_id, t.name, 'todo', 'medium', 40, ph.start_date, ph.end_date, TRUE
  FROM project_phases ph
  JOIN LATERAL (SELECT unnest(CASE ph.seq WHEN 1 THEN ARRAY['Kick-off meeting & data request','Risk assessment & work plan']
                                          WHEN 2 THEN ARRAY['Data extraction & analytics','Interviews & document review','Findings working papers']
                                          ELSE ARRAY['Draft report & QRM review','Client presentation & final report'] END) AS name) t ON TRUE;

-- 33.4 Teams: manager + partner + consultants of the practice (same office first, then any office)
INSERT INTO project_members (project_id, employee_id, project_role, start_date, end_date, allocation_pct)
SELECT p.project_id, p.project_manager_id, 'Engagement Manager', p.start_date, p.planned_end_date, 50 FROM projects p WHERE NOT p.is_internal
UNION
SELECT p.project_id, p.engagement_partner_id, 'Engagement Partner', p.start_date, p.planned_end_date, 10 FROM projects p
 WHERE NOT p.is_internal AND p.engagement_partner_id <> p.project_manager_id;

INSERT INTO project_members (project_id, employee_id, project_role, start_date, end_date, allocation_pct)
SELECT x.project_id, x.employee_id, CASE WHEN x.level = 3 THEN 'Senior Consultant' WHEN x.level = 2 THEN 'Consultant' ELSE 'Analyst' END,
       x.start_date, x.planned_end_date, 80
  FROM (SELECT p.project_id, p.start_date, p.planned_end_date, e.employee_id, g.level, sp.team,
               row_number() OVER (PARTITION BY p.project_id
                                  ORDER BY (e.office_id = p.office_id) DESC,
                                           (SELECT count(*) FROM project_members pm WHERE pm.employee_id = e.employee_id),
                                           (e.employee_id * 7 + p.project_id * 13) % 11) AS rn
          FROM projects p
          JOIN seed_projects sp ON sp.code = p.project_code
          JOIN service_lines sl ON sl.service_line_id = p.service_line_id
          JOIN employees e ON e.is_billable AND (e.department_id = sl.department_id OR e.office_id = p.office_id AND p.office_id <> (SELECT office_id FROM offices WHERE is_head_office))
          JOIN job_grades g ON g.job_grade_id = e.job_grade_id AND g.level BETWEEN 1 AND 3
         WHERE e.hire_date < p.planned_end_date
       ) x
 WHERE x.rn <= x.team
ON CONFLICT DO NOTHING;

-- make sure every fee earner has at least one engagement (bench staff join the largest active project of their practice)
INSERT INTO project_members (project_id, employee_id, project_role, start_date, end_date, allocation_pct)
SELECT DISTINCT ON (e.employee_id) p.project_id, e.employee_id, 'Consultant', GREATEST(p.start_date, e.hire_date), p.planned_end_date, 60
  FROM employees e JOIN job_grades g USING (job_grade_id)
  JOIN projects p ON NOT p.is_internal AND p.service_line_id = e.service_line_id
 WHERE e.is_billable AND NOT EXISTS (SELECT 1 FROM project_members pm WHERE pm.employee_id = e.employee_id)
 ORDER BY e.employee_id, (p.office_id = e.office_id) DESC, p.budget_fees DESC
ON CONFLICT DO NOTHING;

-- everyone may book internal time
INSERT INTO project_members (project_id, employee_id, project_role, start_date, end_date, allocation_pct)
SELECT p.project_id, e.employee_id, 'Contributor', '2026-01-01', '2026-12-31', 5
  FROM projects p CROSS JOIN employees e WHERE p.is_internal AND e.is_billable;

-- 33.5 CRM pipeline -----------------------------------------------------------------------
INSERT INTO leads (company_name, contact_name, email, industry_id, source, estimated_value, status, owner_id, notes, created_at)
SELECT v.co, v.contact, v.email, (SELECT industry_id FROM industries WHERE name = v.ind), v.src, v.val, v.status,
       (SELECT employee_id FROM employees WHERE employee_number = v.owner), v.notes, v.created::TIMESTAMPTZ
  FROM (VALUES
   ('Karoi Grain Marketing Co-op','Tafara Mashingaidze','tafara@karoigrain.example','Agriculture & Agro-processing','Referral',65000,'qualified','E020','Suspected side-selling; needs forensic review','2026-08-11'),
   ('Mazowe Gold Refiners','Janet Ruzvidzo','janet@mazowegold.example','Mining & Resources','Conference',140000,'contacted','E002','Met at ICAZ Winter School','2026-08-25'),
   ('Lusaka Water Utility','Chanda Mwape','cmwape@lwsc.example','Energy & Utilities','Tender',210000,'new','E013','Public tender - revenue assurance','2026-09-15'),
   ('Nairobi County Revenue Board','Peter Kiprotich','pkiprotich@ncrb.example','Government & Public Sector','Tender',180000,'qualified','E015','Analytics for revenue collection','2026-07-28'),
   ('Sandton Asset Managers','Nomsa Ndaba','nomsa@sam.example','Banking & Financial Services','Website',55000,'contacted','E014','Cyber due diligence','2026-09-02'),
   ('Mutare Timber Holdings','Kuda Chipunza','kuda@mth.example','Manufacturing','Referral',38000,'disqualified','E026','Budget not approved','2026-05-19'),
   ('Dubai Gold Souk Traders','Imran Sheikh','imran@dgst.example','Retail & FMCG','Existing relationship',120000,'qualified','E017','AML review for DMCC licence','2026-08-30'),
   ('Harare Polytechnic Pension Fund','Grace Mudenda','grace@hppf.example','Insurance & Pensions','Referral',46000,'new','E011','Tax & investment compliance review','2026-09-21')
  ) AS v(co, contact, email, ind, src, val, status, owner, notes, created);

INSERT INTO opportunities (opportunity_code, client_id, name, service_line_id, stage, probability_pct, estimated_value, expected_close_date,
                           actual_close_date, owner_id, competitor, lost_reason)
SELECT v.code, (SELECT client_id FROM clients WHERE client_code = v.client), v.name, (SELECT service_line_id FROM service_lines WHERE code = v.sl),
       v.stage::opportunity_stage, v.prob, v.val, v.close::DATE, v.actual::DATE, (SELECT employee_id FROM employees WHERE employee_number = v.owner), v.comp, v.lost
  FROM (VALUES
   ('OPP-26-001','C001','Group-wide fraud risk assessment 2027','FAI','proposal',50,280000,'2026-10-30',NULL,'E002','Big-4 firm',NULL),
   ('OPP-26-002','C002','Anti-fraud analytics phase 2','DAA','negotiation',75,210000,'2026-10-15',NULL,'E003',NULL,NULL),
   ('OPP-26-003','C005','Treasury single account forensic audit','FAI','qualification',25,450000,'2026-12-15',NULL,'E001','Auditor-General team',NULL),
   ('OPP-26-004','C007','SOC-as-a-service (managed detection)','CYB','proposal',40,180000,'2026-11-20',NULL,'E012',NULL,NULL),
   ('OPP-26-005','C012','Outsourced internal audit 2027-2029','RAS','negotiation',70,390000,'2026-10-31',NULL,'E010',NULL,NULL),
   ('OPP-26-006','C022','Model validation & credit-risk analytics','DAA','proposal',45,160000,'2026-11-06',NULL,'E014',NULL,NULL),
   ('OPP-26-007','C024','Agent-network fraud investigation','FAI','qualification',30,120000,'2026-12-04',NULL,'E015',NULL,NULL),
   ('OPP-26-008','C028','Fintech portfolio IFRS 18 readiness','FAV','proposal',55,95000,'2026-10-23',NULL,'E016',NULL,NULL),
   ('OPP-26-009','C030','Insider-threat programme design','CYB','won',100,140000,'2026-03-31','2026-03-28','E017',NULL,NULL),
   ('OPP-26-010','C015','Post-acquisition integration audit','FAV','won',100,96000,'2026-03-20','2026-03-18','E013',NULL,NULL),
   ('OPP-26-011','C009','Cost-reduction diagnostic','FAV','lost',0,70000,'2026-05-29','2026-05-27','E026','Local boutique firm','Price - competitor 30% cheaper'),
   ('OPP-26-012','C016','Fleet telematics analytics','DAA','lost',0,55000,'2026-06-30','2026-06-22','E026',NULL,'Client postponed the project to 2027'),
   ('OPP-26-013','C031','Hydro concession phase 2','FAI','negotiation',65,160000,'2026-10-20',NULL,'E013',NULL,NULL),
   ('OPP-26-014','C034','Results-management system audit','CYB','proposal',35,130000,'2026-11-27',NULL,'E012','International firm',NULL),
   ('OPP-26-015','C038','Claims-fraud analytics roll-out (6 countries)','DAA','qualification',20,300000,'2027-01-29',NULL,'E015',NULL,NULL)
  ) AS v(code, client, name, sl, stage, prob, val, close, actual, owner, comp, lost);

INSERT INTO crm_activities (activity_type, subject, details, activity_date, client_id, opportunity_id, employee_id, follow_up_date, is_completed)
SELECT (ARRAY['meeting','call','email','presentation'])[1 + (o.opportunity_id % 4)::INT],
       'Follow-up: ' || o.name, 'Discussed scope, timelines and fees.', '2026-09-24 10:00+02'::TIMESTAMPTZ - make_interval(days => (o.opportunity_id * 3 % 40)::INT),
       o.client_id, o.opportunity_id, o.owner_id, '2026-09-24'::DATE + (o.opportunity_id % 14)::INT, o.stage IN ('won','lost')
  FROM opportunities o;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  34_seed_time_leave.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   34. SEED - LEAVE, TIMESHEETS & TIME ENTRIES (5 Jan - 24 Sep 2026), PROJECT GOVERNANCE
   -------------------------------------------------------------------------------------
   * Every fee earner books 8 hours a day: client work on the engagements they are
     staffed on (according to their utilisation target), the rest internal time.
   * Public holidays and approved annual leave are booked as HOLIDAY / LEAVE.
   * Timesheets up to week 7 Sep are approved; week 14 Sep is waiting for approval;
     the current week (21 Sep) is still a draft.
   ===================================================================================== */

-- 34.1 Leave ------------------------------------------------------------------------------
INSERT INTO leave_requests (employee_id, leave_type_id, start_date, end_date, days_requested, reason, status, approver_id, created_at)
SELECT e.employee_id, (SELECT leave_type_id FROM leave_types WHERE code = 'AL'),
       w.ws, w.ws + 4, 5, 'Annual leave', 'submitted', COALESCE(e.manager_id, e.employee_id),
       w.ws - 21
  FROM employees e
 CROSS JOIN LATERAL (SELECT ('2026-01-12'::DATE + (7 * ((e.employee_id * 7) % 33))::INT) AS ws) w
 WHERE e.employee_number <> 'E001';
UPDATE leave_requests SET status = 'approved', decision_comment = 'Approved' WHERE status = 'submitted';

-- sick leave for some people, and a few requests still waiting for approval
INSERT INTO leave_requests (employee_id, leave_type_id, start_date, end_date, days_requested, reason, status, approver_id)
SELECT e.employee_id, (SELECT leave_type_id FROM leave_types WHERE code = 'SL'), d, d + 1, 2, 'Flu - doctor''s note attached', 'submitted', e.manager_id
  FROM employees e CROSS JOIN LATERAL (SELECT ('2026-02-03'::DATE + (7 * (e.employee_id % 28))::INT) AS d) x
 WHERE e.employee_id % 9 = 0 AND e.manager_id IS NOT NULL;
UPDATE leave_requests SET status = 'approved', decision_comment = 'Get well soon' WHERE status = 'submitted';

INSERT INTO leave_requests (employee_id, leave_type_id, start_date, end_date, days_requested, reason, status, approver_id)
SELECT e.employee_id, (SELECT leave_type_id FROM leave_types WHERE code = v.lt), v.s::DATE, v.e::DATE, v.d, v.r, 'submitted', e.manager_id
  FROM (VALUES ('E005','AL','2026-10-12','2026-10-16',5,'Family trip to Victoria Falls'),
               ('E031','AL','2026-10-26','2026-10-30',5,'Wedding'),
               ('E040','SP','2026-11-02','2026-11-06',5,'CFE exam preparation'),
               ('E052','AL','2026-12-21','2026-12-31',7,'Christmas holiday'),
               ('E063','CL','2026-09-28','2026-09-30',3,'Family bereavement')) AS v(num, lt, s, e, d, r)
  JOIN employees e ON e.employee_number = v.num;

-- 34.2 Timesheets -------------------------------------------------------------------------
UPDATE employees SET manager_id = (SELECT employee_id FROM employees WHERE employee_number = 'E004') WHERE employee_number = 'E005';

INSERT INTO timesheets (employee_id, week_start_date, status)
SELECT e.employee_id, w::DATE, 'draft'
  FROM employees e CROSS JOIN generate_series('2026-01-05'::DATE, '2026-09-21'::DATE, INTERVAL '7 days') w
 WHERE e.is_billable AND e.hire_date <= w::DATE + 4;

CREATE TEMP TABLE seed_days AS
SELECT t.timesheet_id, t.employee_id, t.week_start_date, d::DATE AS wd,
       (t.week_start_date - '2026-01-05'::DATE) / 7 + 1 AS wn, extract(isodow FROM d)::INT AS dow,
       o.country_code, e.target_utilization_pct AS tu, g.level,
       EXISTS (SELECT 1 FROM public_holidays h WHERE h.country_code = o.country_code AND h.holiday_date = d::DATE) AS is_holiday,
       EXISTS (SELECT 1 FROM leave_requests lr WHERE lr.employee_id = t.employee_id AND lr.status = 'approved'
                  AND d::DATE BETWEEN lr.start_date AND lr.end_date) AS is_leave
  FROM timesheets t
  JOIN employees e ON e.employee_id = t.employee_id
  JOIN job_grades g ON g.job_grade_id = e.job_grade_id
  JOIN offices o ON o.office_id = e.office_id
 CROSS JOIN LATERAL generate_series(t.week_start_date,
                                    t.week_start_date + CASE WHEN t.week_start_date = '2026-09-21' THEN 3 ELSE 4 END, INTERVAL '1 day') d
 WHERE d::DATE >= e.hire_date;

-- holidays & leave
INSERT INTO time_entries (timesheet_id, employee_id, project_id, activity_code, work_date, hours, is_billable, description)
SELECT timesheet_id, employee_id, NULL, CASE WHEN is_holiday THEN 'HOLIDAY' ELSE 'LEAVE' END, wd, 8, FALSE,
       CASE WHEN is_holiday THEN 'Public holiday' ELSE 'Annual / sick leave' END
  FROM seed_days WHERE is_holiday OR is_leave;

-- client work: split the day's billable hours across the engagements active that day (max 3)
CREATE TEMP TABLE seed_client_time AS
WITH active AS (
    SELECT d.*, pm.project_id,
           row_number() OVER (PARTITION BY d.employee_id, d.wd ORDER BY p.priority DESC, pm.allocation_pct DESC, p.project_id) AS rk
      FROM seed_days d
      JOIN project_members pm ON pm.employee_id = d.employee_id AND d.wd BETWEEN pm.start_date AND COALESCE(pm.end_date, 'infinity')
      JOIN projects p ON p.project_id = pm.project_id AND NOT p.is_internal AND d.wd BETWEEN p.start_date AND p.planned_end_date
     WHERE NOT d.is_holiday AND NOT d.is_leave
),
lim AS (SELECT *, count(*) OVER (PARTITION BY employee_id, wd) AS n FROM active WHERE rk <= 3)
SELECT timesheet_id, employee_id, project_id, wd, rk, n,
       GREATEST(0.5, round(LEAST(8, 8 * tu / 100 * (0.92 + ((employee_id * 31 + wn * 17 + dow * 7) % 19) / 100.0)) / n * 2) / 2) AS hours
  FROM lim;

INSERT INTO time_entries (timesheet_id, employee_id, project_id, task_id, activity_code, work_date, hours, is_billable, description)
SELECT c.timesheet_id, c.employee_id, c.project_id,
       (SELECT t.task_id FROM tasks t JOIN project_phases ph ON ph.phase_id = t.phase_id
         WHERE t.project_id = c.project_id AND c.wd BETWEEN ph.start_date AND ph.end_date
         ORDER BY (t.task_id + c.employee_id) % 3 LIMIT 1),
       'CLIENT', c.wd, c.hours, TRUE,
       (ARRAY['Data analysis & testing','Interviews and document review','Working papers & findings','Client meeting',
              'Report drafting','Evidence review & chain of custody','Analytics scripting & validation'])[1 + (c.employee_id + extract(doy FROM c.wd)::INT) % 7]
  FROM seed_client_time c;

-- internal time for the rest of each working day
INSERT INTO time_entries (timesheet_id, employee_id, project_id, activity_code, work_date, hours, is_billable, description)
SELECT d.timesheet_id, d.employee_id,
       CASE x.act WHEN 'BD' THEN (SELECT project_id FROM projects WHERE project_code = 'INT-26-BD')
                  WHEN 'KM' THEN (SELECT project_id FROM projects WHERE project_code = 'INT-26-KM') END,
       x.act, d.wd, 8 - COALESCE(s.billed, 0), FALSE,
       CASE x.act WHEN 'BD' THEN 'Proposals & client development' WHEN 'KM' THEN 'Methodology & tools'
                  WHEN 'TRAINING' THEN 'CPD / certification study' ELSE 'Admin, e-mail & internal meetings' END
  FROM seed_days d
  LEFT JOIN (SELECT employee_id, wd, SUM(hours) AS billed FROM seed_client_time GROUP BY 1, 2) s ON s.employee_id = d.employee_id AND s.wd = d.wd
 CROSS JOIN LATERAL (SELECT CASE WHEN d.level >= 5 THEN 'BD' ELSE (ARRAY['ADMIN','KM','TRAINING','ADMIN','BD'])[1 + (d.employee_id + d.dow) % 5] END AS act) x
 WHERE NOT d.is_holiday AND NOT d.is_leave AND 8 - COALESCE(s.billed, 0) > 0;

-- statuses
UPDATE timesheets t SET status = 'approved', submitted_at = (t.week_start_date + 4) + TIME '17:10',
       approved_by = COALESCE(e.manager_id, (SELECT employee_id FROM employees WHERE employee_number = 'E018')),
       approved_at = (t.week_start_date + 8) + TIME '09:30'
  FROM employees e WHERE e.employee_id = t.employee_id AND t.week_start_date <= '2026-09-07';
UPDATE timesheets t SET status = 'submitted', submitted_at = '2026-09-18 16:45+02'
 WHERE t.week_start_date = '2026-09-14' AND t.employee_id % 4 <> 0;
UPDATE timesheets t SET status = 'approved', submitted_at = '2026-09-18 16:45+02', approved_by = e.manager_id, approved_at = '2026-09-21 08:30+02'
  FROM employees e WHERE e.employee_id = t.employee_id AND t.week_start_date = '2026-09-14' AND t.employee_id % 4 = 0 AND e.manager_id IS NOT NULL;
UPDATE timesheets t SET status = 'rejected', approved_by = e.manager_id,
       rejection_reason = 'Please split the hours between the two engagements and add task descriptions.'
  FROM employees e WHERE e.employee_id = t.employee_id AND t.week_start_date = '2026-09-14' AND t.employee_id IN (37, 58);
UPDATE timesheets SET status = 'submitted', submitted_at = '2026-09-18 16:45+02'
 WHERE week_start_date = '2026-09-14' AND status = 'draft';

-- 34.3 Project progress, governance & forecast --------------------------------------------
UPDATE projects p SET status = 'completed', actual_end_date = sp.finish, completion_pct = 100
  FROM seed_projects sp WHERE sp.code = p.project_code AND sp.final_status = 'completed';
UPDATE projects p
   SET completion_pct = LEAST(95, round(100.0 * (CURRENT_DATE - p.start_date) / GREATEST(p.planned_end_date - p.start_date, 1)))
 WHERE p.status = 'active' AND NOT p.is_internal;
UPDATE project_phases ph SET status = CASE WHEN p.status = 'completed' OR ph.end_date < CURRENT_DATE THEN 'completed'::project_status
                                           WHEN ph.start_date > CURRENT_DATE THEN 'planned'::project_status ELSE 'active'::project_status END
  FROM projects p WHERE p.project_id = ph.project_id;
UPDATE tasks t SET status = CASE ph.status WHEN 'completed' THEN 'done'::task_status WHEN 'active' THEN 'in_progress'::task_status ELSE 'todo'::task_status END,
       assignee_id = (SELECT pm.employee_id FROM project_members pm WHERE pm.project_id = t.project_id ORDER BY (pm.employee_id + t.task_id) % 5 LIMIT 1),
       completed_at = CASE WHEN ph.status = 'completed' THEN ph.end_date + TIME '17:00' END
  FROM project_phases ph WHERE ph.phase_id = t.phase_id;

INSERT INTO project_status_reports (project_id, report_date, overall_rag, schedule_rag, budget_rag, scope_rag, summary, accomplishments, next_steps, author_id)
SELECT p.project_id, r.d,
       CASE WHEN p.priority = 'critical' AND r.d > '2026-08-01' THEN 'A' WHEN p.project_id % 7 = 0 THEN 'R' ELSE 'G' END,
       CASE WHEN p.project_id % 5 = 0 THEN 'A' ELSE 'G' END, CASE WHEN p.project_id % 7 = 0 THEN 'R' ELSE 'G' END, 'G',
       'Engagement progressing; key findings shared with the client steering committee.',
       'Data analytics completed for the period; interviews held with management.',
       'Finalise findings and prepare draft report for QRM review.', p.project_manager_id
  FROM projects p CROSS JOIN (VALUES ('2026-07-31'::DATE), ('2026-08-28'::DATE), ('2026-09-18'::DATE)) AS r(d)
 WHERE p.status = 'active' AND NOT p.is_internal AND p.start_date < r.d;

INSERT INTO project_risks (project_id, title, description, probability, impact, mitigation, owner_id, status, raised_date)
SELECT p.project_id, v.t, v.d, v.p, v.i, v.m, p.project_manager_id, 'open', p.start_date + 20
  FROM projects p
 CROSS JOIN (VALUES ('Delayed access to client data','ERP extracts not yet provided by client IT',3,4,'Escalate via steering committee; use sample data'),
                    ('Key witness unavailable','Former employee has left the country',2,4,'Arrange remote interview through counsel')) AS v(t, d, p, i, m)
 WHERE p.status = 'active' AND NOT p.is_internal AND (p.project_id + length(v.t)) % 3 = 0;

INSERT INTO project_issues (project_id, title, description, priority, status, raised_by, assigned_to, raised_date)
SELECT p.project_id, 'Scope change requested by client', 'Client asked to extend the review period by 12 months.', 'high', 'open',
       p.project_manager_id, p.engagement_partner_id, '2026-09-10'
  FROM projects p WHERE p.status = 'active' AND NOT p.is_internal AND p.project_id % 6 = 1;

INSERT INTO deliverables (project_id, name, owner_id, due_date, delivered_date, status)
SELECT p.project_id, d.name, p.project_manager_id, p.start_date + ((p.planned_end_date - p.start_date) * d.f)::INT,
       CASE WHEN p.start_date + ((p.planned_end_date - p.start_date) * d.f)::INT < CURRENT_DATE THEN p.start_date + ((p.planned_end_date - p.start_date) * d.f)::INT END,
       CASE WHEN p.start_date + ((p.planned_end_date - p.start_date) * d.f)::INT < CURRENT_DATE THEN 'accepted' ELSE 'pending' END
  FROM projects p CROSS JOIN (VALUES ('Inception report', 0.1), ('Interim findings', 0.6), ('Final report', 1.0)) AS d(name, f)
 WHERE NOT p.is_internal;

INSERT INTO resource_allocations (employee_id, project_id, week_start_date, planned_hours, is_tentative)
SELECT pm.employee_id, pm.project_id, w::DATE, CASE WHEN pm.project_role LIKE 'Engagement%' THEN 8 ELSE 24 END, w::DATE > '2026-10-12'
  FROM project_members pm JOIN projects p ON p.project_id = pm.project_id AND p.status = 'active' AND NOT p.is_internal
 CROSS JOIN generate_series('2026-09-28'::DATE, '2026-10-26'::DATE, INTERVAL '7 days') w
 WHERE w::DATE <= p.planned_end_date
ON CONFLICT DO NOTHING;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  35_seed_operations.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   35. SEED - 21 MONTHS OF OPERATIONS (January 2025 - 24 September 2026)
   -------------------------------------------------------------------------------------
   Everything is posted through the ERP's own business functions, so the ledger is
   balanced and every figure ties back to a source document:
     billing & receipts, payroll (ZW + 4 branches), statutory returns (ZIMRA/NSSA/ZIMDEF,
     SARS, KRA, HMRC, FTA), supplier bills & payments (WHT, IMTT), capex, depreciation,
     IFRS 16 leases, loan instalments, rental income, interest, QPDs, income-tax accruals,
     IFRS 9 ECL, revaluations (IAS 16/40), dividends, year-end accruals.
   Jan-Oct 2025 revenue comes from the legacy billing system (summary journals); detailed
   invoicing starts in November 2025 and time-based billing in January 2026.
   Months up to 31 August 2026 are closed; September 2026 is the open month.
   ===================================================================================== */

-- 35.1 Expense claim categories -----------------------------------------------------------
INSERT INTO expense_categories (code, name, gl_account_id, is_billable_default, requires_receipt, max_amount_per_item)
SELECT v.code, v.name, fn_account_id(v.gl), v.bill, TRUE, v.max
  FROM (VALUES ('TRAVEL','Air & road travel','5300',TRUE,2500), ('ACCOM','Accommodation','5310',TRUE,400),
               ('MEALS','Meals & subsistence','5320',TRUE,150), ('MILEAGE','Private vehicle mileage','6800',FALSE,600),
               ('TRAIN','Training & exam fees','6300',FALSE,1500), ('CLIENTENT','Client entertainment','6400',FALSE,300),
               ('DATA','Mobile data & airtime','6500',FALSE,100)) AS v(code, name, gl, bill, max);

-- additional suppliers used below
INSERT INTO vendors (vendor_code, name, vendor_type, tax_number, is_resident, tax_clearance_expiry, email, country_code, currency_code, payment_terms_days, default_expense_account_id)
VALUES ('V045','Non-executive directors (board fees)','professional','BOARD',TRUE,'2026-12-31','board@maxhub.co.zw','ZW','USD',7,fn_account_id('6710')),
       ('V046','Chiedza Children''s Home Trust (CSR)','government','CSR',TRUE,NULL,'info@chiedzahome.example','ZW','USD',7,fn_account_id('6950'));

-- 35.2 Seed helper functions (temporary - they disappear after this session) ------------
CREATE FUNCTION pg_temp.emp(p TEXT) RETURNS BIGINT LANGUAGE sql AS $$ SELECT employee_id FROM erp.employees WHERE employee_number = p $$;
CREATE FUNCTION pg_temp.bank(p TEXT) RETURNS BIGINT LANGUAGE sql AS $$
    SELECT b.bank_account_id FROM erp.bank_accounts b JOIN erp.chart_of_accounts a ON a.account_id = b.gl_account_id WHERE a.account_code = p $$;
CREATE FUNCTION pg_temp.bal(p TEXT) RETURNS NUMERIC LANGUAGE sql AS $$ SELECT erp.fn_account_balance(p, '2099-12-31') $$;
CREATE FUNCTION pg_temp.eom(d DATE) RETURNS DATE LANGUAGE sql AS $$ SELECT (date_trunc('month', d) + INTERVAL '1 month - 1 day')::DATE $$;

-- create + approve a supplier bill (amount in the supplier's currency)
CREATE FUNCTION pg_temp.bill(p_vendor TEXT, p_no TEXT, p_date DATE, p_net NUMERIC, p_vat BOOLEAN, p_acc TEXT, p_office TEXT,
                             p_dept TEXT, p_project BIGINT, p_desc TEXT) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v erp.vendors%ROWTYPE; v_id BIGINT;
BEGIN
    SELECT * INTO v FROM erp.vendors WHERE vendor_code = p_vendor;
    INSERT INTO erp.vendor_bills (vendor_id, project_id, bill_number, bill_date, due_date, currency_code, subtotal, tax_amount,
                                  expense_account_id, office_id, department_id, description)
    VALUES (v.vendor_id, p_project, p_no, p_date, p_date + v.payment_terms_days, v.currency_code, round(p_net, 2),
            CASE WHEN p_vat THEN round(p_net * 0.155, 2) ELSE 0 END,
            CASE WHEN p_acc IS NOT NULL THEN erp.fn_account_id(p_acc) END,
            (SELECT office_id FROM erp.offices WHERE code = p_office), (SELECT department_id FROM erp.departments WHERE code = p_dept), p_desc)
    RETURNING vendor_bill_id INTO v_id;
    PERFORM erp.fn_approve_vendor_bill(v_id, pg_temp.emp('E025'));
    RETURN v_id;
END $$;

-- top a bank account up to a target (USD value) from the client-receipts nostro
CREATE FUNCTION pg_temp.top_up(p_code TEXT, p_target NUMERIC, p_date DATE) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_need NUMERIC := round(p_target - pg_temp.bal(p_code), -3); v_src TEXT;
BEGIN
    IF v_need > 0 THEN
        -- fund from client receipts; call the money-market deposit when the nostro is short
        v_src := CASE WHEN pg_temp.bal('1013') >= v_need + 250000 THEN '1013' ELSE '1017' END;
        PERFORM erp.fn_bank_transfer(pg_temp.bank(v_src), pg_temp.bank(p_code), v_need, p_date,
                                     'Funding transfer to ' || (SELECT name FROM erp.bank_accounts WHERE bank_account_id = pg_temp.bank(p_code)));
    END IF;
END $$;

-- issue an invoice and plan when the client will pay it (by payment behaviour)
CREATE TEMP TABLE seed_receipts (invoice_id BIGINT PRIMARY KEY, pay_date DATE, pct NUMERIC);
CREATE FUNCTION pg_temp.issue(p_invoice BIGINT) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE i erp.invoices%ROWTYPE; v_beh TEXT; v_pay DATE; v_pct NUMERIC := 1;
BEGIN
    PERFORM erp.fn_issue_invoice(p_invoice, (SELECT user_id FROM erp.app_users WHERE username = 'chiedza.mushonga'));
    SELECT * INTO i FROM erp.invoices WHERE invoice_id = p_invoice;
    UPDATE erp.invoices SET issued_at = invoice_date + TIME '16:00' WHERE invoice_id = p_invoice;
    SELECT split_part(notes, ': ', 2) INTO v_beh FROM erp.clients WHERE client_id = i.client_id;
    v_pay := CASE v_beh WHEN 'good' THEN i.due_date - 3 + (i.invoice_id % 9)::INT
                        WHEN 'slow' THEN i.due_date + 12 + (i.invoice_id % 30)::INT
                        ELSE i.due_date + 40 + (i.invoice_id % 70)::INT END;
    IF v_beh = 'bad' AND i.invoice_id % 10 < 3 THEN RETURN; END IF;          -- never paid (ECL / collections)
    IF v_beh = 'slow' AND i.invoice_id % 7 = 0 THEN v_pct := 0.5; END IF;     -- part payment
    INSERT INTO seed_receipts VALUES (p_invoice, GREATEST(v_pay, i.invoice_date + 5), v_pct);
END $$;

-- 35.3 Recurring supplier bills -------------------------------------------------------------
-- freq: M = monthly, Q = Jan/Apr/Jul/Oct, B = every 2nd month, A<mm> = annually in month mm
CREATE TEMP TABLE seed_recurring (vendor TEXT, office TEXT, dept TEXT, amount NUMERIC, vat BOOLEAN, acc TEXT, freq TEXT, descr TEXT, project TEXT);
INSERT INTO seed_recurring VALUES
 ('V001','HRE','FAC',6800,TRUE,NULL,'M','Electricity - Maxhub House',NULL),
 ('V001','BYO','FAC',1450,TRUE,NULL,'M','Electricity - Maxhub Centre',NULL),
 ('V002','HRE','FAC',4200,FALSE,NULL,'M','Rates, refuse & water - Maxhub House',NULL),
 ('V003','BYO','FAC',1100,FALSE,NULL,'M','Rates & water - Maxhub Centre',NULL),
 ('V004','HRE','ICT',7600,TRUE,NULL,'M','Fibre internet, MPLS to Bulawayo & branch VPN',NULL),
 ('V005','HRE','ICT',4700,TRUE,NULL,'M','Corporate mobile lines & data bundles',NULL),
 ('V006','HRE','ICT',9800,FALSE,NULL,'M','Microsoft 365 E5 licences (mailboxes @maxhub.co.zw)',NULL),
 ('V007','HRE','DAA',15500,FALSE,NULL,'M','AWS cloud - analytics platform & secure evidence storage',NULL),
 ('V008','HRE','FAI',26000,FALSE,NULL,'A01','Relativity annual support & maintenance',NULL),
 ('V009','HRE','FAC',5600,TRUE,NULL,'M','Guarding & armed response - Maxhub House',NULL),
 ('V010','HRE','FAC',2300,FALSE,NULL,'M','Office cleaning services',NULL),
 ('V011','HRE','FIN',154800,TRUE,'1300','A01','Annual insurance premiums (property, motor, PI, cyber, EEI)',NULL),
 ('V012','HRE','FIN',30000,TRUE,'2500','A02','External audit FY - final fee (accrued at year end)',NULL),
 ('V012','HRE','FIN',16000,TRUE,NULL,'A09','External audit - interim review',NULL),
 ('V013','HRE','LEG',3400,TRUE,NULL,'Q','Legal retainer - contracts & employment matters',NULL),
 ('V014','HRE','MBD',5600,TRUE,NULL,'M','Brand, digital marketing & events',NULL),
 ('V015','HRE','FAI',9200,TRUE,NULL,'M','Air travel & car hire for engagements',NULL),
 ('V016','HRE','FAI',12500,FALSE,NULL,'B','Subcontract forensic accountants - public finance review','P25-005'),
 ('V017','HRE','DAA',18000,FALSE,NULL,'Q','Subcontract data engineers (South Africa)','P25-004'),
 ('V018','HRE','FAC',5300,TRUE,NULL,'M','Fleet fuel',NULL),
 ('V019','HRE','FAC',1900,TRUE,NULL,'M','Vehicle servicing & repairs',NULL),
 ('V020','HRE','FAC',2100,TRUE,NULL,'M','Stationery, printing & office consumables',NULL),
 ('V020','HRE','FAC',180,TRUE,'6100','M','Low-value equipment rental (IFRS 16 exemption)',NULL),
 ('V021','HRE','HRM',14500,FALSE,NULL,'A01','ICAZ / professional body subscriptions',NULL),
 ('V022','HRE','FAI',9800,FALSE,NULL,'A02','ACFE memberships & CFE exam fees',NULL),
 ('V043','HRE','FAC',1560,TRUE,NULL,'A02','Generator 500-hour services',NULL),
 ('V043','HRE','FAC',1560,TRUE,NULL,'A06','Generator 500-hour services',NULL),
 ('V043','HRE','FAC',1560,TRUE,NULL,'A10','Generator 500-hour services',NULL),
 ('V045','HRE','EXE',18000,FALSE,NULL,'Q','Non-executive directors'' fees',NULL),
 ('V046','HRE','EXE',5000,FALSE,NULL,'A11','CSR donation - Chiedza Children''s Home',NULL),
 ('V032','JNB','FAC',68000,FALSE,NULL,'M','Sandton office services, utilities & parking (ZAR)',NULL),
 ('V033','NBO','FAC',520000,FALSE,NULL,'M','Westlands service charge & utilities (KES)',NULL),
 ('V034','LON','FAC',6800,FALSE,NULL,'M','Service charge, business rates & utilities (GBP)',NULL),
 ('V035','DXB','FAC',21000,FALSE,NULL,'M','DIFC service charge & utilities (AED)',NULL);

-- 35.4 The month-by-month run -----------------------------------------------------------
DO $$
DECLARE
    c_cutoff CONSTANT DATE := '2026-09-24';             -- nothing is dated after this
    c_closed CONSTANT DATE := '2026-08-31';             -- last month-end that has been closed
    m DATE; d0 DATE; d1 DATE; prev0 DATE; prev1 DATE; y INT; mo INT;
    r RECORD; v_id BIGINT; v_run BIGINT; v_amt NUMERIC; v_lines JSONB; v_season NUMERIC; v_total NUMERIC; v_je BIGINT;
    v_cfo BIGINT := pg_temp.emp('E006'); v_hr BIGINT := pg_temp.emp('E007'); v_tax BIGINT := pg_temp.emp('E009');
    v_fin_user BIGINT := (SELECT user_id FROM app_users WHERE username = 'chiedza.mushonga');
    v_legacy_prev NUMERIC := 0; v_bill_no INT := 0; v_rep BIGINT; k INT;
BEGIN
    PERFORM set_config('erp.current_user_id', v_fin_user::TEXT, TRUE);

    -- FY2024 year-end items settled in January 2025 (statutory returns)
    INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, credits_amount, status, prepared_by)
    VALUES ('VAT-2024-12','VAT',(SELECT office_id FROM offices WHERE code='HRE'),'2024-12-01','2024-12-31','2025-01-25',196500,41200,'draft',v_tax),
           ('P2-2024-12','PAYE',(SELECT office_id FROM offices WHERE code='HRE'),'2024-12-01','2024-12-31','2025-01-10',91050,0,'draft',v_tax),
           ('P4-2024-12','NSSA',(SELECT office_id FROM offices WHERE code='HRE'),'2024-12-01','2024-12-31','2025-01-10',14800,0,'draft',v_tax),
           ('ZIMDEF-2024-12','ZIMDEF',(SELECT office_id FROM offices WHERE code='HRE'),'2024-12-01','2024-12-31','2025-01-10',3700,0,'draft',v_tax),
           ('ZA_PAYE-2024-12','ZA_PAYE',(SELECT office_id FROM offices WHERE code='JNB'),'2024-12-01','2024-12-31','2025-01-07',20000,0,'draft',v_tax),
           ('KE_PAYE-2024-12','KE_PAYE',(SELECT office_id FROM offices WHERE code='NBO'),'2024-12-01','2024-12-31','2025-01-09',11000,0,'draft',v_tax),
           ('GB_PAYE-2024-12','GB_PAYE',(SELECT office_id FROM offices WHERE code='LON'),'2024-12-01','2024-12-31','2025-01-22',30000,0,'draft',v_tax),
           ('ITF12C-2024','CIT_FINAL',(SELECT office_id FROM offices WHERE code='HRE'),'2024-01-01','2024-12-31','2025-04-30',342000,0,'draft',v_tax);
    INSERT INTO tax_return_lines VALUES ((SELECT tax_return_id FROM tax_returns WHERE return_number = 'P2-2024-12'), 1, 'P2-C', 'AIDS levy (3% of PAYE)', 2650);
    PERFORM fn_create_qpds(2025, 1250000, v_tax);

    FOR m IN SELECT g::DATE FROM generate_series('2025-01-01'::DATE, '2026-09-01'::DATE, INTERVAL '1 month') g LOOP
        d0 := m; d1 := pg_temp.eom(m); prev0 := (m - INTERVAL '1 month')::DATE; prev1 := m - 1;
        y := extract(year FROM m); mo := extract(month FROM m);

        ------------------------------------------------ 1st of the month: treasury
        IF pg_temp.bal('1013') < 800000 THEN     -- keep the receipts nostro liquid
            PERFORM fn_bank_transfer(pg_temp.bank('1017'), pg_temp.bank('1013'), round(1200000 - pg_temp.bal('1013'), -3), d0, 'Call from money market to nostro');
        END IF;
        PERFORM pg_temp.top_up('1010', 1600000, d0);
        PERFORM pg_temp.top_up('1018', 90000, d0);
        PERFORM pg_temp.top_up('1012', 260000, d0);
        PERFORM pg_temp.top_up('1014', 190000, d0);
        PERFORM pg_temp.top_up('1015', 380000, d0);
        PERFORM pg_temp.top_up('1016', 190000, d0);
        PERFORM fn_post_loan_month(d0);
        -- rent from tenants of Maxhub House floors 5-6 (investment property), VAT 15.5%
        SELECT SUM(payment_amount * CASE WHEN y >= 2026 THEN 1.05 ELSE 1 END) INTO v_amt FROM leases WHERE role = 'lessor';
        PERFORM fn_post_journal(d0, 'Rent received - Maxhub House tenants ' || to_char(d0, 'Mon YYYY'), 'rental_income', NULL, jsonb_build_array(
            jsonb_build_object('acc','1013','dr', round(v_amt * 1.155, 2)),
            jsonb_build_object('acc','4500','cr', v_amt, 'office', (SELECT office_id FROM offices WHERE code='HRE'), 'desc','Rental income'),
            jsonb_build_object('acc','2200','cr', round(v_amt * 0.155, 2), 'desc','Output VAT on commercial rent')));
        -- new leases commencing this month (IFRS 16 recognition)
        FOR r IN SELECT lease_id FROM leases WHERE role = 'lessee' AND exemption IS NULL AND status = 'draft' AND commencement_date BETWEEN d0 AND d1 LOOP
            PERFORM fn_recognise_lease(r.lease_id);
        END LOOP;
        -- short-term lease rent (exempt, expensed)
        IF d0 BETWEEN '2026-05-01' AND '2026-09-01' THEN
            PERFORM fn_post_journal(d0, 'Short-term site office rent - Victoria Falls', 'vendor_payment', NULL, jsonb_build_array(
                jsonb_build_object('acc','6100','dr', 1200, 'office', (SELECT office_id FROM offices WHERE code='HRE')),
                jsonb_build_object('acc','6610','dr', 24), jsonb_build_object('acc','1010','cr', 1224)));
        END IF;

        ------------------------------------------------ 5th: supplier bills
        FOR r IN SELECT * FROM seed_recurring
                  WHERE freq = 'M' OR (freq = 'Q' AND mo IN (1,4,7,10)) OR (freq = 'B' AND mo % 2 = 0)
                     OR (freq LIKE 'A%' AND substr(freq, 2)::INT = mo) LOOP
            CONTINUE WHEN d0 + 4 > c_cutoff;
            v_bill_no := v_bill_no + 1;
            PERFORM pg_temp.bill(r.vendor, upper(r.vendor) || '-' || to_char(d0, 'YYMM') || '-' || v_bill_no, d0 + 4,
                                 r.amount * CASE WHEN y >= 2026 THEN 1.06 ELSE 1 END, r.vat, r.acc, r.office, r.dept,
                                 (SELECT project_id FROM projects WHERE project_code = r.project), r.descr || ' - ' || to_char(d0, 'Mon YYYY'));
        END LOOP;

        ------------------------------------------------ capital expenditure (IAS 16 / IAS 38)
        IF m = '2025-03-01' THEN
            v_id := pg_temp.bill('V023', 'AXIS-INV-25-0311', '2025-03-11', 30000, TRUE, '1530', 'HRE', 'ICT', NULL, 'Dell Latitude 7450 laptops x20 (new joiners)');
            INSERT INTO fixed_assets (asset_tag, name, asset_category_id, status, office_id, department_id, custodian_employee_id, vendor_id, vendor_bill_id,
                                      serial_number, make_model, acquisition_date, available_for_use_date, cost, useful_life_months, insured_value, insurance_policy_id)
            SELECT 'MXH-IT-' || lpad(e.employee_id::TEXT, 5, '0'), 'Laptop - Dell Latitude 7450', (SELECT asset_category_id FROM asset_categories WHERE code='IT'),
                   'in_use', e.office_id, e.department_id, e.employee_id, (SELECT vendor_id FROM vendors WHERE vendor_code='V023'), v_id,
                   'DL' || upper(substr(md5('25' || e.employee_id), 1, 7)), 'Dell Latitude 7450', '2025-03-11', '2025-03-14', 1500, 36, 1500,
                   (SELECT policy_id FROM insurance_policies WHERE policy_number = 'HGI-EEI-2026-118')
              FROM employees e
             WHERE NOT EXISTS (SELECT 1 FROM fixed_assets fa WHERE fa.custodian_employee_id = e.employee_id)
               AND e.hire_date <= '2025-03-31' AND e.job_title NOT IN ('Driver','Office Assistant')
             ORDER BY e.employee_id LIMIT 20;
        ELSIF m = '2025-07-01' THEN
            v_id := pg_temp.bill('V023', 'AXIS-INV-25-0707', '2025-07-07', 150000, TRUE, '1800', 'HRE', 'ICT', NULL, 'Maxhub ERP implementation - capitalised development (IAS 38)');
            INSERT INTO fixed_assets (asset_tag, name, asset_category_id, status, office_id, department_id, custodian_employee_id, vendor_id, vendor_bill_id,
                                      make_model, acquisition_date, available_for_use_date, cost, useful_life_months)
            VALUES ('MXH-SW-003', 'Maxhub ERP platform (PostgreSQL + dashboard) - development costs', (SELECT asset_category_id FROM asset_categories WHERE code='SW'),
                    'in_use', (SELECT office_id FROM offices WHERE code='HRE'), (SELECT department_id FROM departments WHERE code='ICT'), pg_temp.emp('E008'),
                    (SELECT vendor_id FROM vendors WHERE vendor_code='V023'), v_id, 'In-house / Axis', '2025-07-07', '2025-08-01', 150000, 60);
        ELSIF m = '2025-09-01' THEN
            v_id := pg_temp.bill('V025', 'DOF-25-0915', '2025-09-15', 22000, TRUE, '1540', 'BYO', 'FAC', NULL, 'Bulawayo office refurbishment - furniture');
            INSERT INTO fixed_assets (asset_tag, name, asset_category_id, status, office_id, department_id, vendor_id, vendor_bill_id, acquisition_date, available_for_use_date, cost)
            VALUES ('MXH-FF-007','Bulawayo office refurbishment - furniture', (SELECT asset_category_id FROM asset_categories WHERE code='FF'), 'in_use',
                    (SELECT office_id FROM offices WHERE code='BYO'), (SELECT department_id FROM departments WHERE code='FAC'), (SELECT vendor_id FROM vendors WHERE vendor_code='V025'),
                    v_id, '2025-09-15', '2025-09-22', 22000);
        ELSIF m = '2026-02-01' THEN
            v_id := pg_temp.bill('V023', 'AXIS-INV-26-0216', '2026-02-16', 40300, TRUE, '1530', 'HRE', 'ICT', NULL, 'Dell laptops x26 - 2025/26 joiners & refresh');
            INSERT INTO fixed_assets (asset_tag, name, asset_category_id, status, office_id, department_id, custodian_employee_id, vendor_id, vendor_bill_id,
                                      serial_number, make_model, acquisition_date, available_for_use_date, cost, useful_life_months, insured_value, insurance_policy_id)
            SELECT 'MXH-IT-' || lpad(e.employee_id::TEXT, 5, '0'), 'Laptop - Dell Latitude 7450 (2026)', (SELECT asset_category_id FROM asset_categories WHERE code='IT'),
                   'in_use', e.office_id, e.department_id, e.employee_id, (SELECT vendor_id FROM vendors WHERE vendor_code='V023'), v_id,
                   'DL' || upper(substr(md5('26' || e.employee_id), 1, 7)), 'Dell Latitude 7450', '2026-02-16', '2026-02-18', 1550, 36, 1550,
                   (SELECT policy_id FROM insurance_policies WHERE policy_number = 'HGI-EEI-2026-118')
              FROM employees e
             WHERE NOT EXISTS (SELECT 1 FROM fixed_assets fa WHERE fa.custodian_employee_id = e.employee_id AND fa.asset_tag LIKE 'MXH-IT-0%')
               AND e.job_title NOT IN ('Driver','Office Assistant')
             ORDER BY e.employee_id LIMIT 26;
        ELSIF m = '2026-03-01' THEN
            v_id := pg_temp.bill('V025', 'DOF-26-0309', '2026-03-09', 18000, TRUE, '1540', 'NBO', 'FAC', NULL, 'Nairobi office expansion - furniture');
            INSERT INTO fixed_assets (asset_tag, name, asset_category_id, status, office_id, department_id, vendor_id, vendor_bill_id, acquisition_date, available_for_use_date, cost)
            VALUES ('MXH-FF-008','Nairobi office expansion - furniture', (SELECT asset_category_id FROM asset_categories WHERE code='FF'), 'in_use',
                    (SELECT office_id FROM offices WHERE code='NBO'), (SELECT department_id FROM departments WHERE code='FAC'), (SELECT vendor_id FROM vendors WHERE vendor_code='V025'),
                    v_id, '2026-03-09', '2026-03-16', 18000);
        ELSIF m = '2026-04-01' THEN
            v_id := pg_temp.bill('V024', 'ZMD-26-0414', '2026-04-14', 116000, TRUE, '1520', 'HRE', 'FAC', NULL, 'Toyota Hilux 2.8GD-6 double cab x2');
            INSERT INTO fixed_assets (asset_tag, name, asset_category_id, status, office_id, department_id, custodian_employee_id, vendor_id, vendor_bill_id,
                                      serial_number, registration_number, make_model, acquisition_date, available_for_use_date, cost, residual_value, insured_value, insurance_policy_id)
            SELECT 'MXH-MV-0' || (12 + g.n), 'Toyota Hilux 2.8GD-6 double cab', (SELECT asset_category_id FROM asset_categories WHERE code='MV'), 'in_use',
                   (SELECT office_id FROM offices WHERE code='HRE'), (SELECT department_id FROM departments WHERE code = CASE g.n WHEN 1 THEN 'CYB' ELSE 'DAA' END),
                   pg_temp.emp(CASE g.n WHEN 1 THEN 'E012' ELSE 'E003' END), (SELECT vendor_id FROM vendors WHERE vendor_code='V024'), v_id,
                   'AHTJB3DD20K30001' || (2 + g.n), 'AGK ' || (4410 + g.n), 'Toyota Hilux 2.8GD-6 D/C', '2026-04-14', '2026-04-20', 58000, 5800, 58000,
                   (SELECT policy_id FROM insurance_policies WHERE policy_number = 'HGI-MOT-2026-115')
              FROM generate_series(1, 2) AS g(n);
        ELSIF m = '2026-05-01' THEN
            v_id := pg_temp.bill('V023', 'AXIS-INV-26-0518', '2026-05-18', 65000, TRUE, '1530', 'HRE', 'CYB', NULL, 'GPU forensic & AI processing server');
            INSERT INTO fixed_assets (asset_tag, name, asset_category_id, status, office_id, department_id, custodian_employee_id, vendor_id, vendor_bill_id,
                                      serial_number, make_model, acquisition_date, available_for_use_date, cost, useful_life_months, insured_value, insurance_policy_id)
            VALUES ('MXH-IT-SRV-003','GPU server - password recovery & AI analytics', (SELECT asset_category_id FROM asset_categories WHERE code='IT'), 'in_use',
                    (SELECT office_id FROM offices WHERE code='HRE'), (SELECT department_id FROM departments WHERE code='CYB'), pg_temp.emp('E012'),
                    (SELECT vendor_id FROM vendors WHERE vendor_code='V023'), v_id, 'SRV-GPU-0003', 'Supermicro 4x NVIDIA L40S', '2026-05-18', '2026-05-25', 65000, 48, 65000,
                    (SELECT policy_id FROM insurance_policies WHERE policy_number = 'HGI-EEI-2026-118'));
        ELSIF m = '2026-06-01' THEN
            v_id := pg_temp.bill('V026', 'MAG-26-0610', '2026-06-10', 40000, FALSE, '1800', 'HRE', 'CYB', NULL, 'Magnet AXIOM & GRAYKEY perpetual licences');
            INSERT INTO fixed_assets (asset_tag, name, asset_category_id, status, office_id, department_id, custodian_employee_id, vendor_id, vendor_bill_id,
                                      make_model, acquisition_date, available_for_use_date, cost, useful_life_months)
            VALUES ('MXH-SW-004','Magnet AXIOM digital forensics licences', (SELECT asset_category_id FROM asset_categories WHERE code='SW'), 'in_use',
                    (SELECT office_id FROM offices WHERE code='HRE'), (SELECT department_id FROM departments WHERE code='CYB'), pg_temp.emp('E012'),
                    (SELECT vendor_id FROM vendors WHERE vendor_code='V026'), v_id, 'Magnet AXIOM', '2026-06-10', '2026-06-10', 40000, 60);
        ELSIF m = '2026-09-01' THEN
            v_id := pg_temp.bill('V044', 'STA-26-0915', '2026-09-15', 48000, TRUE, '1550', 'BYO', 'FAC', NULL, '60kW solar & battery system - Maxhub Centre Bulawayo');
            INSERT INTO fixed_assets (asset_tag, name, asset_category_id, status, office_id, department_id, vendor_id, vendor_bill_id, make_model,
                                      acquisition_date, available_for_use_date, cost, insured_value, insurance_policy_id)
            VALUES ('MXH-OE-007','60kW solar & battery system - Maxhub Centre', (SELECT asset_category_id FROM asset_categories WHERE code='OE'), 'under_construction',
                    (SELECT office_id FROM offices WHERE code='BYO'), (SELECT department_id FROM departments WHERE code='FAC'), (SELECT vendor_id FROM vendors WHERE vendor_code='V044'),
                    v_id, 'Hybrid PV + Li-ion', '2026-09-15', '2026-09-15', 48000, 48000, (SELECT policy_id FROM insurance_policies WHERE policy_number = 'HGI-PROP-2026-114'));
        END IF;

        ------------------------------------------------ opening-balance clean-up (January / February 2025)
        IF m = '2025-01-01' THEN
            PERFORM fn_post_journal('2025-01-15', 'Settlement of legacy trade payables', 'legacy', NULL, jsonb_build_array(
                jsonb_build_object('acc','2100','dr', 418000), jsonb_build_object('acc','6610','dr', 8360), jsonb_build_object('acc','1010','cr', 426360)));
            PERFORM fn_post_journal('2025-01-20', 'Settlement of December 2024 accruals', 'legacy', NULL, jsonb_build_array(
                jsonb_build_object('acc','2500','dr', 152000), jsonb_build_object('acc','6610','dr', 3040), jsonb_build_object('acc','1010','cr', 155040)));
            PERFORM fn_post_journal('2025-01-07', 'December 2024 pension & medical aid remittances', 'payroll_payment', NULL, jsonb_build_array(
                jsonb_build_object('acc','2420','dr', 52000), jsonb_build_object('acc','2425','dr', 21500), jsonb_build_object('acc','1010','cr', 73500)));
        END IF;
        IF m <= '2025-03-01' THEN   -- client advances earned (IFRS 15 contract liabilities -> revenue)
            PERFORM fn_post_journal(d1, 'Contract liabilities recognised as revenue (performance obligations satisfied)', 'legacy', NULL, jsonb_build_array(
                jsonb_build_object('acc','2600','dr', round(158000 / 3.0, 2)),
                jsonb_build_object('acc','4010','cr', round(158000 / 3.0, 2), 'office', (SELECT office_id FROM offices WHERE code='HRE'))));
        END IF;
        IF y = 2025 THEN            -- prepaid insurance & licences at go-live expensed over 2025
            PERFORM fn_post_journal(d1, 'Prepayments released - legacy', 'accrual', NULL, jsonb_build_array(
                jsonb_build_object('acc','6140','dr', round(176000 / 12.0, 2)), jsonb_build_object('acc','1300','cr', round(176000 / 12.0, 2))));
        END IF;
        IF mo = 1 AND y = 2026 THEN NULL; END IF;
        IF y >= 2025 AND d1 <= c_closed THEN   -- insurance premium (paid each January) released monthly
            SELECT COALESCE(SUM(subtotal), 0) / 12 INTO v_amt FROM vendor_bills b JOIN vendors v USING (vendor_id)
             WHERE v.vendor_code = 'V011' AND extract(year FROM b.bill_date) = y;
            IF v_amt > 0 THEN
                PERFORM fn_post_journal(d1, 'Insurance premium released ' || to_char(d1, 'Mon YYYY'), 'accrual', NULL, jsonb_build_array(
                    jsonb_build_object('acc','6140','dr', round(v_amt, 2)), jsonb_build_object('acc','1300','cr', round(v_amt, 2))));
            END IF;
        END IF;

        ------------------------------------------------ 7th-10th: statutory payments for last month
        FOR r IN SELECT t.tax_return_id, t.tax_code, tt.authority_code, o.code AS office
                   FROM tax_returns t JOIN tax_types tt USING (tax_code) LEFT JOIN offices o ON o.office_id = t.office_id
                  WHERE t.status = 'draft' AND t.tax_code IN ('PAYE','NSSA','ZIMDEF','ZA_PAYE','KE_PAYE','GB_PAYE')
                    AND t.period_end < d0 LOOP
            CONTINUE WHEN d0 + 7 > c_cutoff;
            PERFORM fn_file_tax_return(r.tax_return_id, d0 + 5);
            PERFORM fn_pay_tax_return(r.tax_return_id,
                pg_temp.bank(CASE r.office WHEN 'JNB' THEN '1012' WHEN 'NBO' THEN '1014' WHEN 'LON' THEN '1015' ELSE '1010' END), d0 + 7);
        END LOOP;
        IF m >= '2025-02-01' AND d0 + 6 <= c_cutoff THEN
            SELECT COALESCE(SUM(jl.credit), 0) INTO v_amt FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id)
             WHERE je.source_type = 'payroll' AND je.entry_date BETWEEN prev0 AND prev1 AND jl.account_id = fn_account_id('2420');
            SELECT COALESCE(SUM(jl.credit), 0) INTO v_total FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id)
             WHERE je.source_type = 'payroll' AND je.entry_date BETWEEN prev0 AND prev1 AND jl.account_id = fn_account_id('2425');
            PERFORM fn_post_journal(d0 + 6, 'Pension fund & medical aid remittance ' || to_char(prev0, 'Mon YYYY'), 'payroll_payment', NULL, jsonb_build_array(
                jsonb_build_object('acc','2420','dr', v_amt, 'desc','Maxhub Staff Pension Fund / branch schemes'),
                jsonb_build_object('acc','2425','dr', v_total, 'desc','CIMAS / First Mutual Health'),
                jsonb_build_object('acc','1010','cr', v_amt + v_total)));
            -- withholding tax deducted from suppliers last month -> ZIMRA
            v_amt := -fn_account_movement('2430', prev0, prev1, ARRAY['tax_payment']);
            IF v_amt > 0 THEN
                INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, status, prepared_by)
                VALUES ('WHT-' || to_char(prev0, 'YYYY-MM'), 'WHT', (SELECT office_id FROM offices WHERE code='HRE'), prev0, prev1, d0 + 9, v_amt, 'draft', v_tax)
                RETURNING tax_return_id INTO v_id;
                PERFORM fn_file_tax_return(v_id, d0 + 6);
                PERFORM fn_pay_tax_return(v_id, pg_temp.bank('1010'), d0 + 8);
            END IF;
        END IF;

        ------------------------------------------------ 20th-24th: VAT returns for last month
        IF d0 + 19 <= c_cutoff THEN
            IF m > '2025-01-01' THEN v_id := fn_prepare_vat_return(prev0, v_tax);
            ELSE SELECT tax_return_id INTO v_id FROM tax_returns WHERE return_number = 'VAT-2024-12'; END IF;
            PERFORM fn_file_tax_return(v_id, d0 + 19);
            IF m < '2026-09-01' THEN                       -- August VAT7 is filed; payment is scheduled for the 25th
                PERFORM fn_pay_tax_return(v_id, pg_temp.bank('1010'), d0 + 23);
            END IF;
            -- branch VAT
            IF m > '2025-01-01' THEN
                v_id := fn_prepare_branch_vat_return('KE_VAT', prev0, prev1, v_tax);
                IF v_id IS NOT NULL THEN PERFORM fn_file_tax_return(v_id, d0 + 17); PERFORM fn_pay_tax_return(v_id, pg_temp.bank('1014'), d0 + 18); END IF;
                IF mo % 2 = 1 THEN
                    v_id := fn_prepare_branch_vat_return('ZA_VAT', (prev0 - INTERVAL '1 month')::DATE, prev1, v_tax);
                    IF v_id IS NOT NULL THEN PERFORM fn_file_tax_return(v_id, d0 + 20); PERFORM fn_pay_tax_return(v_id, pg_temp.bank('1012'), d0 + 22); END IF;
                END IF;
                IF mo IN (2,5,8,11) THEN
                    v_id := fn_prepare_branch_vat_return('GB_VAT', (prev0 - INTERVAL '2 months')::DATE, prev1, v_tax);
                    IF v_id IS NOT NULL THEN PERFORM fn_file_tax_return(v_id, d0 + 5); PERFORM fn_pay_tax_return(v_id, pg_temp.bank('1015'), d0 + 6); END IF;
                    v_id := fn_prepare_branch_vat_return('AE_VAT', (prev0 - INTERVAL '2 months')::DATE, prev1, v_tax);
                    IF v_id IS NOT NULL THEN PERFORM fn_file_tax_return(v_id, d0 + 20); PERFORM fn_pay_tax_return(v_id, pg_temp.bank('1016'), d0 + 22); END IF;
                END IF;
            END IF;
        END IF;

        ------------------------------------------------ income tax returns & payments (QPDs / final / branches)
        IF m = '2026-01-01' THEN
            PERFORM fn_create_qpds(2026, 1150000, v_tax);                 -- estimate based on FY2025 results
        ELSIF m = '2026-04-01' THEN                                        -- ITF12C: FY2025 balance of tax
            INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, status, prepared_by, notes)
            VALUES ('ITF12C-2025', 'CIT_FINAL', (SELECT office_id FROM offices WHERE code='HRE'), '2025-01-01', '2025-12-31', '2026-04-30',
                    GREATEST(-fn_account_balance('2260','2025-12-31'), 0), 'draft', v_tax, 'FY2025 self-assessment - balance after QPDs');
        ELSIF m = '2026-06-01' THEN                                        -- branch corporate taxes for FY2025
            FOR r IN SELECT o.code, o.office_id, tt.tax_code,
                            -COALESCE((SELECT SUM(jl.debit - jl.credit) FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id)
                                        WHERE jl.account_id = fn_account_id('2265') AND jl.office_id = o.office_id AND je.entry_date <= '2025-12-31'), 0) AS due
                       FROM offices o JOIN (VALUES ('JNB','ZA_CIT','1012'), ('NBO','KE_CIT','1014'), ('LON','GB_CT','1015'), ('DXB','AE_CT','1016')) AS b(code, tc, bank)
                         ON b.code = o.code JOIN tax_types tt ON tt.tax_code = b.tc LOOP
                CONTINUE WHEN r.due <= 0;
                INSERT INTO tax_returns (return_number, tax_code, office_id, period_start, period_end, due_date, gross_amount, status, prepared_by)
                VALUES (r.tax_code || '-2025', r.tax_code, r.office_id, '2025-01-01', '2025-12-31', '2026-06-30', r.due, 'draft', v_tax)
                RETURNING tax_return_id INTO v_id;
                PERFORM fn_file_tax_return(v_id, '2026-06-24');
                PERFORM fn_pay_tax_return(v_id, pg_temp.bank(CASE r.code WHEN 'JNB' THEN '1012' WHEN 'NBO' THEN '1014' WHEN 'LON' THEN '1015' ELSE '1016' END), '2026-06-26');
            END LOOP;
        END IF;
        FOR r IN SELECT tax_return_id, due_date FROM tax_returns
                  WHERE tax_code IN ('CIT_QPD','CIT_FINAL') AND status = 'draft' AND due_date BETWEEN d0 AND d1 AND due_date - 2 <= c_cutoff LOOP
            PERFORM fn_file_tax_return(r.tax_return_id, r.due_date - 3);
            PERFORM fn_pay_tax_return(r.tax_return_id, pg_temp.bank('1010'), r.due_date - 2);
        END LOOP;

        ------------------------------------------------ expense claims (2026: billable to T&M engagements)
        IF y = 2026 THEN
            FOR r IN SELECT DISTINCT ON (pm.employee_id) pm.employee_id, pm.project_id, e.manager_id
                       FROM project_members pm JOIN projects p ON p.project_id = pm.project_id AND p.billing_type = 'time_and_materials' AND NOT p.is_internal
                       JOIN employees e ON e.employee_id = pm.employee_id
                      WHERE d0 + 10 BETWEEN pm.start_date AND COALESCE(pm.end_date, 'infinity') AND e.manager_id IS NOT NULL
                        AND (pm.employee_id + mo) % 9 = 0
                      ORDER BY pm.employee_id, p.project_id LIMIT 14 LOOP
                CONTINUE WHEN d0 + 12 > c_cutoff;
                INSERT INTO expense_reports (employee_id, title, currency_code) VALUES (r.employee_id,
                    'Field work ' || to_char(d0, 'Mon YYYY') || ' - ' || (SELECT project_code FROM projects WHERE project_id = r.project_id), 'USD')
                RETURNING expense_report_id INTO v_rep;
                INSERT INTO expense_items (expense_report_id, expense_date, expense_category_id, project_id, description, merchant, amount, is_billable)
                SELECT v_rep, d0 + x.dd, (SELECT expense_category_id FROM expense_categories WHERE code = x.cat), r.project_id, x.descr, x.merchant,
                       x.amt + (r.employee_id % 7) * 11, TRUE
                  FROM (VALUES (6,'TRAVEL','Return trip to client site','Fastjet / Zambezi Travel',420),
                               (7,'ACCOM','Hotel - 2 nights','Rainbow Hotels',260), (7,'MEALS','Meals while on site','Various',55)) AS x(dd, cat, descr, merchant, amt);
                CALL sp_submit_expense_report(v_rep);
                IF d0 + 14 <= c_cutoff AND NOT (m = '2026-09-01' AND r.employee_id % 2 = 0) THEN
                    CALL sp_approve_expense_report(v_rep, r.manager_id, d0 + 14);
                    IF d0 + 24 <= c_cutoff THEN
                        SELECT total_amount INTO v_amt FROM expense_reports WHERE expense_report_id = v_rep;
                        PERFORM fn_post_journal(d0 + 24, 'Reimbursement ' || (SELECT report_number FROM expense_reports WHERE expense_report_id = v_rep),
                            'expense', v_rep, jsonb_build_array(jsonb_build_object('acc','2300','dr', v_amt, 'employee', r.employee_id),
                                                               jsonb_build_object('acc','1010','cr', v_amt)));
                        UPDATE expense_reports SET reimbursed_at = (d0 + 24) + TIME '11:00' WHERE expense_report_id = v_rep;
                    END IF;
                END IF;
            END LOOP;
        END IF;

        ------------------------------------------------ supplier payments falling due this month
        FOR r IN SELECT b.vendor_bill_id, b.total_amount - b.amount_paid AS bal, b.due_date, b.currency_code, b.bill_number, o.code AS office
                   FROM vendor_bills b LEFT JOIN offices o ON o.office_id = b.office_id
                  WHERE b.status IN ('approved','partially_paid') AND b.due_date <= LEAST(d1, c_cutoff)
                  ORDER BY b.due_date LOOP
            PERFORM fn_pay_vendor_bill(r.vendor_bill_id, r.bal,
                pg_temp.bank(CASE r.currency_code WHEN 'ZAR' THEN '1012' WHEN 'KES' THEN '1014' WHEN 'GBP' THEN '1015' WHEN 'AED' THEN '1016'
                                                  ELSE CASE WHEN r.office = 'BYO' THEN '1018' ELSE '1010' END END),
                GREATEST(r.due_date, d0), 'EFT ' || r.bill_number);
        END LOOP;

        ------------------------------------------------ client receipts
        IF m <= '2026-01-01' THEN                 -- legacy ledger collections
            v_amt := v_legacy_prev + CASE WHEN m = '2025-01-01' THEN 2180000 * 0.6 WHEN m = '2025-02-01' THEN 2180000 * 0.4 ELSE 0 END;
            IF v_amt > 0 THEN
                PERFORM fn_post_journal(d0 + 17, 'Client receipts - legacy ledger ' || to_char(d0, 'Mon YYYY'), 'legacy', NULL, jsonb_build_array(
                    jsonb_build_object('acc','1013','dr', v_amt), jsonb_build_object('acc','1100','cr', v_amt, 'desc','Receipts against legacy invoices')));
            END IF;
        END IF;
        FOR r IN SELECT s.invoice_id, s.pay_date, s.pct, i.client_id, i.balance_due, i.total_amount, i.invoice_number
                   FROM seed_receipts s JOIN invoices i USING (invoice_id)
                  WHERE s.pay_date BETWEEN d0 AND LEAST(d1, c_cutoff) AND i.balance_due > 0 ORDER BY s.pay_date LOOP
            v_amt := LEAST(r.balance_due, round(r.total_amount * r.pct, 2));
            v_id := fn_record_client_payment(r.client_id, v_amt, pg_temp.bank('1013'), r.pay_date, 'bank_transfer', 'EFT ' || r.invoice_number, FALSE);
            INSERT INTO payment_allocations (payment_id, invoice_id, amount) VALUES (v_id, r.invoice_id, v_amt);
            IF r.pct < 1 THEN UPDATE seed_receipts SET pay_date = pay_date + 35, pct = 1 WHERE invoice_id = r.invoice_id; END IF;
        END LOOP;

        ------------------------------------------------ 25th: payroll
        FOR r IN SELECT DISTINCT o.country_code FROM employees e JOIN offices o USING (office_id) ORDER BY 1 LOOP
            v_run := fn_run_payroll(r.country_code, d0, d0 + 24);
            IF d1 <= c_closed THEN
                PERFORM fn_approve_payroll(v_run, CASE WHEN r.country_code = 'ZW' THEN v_cfo ELSE v_hr END);
                UPDATE payroll_runs SET approved_at = (d0 + 21) + TIME '15:00' WHERE payroll_run_id = v_run;
                PERFORM fn_pay_payroll(v_run, pg_temp.bank(CASE r.country_code WHEN 'ZA' THEN '1012' WHEN 'KE' THEN '1014' WHEN 'GB' THEN '1015'
                                                                                WHEN 'AE' THEN '1016' ELSE '1010' END));
            END IF;
        END LOOP;
        IF d1 <= c_closed THEN PERFORM fn_prepare_payroll_returns(d0, v_tax); END IF;

        ------------------------------------------------ month end (closed months only)
        CONTINUE WHEN d1 > c_closed;

        -- revenue & invoicing
        IF m <= '2025-12-01' THEN
            -- legacy billing system; in Nov/Dec 2025 engagements not yet migrated still bill through it (~60%)
            v_season := (ARRAY[0.86, 0.95, 1.05, 0.93, 1.06, 1.10, 1.00, 1.04, 1.09, 1.07, 1.02, 0.85])[mo];
            v_total := round(1360000 * v_season * CASE WHEN m >= '2025-11-01' THEN 0.6 ELSE 1 END, 2);
            v_lines := jsonb_build_array(jsonb_build_object('acc','1100','dr', 0));   -- placeholder, replaced below
            v_lines := '[]'::JSONB; v_amt := 0;
            FOR r IN SELECT o.office_id, o.code, s.share, t.gl, t.rate
                       FROM (VALUES ('HRE',0.70), ('BYO',0.07), ('JNB',0.09), ('NBO',0.06), ('LON',0.05), ('DXB',0.03)) AS s(code, share)
                       JOIN offices o ON o.code = s.code
                       JOIN (VALUES ('HRE','2200',0.124), ('BYO','2200',0.155), ('JNB','2201',0.15), ('NBO','2202',0.16),
                                    ('LON','2203',0.20), ('DXB','2204',0.05)) AS t(code, gl, rate) ON t.code = s.code LOOP
                v_lines := v_lines
                  || jsonb_build_object('acc','4000','cr', round(v_total * r.share * 0.68, 2), 'office', r.office_id, 'desc','Fees - legacy billing')
                  || jsonb_build_object('acc','4010','cr', round(v_total * r.share * 0.22, 2), 'office', r.office_id, 'desc','Fixed fees - legacy billing')
                  || jsonb_build_object('acc','4020','cr', round(v_total * r.share * 0.10, 2), 'office', r.office_id, 'desc','Retainers - legacy billing')
                  || jsonb_build_object('acc', r.gl, 'cr', round(v_total * r.share * r.rate, 2), 'desc','Output VAT');
                v_amt := v_amt + round(v_total * r.share * 0.68, 2) + round(v_total * r.share * 0.22, 2) + round(v_total * r.share * 0.10, 2)
                               + round(v_total * r.share * r.rate, 2);
            END LOOP;
            v_lines := jsonb_build_array(jsonb_build_object('acc','1100','dr', v_amt, 'desc','Legacy billing - trade receivables')) || v_lines;
            PERFORM fn_post_journal(d1, 'Billing summary from legacy system - ' || to_char(d1, 'Mon YYYY'), 'legacy', NULL, v_lines);
            v_legacy_prev := v_amt;
        END IF;
        IF m >= '2025-11-01' THEN
            -- time & materials: invoice approved time + billable expenses
            IF y = 2026 THEN
                FOR r IN SELECT DISTINCT p.project_id, sp.tax FROM projects p JOIN seed_projects sp ON sp.code = p.project_code
                           JOIN time_entries te ON te.project_id = p.project_id AND te.is_billable AND te.invoice_line_id IS NULL AND te.work_date <= d1
                          WHERE p.billing_type = 'time_and_materials' LOOP
                    v_id := fn_generate_invoice_from_time(r.project_id, d0 - 40, d1, d1, r.tax, TRUE, v_fin_user);
                    PERFORM pg_temp.issue(v_id);
                END LOOP;
            ELSE   -- Nov/Dec 2025: first invoices from the new system, based on agreed monthly fee estimates
                FOR r IN SELECT p.project_id, p.client_id, p.contract_id, p.budget_fees, p.start_date, p.planned_end_date, c.payment_terms_days, sp.tax
                           FROM projects p JOIN seed_projects sp ON sp.code = p.project_code JOIN clients c ON c.client_id = p.client_id
                          WHERE p.billing_type = 'time_and_materials' AND p.start_date <= d1 - 10 LOOP
                    INSERT INTO invoices (client_id, project_id, contract_id, invoice_date, due_date, currency_code, notes, created_by)
                    VALUES (r.client_id, r.project_id, r.contract_id, d1, d1 + r.payment_terms_days, 'USD',
                            'Professional services ' || to_char(d1, 'FMMonth YYYY'), v_fin_user) RETURNING invoice_id INTO v_id;
                    v_amt := round(r.budget_fees / GREATEST((r.planned_end_date - r.start_date) / 30.0, 1) * 0.9, -1);
                    INSERT INTO invoice_lines (invoice_id, line_no, line_type, description, quantity, unit, unit_price, tax_rate_id, project_id)
                    VALUES (v_id, 1, 'time', 'Professional services - ' || to_char(d1, 'FMMonth YYYY') || ' (per engagement letter)',
                            round(v_amt / 150), 'hour', 150, (SELECT tax_rate_id FROM tax_rates WHERE code = r.tax), r.project_id);
                    PERFORM pg_temp.issue(v_id);
                END LOOP;
            END IF;
            -- retainers
            FOR r IN SELECT p.project_id, p.client_id, p.contract_id, ct.retainer_fee_per_month, ct.payment_terms_days, sp.tax
                       FROM projects p JOIN contracts ct ON ct.contract_id = p.contract_id JOIN seed_projects sp ON sp.code = p.project_code
                      WHERE p.billing_type = 'retainer' AND p.start_date <= d1 AND p.planned_end_date >= d0 LOOP
                INSERT INTO invoices (client_id, project_id, contract_id, invoice_date, due_date, currency_code, notes, created_by)
                VALUES (r.client_id, r.project_id, r.contract_id, d1, d1 + r.payment_terms_days, 'USD', 'Monthly retainer ' || to_char(d1, 'FMMonth YYYY'), v_fin_user)
                RETURNING invoice_id INTO v_id;
                INSERT INTO invoice_lines (invoice_id, line_no, line_type, description, quantity, unit, unit_price, tax_rate_id, project_id)
                VALUES (v_id, 1, 'retainer', 'Monthly retainer - ' || to_char(d1, 'FMMonth YYYY'), 1, 'month', r.retainer_fee_per_month,
                        (SELECT tax_rate_id FROM tax_rates WHERE code = r.tax), r.project_id);
                PERFORM pg_temp.issue(v_id);
            END LOOP;
            -- milestones reached this month
            FOR r IN SELECT ms.milestone_id, sp.tax FROM contract_milestones ms JOIN contracts ct USING (contract_id)
                       JOIN projects p ON p.contract_id = ct.contract_id JOIN seed_projects sp ON sp.code = p.project_code
                      WHERE ms.status = 'pending' AND ms.due_date <= d1 LOOP
                UPDATE contract_milestones SET status = 'achieved', achieved_date = LEAST(due_date, d1) WHERE milestone_id = r.milestone_id;
                v_id := fn_invoice_milestone(r.milestone_id, d1, r.tax, v_fin_user);
                PERFORM pg_temp.issue(v_id);
            END LOOP;
        END IF;

        -- depreciation, leases, interest, bank charges
        PERFORM fn_run_depreciation(d1, v_fin_user);
        PERFORM fn_post_lease_month(d0, v_fin_user);
        v_amt := round(pg_temp.bal('1017') * 0.07 / 12, 2);
        PERFORM fn_post_journal(d1, 'Interest on money market call account (7% p.a.)', 'interest', NULL, jsonb_build_array(
            jsonb_build_object('acc','1017','dr', v_amt), jsonb_build_object('acc','4600','cr', v_amt)));
        PERFORM fn_post_journal(d1, 'Bank charges ' || to_char(d1, 'Mon YYYY'), 'manual', NULL, jsonb_build_array(
            jsonb_build_object('acc','6600','dr', 1385),
            jsonb_build_object('acc','1010','cr', 620), jsonb_build_object('acc','1013','cr', 410), jsonb_build_object('acc','1018','cr', 55),
            jsonb_build_object('acc','1012','cr', 90), jsonb_build_object('acc','1014','cr', 70), jsonb_build_object('acc','1015','cr', 85),
            jsonb_build_object('acc','1016','cr', 55)));
        -- quarter-end sweep of surplus cash into the money market
        IF pg_temp.bal('1013') > 2500000 THEN
            PERFORM fn_bank_transfer(pg_temp.bank('1013'), pg_temp.bank('1017'), round(pg_temp.bal('1013') - 1500000, -4), d1, 'Sweep surplus cash to money market');
        END IF;

        -- income taxes (IAS 12): Zimbabwe provision every month; branch taxes each quarter
        PERFORM fn_accrue_income_tax(d1, v_fin_user);
        IF mo IN (3,6,9,12) THEN
            FOR r IN SELECT o.office_id, o.code, s.rate FROM offices o
                       JOIN (VALUES ('JNB',27.0), ('NBO',30.0), ('LON',25.0), ('DXB',9.0)) AS s(code, rate) ON s.code = o.code LOOP
                SELECT COALESCE(SUM(jl.credit - jl.debit), 0) INTO v_amt FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id)
                  JOIN chart_of_accounts a ON a.account_id = jl.account_id
                 WHERE a.ifrs_line_code = 'PL_REV' AND jl.office_id = r.office_id AND je.entry_date BETWEEN (d0 - INTERVAL '2 months')::DATE AND d1;
                v_amt := round(v_amt * 0.22 * r.rate / 100, 2);     -- branch profit ~22% of branch revenue
                IF v_amt > 0 THEN
                    PERFORM fn_post_journal(d1, 'Branch income tax provision - ' || r.code, 'tax', NULL, jsonb_build_array(
                        jsonb_build_object('acc','9010','dr', v_amt, 'office', r.office_id), jsonb_build_object('acc','2265','cr', v_amt, 'office', r.office_id)));
                END IF;
            END LOOP;
            PERFORM fn_update_ecl_provision(d1, v_fin_user);
        END IF;

        -- year end 2025
        IF m = '2025-12-01' THEN
            PERFORM fn_revalue_asset(fa.asset_id, '2025-12-31', v.fv, 'Knight Frank Zimbabwe (independent valuers)', 3::SMALLINT, v_fin_user)
               FROM fixed_assets fa JOIN (VALUES ('MXH-LND-001',1240000), ('MXH-BLD-001',3650000), ('MXH-LND-002',275000),
                                                 ('MXH-BLD-002',820000), ('MXH-LND-003',560000), ('MXH-IP-001',1560000)) AS v(tag, fv) ON v.tag = fa.asset_tag;
            PERFORM fn_post_journal('2025-12-31', 'Leave pay accrual adjustment (IAS 19)', 'accrual', NULL, jsonb_build_array(
                jsonb_build_object('acc','5160','dr', 21000), jsonb_build_object('acc','2510','cr', 21000)));
            PERFORM fn_post_journal('2025-12-31', 'Staff bonus accrual FY2025 (paid March 2026)', 'accrual', NULL, jsonb_build_array(
                jsonb_build_object('acc','5150','dr', 380000), jsonb_build_object('acc','2520','cr', 380000)));
            PERFORM fn_post_journal('2025-12-31', 'External audit fee accrual FY2025', 'accrual', NULL, jsonb_build_array(
                jsonb_build_object('acc','6700','dr', 30000), jsonb_build_object('acc','2500','cr', 30000)));
            PERFORM fn_accrue_income_tax('2025-12-31', v_fin_user);
            -- deferred tax to the IAS 12 schedule (movement not already booked through OCI / P&L)
            SELECT SUM(deferred_tax) INTO v_amt FROM fn_deferred_tax_schedule('2025-12-31');
            v_amt := round(v_amt - (-(pg_temp.bal('2900')) + pg_temp.bal('1900')), 2);
            IF v_amt <> 0 THEN
                PERFORM fn_post_journal('2025-12-31', 'Deferred tax movement FY2025 (IAS 12)', 'tax', NULL, jsonb_build_array(
                    jsonb_build_object('acc','9020','dr', v_amt), jsonb_build_object('acc','2900','cr', v_amt)));
            END IF;
        END IF;

        -- interim / final dividends
        IF m = '2025-09-01' THEN
            PERFORM fn_post_journal('2025-09-30', 'Interim dividend FY2025 declared (USD 1.00 per share)', 'dividend', NULL, jsonb_build_array(
                jsonb_build_object('acc','3200','dr', 1000000), jsonb_build_object('acc','2950','cr', 1000000)));
        END IF;
        IF m = '2026-04-01' THEN
            PERFORM fn_post_journal('2026-04-15', 'Final dividend FY2025 declared at AGM (USD 1.50 per share)', 'dividend', NULL, jsonb_build_array(
                jsonb_build_object('acc','3200','dr', 1500000), jsonb_build_object('acc','2950','cr', 1500000)));
        END IF;
    END LOOP;

    -- dividends paid (net to shareholders + 10% resident shareholders' tax to ZIMRA)
    PERFORM fn_post_journal('2025-10-15', 'Interim dividend paid - net to shareholders and 10% shareholders tax to ZIMRA', 'dividend', NULL, jsonb_build_array(
        jsonb_build_object('acc','2950','dr', 1000000), jsonb_build_object('acc','1017','cr', 1000000)));
    PERFORM fn_post_journal('2026-05-08', 'Final dividend paid - net to shareholders and 10% shareholders tax to ZIMRA', 'dividend', NULL, jsonb_build_array(
        jsonb_build_object('acc','2950','dr', 1500000), jsonb_build_object('acc','1017','cr', 1500000)));
    -- FY2025 bonuses paid with March 2026 salaries
    PERFORM fn_post_journal('2026-03-25', 'FY2025 performance bonuses paid', 'payroll_payment', NULL, jsonb_build_array(
        jsonb_build_object('acc','2520','dr', 380000), jsonb_build_object('acc','1010','cr', 380000)));
    -- asset disposal
    PERFORM fn_dispose_asset((SELECT asset_id FROM fixed_assets WHERE asset_tag = 'MXH-MV-008'), '2026-07-15', 9000, pg_temp.bank('1010'),
                             'Public auction - Harare Auctioneers', 'sale', v_cfo, v_fin_user);
END $$;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  36_seed_communications_close.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   36. SEED - COMMUNICATIONS, TAX COMPUTATION, PERIOD CLOSE, FINISHING TOUCHES
   ===================================================================================== */

-- 36.1 Mailing lists & shared mailboxes ---------------------------------------------------
INSERT INTO mailing_lists (address, display_name, list_type, is_all_staff, owner_employee_id, description)
VALUES ('all-staff@maxhub.co.zw', 'All Maxhub staff', 'distribution', TRUE, (SELECT employee_id FROM employees WHERE employee_number='E007'), 'Every employee in every office'),
       ('leadership@maxhub.co.zw', 'Leadership team', 'distribution', FALSE, (SELECT employee_id FROM employees WHERE employee_number='E001'), 'Partners, directors and heads of department'),
       ('info@maxhub.co.zw', 'General enquiries', 'shared', FALSE, (SELECT employee_id FROM employees WHERE employee_number='E020'), 'Website contact form & switchboard'),
       ('accounts@maxhub.co.zw', 'Accounts receivable', 'shared', FALSE, (SELECT employee_id FROM employees WHERE employee_number='E025'), 'Remittance advices & statements'),
       ('whistleblower@maxhub.co.zw', 'Ethics & whistle-blowing line', 'shared', FALSE, (SELECT employee_id FROM employees WHERE employee_number='E024'), 'Confidential - Internal Audit only');
INSERT INTO mailing_lists (address, display_name, list_type, department_id, owner_employee_id, description)
SELECT d.email, d.name, 'distribution', d.department_id, d.head_employee_id, 'Everyone in ' || d.name FROM departments d;
INSERT INTO mailing_lists (address, display_name, list_type, office_id, owner_employee_id, description)
SELECT o.email, o.name, 'distribution', o.office_id, o.manager_employee_id, 'Everyone based in ' || o.city FROM offices o;
INSERT INTO mailing_list_members (list_id, employee_id)
SELECT (SELECT list_id FROM mailing_lists WHERE address = 'leadership@maxhub.co.zw'), e.employee_id
  FROM employees e JOIN job_grades g USING (job_grade_id)
 WHERE g.level >= 6 OR e.employee_id IN (SELECT head_employee_id FROM departments);

-- 36.2 Announcements ----------------------------------------------------------------------
INSERT INTO announcements (title, body, category, audience, department_id, office_id, author_id, is_pinned, publish_at, expires_at)
SELECT v.title, v.body, v.cat, v.aud, (SELECT department_id FROM departments WHERE code = v.dept), (SELECT office_id FROM offices WHERE code = v.office),
       (SELECT employee_id FROM employees WHERE employee_number = v.author), v.pin, v.pub::TIMESTAMPTZ, v.exp::TIMESTAMPTZ
  FROM (VALUES
   ('Welcome to the new Maxhub ERP','Colleagues, from today every timesheet, expense claim, leave request and approval runs through the Maxhub ERP. Log in with your company username (firstname.lastname) and change your password on first use. What you see depends on your department and role. Thank you for making Maxhub a data-driven firm. - Tendai',
    'general','all',NULL,NULL,'E001',TRUE,'2026-09-01 08:00+02',NULL),
   ('Early adoption of IFRS 18 for FY2026','The Board has approved early adoption of IFRS 18 (Presentation and Disclosure in Financial Statements) for the year ending 31 December 2026. Our income statement now shows Operating profit and Profit before financing and income taxes, and our MPMs (Adjusted operating profit, Adjusted EBITDA) are disclosed in a single note. Finance will run short training sessions in October.',
    'finance','all',NULL,NULL,'E006',TRUE,'2026-02-10 09:00+02',NULL),
   ('QPD 3 paid - 30% of estimated 2026 tax','The third Quarterly Payment Date instalment was paid to ZIMRA on 23 September, ahead of the 25 September deadline. VAT7 for September is due 25 October; PAYE/NSSA/ZIMDEF by 10 October.',
    'compliance','department','FIN',NULL,'E009',FALSE,'2026-09-23 12:00+02','2026-10-31 00:00+02'),
   ('Timesheets due every Friday by 17:00','Please submit your timesheet every Friday. Unsubmitted time cannot be billed and delays our invoicing. Managers approve by Monday 10:00.',
    'general','all',NULL,NULL,'E018',FALSE,'2026-09-18 08:30+02',NULL),
   ('Phishing alert: fake "ZIMRA refund" e-mails','We are seeing e-mails pretending to be ZIMRA offering tax refunds. Do not click links or open attachments. Forward suspicious mail to itsupport@maxhub.co.zw. Remember: IT will never ask for your password.',
    'it','all',NULL,NULL,'E008',TRUE,'2026-09-22 10:15+02','2026-10-22 00:00+02'),
   ('Fire drill - Maxhub House, Wednesday 30 September 10:00','All staff at Maxhub House must evacuate to the assembly point in the car park when the alarm sounds. Floor wardens will take the roll.',
    'health_safety','office',NULL,'HRE','E022',FALSE,'2026-09-21 09:00+02','2026-10-01 00:00+02'),
   ('Maxhub Annual Awards Dinner - 31 October','Save the date! Our annual awards dinner is at Meikles Hotel, Harare. Branch colleagues will join by live stream.',
    'event','all',NULL,NULL,'E007',FALSE,'2026-09-15 08:00+02','2026-11-01 00:00+02'),
   ('Nairobi office expansion complete','The additional floor space at Westlands Square is now furnished and open. Welcome to our three new colleagues in Data Analytics.',
    'general','office',NULL,'NBO','E015',FALSE,'2026-03-20 09:00+03',NULL),
   ('NSSA insurable earnings ceiling','Payroll reminder: NSSA contributions are 4.5% employee + 4.5% employer on insurable earnings capped at USD 700 per month. The ceiling is held in the statutory rates table - HR will update it when NSSA gazettes a change.',
    'hr','department','HRM',NULL,'E007',FALSE,'2026-01-12 08:00+02',NULL),
   ('New engagement: commodity trade-finance investigation','London has completed the Thames Commodity Traders investigation. Great teamwork across London, Harare and Dubai.',
    'general','all',NULL,NULL,'E016',FALSE,'2026-08-31 11:00+01',NULL)
  ) AS v(title, body, cat, aud, dept, office, author, pin, pub, exp);

INSERT INTO announcement_reads (announcement_id, employee_id, read_at)
SELECT a.announcement_id, e.employee_id, a.publish_at + make_interval(hours => (e.employee_id % 30)::INT)
  FROM announcements a CROSS JOIN employees e
 WHERE a.audience = 'all' AND (e.employee_id + a.announcement_id) % 3 <> 0
   AND a.publish_at + make_interval(hours => (e.employee_id % 30)::INT) < '2026-09-24 18:00+02';

-- 36.3 Internal messages ------------------------------------------------------------------
CREATE TEMP TABLE seed_msgs (n INT, sender TEXT, recipients TEXT[], subject TEXT, body TEXT, prio TEXT, sent TIMESTAMPTZ, read_by TEXT[]);
INSERT INTO seed_msgs VALUES
 (1,'E004',ARRAY['E005'],'Timesheet for week of 14 September','Hi Kuda, please make sure your time on the loan-book forensic audit is split by task before I approve. Thanks, Nyasha','normal','2026-09-21 08:40+02',ARRAY[]::TEXT[]),
 (2,'E002',ARRAY['E004','E005'],'Zambezi Mining - draft report review','Team, the partner review of the procurement fraud report is set for Tuesday 29 September at 10:00 in the Boardroom (4th floor). Please circulate the working papers by Monday.','high','2026-09-23 16:05+02',ARRAY['E004']),
 (3,'E009',ARRAY['E006','E025'],'QPD 3 paid to ZIMRA','QPD 3 (30%) was paid on 23 Sep via CBZ. Acknowledgement is filed in TaRMS. Next: VAT7 for September due 25 October.','normal','2026-09-23 12:10+02',ARRAY['E006','E025']),
 (4,'E006',ARRAY['E009'],'RE: QPD 3 paid to ZIMRA','Thanks Memory. Please also prepare the IFRS 18 MPM reconciliation for the Audit Committee pack.','normal','2026-09-23 13:02+02',ARRAY[]::TEXT[]),
 (5,'E008',ARRAY['E001','E006','E007','E018'],'ERP go-live: access by department','All staff logins are active. Access is automatic by department and grade (e.g. Finance = Accountant, Finance managers = Finance Manager). Accounts lock for 15 minutes after 5 wrong passwords. Please ask your teams to change the demo password.','high','2026-09-01 07:45+02',ARRAY['E001','E006','E007']),
 (6,'E007',ARRAY['E006'],'September payroll ready for approval','The September payroll runs for Zimbabwe and the four branches are prepared in the ERP. Please review and approve by the 24th so salaries go out on the 25th.','high','2026-09-22 15:30+02',ARRAY[]::TEXT[]),
 (7,'E022',ARRAY['E008','E021'],'Bulawayo solar installation','SolarTech will commission the 60kW system at Maxhub Centre next week. The asset is in the register as under construction until handover.','normal','2026-09-16 11:20+02',ARRAY['E008','E021']),
 (8,'E025',ARRAY['E006'],'August management accounts','August is closed. Revenue YTD USD 9.7m; operating profit USD 2.6m. The IFRS statements are available on the Financial Statements page.','normal','2026-09-10 17:45+02',ARRAY['E006']),
 (9,'E020',ARRAY['E002','E003','E010'],'Proposal deadline - Lusaka Water tender','The Lusaka Water revenue-assurance tender closes 9 October. Can each practice send CVs and a fee estimate by 2 October?','normal','2026-09-18 09:12+02',ARRAY['E003']),
 (10,'E014',ARRAY['E018'],'Johannesburg Q3 pipeline','Gauteng Treasury phase 2 looks likely (USD 160k). Rand Merchant Credit has asked for a model-validation proposal.','normal','2026-09-14 14:30+02',ARRAY['E018']),
 (11,'E023',ARRAY['E004'],'QRM review booked','Your engagement file for P25-001 is scheduled for an ISQM 1 quality review on 5 October.','normal','2026-09-24 09:00+02',ARRAY[]::TEXT[]),
 (12,'E001',ARRAY['E002','E010','E011','E018'],'Board pack - Q3','Partners, please send your practice updates for the Q3 board pack by 2 October.','high','2026-09-24 07:30+02',ARRAY[]::TEXT[]);

INSERT INTO internal_messages (sender_id, subject, body, priority, sent_at)
SELECT (SELECT employee_id FROM employees WHERE employee_number = m.sender), m.subject, m.body, m.prio, m.sent FROM seed_msgs m ORDER BY m.n;
UPDATE internal_messages im SET thread_id = (SELECT message_id FROM internal_messages WHERE subject = 'QPD 3 paid to ZIMRA') WHERE subject LIKE 'RE: QPD 3%';
INSERT INTO message_recipients (message_id, recipient_id, read_at)
SELECT im.message_id, e.employee_id, CASE WHEN e.employee_number = ANY (m.read_by) THEN m.sent + INTERVAL '35 minutes' END
  FROM seed_msgs m
  JOIN internal_messages im ON im.subject = m.subject AND im.sent_at = m.sent
  JOIN employees e ON e.employee_number = ANY (m.recipients);

-- a company-wide message via the all-staff list
INSERT INTO internal_messages (sender_id, subject, body, priority, sent_to_list_id, sent_at)
VALUES ((SELECT employee_id FROM employees WHERE employee_number='E007'), 'Wellness Wednesday - free health screening',
        'CIMAS will run free blood-pressure and glucose screening at Maxhub House and Maxhub Centre on Wednesday. Branch staff can claim a screening through the medical aid.',
        'low', (SELECT list_id FROM mailing_lists WHERE address = 'all-staff@maxhub.co.zw'), '2026-09-21 12:00+02');
INSERT INTO message_recipients (message_id, recipient_id, read_at)
SELECT currval(pg_get_serial_sequence('internal_messages','message_id')), e.employee_id,
       CASE WHEN e.employee_id % 2 = 0 THEN '2026-09-21 13:00+02'::TIMESTAMPTZ END
  FROM employees e;

-- 36.4 System e-mail outbox ----------------------------------------------------------------
INSERT INTO email_outbox (to_address, subject, body, template_code, related_entity, related_id, status, attempts, queued_at, sent_at)
SELECT e.email, 'Reminder: submit your timesheet for the week of 14 September',
       'Hi ' || e.first_name || ', your timesheet for the week starting 14 Sep is still not submitted. Please submit it in the Maxhub ERP.',
       'timesheet_reminder', 'timesheet', t.timesheet_id, 'sent', 1, '2026-09-18 17:05+02', '2026-09-18 17:05+02'
  FROM timesheets t JOIN employees e USING (employee_id) WHERE t.week_start_date = '2026-09-14' AND t.status IN ('draft','rejected');
INSERT INTO email_outbox (to_address, subject, body, template_code, related_entity, related_id, status, attempts, queued_at, sent_at)
SELECT e.email, 'Your payslip for August 2026', 'Your August 2026 payslip is available in the Maxhub ERP (People > My payslips).',
       'payslip', 'payslip', p.payslip_id, 'sent', 1, '2026-08-25 06:00+02', '2026-08-25 06:01+02'
  FROM payslips p JOIN payroll_runs r USING (payroll_run_id) JOIN employees e USING (employee_id) WHERE r.period_start = '2026-08-01';
INSERT INTO email_outbox (to_address, cc_address, subject, body, template_code, related_entity, related_id, status, attempts, queued_at, sent_at)
SELECT c.billing_email, 'accounts@maxhub.co.zw', 'Tax invoice ' || i.invoice_number || ' from Maxhub Pvt Ltd',
       'Please find attached fiscalised tax invoice ' || i.invoice_number || ' (FDMS ' || i.fiscal_invoice_number || ') for USD ' || to_char(i.total_amount, 'FM999,999,990.00') || '.',
       'invoice', 'invoice', i.invoice_id, 'sent', 1, i.invoice_date + TIME '17:00', i.invoice_date + TIME '17:01'
  FROM invoices i JOIN clients c USING (client_id) WHERE i.invoice_date >= '2026-07-01' AND i.status <> 'draft';
INSERT INTO email_outbox (to_address, subject, body, template_code, status, attempts, last_error, queued_at)
VALUES ('accounts@beiracorridor.example', 'Statement of account - overdue invoices', 'Our records show overdue invoices on your account. Please arrange payment.',
        'statement', 'failed', 3, 'SMTP 550: mailbox unavailable', '2026-09-22 08:00+02'),
       ('ruvimbo.zvobgo@maxhub.co.zw', 'Board resolution register updated', 'The Q3 board resolutions have been added to the register.', 'notification', 'queued', 0, NULL, '2026-09-24 16:40+02');

INSERT INTO calendar_events (title, event_type, starts_at, ends_at, location, office_id, organiser_id, description)
SELECT v.t, v.ty, v.s::TIMESTAMPTZ, v.e::TIMESTAMPTZ, v.loc, (SELECT office_id FROM offices WHERE code = v.o),
       (SELECT employee_id FROM employees WHERE employee_number = v.org), v.d
  FROM (VALUES ('ZIMRA QPD 3 deadline (30%)','deadline','2026-09-25 00:00+02',NULL,'ZIMRA TaRMS','HRE','E009','Paid 23 Sep'),
               ('Fire drill - Maxhub House','meeting','2026-09-30 10:00+02','2026-09-30 10:30+02','Car park assembly point','HRE','E022',NULL),
               ('Audit Committee meeting (Q3)','board','2026-10-08 09:00+02','2026-10-08 12:00+02','Boardroom, 4th floor','HRE','E019','IFRS 18 MPM note & internal audit report'),
               ('PAYE / NSSA / ZIMDEF returns due','deadline','2026-10-10 00:00+02',NULL,'ZIMRA / NSSA portals','HRE','E009',NULL),
               ('IFRS 18 training for practice leads','training','2026-10-14 14:00+02','2026-10-14 16:00+02','Maxhub Academy, Borrowdale','HRE','E006',NULL),
               ('VAT7 September due','deadline','2026-10-25 00:00+02',NULL,'ZIMRA TaRMS','HRE','E009',NULL),
               ('Maxhub Annual Awards Dinner','social','2026-10-31 18:30+02','2026-10-31 23:00+02','Meikles Hotel, Harare','HRE','E007',NULL),
               ('QPD 4 deadline (35%)','deadline','2026-12-20 00:00+02',NULL,'ZIMRA TaRMS','HRE','E009',NULL)) AS v(t, ty, s, e, loc, o, org, d);

INSERT INTO notifications (user_id, title, message, link, created_at)
SELECT u.user_id, 'Timesheets waiting for your approval',
       count(*) || ' timesheet(s) for the week of 14 Sep are waiting for you.', 'Timesheets > Approvals', '2026-09-21 08:00+02'
  FROM timesheets t JOIN employees e ON e.employee_id = t.employee_id JOIN app_users u ON u.employee_id = e.manager_id
 WHERE t.status = 'submitted' GROUP BY u.user_id;

-- 36.5 FY2025 corporate income tax computation (ITF12C) ------------------------------------
INSERT INTO income_tax_computations (fiscal_year_id, profit_before_tax, add_backs, capital_allowances, exempt_income, foreign_branch_profit,
                                     taxable_income, tax_rate_pct, income_tax, aids_levy, foreign_tax_credit, total_tax, qpds_paid, status, filed_date, notes)
SELECT fy.fiscal_year_id, x.pbt, x.addb, x.ca, x.fv, 0,
       x.pbt + x.addb - x.ca - x.fv, 24, round((x.pbt + x.addb - x.ca - x.fv) * 0.24, 2), round((x.pbt + x.addb - x.ca - x.fv) * 0.24 * 0.03, 2),
       0, round((x.pbt + x.addb - x.ca - x.fv) * 0.2472, 2),
       (SELECT COALESCE(SUM(amount_paid), 0) FROM tax_returns WHERE tax_code = 'CIT_QPD' AND period_start >= '2025-01-01' AND period_end <= '2025-12-31'),
       'filed', '2026-04-28', 'Add-backs: accounting depreciation, donations, fines & non-deductible entertainment. Allowances: wear & tear per ZIMRA rates.'
  FROM fiscal_years fy
 CROSS JOIN LATERAL (SELECT (SELECT amount FROM fn_ifrs_profit_or_loss('2025-01-01','2025-12-31') WHERE line_code = 'ST_PBT') AS pbt,
                            fn_account_movement('7000','2025-01-01','2025-12-31') + fn_account_movement('7020','2025-01-01','2025-12-31')
                              + fn_account_movement('6950','2025-01-01','2025-12-31') AS addb,
                            round(fn_account_movement('7000','2025-01-01','2025-12-31') * 0.92, 2) AS ca,
                            110000::NUMERIC AS fv) x
 WHERE fy.name = 'FY2025';
-- the final balance was paid through the ITF12C return seeded in module 35
UPDATE tax_returns SET notes = 'FY2024 final - paid' WHERE return_number = 'ITF12C-2024';

-- 36.6 Period close -----------------------------------------------------------------------
INSERT INTO period_close_tasks (fiscal_period_id, task_name, owner_role, due_date, completed_by, completed_at)
SELECT fp.fiscal_period_id, t.name, t.role, fp.end_date + t.days, (SELECT employee_id FROM employees WHERE employee_number = t.who),
       CASE WHEN fp.end_date <= '2026-08-31' THEN (fp.end_date + t.days) + TIME '16:00' END
  FROM fiscal_periods fp JOIN fiscal_years fy USING (fiscal_year_id)
 CROSS JOIN (VALUES ('Issue all month-end invoices', 'ACCOUNTANT', 1, 'E025'), ('Run depreciation', 'FINANCE_MANAGER', 2, 'E025'),
                    ('Post IFRS 16 lease entries', 'FINANCE_MANAGER', 2, 'E025'), ('Bank reconciliations (all accounts)', 'ACCOUNTANT', 4, 'E025'),
                    ('Prepare VAT7, P2 and P4 returns', 'TAX_OFFICER', 5, 'E009'), ('Review AR ageing & ECL', 'FINANCE_MANAGER', 5, 'E006'),
                    ('Management accounts to CFO', 'FINANCE_MANAGER', 8, 'E025')) AS t(name, role, days, who)
 WHERE fy.name = 'FY2026' AND fp.period_no <= 9;

UPDATE fiscal_periods SET is_closed = TRUE
 WHERE fiscal_year_id = (SELECT fiscal_year_id FROM fiscal_years WHERE name = 'FY2025')
    OR (fiscal_year_id = (SELECT fiscal_year_id FROM fiscal_years WHERE name = 'FY2026') AND end_date <= '2026-08-31');
UPDATE fiscal_years SET is_closed = TRUE WHERE name IN ('FY2024','FY2025');

-- 36.7 Finish ------------------------------------------------------------------------------
SELECT set_config('erp.current_user_id', '', false);
SET erp.skip_audit = 'off';
ANALYZE;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  99_optional_grants_and_checks.sql  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

/* =====================================================================================
   19. OPTIONAL: DATABASE ROLES & GRANTS (uncomment and adapt)
   =====================================================================================
-- CREATE ROLE erp_app   LOGIN PASSWORD 'change-me';
-- CREATE ROLE erp_read  NOLOGIN;
-- GRANT USAGE ON SCHEMA erp TO erp_app, erp_read;
-- GRANT SELECT ON ALL TABLES IN SCHEMA erp TO erp_read;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA erp TO erp_app;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA erp TO erp_app;
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA erp TO erp_app;
-- REVOKE UPDATE, DELETE ON erp.audit_log FROM erp_app;         -- audit log is append-only
*/


/* =====================================================================================
   QUICK CHECKS - run these after install (all should return 0 / balanced)
   =====================================================================================
   -- the ledger balances
   SELECT SUM(debit) - SUM(credit) AS difference FROM erp.fn_trial_balance(CURRENT_DATE);

   -- IFRS 18 statements (FY2025 audited year and 2026 year-to-date)
   SELECT caption, amount FROM erp.fn_ifrs_profit_or_loss('2025-01-01','2025-12-31');
   SELECT caption, amount FROM erp.fn_ifrs_profit_or_loss('2026-01-01','2026-08-31');
   SELECT section, caption, amount FROM erp.fn_ifrs_financial_position('2026-08-31');
   SELECT caption, amount FROM erp.fn_ifrs_cash_flows('2026-01-01','2026-08-31');
   SELECT * FROM erp.fn_ifrs_changes_in_equity('2026-01-01','2026-08-31');
   SELECT * FROM erp.fn_ifrs_mpm_note('2026-01-01','2026-08-31');
   SELECT * FROM erp.fn_ppe_movement('2026-01-01','2026-08-31');
   SELECT * FROM erp.fn_deferred_tax_schedule('2025-12-31');

   -- operations
   SELECT * FROM erp.v_project_financials ORDER BY budget_fees DESC;
   SELECT * FROM erp.v_employee_utilization_monthly ORDER BY month_start DESC, utilization_pct DESC;
   SELECT * FROM erp.v_ar_aging;
   SELECT * FROM erp.v_tax_calendar ORDER BY due_date DESC;
   SELECT * FROM erp.v_payroll_summary ORDER BY period_start DESC;
   SELECT * FROM erp.v_fixed_asset_register ORDER BY carrying_amount DESC;
   SELECT * FROM erp.v_lease_register;
   SELECT * FROM erp.v_user_access ORDER BY department, full_name;

   -- log-in (demo password for every user is Maxhub@2026)
   SELECT * FROM erp.fn_login('blessing.marufu', 'Maxhub@2026', '127.0.0.1', 'psql');
   SELECT erp.fn_user_permissions(u.user_id) FROM erp.app_users u WHERE username = 'blessing.marufu';
   ===================================================================================== */
