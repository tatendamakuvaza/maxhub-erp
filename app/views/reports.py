"""Financial statements - IFRS 18 statement of profit or loss, financial position, cash flows, equity & notes."""
from datetime import date

import pandas as pd
import plotly.express as px
import streamlit as st

from auth import require
from db import query, scalar
from ui import BRAND, GOLD, page_header, statement, table

require("page.reports")
page_header(":material/summarize: Financial statements",
            "IFRS Accounting Standards · IFRS 18 early adopted for FY2026 · presentation currency USD")

last_closed = scalar("SELECT max(end_date) FROM fiscal_periods WHERE is_closed") or date.today()
c1, c2, c3 = st.columns([1.4, 1, 1])
choice = c1.selectbox("Period", ["Year to date (last closed month)", "Financial year 2025 (audited)", "Custom"])
if choice.startswith("Year to date"):
    p_to = last_closed
    p_from = date(p_to.year, 1, 1)
elif choice.startswith("Financial year 2025"):
    p_from, p_to = date(2025, 1, 1), date(2025, 12, 31)
else:
    p_from = c2.date_input("From", date(last_closed.year, 1, 1))
    p_to = c3.date_input("To", last_closed)
# comparative: same period one year earlier
c_from, c_to = p_from.replace(year=p_from.year - 1), p_to.replace(year=p_to.year - 1)
has_comp = c_from >= date(2025, 1, 1)
st.caption(f"Current period **{p_from:%d %b %Y} – {p_to:%d %b %Y}**" +
           (f" · comparative **{c_from:%d %b %Y} – {c_to:%d %b %Y}**" if has_comp else " · no comparative (ERP went live 1 Jan 2025)"))

tabs = st.tabs(["Profit or loss & OCI", "Financial position", "Cash flows", "Changes in equity",
                "MPM note (IFRS 18)", "PPE & intangibles", "Segments (IFRS 8)", "Tax notes", "Trial balance"])

cur_lbl, cmp_lbl = f"{p_from:%b}–{p_to:%b %Y}", f"{c_from:%b}–{c_to:%b %Y}"


def with_comparative(fn: str, key: str):
    cur = query(f"SELECT * FROM {fn}(:a, :b)", {"a": p_from, "b": p_to}).rename(columns={"amount": cur_lbl})
    if has_comp:
        cmp_ = query(f"SELECT {key}, amount FROM {fn}(:a, :b)", {"a": c_from, "b": c_to}).rename(columns={"amount": cmp_lbl})
        cur = cur.merge(cmp_, on=key, how="left")
    return cur


# ------------------------------------------------------------------ P&L
with tabs[0]:
    pl = with_comparative("fn_ifrs_profit_or_loss", "line_code")
    pl["category"] = pl["category"].str.replace("_", " ").str.title()
    cols = [cur_lbl] + ([cmp_lbl] if has_comp else [])
    a, b = st.columns([3, 2])
    with a:
        st.markdown("##### Statement of profit or loss and other comprehensive income")
        statement(pl.rename(columns={"caption": "USD"}), "USD", cols, height=880)
    with b:
        st.markdown("##### IFRS 18 categories")
        st.caption("Every income and expense line is classified as **operating**, **investing**, **financing**, "
                   "**income taxes** or **discontinued**. Two new required subtotals: *Operating profit* and "
                   "*Profit before financing and income taxes*. Expenses are presented **by nature**.")
        cat = pl[~pl.is_subtotal & pl.category.isin(["Operating", "Investing", "Financing", "Income Taxes"])]
        chart = cat.groupby("category", as_index=False)[cur_lbl].sum()
        fig = px.bar(chart, x="category", y=cur_lbl, color="category", text_auto=",.0f",
                     color_discrete_sequence=[BRAND, GOLD, "#1FA3D8", "#8A9BB3"])
        fig.update_layout(height=300, showlegend=False, margin=dict(t=10, b=10), yaxis_title="USD", xaxis_title="")
        st.plotly_chart(fig, width="stretch")
        rev = pl.loc[pl.line_code == "PL_REV", cur_lbl].sum()
        op = pl.loc[pl.line_code == "ST_OP", cur_lbl].sum()
        pat = pl.loc[pl.line_code == "ST_PROFIT", cur_lbl].sum()
        m1, m2 = st.columns(2)
        m1.metric("Operating margin", f"{100 * op / rev:.1f}%" if rev else "–", border=True)
        m2.metric("Net margin", f"{100 * pat / rev:.1f}%" if rev else "–", border=True)

