# 🧭 Maxhub ERP: Beginner's Step-by-Step Guide (Windows)

This guide takes you from **an empty Windows computer** to:

1. ✅ A working **enterprise ERP database** for Maxhub Pvt Ltd (t/a *Maxhub Forensic Data Analytics*)
2. ✅ A **dashboard** in your web browser where every employee **logs in** and sees only what their department allows
3. ✅ The project **published on GitHub** as part of your portfolio

⏱️ Allow about **1½–2 hours** the first time. Do the parts in order.

> 🛡️ **Avast / antivirus users:** Avast sometimes quarantines `.bat` files. Every step below gives you the
> **manual commands** too, so you never *need* the `.bat` files.

---

## 📚 Contents

- [Part 0: What you are building](#part-0-what-you-are-building-read-first)
- [Part 1: Install the tools](#part-1-install-the-tools-30-min)
- [Part 2: Put the project on your computer](#part-2-put-the-project-on-your-computer-5-min)
- [Part 3: Create the database](#part-3-create-the-database-10-min)
- [Part 4: Look inside the database](#part-4-look-inside-the-database-20-min)
- [Part 5: Start the dashboard](#part-5-start-the-dashboard-10-min)
- [Part 6: Log in and use the ERP](#part-6-log-in-and-use-the-erp-20-min)
- [Part 7: Publish on GitHub](#part-7-publish-on-github-20-min)
- [Part 8: Make it your own and next steps](#part-8-make-it-your-own-and-next-steps)
- [Troubleshooting](#-troubleshooting)
- [Daily cheat-sheet](#-daily-cheat-sheet)

---

## Part 0: What you are building (read first)

```
┌────────────────────────────────────┐
│ 1. DASHBOARD (Python + Streamlit)  │  log-in screen, pages, charts, forms, buttons
│    app/                            │  → pages appear according to your PERMISSIONS
└─────────────────┬──────────────────┘
                  │ SQL
┌─────────────────▼──────────────────┐
│ 2. BUSINESS RULES (inside Postgres)│  90 functions + 59 triggers: bcrypt log-in & lock-out,
│    database/modules/20-23          │  payroll (PAYE, NSSA, ZIMDEF), VAT returns, IFRS 16 leases,
│                                    │  depreciation, IFRS 18 statements, "journals must balance"…
├────────────────────────────────────┤
│ 3. DATA (PostgreSQL)               │  120 tables: 6 offices, 16 departments, 169 staff,
│    database/modules/00-19          │  clients, projects, timesheets, invoices, assets,
│                                    │  leases, tax returns, messages, users & roles …
└────────────────────────────────────┘
```

**The company in the demo data:** Maxhub Pvt Ltd is a large forensic-audit, data-analytics, cyber, risk,
tax and advisory firm. It **owns** Maxhub House in Harare (part of it is let to tenants), an office building in
Bulawayo and a plot of land for a future campus, and it **rents** offices in Johannesburg, Nairobi, London
and Dubai. It prepares **IFRS** financial statements (IFRS 18 early-adopted) and pays tax to **ZIMRA**, **NSSA**
and **ZIMDEF** (plus SARS, KRA, HMRC and the UAE FTA for its branches). The data covers **January 2025 –
24 September 2026**; August 2026 is the last closed month.

**Words you will see:**

| Word | Meaning |
|---|---|
| **PostgreSQL** | Free database software. It stores all the ERP data. |
| **SQL** | The language used to talk to the database (`SELECT * FROM erp.clients`). |
| **pgAdmin** | A program for looking inside PostgreSQL with a mouse (installs with PostgreSQL). |
| **Python / Streamlit** | The language and library the dashboard is written in. |
| **bcrypt** | A slow, salted way of storing passwords so they can't be read even if the database is stolen. |
| **Role / permission** | A role (e.g. *Accountant*) is a bundle of permissions (e.g. *page.billing*, *invoice.issue*). |
| **Terminal** | A window where you type commands (Command Prompt / PowerShell / VS Code terminal). |
| **Git / GitHub** | Version control / the website where your project is shown to the world. |

---

## Part 1: Install the tools (30 min)

### 1.1 PostgreSQL (the database)

1. Go to **https://www.postgresql.org/download/windows/** → **Download the installer** (EDB) → latest **17.x**, **Windows x86-64**.
2. Run the installer, clicking **Next**. Watch for:
   - **Components:** leave all ticked (Server, **pgAdmin 4**, Command Line Tools).
   - **Password** for the `postgres` superuser. 🔴 **Write it down.**
   - **Port:** leave **5432**. **Locale:** default.
3. Untick "Launch Stack Builder" → **Finish**.

✅ **Check:** ⊞ key → type **pgAdmin 4** → open it.

### 1.2 Python (runs the dashboard)

1. **https://www.python.org/downloads/** → **Python 3.12.x** (or 3.13.x).
2. 🔴 On the first screen tick **"Add python.exe to PATH"** → **Install Now**.

✅ **Check:** open **Command Prompt** (⊞ → `cmd`) → `python --version` → `Python 3.12.x`.

### 1.3 Git

**https://git-scm.com/download/win** → 64-bit installer → Next, Next… (defaults are fine).
✅ **Check:** reopen Command Prompt → `git --version`.

### 1.4 Visual Studio Code

**https://code.visualstudio.com/** → install (tick **"Add 'Open with Code' action"**) → Extensions → install **Python** (Microsoft).

### 1.5 GitHub account

**https://github.com/signup** – choose a professional username.

---

## Part 2: Put the project on your computer (5 min)

1. Download **`maxhub-erp.zip`**.
2. Create **`C:\Projects`** → right-click the zip → **Extract All…** → `C:\Projects`.
3. You should have **`C:\Projects\maxhub-erp`** containing `app`, `database`, `docs`, `scripts`, `README.md` …
   (Not `C:\Projects\maxhub-erp\maxhub-erp` – if so, move the inner folder up.)
4. Right-click the folder → **Open with Code** → **"Yes, I trust the authors"**.

---

## Part 3: Create the database (10 min)

The whole ERP is **one file: `database\maxhub_erp.sql`** (about 7,600 lines). It is *built* from the readable
modules in `database\modules\` (see Part 4). Loading it takes about **20–60 seconds**.

### ✅ Option A: manual commands (recommended – works even if Avast blocks `.bat` files)

Open **Command Prompt** and type (change `17` if you installed another version):

```bat
cd C:\Projects\maxhub-erp
set PATH=%PATH%;C:\Program Files\PostgreSQL\17\bin
set PGCLIENTENCODING=UTF8
psql -U postgres -h localhost -c "CREATE DATABASE maxhub_erp;"
psql -U postgres -h localhost -d maxhub_erp -v ON_ERROR_STOP=1 -q -f database\maxhub_erp.sql
```

Each `psql` line asks for your **postgres password** (nothing appears while you type – that's normal).
A message *"database maxhub_erp already exists"* is fine. Lines saying `NOTICE` are fine.

### Option B: double-click `scripts\setup_database.bat`

If Windows says *"Windows protected your PC"* → **More info → Run anyway**. Type your password when asked and
wait for **SUCCESS**. (If Avast removes the file, use Option A.)

### Option C: pgAdmin (with the mouse)

1. pgAdmin → **Servers → PostgreSQL 17** → right-click **Databases → Create → Database…** → `maxhub_erp` → **Save**.
2. Click **maxhub_erp** → **Tools → Query Tool** → 📂 **Open File** → `C:\Projects\maxhub-erp\database\maxhub_erp.sql`.
3. Press **F5**. Wait for *"Query returned successfully"* (up to a minute).

### ✅ Check it worked

In the Query Tool on `maxhub_erp`:
```sql
SELECT legal_name, trading_name FROM erp.firm_settings;
SELECT COUNT(*) FROM erp.employees;                              -- 169
SELECT SUM(debit) - SUM(credit) FROM erp.fn_trial_balance(CURRENT_DATE);   -- 0.00 = the books balance
SELECT * FROM erp.fn_login('blessing.marufu', 'Maxhub@2026');    -- status = ok
```

> 💡 The script **deletes and rebuilds** the `erp` schema each time. Great for resetting the demo – but
> **never run it again once you hold real data**.

---

## Part 4: Look inside the database (20 min)

In pgAdmin expand **maxhub_erp → Schemas → erp**: **Tables (120)**, **Views (22)**, **Functions (90)**.

In VS Code open **`database\modules\`** – one file per module:

| Files | What's inside |
|---|---|
| `00`–`14` | Core tables: reference data, chart of accounts (with IFRS mapping), offices, HR & payroll, security, CRM, contracts, projects, billing, time & expense, procurement, general ledger |
| `15_fixed_assets.sql` | IAS 16 / IAS 38 / IAS 40 asset register, valuations, disposals, maintenance, insurance |
| `16_leases_borrowings.sql` | IFRS 16 leases and schedules, the CBZ mortgage loan |
| `17_tax_compliance.sql` | ZIMRA/NSSA/ZIMDEF tax types, statutory rates, PAYE tables, returns, ITF263, WHT |
| `18_communications.sql` | Mailing lists, internal messages, announcements, e-mail outbox, calendar |
| `19_ifrs_reporting.sql` | IFRS 18 MPMs, IFRS 9 ECL matrix, cash-flow classification |
| `20`–`22` | Business logic: rules, **log-in & permissions**, payroll, payables, depreciation, leases, tax |
| `23a/23b` | Reports: views and the **IFRS financial statements** functions |
| `30`–`36` | Demo data (reference, 169 staff, assets, clients & projects, timesheets, 21 months of operations, messages) |

After editing a module, rebuild the single file with: `python database\build.py`

Try these (highlight one and press **F5**):

```sql
-- IFRS 18 income statement for 2026 to date (see "Operating profit" and "Profit before financing and income taxes")
SELECT caption, amount FROM erp.fn_ifrs_profit_or_loss('2026-01-01', '2026-08-31');

-- Balance sheet and cash-flow statement
SELECT section, caption, amount FROM erp.fn_ifrs_financial_position('2026-08-31');
SELECT caption, amount FROM erp.fn_ifrs_cash_flows('2026-01-01', '2026-08-31');

-- ZIMRA PAYE on USD 1,500 of taxable income this month
SELECT erp.fn_calc_paye(1500, CURRENT_DATE);

-- Who can do what?
SELECT username, department, roles FROM erp.v_user_access WHERE username IN ('blessing.marufu', 'kudakwashe.banda');

-- Tax deadlines
SELECT return_number, tax_name, due_date, amount_due, status FROM erp.v_tax_calendar ORDER BY due_date DESC LIMIT 10;
```

**See the security rules work.** Passwords are never stored in plain text:
```sql
SELECT username, left(password_hash, 20) || '…' AS bcrypt_hash FROM erp.app_users LIMIT 3;
SELECT * FROM erp.fn_login('kudakwashe.banda', 'wrong-password');   -- "4 attempt(s) left"
```

**See a business rule refuse bad data** – try to change an *approved* timesheet:
```sql
INSERT INTO erp.time_entries (timesheet_id, work_date, hours)
SELECT timesheet_id, week_start_date, 2 FROM erp.timesheets WHERE status = 'approved' LIMIT 1;
```
→ **"Timesheet … is approved - entries are locked"**. Or post into a closed month:
```sql
SELECT erp.fn_post_journal('2026-05-31', 'test', 'manual', NULL,
       '[{"acc":"6900","dr":10},{"acc":"1010","cr":10}]');
```
→ **"Fiscal period for 2026-05-31 is closed"**.

---

## Part 5: Start the dashboard (10 min)

### ✅ Option A: manual commands (recommended)

In VS Code: **Terminal → New Terminal**, then one line at a time:

```bat
cd C:\Projects\maxhub-erp
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt
copy .env.example .env
notepad .env
```
In Notepad change `DB_PASSWORD=your_postgres_password_here` to your real password → **Save** → close. Then:
```bat
.venv\Scripts\python -m streamlit run app\app.py
```
Your browser opens at **http://localhost:8501**. Keep the terminal open; **Ctrl+C** stops it.

Next time you only need:
```bat
cd C:\Projects\maxhub-erp
.venv\Scripts\python -m streamlit run app\app.py
```

### Option B: double-click `scripts\run_dashboard.bat`

It does all of the above automatically (first run takes 2–5 minutes).

| Command | Purpose |
|---|---|
| `python -m venv .venv` | A private Python folder for this project |
| `pip install -r requirements.txt` | Installs Streamlit, pandas, Plotly, SQLAlchemy, psycopg2 … |
| `copy .env.example .env` | Your personal settings file (holds your DB password – Git ignores it) |
| `streamlit run app\app.py` | Starts the web dashboard |

---

## Part 6: Log in and use the ERP (20 min)

Everyone must **log in first**. Username = `firstname.lastname`, or the company e-mail
`firstname.lastname@maxhub.co.zw`. **Demo password for every user: `Maxhub@2026`.**

| Username | Person | Department → roles | Pages they see |
|---|---|---|---|
| `tendai.moyo` | Managing Partner & CEO | Executive → EXECUTIVE | All business pages |
| `blessing.marufu` | Chief Financial Officer | Finance → FINANCE_MANAGER, ACCOUNTANT | Billing, GL, IFRS statements, Tax, Assets, Leases, Payroll |
| `memory.nkomo` | Tax Compliance Manager | Finance → + TAX_OFFICER | Tax (ZIMRA/NSSA) + finance |
| `chipo.sibanda` | HR Director | HR → HR_MANAGER | People & leave, Payroll |
| `tawanda.gumbo` | IT Manager | IT → **ADMIN** | Everything incl. Users & security |
| `nyasha.mutasa` | Manager, Forensic Audit | Forensic → PROJECT_MANAGER | Projects, approvals, CRM |
| `kudakwashe.banda` | Consultant | Forensic → CONSULTANT | Home, timesheets, expenses, leave, messages |
| `tapiwa.mlambo` | Facilities Manager | Facilities → FACILITIES | Fixed assets, leases |
| `munyaradzi.mandaza` | Head of Internal Audit | Internal Audit → AUDITOR | Read-only finance + audit trail |

Every other employee can log in too – find usernames on **Messages & notices → Staff directory**.
Roles are given **automatically from the department and grade**; move someone to another department and
their access changes by itself.

### A full business cycle

| # | Log in as | Page | Do this |
|---|---|---|---|
| 1 | `kudakwashe.banda` | Timesheets | This week already has hours. Add Friday: project **P25-005**, 8 h → **Add entry** → **Submit timesheet** |
| 2 | `nyasha.mutasa` | Timesheets → Approvals | Approve Kudakwashe's week |
| 3 | `blessing.marufu` | Billing → Create invoice | Project **P25-005**, period 1–30 Sep → **Create draft** → **Issue & post** (it gets a ZIMRA FDMS fiscal number) |
| 4 | `blessing.marufu` | Billing → Receive payment | Record the client's payment |
| 5 | `chipo.sibanda` | Payroll | Approve the September draft runs (PAYE, AIDS levy, NSSA, ZIMDEF are calculated) |
| 6 | `memory.nkomo` | Tax (ZIMRA / NSSA) | Pay the August **VAT7** (due 25 Sep) → **Pay now** |
| 7 | `blessing.marufu` | Financial statements | See the IFRS 18 P&L, balance sheet, cash flows, MPM note |
| 8 | `tawanda.gumbo` | Users & security | Look at log-in history, reset a password, see the permissions matrix |

### Try the security features
- Type a wrong password 5 times → the account **locks for 15 minutes** (IT can unlock it in *Users & security*).
- As `tawanda.gumbo`, reset someone's password → they must choose a new one at next log-in
  (the database refuses weak passwords and your last 5 passwords).
- Log in as `kudakwashe.banda` → notice there is **no Billing, Tax or Admin** in the menu.

---

## Part 7: Publish on GitHub (20 min)

### 7.1 Tell Git who you are (once)
```bat
git config --global user.name "Your Full Name"
git config --global user.email "the-email-you-used-on-github@example.com"
```

### 7.2 Personalise
Edit the bottom of **`README.md`** (your name, LinkedIn). 🔴 `.env` must be in `.gitignore` (it is).

### 7.3 Create the local repository
```bat
cd C:\Projects\maxhub-erp
git init
git add .
git status
```
✅ You should see `app/`, `database/`, `docs/`, `scripts/` … ❌ You must **not** see `.env` or `.venv/`.
```bat
git commit -m "Maxhub enterprise ERP: PostgreSQL (IFRS 18, ZIMRA/NSSA, IFRS 16, RBAC log-in) + Streamlit dashboard"
```

### 7.4 Create the repository on GitHub
**github.com → + → New repository** → name `maxhub-erp` → description
`Enterprise ERP for a forensic & data-analytics consultancy: PostgreSQL (IFRS 18 statements, ZIMRA/NSSA tax, IFRS 16 leases, bcrypt login & role-based access) + Python/Streamlit dashboard`
→ **Public** → 🔴 do **not** add README/.gitignore/licence → **Create**.

### 7.5 Push
```bat
git remote add origin https://github.com/YOUR-USERNAME/maxhub-erp.git
git branch -M main
git push -u origin main
```
Sign in with your browser when asked.

**Already published the earlier version?** Just commit the new version on top:
```bat
cd C:\Projects\maxhub-erp
git add -A
git commit -m "Rebuild: enterprise schema, IFRS 18 reporting, ZIMRA/NSSA tax, assets, leases, login & RBAC"
git push
```

### 7.6 Make it shine
Topics: `erp`, `postgresql`, `plpgsql`, `ifrs`, `accounting`, `streamlit`, `python`, `rbac`, `zimbabwe`, `portfolio`. Pin the repo on your profile and add it to your CV/LinkedIn.

### 7.7 Every change later
```bat
git add .
git commit -m "Describe what you changed"
git push
```

---

## Part 8: Make it your own and next steps

**Put it online (free):** follow **[DEPLOY_ONLINE.md](DEPLOY_ONLINE.md)** (Neon database + Streamlit Community Cloud).

**Demo mode:** the demo database protects the 9 shared demo log-ins (their passwords can't be changed and they
never lock). For your own private copy switch it off in the Query Tool:
`UPDATE erp.security_policy SET demo_mode = FALSE;`

**Real company details** (Query Tool):
```sql
UPDATE erp.firm_settings SET registration_number = '…', zimra_tin = '…', vat_number = '…',
       nssa_employer_number = '…', address = '…', phone = '…', email = 'info@yourdomain.co.zw';
```

**Tax rates change?** No code changes needed – update `erp.statutory_rates` and `erp.paye_tax_bands`
(e.g. a new NSSA ceiling). Always confirm figures with current ZIMRA and NSSA public notices.

**Install without demo data:** `python database\build.py --schema` creates `database\maxhub_erp_schema.sql`
(schema + logic only). You'll then need your own reference data (currencies, chart of accounts, roles …) –
copy what you need from `database\modules\30_seed_reference.sql`.

**Portfolio ideas:**
1. ⭐ Add a chart (e.g. revenue by client) to the Firm dashboard.
2. ⭐⭐ PDF payslips / invoices with `reportlab`.
3. ⭐⭐ Two-factor log-in (TOTP) – the `mfa_enabled` / `mfa_secret` columns are already there.
4. ⭐⭐⭐ Host it: database on **Neon** or **Supabase**, app on **Streamlit Community Cloud** – then add a "Live demo" link.

---

## 🛠️ Troubleshooting

| Problem | Fix |
|---|---|
| Avast deleted / blocked a `.bat` file | Use the manual commands (Option A in Parts 3 and 5), or add `C:\Projects` as an exception in Avast → *Settings → Exceptions*. |
| `python` not recognised / Microsoft Store opens | Reinstall Python with **"Add python.exe to PATH"**; ⊞ → *Manage app execution aliases* → turn **off** the python aliases. |
| `psql` not recognised | Run `set PATH=%PATH%;C:\Program Files\PostgreSQL\17\bin` in that window first. |
| `extension "pgcrypto" is not available` | Your PostgreSQL install is missing its extensions – reinstall PostgreSQL with the EDB installer (it includes pgcrypto). |
| Log-in says *"Incorrect username or password"* | Password is `Maxhub@2026` (capital M). Use `firstname.lastname`. |
| *"Account locked…"* | Wait 15 minutes, or log in as `tawanda.gumbo` → Users & security → **Unlock account**. |
| *"Cannot connect … password authentication failed"* | The password in `.env` is wrong. Fix, save, refresh. |
| *"Connection refused"* | ⊞ → *Services* → **postgresql-x64-17** → **Start**. |
| *"ERP schema is missing"* | Load `database\maxhub_erp.sql` (Part 3). |
| *"Fiscal period … is closed"* | Months up to Aug 2026 are closed (as in a real audited company). Use a September date. |
| Port 8501 busy | Close the other dashboard window, or add `--server.port 8502`. |
| Broke the demo data | Re-run the Part 3 commands – everything is rebuilt. |
| `git push` rejected ("fetch first") | `git pull origin main --allow-unrelated-histories`, then `git push`. |
| Committed `.env` by mistake | Change your DB password, `git rm --cached .env`, commit, push. |

---

## 📋 Daily cheat-sheet

| I want to… | Do this |
|---|---|
| Start the ERP | `cd C:\Projects\maxhub-erp` → `.venv\Scripts\python -m streamlit run app\app.py` |
| Log in | http://localhost:8501 → `firstname.lastname` / `Maxhub@2026` |
| Stop the ERP | Ctrl+C in the terminal |
| Reset the demo data | `psql -U postgres -h localhost -d maxhub_erp -q -f database\maxhub_erp.sql` |
| Rebuild the SQL after editing a module | `python database\build.py` |
| Save my work to GitHub | `git add .` → `git commit -m "message"` → `git push` |
