
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
