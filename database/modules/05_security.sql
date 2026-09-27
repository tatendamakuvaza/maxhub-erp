
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
    demo_protected       BOOLEAN      NOT NULL DEFAULT FALSE,  -- shared public-demo login (see module 25)
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
    bcrypt_cost            SMALLINT NOT NULL DEFAULT 10 CHECK (bcrypt_cost BETWEEN 6 AND 14),
    demo_mode              BOOLEAN  NOT NULL DEFAULT FALSE   -- TRUE = public demo (see module 25)
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

