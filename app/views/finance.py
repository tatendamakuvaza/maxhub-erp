"""Finance - trial balance, income statement, balance sheet, journals and budgets."""
from datetime import date

import pandas as pd
import plotly.express as px
import streamlit as st

from db import query, run_action
from ui import BRAND, has_role, md, money, page_header, table, empty_note
from auth import can, require

require("page.finance")
page_header(":material/account_balance: Finance", "General ledger reports")

tab_pl, tab_bs, tab_tb, tab_bud, tab_je = st.tabs(
    ["📈 Income statement", "⚖️ Balance sheet", "🧮 Trial balance", "🎯 Budget vs actual", "📒 Journals"])

# ------------------------------------------------------------------ income statement
with tab_pl:
    pl = query("SELECT month_start, account_type, account_code, account_name, amount FROM v_income_statement_monthly")
    if not empty_note(pl, "Nothing posted yet."):
        pl["month"] = pl.month_start.apply(lambda d: d.strftime("%Y-%m"))
        pivot = pl.pivot_table(index=["account_type", "account_code", "account_name"], columns="month",
                               values="amount", aggfunc="sum", fill_value=0)
        pivot["Total"] = pivot.sum(axis=1)
        pivot = pivot.sort_index(level=[0, 1], ascending=[False, True])
        st.dataframe(pivot.style.format("{:,.2f}"), width="stretch")
        rev = pl[pl.account_type == "revenue"].amount.sum()
        exp = pl[pl.account_type == "expense"].amount.sum()
        c1, c2, c3 = st.columns(3)
        c1.metric("Total revenue", money(rev), border=True)
        c2.metric("Total expenses", money(exp), border=True)
        c3.metric("Net profit", money(rev - exp), f"{100 * (rev - exp) / rev if rev else 0:.1f}% margin", border=True)
        fig = px.pie(pl[pl.account_type == "revenue"], values="amount", names="account_name", hole=0.5,
                     title="Revenue mix", color_discrete_sequence=["#0E2C52", "#1FA3D8", "#C9A45C", "#5B7DA8"])
        st.plotly_chart(fig, width="stretch")

# ------------------------------------------------------------------ balance sheet
with tab_bs:
    tb = query("SELECT * FROM v_trial_balance WHERE total_debit <> 0 OR total_credit <> 0 ORDER BY account_code")
    if not empty_note(tb):
        profit = tb[tb.account_type == "revenue"].balance.sum() - tb[tb.account_type == "expense"].balance.sum()
        c1, c2 = st.columns(2)
        with c1:
            st.markdown("### Assets")
            assets = tb[tb.account_type == "asset"][["account_code", "account_name", "balance"]]
            table(assets, money_cols=["balance"])
            st.markdown(md(f"**Total assets: {money(assets.balance.sum())}**"))
        with c2:
            st.markdown("### Liabilities & equity")
            le = tb[tb.account_type.isin(["liability", "equity"])][["account_code", "account_name", "balance"]]
            le = pd.concat([le, pd.DataFrame([{"account_code": "—", "account_name": "Current year profit",
                                               "balance": profit}])], ignore_index=True)
            table(le, money_cols=["balance"])
            st.markdown(md(f"**Total liabilities & equity: {money(le.balance.sum())}**"))
        diff = assets.balance.sum() - le.balance.sum()
        (st.success if abs(diff) < 0.01 else st.error)(md(f"Balance check: difference {money(diff)}"))

# ------------------------------------------------------------------ trial balance
with tab_tb:
    tb_all = query("SELECT * FROM v_trial_balance WHERE total_debit <> 0 OR total_credit <> 0 ORDER BY account_code")
    table(tb_all, money_cols=["total_debit", "total_credit", "balance"])
    st.caption(md(f"Total debits {money(tb_all.total_debit.sum())} · Total credits {money(tb_all.total_credit.sum())}"))

