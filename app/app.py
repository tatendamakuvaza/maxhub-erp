"""
Maxhub ERP - main entry point.

Start the dashboard from the project folder with:
    python -m streamlit run app/app.py

Everyone must LOG IN first. What you can see afterwards depends on your
department and grade (roles -> permissions, stored in the database).
"""
from pathlib import Path

import streamlit as st

import auth
from db import check_connection, scalar

ASSETS = Path(__file__).parent / "assets"
st.set_page_config(page_title="Maxhub ERP", page_icon=str(ASSETS / "favicon.png"), layout="wide")

# ------------------------------------------------------------------ database check
ok, error = check_connection()
if not ok:
    st.image(str(ASSETS / "maxhub_logo.png"), width=260)
    st.error(error)
    st.markdown("""
**How to fix this**
1. Make sure PostgreSQL is running (Windows: *Services* → `postgresql-x64-17` → *Running*).
2. Check the settings in your **`.env`** file (copy `.env.example` → `.env` and put your password in).
3. Make sure you created the database and ran **`database/maxhub_erp.sql`**
   (see the guide: *docs/STEP_BY_STEP_GUIDE.md*).
4. Refresh this page.
""")
    st.stop()


# ------------------------------------------------------------------ log-in screen
def login_page():
    left, mid, right = st.columns([1, 1.1, 1])
    with mid:
        a, b, c = st.columns([1, 1.4, 1])
        b.image(str(ASSETS / "maxhub_logo.png"), width="stretch")
        st.markdown("<h3 style='text-align:center;margin-top:0'>Sign in to Maxhub ERP</h3>", unsafe_allow_html=True)
        notice = st.session_state.pop("login_notice", None)
        if notice:
            st.info(notice)
        with st.form("login", border=True):
            username = st.text_input("Username or company e-mail", placeholder="firstname.lastname")
            password = st.text_input("Password", type="password")
            submitted = st.form_submit_button("Log in", type="primary", width="stretch", icon=":material/login:")
        if submitted:
            if not username or not password:
                st.warning("Enter your username and password.")
            else:
                success, message = auth.login(username, password)
                if success:
                    st.rerun()
                st.error(message)
        st.caption("🔒 Passwords are checked by the database using bcrypt. Accounts lock for 15 minutes after "
                   "5 wrong attempts. Forgot your password? E-mail itsupport@maxhub.co.zw.")
        with st.expander("Demo accounts (portfolio version) - password for all: Maxhub@2026"):
            st.markdown("""
| Username | Who | What they can see |
|---|---|---|
| `tendai.moyo` | Managing Partner & CEO | Everything except admin (executive) |
| `blessing.marufu` | Chief Financial Officer | Finance, billing, IFRS statements, tax, assets, leases, payroll |
| `memory.nkomo` | Tax Compliance Manager | ZIMRA / NSSA returns + finance |
| `chipo.sibanda` | HR Director | People, leave, payroll |
| `tawanda.gumbo` | IT Manager | **Administrator** - users, roles, audit log |
| `nyasha.mutasa` | Manager, Forensic Audit | Projects, approvals, CRM |
| `kudakwashe.banda` | Consultant | Own timesheets, expenses, leave, messages |
| `tapiwa.mlambo` | Facilities Manager | Fixed assets & leases |
| `munyaradzi.mandaza` | Head of Internal Audit | Read-only finance + audit trail |
""")


def change_password_page():
    st.title(":material/key: Choose a new password")
    st.info("For security you must set your own password before continuing.")
    from views.account import password_form   # re-use the form from the Account page
    password_form(forced=True)


# ------------------------------------------------------------------ router
if not auth.is_logged_in():
    st.navigation([st.Page(login_page, title="Log in", icon=":material/login:")], position="hidden").run()
    st.stop()

st.logo(str(ASSETS / "maxhub_sidebar.png"), icon_image=str(ASSETS / "maxhub_icon.png"), size="large")

if st.session_state.get("must_change_password"):
    st.navigation([st.Page(change_password_page, title="Change password", icon=":material/key:")], position="hidden").run()
    st.stop()

# ------------------------------------------------------------------ sidebar: who is logged in
firm = scalar("SELECT COALESCE(trading_name, legal_name) FROM firm_settings") or "Maxhub"
unread = scalar("SELECT COUNT(*) FROM message_recipients WHERE recipient_id = :e AND read_at IS NULL AND NOT is_archived",
                {"e": st.session_state["employee_id"]}) or 0
with st.sidebar:
    st.caption(f"**{firm}**")
    with st.container(border=True):
        st.markdown(f"**{st.session_state['employee_name']}**  \n{st.session_state['job_title']}  \n"
                    f":small[{st.session_state['department']} · {st.session_state['office']}]")
        st.caption("Roles: " + ", ".join(r.replace("_", " ").title() for r in st.session_state["roles"] if r != "EMPLOYEE"))
        if unread:
            st.caption(f"📬 {unread} unread message(s)")
        if st.button("Log out", icon=":material/logout:", width="stretch"):
            auth.logout()
            st.rerun()

# ------------------------------------------------------------------ navigation (only what you may see)
P = st.Page
sections = {
    "My workspace": [
        (None,             P("views/home.py",       title="Home",                 icon=":material/home:", default=True)),
        ("page.comms",     P("views/comms.py",      title="Messages & notices",   icon=":material/mail:")),
        (None,             P("views/account.py",    title="My account",           icon=":material/manage_accounts:")),
    ],
    "Overview": [
        ("page.dashboard", P("views/dashboard.py",  title="Firm dashboard",       icon=":material/space_dashboard:")),
    ],
    "Delivery": [
        ("page.projects",   P("views/projects.py",   title="Projects",   icon=":material/folder_open:")),
        ("page.timesheets", P("views/timesheets.py", title="Timesheets", icon=":material/schedule:")),
        ("page.expenses",   P("views/expenses.py",   title="Expenses",   icon=":material/receipt_long:")),
    ],
    "Sales & Finance": [
        ("page.crm",     P("views/crm.py",     title="Clients & CRM",          icon=":material/handshake:")),
        ("page.billing", P("views/billing.py", title="Billing",                icon=":material/request_quote:")),
        ("page.finance", P("views/finance.py", title="General ledger",         icon=":material/account_balance:")),
        ("page.reports", P("views/reports.py", title="Financial statements",   icon=":material/summarize:")),
        ("page.tax",     P("views/tax.py",     title="Tax (ZIMRA / NSSA)",     icon=":material/gavel:")),
    ],
    "Assets & Property": [
        ("page.assets", P("views/assets.py", title="Fixed assets",    icon=":material/inventory_2:")),
        ("page.leases", P("views/leases.py", title="Leases & loans",  icon=":material/real_estate_agent:")),
    ],
    "People": [
        ("page.people",  P("views/people.py",  title="People & leave", icon=":material/groups:")),
        ("page.payroll", P("views/payroll.py", title="Payroll",        icon=":material/payments:")),
    ],
    "Administration": [
        ("page.admin", P("views/admin.py", title="Users & security", icon=":material/admin_panel_settings:")),
    ],
}
pages = {}
for section, items in sections.items():
    allowed = [page for perm, page in items if perm is None or auth.can(perm)]
    if allowed:
        pages[section] = allowed
st.navigation(pages, expanded=True).run()
