"""
auth.py - log-in, sessions and permissions for the Maxhub ERP dashboard.

The PASSWORD CHECK happens inside PostgreSQL (erp.fn_login) using bcrypt hashes,
so passwords never have to be compared in Python.  After a successful log-in the
database gives us a random session token; we keep the token in Streamlit's
session_state and re-check it on every page load (erp.fn_validate_session), so a
disabled account or an expired session is logged out automatically.
"""
from __future__ import annotations

import streamlit as st
from sqlalchemy import text

from db import get_engine, query

SESSION_KEYS = ("auth_token", "app_user_id", "employee_id", "employee_name", "job_title", "department",
                "department_code", "office", "roles", "permissions", "must_change_password", "username", "email")


def _client_info() -> tuple[str | None, str | None]:
    """Best-effort IP address and browser name for the login audit trail."""
    ctx = getattr(st, "context", None)
    ip = getattr(ctx, "ip_address", None) if ctx else None
    agent = None
    try:
        agent = ctx.headers.get("User-Agent") if ctx else None
    except Exception:  # headers are not available in every environment (e.g. tests)
        agent = None
    ip = ip if isinstance(ip, str) else None                 # ignore anything that isn't plain text
    agent = agent if isinstance(agent, str) else None
    return ip, (agent or "Streamlit")[:300]


def login(username: str, password: str) -> tuple[bool, str]:
    """Check the password in the database. Returns (success, message)."""
    ip, agent = _client_info()
    with get_engine().begin() as conn:             # commit so failed attempts are recorded too
        row = conn.execute(text("SELECT status, user_id, message FROM erp.fn_login(:u, :p, :ip, :a)"),
                           {"u": username.strip(), "p": password, "ip": ip, "a": agent}).mappings().one()
        if row["status"] != "ok":
            return False, row["message"]
        token = conn.execute(text("SELECT erp.fn_create_session(:u, :ip)"), {"u": row["user_id"], "ip": ip}).scalar()
    st.session_state["auth_token"] = token
    load_profile(int(row["user_id"]))
    st.session_state["flash"] = row["message"] if row["message"] != "Welcome back!" else \
        f"Welcome back, {st.session_state['employee_name'].split()[0]}!"
    return True, row["message"]


def load_profile(user_id: int) -> None:
    """Load who the user is, their roles and their permissions into the session."""
    p = query("""
        SELECT u.user_id, u.username, u.email, u.must_change_password, e.employee_id,
               e.first_name || ' ' || e.last_name AS name, e.job_title, d.name AS department, d.code AS department_code,
               o.name AS office
          FROM app_users u
          JOIN employees e ON e.employee_id = u.employee_id
          LEFT JOIN departments d ON d.department_id = e.department_id
          LEFT JOIN offices o ON o.office_id = e.office_id
         WHERE u.user_id = :u""", {"u": user_id}).iloc[0]
    roles = query("""SELECT r.code FROM user_roles ur JOIN roles r USING (role_id)
                      WHERE ur.user_id = :u ORDER BY r.code""", {"u": user_id})["code"].tolist()
    perms = set(query("SELECT erp.fn_user_permissions(:u) AS p", {"u": user_id})["p"].tolist())
    st.session_state.update({
        "app_user_id": int(p.user_id), "employee_id": int(p.employee_id), "employee_name": p["name"],
        "job_title": p.job_title, "department": p.department, "department_code": p.department_code,
        "office": p.office, "roles": roles, "permissions": perms, "username": p.username, "email": p.email,
        "must_change_password": bool(p.must_change_password),
    })


def is_logged_in() -> bool:
    """True if there is a valid (not expired / not revoked) session."""
    token = st.session_state.get("auth_token")
    if not token:
        return False
    with get_engine().begin() as conn:
        user_id = conn.execute(text("SELECT erp.fn_validate_session(:t)"), {"t": token}).scalar()
    if user_id is None or int(user_id) != st.session_state.get("app_user_id"):
        clear_session()
        st.session_state["login_notice"] = "Your session has ended - please log in again."
        return False
    return True


def logout() -> None:
    token = st.session_state.get("auth_token")
    if token:
        with get_engine().begin() as conn:
            conn.execute(text("SELECT erp.fn_logout(:t)"), {"t": token})
    clear_session()
    st.session_state["login_notice"] = "You have been logged out."


def clear_session() -> None:
    for k in list(st.session_state.keys()):
        if k in SESSION_KEYS or k.startswith("_"):
            del st.session_state[k]
    for k in ("flash",):
        st.session_state.pop(k, None)


def can(*permissions: str) -> bool:
    """True if the logged-in user has ANY of the given permissions."""
    perms = st.session_state.get("permissions", set())
    return any(p in perms for p in permissions)


def require(permission: str) -> None:
    """Stop the page if the user lacks a permission (defence in depth - pages are also hidden)."""
    if not can(permission):
        st.error("🔒 You do not have access to this page. Ask IT Support if you think this is wrong.")
        st.stop()
