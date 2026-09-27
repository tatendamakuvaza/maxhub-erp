"""
db.py - database connection and helper functions for the Maxhub ERP dashboard.

All pages import from here, so connection settings live in ONE place.
Settings are read from the .env file in the project root (see .env.example).
"""
import os
from pathlib import Path

import pandas as pd
import streamlit as st
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL
from sqlalchemy.exc import DBAPIError, OperationalError

# Load the .env file that sits in the project root (one level above /app)
load_dotenv(Path(__file__).resolve().parent.parent / ".env")


@st.cache_resource(show_spinner=False)
def get_engine():
    """Create ONE shared connection pool for the whole app."""
    url = URL.create(
        drivername="postgresql+psycopg2",
        username=os.getenv("DB_USER", "postgres"),
        password=os.getenv("DB_PASSWORD", ""),
        host=os.getenv("DB_HOST", "localhost"),
        port=int(os.getenv("DB_PORT", "5432")),
        database=os.getenv("DB_NAME", "maxhub_erp"),
    )
    return create_engine(
        url,
        pool_pre_ping=True,
        # every connection automatically looks inside the "erp" schema
        connect_args={"options": "-csearch_path=erp,public"},
    )


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
