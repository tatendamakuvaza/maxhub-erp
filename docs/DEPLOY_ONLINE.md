# 🌍 Put Maxhub ERP online (free) — step by step for Windows

This guide puts your ERP on the internet so anyone can open it with a link like
**https://maxhub-erp.streamlit.app** — no installing, works on phones too.

| Part | What | Where it runs | Cost |
|---|---|---|---|
| **Back end** | PostgreSQL database (all the data, logins, tax & accounting logic) | **Neon** (neon.tech) | Free, no bank card |
| **Front end** | The Streamlit app (pages, charts, forms) | **Streamlit Community Cloud** (share.streamlit.io) | Free, no bank card |

```
 Visitor's browser  ──►  Streamlit Community Cloud  ──►  Neon PostgreSQL
 (phone / laptop)        runs app/app.py from GitHub      database "neondb", schema "erp"
```

⏱️ About **45 minutes** the first time. You need: your GitHub account, the project folder on your PC
(`C:\Users\Admin\Desktop\maxhub-erp\maxhub-erp`), and PostgreSQL installed on your PC (you already have it —
we only use its `psql` tool to send the data to Neon).

**Free-plan facts (good to know)**
- The Neon database **sleeps after 5 minutes** without visitors; the next visitor waits a few seconds while it wakes.
- The Streamlit app **sleeps after about 12 hours** without visitors; a visitor then sees
  *"This app has gone to sleep"* → clicks **"Yes, get this app back up!"** → about 1 minute.
- Neon free storage is 0.5 GB; the Maxhub database uses about **45 MB**.

---

## Part 1 — Update your GitHub project (5 min)

The project was updated for online use (single connection string, public-demo protection, this guide).

1. Download the new **maxhub-erp.zip** → right-click → **Extract All** → e.g. `C:\Users\Admin\Downloads\maxhub-new`.
2. Open the extracted folder until you see `README.md`, `app`, `database` … → press **Ctrl + A** → **Ctrl + C**.
3. Open `C:\Users\Admin\Desktop\maxhub-erp\maxhub-erp` → **Ctrl + V** → choose **"Replace the files in the destination"**.
   (Your `.env` and `.venv` are not in the zip, so they are left alone.)
4. In **PowerShell**:
   ```powershell
   cd "C:\Users\Admin\Desktop\maxhub-erp\maxhub-erp"
   git add .
   git status
   git commit -m "Prepare for online hosting (Neon + Streamlit Cloud)"
   git push
   ```
   ✅ `git status` must **not** list `.env`.

---

## Part 2 — Create the online database on Neon (10 min)

1. Go to **https://neon.tech** → **Sign up** → **Continue with GitHub** (easiest) → approve.
2. **Create project**:
   - **Project name:** `maxhub-erp`
   - **Postgres version:** 17
   - **Region:** **AWS US East (N. Virginia)** ← important: Streamlit's servers are in the USA, and the app talks
     to the database many times per page, so they must be close to *each other* (not to you).
   - Click **Create project**.
3. On the project dashboard click **Connect** (top right). In the window:
   - **Database:** `neondb` · **Role:** `neondb_owner`
   - Switch **Connection pooling** **OFF** (the app also fixes this automatically, but OFF is cleaner).
   - Click **Show password**, then **Copy snippet**. It looks like:
     ```
     postgresql://neondb_owner:AbC123xyz@ep-cool-name-a1b2c3d4.us-east-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require
     ```
   - Paste it into **Notepad** for now. 🔴 This is a password — never put it in GitHub, WhatsApp or screenshots.

---

## Part 3 — Send the Maxhub data to Neon (10 min)

1. Find your PostgreSQL version folder:
   ```powershell
   dir "C:\Program Files\PostgreSQL"
   ```
   You will see a number such as `17` (use your number below if it is different).
2. Load the database — replace `PASTE-YOUR-NEON-CONNECTION-STRING` with the string from Notepad
   (keep the double quotes around it):
   ```powershell
   cd "C:\Users\Admin\Desktop\maxhub-erp\maxhub-erp"
   $env:PGCLIENTENCODING="UTF8"
   & "C:\Program Files\PostgreSQL\17\bin\psql.exe" "PASTE-YOUR-NEON-CONNECTION-STRING" -v ON_ERROR_STOP=1 -f database\maxhub_erp.sql
   ```
   - The `&` at the start is needed in PowerShell.
   - It takes **5–10 minutes** from Zimbabwe (the file is sent one command at a time across the internet).
   - Lines starting with `NOTICE:` are normal. It is finished when you get the `PS C:\...>` prompt back.
   - ❌ If you see `ERROR:`, stop and send a screenshot.
3. Check it worked: in Neon open **SQL Editor** (left menu) and run:
   ```sql
   SELECT COUNT(*) FROM erp.employees;
   ```
   ✅ Answer: **169**.

---

## Part 4 — Put the app online with Streamlit Community Cloud (10 min)