# ------------------------------------------------------------------ SFP
with tabs[1]:
    sfp = query("SELECT * FROM fn_ifrs_financial_position(:d)", {"d": p_to}).rename(columns={"amount": f"{p_to:%d %b %Y}"})
    prior = date(p_to.year - 1, 12, 31)
    cols = [f"{p_to:%d %b %Y}"]
    if prior >= date(2024, 12, 31):
        pr = query("SELECT line_code, amount FROM fn_ifrs_financial_position(:d)", {"d": prior}).rename(columns={"amount": f"{prior:%d %b %Y}"})
        sfp = sfp.merge(pr, on="line_code", how="left")
        cols.append(f"{prior:%d %b %Y}")
    st.markdown("##### Statement of financial position")
    statement(sfp.rename(columns={"caption": "USD"}), "USD", cols, height=1230)
    diff = sfp.loc[sfp.line_code == "T_A", cols[0]].sum() - sfp.loc[sfp.line_code == "T_EL", cols[0]].sum()
    st.caption("✅ Balances: total assets = total equity and liabilities" if abs(diff) < 1 else f"⚠️ Out of balance by {diff:,.2f}")
    st.caption("Lease liabilities and borrowings are split into current / non-current from their repayment schedules. "
               "Land & buildings are carried at revalued amounts (IAS 16); investment property at fair value (IAS 40).")

# ------------------------------------------------------------------ cash flows
with tabs[2]:
    cf = with_comparative("fn_ifrs_cash_flows", "cf_code")
    cols = [cur_lbl] + ([cmp_lbl] if has_comp else [])
    st.markdown("##### Statement of cash flows (direct method)")
    statement(cf.rename(columns={"caption": "USD"}), "USD", cols, height=780)
    st.caption("As required by IFRS 18's amendments to IAS 7: **interest paid** is a *financing* cash flow and "
               "**interest and dividends received** are *investing* cash flows. Transfers between the firm's own bank accounts are excluded.")

# ------------------------------------------------------------------ SOCE
with tabs[3]:
    soce = query("SELECT * FROM fn_ifrs_changes_in_equity(:a, :b)", {"a": p_from, "b": p_to})
    soce["is_subtotal"] = soce.sort_order.isin([1, 4, 7])
    st.markdown("##### Statement of changes in equity")
    statement(soce, "caption", ["share_capital", "revaluation_reserve", "translation_reserve", "retained_earnings", "total_equity"])

# ------------------------------------------------------------------ MPM note
with tabs[4]:
    st.markdown("##### Management-defined performance measures")
    defs = query("SELECT mpm_code, name, description, why_useful FROM mpm_definitions WHERE is_active ORDER BY sort_order")
    note = query("SELECT * FROM fn_ifrs_mpm_note(:a, :b)", {"a": p_from, "b": p_to})
    for _, d in defs.iterrows():
        with st.container(border=True):
            st.markdown(f"**{d['name']}** — {d.description}")
            st.caption(f"Why management uses it: {d.why_useful}")
            n = note[note.mpm_code == d.mpm_code].copy()
            n["is_subtotal"] = n.sort_order.isin([1, 9])
            statement(n.rename(columns={"caption": "Reconciliation (USD)", "amount": "Amount", "tax_effect": "Income-tax effect"}),
                      "Reconciliation (USD)", ["Amount", "Income-tax effect"])
    st.caption("IFRS 18.117-125: MPMs are disclosed in a single note, reconciled to the most directly comparable IFRS subtotal, "
               "with the income-tax effect of each reconciling item (at the Zimbabwe rate of 24.72%).")

