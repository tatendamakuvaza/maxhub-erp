"""
db.py - database connection and helper functions for the Maxhub ERP dashboard.

All pages import from here, so connection settings live in ONE place.

Where the connection settings come from (first one found wins):
  1. DATABASE_URL  - one connection string, e.g. from Neon:
         postgresql://user:password@ep-xxx.aws.neon.tech/neondb?sslmode=require
     (Streamlit Community Cloud: put it in the app's "Secrets" box.)
  2. DB_HOST / DB_PORT / DB_NAME / DB_USER / DB_PASSWORD (+ optional DB_SSLMODE)
     - on your own PC these come from the .env file (see .env.example).
"""
import os
from pathlib import Path

import pandas as pd
import streamlit as st
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL, make_url
from sqlalchemy.exc import DBAPIError, OperationalError

# Load the .env file that sits in the project root (one level above /app)
load_dotenv(Path(__file__).resolve().parent.parent / ".env")


def _setting(name: str, default: str | None = None) -> str | None:
    """Read a setting from the environment / .env file, or from Streamlit secrets (hosting)."""
    value = os.getenv(name)
    if value:
        return value
    try:
        if name in st.secrets:
            return str(st.secrets[name])
    except Exception:          # no secrets.toml on this computer - that's fine
        pass
    return default


def _connection_url() -> URL:
    database_url = _setting("DATABASE_URL")
    if database_url:
        url = make_url(database_url.strip().strip('"').strip("'"))
        url = url.set(drivername="postgresql+psycopg2")
        # Neon: the "-pooler" address does not accept our search_path setting, so use the
        # direct address instead (same database, same password).
        if url.host and "-pooler." in url.host:
            url = url.set(host=url.host.replace("-pooler.", "."))
        return url
    query = {"sslmode": _setting("DB_SSLMODE")} if _setting("DB_SSLMODE") else {}
    return URL.create(
        drivername="postgresql+psycopg2",
        username=_setting("DB_USER", "postgres"),
        password=_setting("DB_PASSWORD", ""),
        host=_setting("DB_HOST", "localhost"),
        port=int(_setting("DB_PORT", "5432")),
        database=_setting("DB_NAME", "maxhub_erp"),
        query=query,
    )


@st.cache_resource(show_spinner=False)
def get_engine():
    """Create ONE shared connection pool for the whole app."""
    return create_engine(
        _connection_url(),
        pool_pre_ping=True,          # hosted databases sleep when idle - reconnect automatically
        pool_recycle=240,            # ...and close connections before the host drops them
        # every connection automatically looks inside the "erp" schema
        connect_args={"options": "-csearch_path=erp,public", "connect_timeout": 20},
    )


def is_hosted() -> bool:
    """True when running online (a DATABASE_URL is configured) rather than on your own PC."""
    return bool(_setting("DATABASE_URL"))


def check_connection():
    """Return (True, None) if the database is reachable, else (False, error text)."""
    try:
        with get_engine().connect() as conn:
            conn.execute(text("SELECT 1 FROM erp.firm_settings LIMIT 1"))
        return True, None
    except OperationalError as e:
        return False, f"Cannot connect to PostgreSQL: {e.orig}"
    except DBAPIError as e:
        return False, f"Connected, but the ERP schema is missing. Did you run database/maxhub_erp.sql?  ({e.orig})"


def query(sql: str, params: dict | None = None) -> pd.DataFrame:
    """Run a SELECT and return the result as a pandas DataFrame."""
    with get_engine().connect() as conn:
        return pd.read_sql(text(sql), conn, params=params or {})


def scalar(sql: str, params: dict | None = None):
    """Run a SELECT that returns a single value."""
    with get_engine().connect() as conn:
        return conn.execute(text(sql), params or {}).scalar()


def execute(sql: str, params: dict | None = None):
    """
    Run INSERT / UPDATE / CALL / SELECT fn() inside a transaction.
    Also tells the database WHO is making the change (for the audit log).
    Returns the first column of the first row if the statement returns rows.
    """
    user_id = st.session_state.get("app_user_id")
    with get_engine().begin() as conn:
        if user_id:
            conn.execute(text("SELECT set_config('erp.current_user_id', :u, true)"), {"u": str(user_id)})
        result = conn.execute(text(sql), params or {})
        if result.returns_rows:
            row = result.fetchone()
            return row[0] if row else None
        return None


def db_error_message(err: Exception) -> str:
    """Turn a database exception into a short, human-readable message."""
    orig = getattr(err, "orig", None)
    diag = getattr(orig, "diag", None)
    if diag is not None and diag.message_primary:
        return diag.message_primary
    return str(orig or err).split("\n")[0]


def run_action(sql: str, params: dict | None = None, success: str = "Saved.") -> bool:
    """
    Execute a change.
      * On success: remember a green message, then reload the page so every
        table shows the new data (the message is shown by ui.page_header()).
      * On failure: show a red error box and keep what the user typed.
    Business rules (e.g. 'timesheet is locked') are enforced by database
    triggers, so their messages are shown straight to the user.
    """
    try:
        result = execute(sql, params)
    except DBAPIError as e:
        st.error("⚠️ " + db_error_message(e).replace("$", "\\$"))
        return False
    st.session_state["flash"] = success.format(result=result)
    st.rerun()
    return True  # never reached - st.rerun() restarts the script
