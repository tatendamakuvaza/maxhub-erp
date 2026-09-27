
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
