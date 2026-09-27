"""Users & security - accounts, roles & permissions, department rules, log-in history, audit trail, policy."""
import pandas as pd
import streamlit as st

from auth import can, require
from db import query, run_action, scalar
from ui import page_header, table

require("page.admin")
me_user = st.session_state["app_user_id"]
page_header(":material/admin_panel_settings: Users & security", "Who can log in, what they can do, and who did what")

c1, c2, c3, c4 = st.columns(4)
c1.metric("Active users", scalar("SELECT COUNT(*) FROM app_users WHERE is_active"), border=True)
c2.metric("Sessions open now", scalar("SELECT COUNT(*) FROM user_sessions WHERE revoked_at IS NULL AND expires_at > now()"), border=True)
c3.metric("Locked accounts", scalar("SELECT COUNT(*) FROM app_users WHERE locked_until > now()"), border=True)
c4.metric("Failed log-ins (7 days)", scalar("SELECT COUNT(*) FROM login_attempts WHERE NOT success AND attempted_at > now() - INTERVAL '7 days'"),
          border=True)

tabs = st.tabs(["👤 Users", "🛡️ Roles & permissions", "🏢 Department rules", "🔐 Log-in history", "📜 Audit trail", "⚙️ Security policy", "➕ New login"])

# ------------------------------------------------------------------ users
with tabs[0]:
    users = query("SELECT * FROM v_user_access ORDER BY department, full_name")
    q = st.text_input("🔎 Search users")
    view = users if not q else users[users.apply(lambda r: q.lower() in " ".join(map(str, r.values)).lower(), axis=1)]
    table(view[["username", "full_name", "department", "grade", "roles", "is_active", "is_locked", "must_change_password",
                "last_login_at", "failed_logins"]], height=380)
    if can("user.manage"):
        uid = st.selectbox("Manage user", users.user_id, format_func=lambda i: f"{users.set_index('user_id').full_name[i]} "
                                                                             f"({users.set_index('user_id').username[i]})")
        u = users.set_index("user_id").loc[uid]
        a, b, c = st.columns(3)
        with a.container(border=True):
            st.markdown("**Reset password**")
            temp = st.text_input("Temporary password", "Welcome@2026!", key="tmp")
            if st.button("Reset & force change"):
                run_action("SELECT fn_admin_reset_password(:a, :t, :p)", {"a": me_user, "t": int(uid), "p": temp},
                           success="Password reset - the user must choose a new one at next log-in.")
        with b.container(border=True):
            st.markdown("**Account status**")
            if u.is_locked and st.button("Unlock account"):
                run_action("SELECT fn_unlock_user(:a, :t)", {"a": me_user, "t": int(uid)}, success="Account unlocked.")
            if int(uid) != me_user:
                if u.is_active and st.button("Disable login", type="secondary"):
                    run_action("""WITH x AS (UPDATE app_users SET is_active = FALSE WHERE user_id = :t RETURNING user_id)
                                  UPDATE user_sessions SET revoked_at = now(), revoke_reason = 'disabled'
                                   WHERE user_id IN (SELECT user_id FROM x) AND revoked_at IS NULL""", {"t": int(uid)}, success="Login disabled.")
                if not u.is_active and st.button("Enable login"):
                    run_action("UPDATE app_users SET is_active = TRUE WHERE user_id = :t", {"t": int(uid)}, success="Login enabled.")
            else:
                st.caption("You cannot disable your own account.")
        with c.container(border=True):
            st.markdown("**Roles**")
            roles = query("SELECT role_id, code FROM roles ORDER BY code")
            add = st.selectbox("Add a manual role", roles.role_id, format_func=lambda i: roles.set_index("role_id").code[i])
            x, y = st.columns(2)
            if x.button("Add role"):
                run_action("INSERT INTO user_roles (user_id, role_id, source, granted_by) VALUES (:u, :r, 'manual', :g) ON CONFLICT DO NOTHING",
                           {"u": int(uid), "r": int(add), "g": me_user}, success="Role added.")
            if y.button("Re-sync from department"):
                run_action("SELECT fn_sync_user_roles(:u)", {"u": int(uid)}, success="Automatic roles refreshed ({result} added).")
            manual = query("""SELECT ur.role_id, r.code FROM user_roles ur JOIN roles r USING (role_id)
                               WHERE ur.user_id = :u AND ur.source = 'manual'""", {"u": int(uid)})
            if not manual.empty:
                rem = st.selectbox("Remove manual role", manual.role_id, format_func=lambda i: manual.set_index("role_id").code[i])
                if st.button("Remove"):
                    run_action("DELETE FROM user_roles WHERE user_id = :u AND role_id = :r AND source = 'manual'",
                               {"u": int(uid), "r": int(rem)}, success="Role removed.")

