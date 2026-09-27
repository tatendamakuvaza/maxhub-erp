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