# ------------------------------------------------------------------ PPE movement
with tabs[5]:
    mv = query("SELECT * FROM fn_ppe_movement(:a, :b)", {"a": p_from, "b": p_to})
    total = mv.select_dtypes("number").sum()
    mv = pd.concat([mv, pd.DataFrame([{"category": "TOTAL", "standard": "", **total.to_dict()}])], ignore_index=True)
    mv["is_subtotal"] = mv.category == "TOTAL"
    st.markdown("##### Carrying amount reconciliation - PPE (IAS 16), intangibles (IAS 38), investment property (IAS 40)")
    statement(mv, "category", ["opening_nbv", "additions", "revaluations", "disposals", "depreciation", "closing_nbv"])
    st.caption("ROU assets (IFRS 16) are shown on the Leases page.")

# ------------------------------------------------------------------ segments
with tabs[6]:
    seg = query("""SELECT service_line, office, SUM(revenue) AS revenue FROM v_segment_revenue
                    WHERE month_start BETWEEN :a AND :b GROUP BY 1, 2""", {"a": p_from, "b": p_to})
    a, b = st.columns(2)
    with a:
        st.markdown("##### Revenue by service line")
        s1 = seg.groupby("service_line", as_index=False).revenue.sum().sort_values("revenue", ascending=False)
        fig = px.bar(s1, x="revenue", y="service_line", orientation="h", text_auto=",.0f", color_discrete_sequence=[BRAND])
        fig.update_layout(height=340, margin=dict(t=10, b=10), yaxis_title="", xaxis_title="USD")
        st.plotly_chart(fig, width="stretch")
    with b:
        st.markdown("##### Revenue by geography (office)")
        s2 = seg.groupby("office", as_index=False).revenue.sum()
        fig = px.pie(s2, names="office", values="revenue", hole=0.45,
                     color_discrete_sequence=[BRAND, GOLD, "#1FA3D8", "#8A9BB3", "#2E6DB4", "#E0C58E"])
        fig.update_layout(height=340, margin=dict(t=10, b=10))
        st.plotly_chart(fig, width="stretch")
    st.caption("Legacy-system revenue (Jan–Oct 2025) is summarised by office only, so it appears as 'Other / unallocated' by service line.")

# ------------------------------------------------------------------ tax notes
with tabs[7]:
    a, b = st.columns(2)
    with a:
        st.markdown(f"##### Deferred tax (IAS 12) at {p_to:%d %b %Y}")
        dt = query("SELECT * FROM fn_deferred_tax_schedule(:d)", {"d": p_to})
        table(dt, money_cols=["carrying_amount", "tax_base", "temporary_difference", "deferred_tax"])
    with b:
        st.markdown("##### Corporate income tax computation (ITF12C)")
        itc = query("""SELECT fy.name AS year, c.profit_before_tax, c.add_backs, c.capital_allowances, c.exempt_income, c.taxable_income,
                              c.income_tax, c.aids_levy, c.total_tax, c.qpds_paid, c.balance_due, c.status
                         FROM income_tax_computations c JOIN fiscal_years fy USING (fiscal_year_id)""")
        if not itc.empty:
            view = itc.T.rename(columns={0: "FY2025"})
            view["FY2025"] = [f"{v:,.2f}" if isinstance(v, (int, float)) else str(v) for v in view["FY2025"]]
            st.dataframe(view, width="stretch")

# ------------------------------------------------------------------ TB
with tabs[8]:
    tb = query("SELECT * FROM fn_trial_balance(:d)", {"d": p_to})
    c1, c2 = st.columns(2)
    c1.metric("Total debits", f"${tb.debit.sum():,.2f}", border=True)
    c2.metric("Total credits", f"${tb.credit.sum():,.2f}", border=True)
    table(tb, money_cols=["debit", "credit"], height=500)
    st.download_button("⬇️ Download trial balance (CSV)", tb.to_csv(index=False), f"trial_balance_{p_to}.csv", "text/csv")
