
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
