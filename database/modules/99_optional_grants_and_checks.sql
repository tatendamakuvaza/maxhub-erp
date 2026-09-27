
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
