"""
ui.py - small shared helpers for layout, formatting and the 'logged in' user.
"""
from datetime import date, timedelta

import pandas as pd
import streamlit as st


BRAND = "#0E2C52"          # Maxhub navy  - also set in .streamlit/config.toml
GOLD = "#C9A45C"           # Maxhub gold
CYAN = "#1FA3D8"           # Maxhub accent blue
RAG_COLOURS = {"R": "#F8D7DA", "A": "#FFF3CD", "G": "#D4EDDA"}


# ---------------------------------------------------------------- user session
# Log-in is handled by auth.py; these helpers read the logged-in user from the session.
from auth import can, require  # noqa: E402,F401  (re-exported for the pages)


def ensure_user():
    """Kept for backwards compatibility - the router in app.py guarantees a logged-in user."""
    if "employee_id" not in st.session_state:
        st.warning("Please log in.")
        st.stop()


def me() -> int:
    """employee_id of the logged-in user."""
    ensure_user()
    return st.session_state["employee_id"]


def has_role(*codes) -> bool:
    """True if the user has one of the role codes (ADMIN always counts)."""
    roles = st.session_state.get("roles", [])
    return "ADMIN" in roles or any(c in roles for c in codes)


# ---------------------------------------------------------------- layout
def page_header(title: str, subtitle: str = ""):
    ensure_user()
    st.title(title)
    if subtitle:
        st.caption(subtitle)
    flash = st.session_state.pop("flash", None)
    if flash:
        st.success(md(flash), icon="✅")


def md(text: str) -> str:
    """Escape $ signs so Streamlit markdown doesn't treat them as maths formulas."""
    return text.replace("$", "\\$")


def money(value, currency: str = "USD") -> str:
    if value is None or pd.isna(value):
        value = 0
    symbol = {"USD": "$", "ZAR": "R ", "ZWG": "ZiG ", "EUR": "€", "GBP": "£", "KES": "KSh ", "AED": "AED "}.get(currency, currency + " ")
    return f"{symbol}{value:,.2f}"


def short_money(value) -> str:
    value = float(value or 0)
    if abs(value) >= 1_000_000:
        return f"${value / 1_000_000:,.2f}M"
    if abs(value) >= 1_000:
        return f"${value / 1_000:,.1f}K"
    return f"${value:,.0f}"


def rag_style(df: pd.DataFrame, columns):
    """Colour R / A / G cells red, amber, green."""
    def colour(v):
        return f"background-color: {RAG_COLOURS[v]}" if v in RAG_COLOURS else ""
    return df.style.map(colour, subset=[c for c in columns if c in df.columns])


def table(df: pd.DataFrame, money_cols=(), pct_cols=(), height=None, num_cols=(), **kwargs):
    """Show a DataFrame with nice number formatting."""
    config = {c: st.column_config.NumberColumn(format="dollar") for c in money_cols if c in df.columns}
    config.update({c: st.column_config.NumberColumn(format="localized") for c in num_cols if c in df.columns})
    config.update({c: st.column_config.NumberColumn(format="%.1f%%") for c in pct_cols if c in df.columns})
    if height:
        kwargs["height"] = height
    st.dataframe(df, width="stretch", hide_index=True, column_config=config, **kwargs)


def monday(d: date) -> date:
    return d - timedelta(days=d.weekday())


def empty_note(df: pd.DataFrame, text: str = "Nothing to show yet.") -> bool:
    if df.empty:
        st.info(text)
        return True
    return False


def statement(df: pd.DataFrame, label_col: str, value_cols, subtotal_col: str = "is_subtotal", height=None):
    """Show a financial statement: bold subtotal rows, numbers with thousands separators, negatives in brackets."""
    def fmt(v):
        if v is None or pd.isna(v):
            return ""
        return f"({abs(v):,.0f})" if v < 0 else f"{v:,.0f}"
    df = df.reset_index(drop=True)
    view = df[[label_col, *value_cols]].copy()
    styler = view.style.format({c: fmt for c in value_cols})
    if subtotal_col in df.columns:
        flags = df[subtotal_col].fillna(False).tolist()
        styler = styler.apply(lambda r: ["font-weight: 700; background-color: #EEF3FA" if flags[r.name] else "" for _ in r], axis=1)
    kwargs = {"height": height} if height else {}
    st.dataframe(styler, width="stretch", hide_index=True, **kwargs)
