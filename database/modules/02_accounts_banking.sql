
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
