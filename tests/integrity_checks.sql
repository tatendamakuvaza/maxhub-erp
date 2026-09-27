-- Integrity checks: every result should be 0 (run in pgAdmin or: psql -U postgres -d maxhub_erp -f tests/integrity_checks.sql)
set search_path=erp;
select 'TB diff' chk, sum(debit)-sum(credit) v from fn_trial_balance('2026-09-24');
-- minimum month-end balance of each bank account over the history
select a.account_code, min(fn_account_balance(a.account_code, (d + interval '1 month - 1 day')::date))::int min_month_end,
       fn_account_balance(a.account_code,'2026-09-24')::int now
  from chart_of_accounts a, generate_series('2025-01-01'::date,'2026-08-01','1 month') d where a.is_cash group by 1 order by 1;
-- SFP balances?
select 'SFP A-(E+L)' chk, (select amount from fn_ifrs_financial_position('2026-08-31') where line_code='T_A') - (select amount from fn_ifrs_financial_position('2026-08-31') where line_code='T_EL') v;
select 'SFP 2025 A-(E+L)', (select amount from fn_ifrs_financial_position('2025-12-31') where line_code='T_A') - (select amount from fn_ifrs_financial_position('2025-12-31') where line_code='T_EL');
-- cash flow ties to cash movement?
select 'CF 2026 open+net-close', (select amount from fn_ifrs_cash_flows('2026-01-01','2026-08-31') where cf_code='T_OPEN') + (select sum(amount) from fn_ifrs_cash_flows('2026-01-01','2026-08-31') where not is_subtotal) - (select amount from fn_ifrs_cash_flows('2026-01-01','2026-08-31') where cf_code='T_CLOSE');
select 'CF 2025 open+net-close', (select amount from fn_ifrs_cash_flows('2025-01-01','2025-12-31') where cf_code='T_OPEN') + (select sum(amount) from fn_ifrs_cash_flows('2025-01-01','2025-12-31') where not is_subtotal) - (select amount from fn_ifrs_cash_flows('2025-01-01','2025-12-31') where cf_code='T_CLOSE');
-- SOCE closing equity = SFP equity
select 'SOCE vs SFP equity', (select total_equity from fn_ifrs_changes_in_equity('2026-01-01','2026-08-31') where sort_order=7) - (select amount from fn_ifrs_financial_position('2026-08-31') where line_code='T_E');
-- PPE movement check
select 'PPE movement check', sum(opening_nbv+additions+revaluations+disposals+depreciation-closing_nbv) from fn_ppe_movement('2026-01-01','2026-08-31');
-- sub-ledger vs GL: AR
select 'AR subledger-GL', (select sum(balance_due) from invoices where status not in ('draft','void')) - fn_account_balance('1100','2026-09-24');
select 'AP subledger-GL', (select sum((total_amount-amount_paid)*exchange_rate) from vendor_bills where status in ('approved','partially_paid')) + fn_account_balance('2100','2026-09-24') + fn_account_balance('2110','2026-09-24');
select 'Lease liab schedule-GL', (select sum(liability_usd_balance) from leases where status='active' and exemption is null and role='lessee') + fn_account_balance('2700','2026-09-24') + fn_account_balance('2705','2026-09-24');
