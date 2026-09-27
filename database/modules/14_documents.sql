
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

