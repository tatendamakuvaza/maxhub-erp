
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

