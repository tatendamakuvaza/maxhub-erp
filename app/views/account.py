"""My account - profile, change password, my permissions, my recent log-ins."""
import streamlit as st
from sqlalchemy.exc import DBAPIError

from db import db_error_message, execute, query


def password_form(forced: bool = False):
    """Change-password form. Rules (length, capitals, numbers, symbols, history) are enforced by the database."""
    with st.form("pwd", clear_on_submit=True):
        current = st.text_input("Current (or temporary) password", type="password")
        new = st.text_input("New password", type="password",
                            help="At least 8 characters with a capital letter, a small letter, a number and a symbol. "
                                 "You cannot re-use your last 5 passwords.")
        again = st.text_input("Repeat new password", type="password")
        if st.form_submit_button("Change password", type="primary", icon=":material/key:"):
            if new != again:
                st.error("The two new passwords are not the same.")
            elif not current or not new:
                st.error("Fill in all three boxes.")
            else:
                try:
                    execute("SELECT fn_change_password(:u, :o, :n)", {"u": st.session_state["app_user_id"], "o": current, "n": new})
                except DBAPIError as e:
                    st.error("⚠️ " + db_error_message(e))
                else:
                    st.session_state["must_change_password"] = False
                    st.session_state["flash"] = "Password changed. Use your new password next time you log in."
                    st.rerun()


if __name__ == "__main__":        # run as a page (not when imported by app.py)
    from ui import page_header, table

    page_header(":material/manage_accounts: My account", "Your login, access rights and security")
    s = st.session_state
    c1, c2 = st.columns(2)
    with c1:
        with st.container(border=True):
            st.markdown(f"**{s['employee_name']}**  \n{s['job_title']}  \n{s['department']} · {s['office']}")
            st.markdown(f"Username: `{s['username']}`  \nCompany e-mail: `{s['email']}`")
            st.markdown("Roles: " + " ".join(f":blue-badge[{r.replace('_', ' ').title()}]" for r in s["roles"]))
        st.subheader("Change password")
        password_form()
    with c2:
        st.subheader("What I can access")
        perms = query("""SELECT p.module, p.code, p.description FROM permissions p
                          WHERE p.code IN (SELECT erp.fn_user_permissions(:u)) ORDER BY p.module, p.code""", {"u": s["app_user_id"]})
        table(perms, height=300)
        st.subheader("My recent log-ins")
        hist = query("""SELECT attempted_at AT TIME ZONE 'Africa/Harare' AS "when (Harare)", success, failure_reason, ip_address, user_agent
                          FROM login_attempts WHERE user_id = :u ORDER BY attempted_at DESC LIMIT 10""", {"u": s["app_user_id"]})
        table(hist)
        st.caption("See a log-in you don't recognise? Change your password and tell IT Support immediately.")