# ------------------------------------------------------------------ roles matrix
with tabs[1]:
    rp = query("""SELECT r.code AS role, p.code AS permission FROM role_permissions x JOIN roles r USING (role_id) JOIN permissions p USING (permission_id)""")
    if not rp.empty:
        rp["x"] = "✔"
        matrix = rp.pivot_table(index="permission", columns="role", values="x", aggfunc="first").fillna("")
        st.dataframe(matrix, width="stretch", height=520)
    table(query("""SELECT r.code, r.name, r.description, (SELECT COUNT(*) FROM user_roles ur WHERE ur.role_id = r.role_id) AS users
                     FROM roles r ORDER BY r.code"""))

# ------------------------------------------------------------------ department rules
with tabs[2]:
    st.caption("When someone joins or moves department / grade, these rules decide their roles automatically.")
    table(query("""SELECT COALESCE(d.name, '(every department)') AS department, x.min_grade_level, x.max_grade_level, r.code AS role, x.description
                     FROM department_role_rules x JOIN roles r USING (role_id) LEFT JOIN departments d ON d.department_id = x.department_id
                    ORDER BY d.name NULLS FIRST, x.min_grade_level"""), height=500)

# ------------------------------------------------------------------ login history
with tabs[3]:
    only_failed = st.toggle("Only failed attempts")
    la = query(f"""SELECT attempted_at AT TIME ZONE 'Africa/Harare' AS "time (Harare)", username_tried, success, failure_reason,
                          ip_address, user_agent FROM login_attempts {"WHERE NOT success" if only_failed else ""}
                    ORDER BY attempted_at DESC LIMIT 300""")
    table(la, height=450)

# ------------------------------------------------------------------ audit trail
with tabs[4]:
    if not can("audit.view"):
        st.info("You need the audit.view permission.")
    else:
        tables_ = query("SELECT DISTINCT table_name FROM audit_log ORDER BY 1").table_name.tolist()
        pick = st.multiselect("Tables", tables_)
        al = query(f"""SELECT a.changed_at AT TIME ZONE 'Africa/Harare' AS "time (Harare)", a.table_name, a.record_pk, a.action,
                              u.username AS changed_by, a.new_data::TEXT AS new_values
                         FROM audit_log a LEFT JOIN app_users u ON u.user_id = a.changed_by
                        {"WHERE a.table_name = ANY(:t)" if pick else ""} ORDER BY a.audit_id DESC LIMIT 300""", {"t": pick})
        table(al, height=450)
        st.caption("The audit log is append-only: a database trigger blocks any UPDATE or DELETE on it.")

# ------------------------------------------------------------------ policy
with tabs[5]:
    pol = query("SELECT * FROM security_policy").iloc[0]
    with st.form("policy"):
        x, y, z = st.columns(3)
        minlen = x.number_input("Minimum password length", 6, 32, int(pol.min_password_length))
        maxf = y.number_input("Wrong passwords before lock-out", 3, 20, int(pol.max_failed_logins))
        lock = z.number_input("Lock-out minutes", 1, 1440, int(pol.lockout_minutes))
        x, y, z = st.columns(3)
        hist = x.number_input("Password history (no re-use)", 0, 24, int(pol.password_history_count))
        sess = y.number_input("Session length (hours)", 1, 72, int(pol.session_hours))
        age = z.number_input("Password max age (days)", 30, 365, int(pol.password_max_age_days))
        if st.form_submit_button("Save policy", type="primary", disabled=not can("user.manage")):
            run_action("""UPDATE security_policy SET min_password_length = :a, max_failed_logins = :b, lockout_minutes = :c,
                                 password_history_count = :d, session_hours = :e, password_max_age_days = :f""",
                       {"a": minlen, "b": maxf, "c": lock, "d": hist, "e": sess, "f": age}, success="Security policy saved.")
    st.caption(f"Passwords are hashed with bcrypt (cost {int(pol.bcrypt_cost)}) using PostgreSQL's pgcrypto extension.")

# ------------------------------------------------------------------ onboarding
with tabs[6]:
    new = query("""SELECT e.employee_id, e.first_name || ' ' || e.last_name || ' - ' || COALESCE(d.name, '') AS label
                     FROM employees e LEFT JOIN departments d USING (department_id)
                    WHERE e.status <> 'terminated' AND NOT EXISTS (SELECT 1 FROM app_users u WHERE u.employee_id = e.employee_id)
                    ORDER BY e.employee_id DESC""")
    if new.empty:
        st.success("Every employee already has a login.")
    elif can("user.manage"):
        with st.form("onboard"):
            eid = st.selectbox("Employee without a login", new.employee_id, format_func=lambda i: new.set_index("employee_id").label[i])
            temp = st.text_input("Temporary password", "Welcome@2026!")
            if st.form_submit_button("Create login", type="primary"):
                run_action("SELECT fn_create_user_for_employee(:e, :p)", {"e": int(eid), "p": temp},
                           success="Login created - roles were assigned from the department and a welcome e-mail is queued.")