# ------------------------------------------------------------------ budget vs actual
with tab_bud:
    bva = query("""
        SELECT a.account_code || ' ' || a.name AS account, b.period_no AS month, b.amount AS budget,
               COALESCE((SELECT SUM(CASE WHEN a.account_type = 'revenue' THEN jl.credit - jl.debit ELSE jl.debit - jl.credit END)
                           FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id)
                           JOIN fiscal_periods fp ON fp.fiscal_period_id = je.fiscal_period_id
                          WHERE jl.account_id = a.account_id AND je.status IN ('posted','reversed')
                            AND fp.fiscal_year_id = b.fiscal_year_id AND fp.period_no = b.period_no), 0) AS actual
          FROM budgets b JOIN chart_of_accounts a USING (account_id)
         WHERE b.period_no <= extract(month FROM CURRENT_DATE)
         ORDER BY account, month""")
    if not empty_note(bva, "No budgets loaded."):
        acct = st.selectbox("Account", bva.account.unique())
        d = bva[bva.account == acct].melt(id_vars=["account", "month"], value_vars=["budget", "actual"])
        fig = px.bar(d, x="month", y="value", color="variable", barmode="group",
                     color_discrete_map={"budget": "#BDC3C7", "actual": BRAND}, labels={"value": "USD", "variable": ""})
        fig.update_layout(height=320, margin=dict(t=10))
        st.plotly_chart(fig, width="stretch")
        s = bva.groupby("account")[["budget", "actual"]].sum().reset_index()
        s["variance"] = s.actual - s.budget
        table(s, money_cols=["budget", "actual", "variance"])

# ------------------------------------------------------------------ journals
with tab_je:
    je = query("""SELECT je.journal_entry_id, je.entry_number, je.entry_date, je.description, je.source_type, je.status,
                         SUM(jl.debit) AS amount
                    FROM journal_entries je JOIN journal_lines jl USING (journal_entry_id)
                   GROUP BY je.journal_entry_id ORDER BY je.journal_entry_id DESC""")
    table(je.drop(columns=["journal_entry_id"]), money_cols=["amount"])
    if not je.empty:
        jid = st.selectbox("Journal lines", je.journal_entry_id, format_func=lambda i: je.set_index("journal_entry_id").entry_number[i])
        table(query("""SELECT jl.line_no, a.account_code, a.name AS account, jl.debit, jl.credit, jl.description
                         FROM journal_lines jl JOIN chart_of_accounts a USING (account_id)
                        WHERE jl.journal_entry_id = :j ORDER BY line_no""", {"j": int(jid)}), money_cols=["debit", "credit"])

    st.markdown("#### Manual journal (simple two-line entry)")
    if not can("gl.post"):
        st.warning("Finance or partner role required to post journals.")
    else:
        accts = query("SELECT account_id, account_code || ' ' || name AS label FROM chart_of_accounts WHERE is_postable AND is_active ORDER BY account_code")
        lbl = dict(zip(accts.account_id, accts.label))
        with st.form("manual_je", clear_on_submit=True):
            c1, c2 = st.columns(2)
            dr = c1.selectbox("Debit account", accts.account_id, format_func=lbl.get)
            cr = c2.selectbox("Credit account", accts.account_id, format_func=lbl.get, index=1)
            c1, c2, c3 = st.columns([1, 1, 2])
            amt = c1.number_input("Amount (USD)", min_value=0.01, value=100.0)
            jdate = c2.date_input("Date", date.today())
            desc = c3.text_input("Description *", placeholder="e.g. Monthly internet - Liquid")
            if st.form_submit_button("Post journal", type="primary") and desc:
                run_action("""
                    WITH h AS (INSERT INTO journal_entries (entry_date, description, source_type, created_by)
                               VALUES (:d, :desc, 'manual', :u) RETURNING journal_entry_id),
                         l AS (INSERT INTO journal_lines (journal_entry_id, line_no, account_id, debit, credit)
                               SELECT journal_entry_id, 1, :dr, :a, 0 FROM h UNION ALL
                               SELECT journal_entry_id, 2, :cr, 0, :a FROM h RETURNING journal_entry_id)
                    SELECT journal_entry_id FROM h""",
                    {"d": jdate, "desc": desc, "u": st.session_state.get("app_user_id"), "dr": int(dr), "cr": int(cr), "a": amt},
                    success="Draft journal {result} saved.")
        drafts = query("SELECT journal_entry_id, entry_number, description FROM journal_entries WHERE status = 'draft' ORDER BY 1")
        if not drafts.empty:
            with st.form("post_je"):
                jid = st.selectbox("Draft journals", drafts.journal_entry_id,
                                   format_func=lambda i: (lambda r: f"{r.entry_number} — {r.description}")(drafts.set_index("journal_entry_id").loc[i]))
                if st.form_submit_button("✅ Post to ledger"):
                    run_action("UPDATE journal_entries SET status = 'posted' WHERE journal_entry_id = :j", {"j": int(jid)},
                               success="Journal posted.")