1. Go to **https://share.streamlit.io** → **Continue with GitHub** → approve (allow access to your repositories).
2. Click **Create app** (top right) → **"Yup, I have an app"** / **Deploy a public app from GitHub**.
3. Fill in:
   | Field | Value |
   |---|---|
   | Repository | `tatendamakuvaza/maxhub-erp` |
   | Branch | `main` |
   | Main file path | `app/app.py` |
   | App URL (optional) | `maxhub-erp` → **maxhub-erp.streamlit.app** (choose another name if taken) |
4. Click **Advanced settings**:
   - **Python version:** `3.12`
   - **Secrets:** paste this **one line** (with your Neon string inside the quotes):
     ```toml
     DATABASE_URL = "postgresql://neondb_owner:AbC123xyz@ep-cool-name-a1b2c3d4.us-east-1.aws.neon.tech/neondb?sslmode=require&channel_binding=require"
     ```
   - Click **Save**.
5. Click **Deploy**. Wait 2–5 minutes while it installs (you can watch the log on the right).
6. The Maxhub log-in page appears with a blue **Public demo** box. Log in as `tendai.moyo` / `Maxhub@2026`. 🎉

**Share your link** — put it in your GitHub README, CV and LinkedIn.

---

## Part 5 — Add the live link to your GitHub page (2 min)

1. On your repository page, click the ⚙️ next to **About** → **Website** → paste your
   `https://….streamlit.app` link → **Save changes**.
2. Optional: open `README.md` on GitHub → ✏️ (edit) → replace `https://YOUR-APP.streamlit.app` near the top
   with your link → **Commit changes**. Then on your PC run `git pull` so your copy has the same change.

---

## How the public demo is protected

Strangers share the same 9 demo log-ins, so the database runs in **demo mode**
(`erp.security_policy.demo_mode = TRUE`, see `database/modules/25_demo_mode.sql`):

| Visitors CAN | Visitors CANNOT (blocked by the database) |
|---|---|
| Use every page their role allows, enter timesheets, approve, invoice, post journals, run payroll… | Change the password, username, e-mail or active status of the 9 demo accounts |
| Reset passwords / disable logins of the **other 160** staff (to try the admin features) | Lock the demo accounts with wrong passwords (they never lock) |
| | Remove the demo accounts' roles, or terminate / move / re-grade those employees |
| | Change the security policy |

**Reset the demo** (wipe visitors' changes) at any time by running the Part 3 command again.

---

## Updating the online app later

Change code on your PC → test locally → then:
```powershell
cd "C:\Users\Admin\Desktop\maxhub-erp\maxhub-erp"
git add .
git commit -m "What I changed"
git push
```
Streamlit Cloud notices the push and updates the online app within a minute.
If you changed files in `database/`, also re-run the Part 3 command so Neon gets the new database.

---

## Later: using it for a real company (private)

The free demo set-up is **not** suitable for real staff or payroll data. When you are ready:
1. **Private hosting:** paid, always-on hosting for the app and database (e.g. Neon Launch + Render/Railway,
   or a server in Zimbabwe/South Africa) with daily backups.
2. **Data protection:** payroll, IDs and bank details are personal data under Zimbabwe's
   **Cyber and Data Protection Act [Chapter 12:07]** — restrict access, keep backups, register with POTRAZ if required.
3. **Switch off demo mode** and remove the demo log-in list (the log-in page hides it automatically):
   ```sql
   UPDATE erp.security_policy SET demo_mode = FALSE;
   ```
4. **Load real data instead of the demo data** (real staff, clients, opening balances) and give every person
   their own password (the app forces a change at first log-in).
5. Make the GitHub repository **private** if it will contain company-specific changes.

Ask for help with this step when you get there — it is a separate project.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `psql.exe` *not recognized* / *cannot find the path* | Check the version number with `dir "C:\Program Files\PostgreSQL"` and use it in the path. |
| `password authentication failed` | You copied the string without the real password. In Neon → Connect → **Show password** → copy again. |
| `SSL` / `channel binding` error while loading | Update PostgreSQL on your PC, or remove `&channel_binding=require` from the end of the string. |
| App shows **"Cannot connect to PostgreSQL"** | Wait 30 s (Neon waking up) and refresh. Then check **⋮ → Settings → Secrets** on share.streamlit.io: one line, `DATABASE_URL = "…"`, straight double quotes. |
| App shows **"ERP schema is missing"** | Part 3 didn't finish — run it again. |
| **"This app has gone to sleep"** | Normal on the free plan — click **"Yes, get this app back up!"**. |
| Deploy log shows `ModuleNotFoundError` | Make sure `requirements.txt` is in the top folder of your GitHub repository (it is, if Part 1 was done). |
| Someone messed up the demo data | Re-run the Part 3 command (≈10 min) — everything is restored. |
| I leaked the connection string | Neon → **Branches** → `main` → **Roles & Databases** → `neondb_owner` → **Reset password** → put the new string in the Streamlit secret. |
