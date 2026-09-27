"""Expenses - create expense claims, add receipts, submit and approve."""
from datetime import date

import pandas as pd
import streamlit as st

from db import query, run_action
from ui import has_role, me, page_header, table, empty_note
from auth import can, require

require("page.expenses")
page_header(":material/receipt_long: Expenses", "Claim travel, accommodation and other business costs")

tab_my, tab_approve = st.tabs(["🧾 My claims", "✔️ Approvals"])
BADGE = {"draft": "🟦 Draft", "submitted": "🟨 Submitted", "approved": "🟩 Approved", "rejected": "🟥 Rejected"}

def render_my_claims():
    with st.form("new_claim", clear_on_submit=True):
        c1, c2 = st.columns([4, 1])
        title = c1.text_input("New claim title", placeholder="e.g. Bulawayo client visit - October")
        c2.write(""); c2.write("")
        if c2.form_submit_button("➕ Create claim", width="stretch") and title:
            run_action("INSERT INTO expense_reports (employee_id, title) VALUES (:e, :t) RETURNING report_number",
                       {"e": me(), "t": title}, success="Claim {result} created - add your items below.")

    claims = query("""SELECT expense_report_id, report_number, title, status::text AS status, total_amount,
                             submitted_at, approved_at
                        FROM expense_reports WHERE employee_id = :e ORDER BY expense_report_id DESC""", {"e": me()})
    if empty_note(claims, "You have no expense claims yet."):
        return
    table(claims.drop(columns=["expense_report_id"]), money_cols=["total_amount"])

    rid = st.selectbox("Open claim", claims.expense_report_id,
                       format_func=lambda i: (lambda r: f"{r.report_number} — {r.title} ({BADGE[r.status]})")(
                           claims.set_index("expense_report_id").loc[i]))
    claim = claims.set_index("expense_report_id").loc[rid]
    items = query("""
        SELECT ei.expense_date, ec.name AS category, COALESCE(p.project_code, '—') AS project, ei.description,
               ei.merchant, ei.amount, ei.currency_code, ei.amount_base, ei.is_billable,
               (ei.invoice_line_id IS NOT NULL) AS recharged_to_client
          FROM expense_items ei
          JOIN expense_categories ec ON ec.expense_category_id = ei.expense_category_id
          LEFT JOIN projects p       ON p.project_id = ei.project_id
         WHERE ei.expense_report_id = :r ORDER BY ei.expense_date""", {"r": int(rid)})
    table(items, money_cols=["amount_base"])

    if claim.status in ("draft", "rejected"):
        cats = query("SELECT expense_category_id, name, is_billable_default, max_amount_per_item FROM expense_categories ORDER BY name")
        projects = query("""SELECT p.project_id, p.project_code || ' — ' || p.name AS label
                              FROM project_members m JOIN projects p USING (project_id)
                             WHERE m.employee_id = :e AND NOT p.is_internal ORDER BY 1""", {"e": me()})
        with st.form("add_item", clear_on_submit=True):
            st.markdown("**Add item**")
            c1, c2, c3 = st.columns(3)
            edate = c1.date_input("Date", date.today())
            cat_labels = {r.expense_category_id: r["name"] + (f" (max ${r.max_amount_per_item:,.0f})"
                          if pd.notna(r.max_amount_per_item) else "") for _, r in cats.iterrows()}
            cat = c2.selectbox("Category", cats.expense_category_id, format_func=cat_labels.get)
            proj = c3.selectbox("Project (for client recharge)", [None] + projects.project_id.tolist(),
                                format_func=lambda i: "— none —" if i is None else projects.set_index("project_id").label[i])
            c1, c2, c3, c4 = st.columns(4)
            amount = c1.number_input("Amount", min_value=0.01, value=10.0, step=1.0)
            cur = c2.selectbox("Currency", ["USD", "ZWG", "ZAR"])
            fx = c3.number_input("Rate to USD", min_value=0.00000001, value=1.0, format="%.6f",
                                 help="1 for USD. For ZiG or Rand, enter the USD value of one unit.")
            billable = c4.checkbox("Recharge to client", value=True)
            desc = st.text_input("Description *")
            merchant = st.text_input("Merchant / supplier")
            if st.form_submit_button("Add item", type="primary"):
                if not desc:
                    st.error("Description is required.")
                else:
                    run_action("""INSERT INTO expense_items (expense_report_id, expense_date, expense_category_id, project_id,
                                         description, merchant, amount, currency_code, exchange_rate, is_billable)
                                  VALUES (:r, :d, :c, :p, :desc, :m, :a, :cur, :fx, :b)""",
                               {"r": int(rid), "d": edate, "c": int(cat), "p": int(proj) if proj else None,
                                "desc": desc, "m": merchant, "a": amount, "cur": cur, "fx": fx,
                                "b": billable and proj is not None}, success="Item added.")
        if st.button("📤 Submit claim for approval", type="primary", disabled=items.empty):
            run_action("CALL sp_submit_expense_report(:r)", {"r": int(rid)}, success="Claim submitted.")


with tab_my:
    render_my_claims()

with tab_approve:
    pending = query("""
        SELECT er.expense_report_id, er.report_number, e.first_name || ' ' || e.last_name AS employee,
               er.title, er.total_amount, er.submitted_at
          FROM expense_reports er JOIN employees e ON e.employee_id = er.employee_id
         WHERE er.status = 'submitted' AND er.employee_id <> :me
           AND (e.manager_id = :me OR :senior)""", {"me": me(), "senior": can("expense.approve_all")})
    if not empty_note(pending, "🎉 No expense claims waiting for approval."):
        table(pending.drop(columns=["expense_report_id"]), money_cols=["total_amount"])
        rid = st.selectbox("Review claim", pending.expense_report_id,
                           format_func=lambda i: pending.set_index("expense_report_id").report_number[i])
        table(query("""SELECT ei.expense_date, ec.name AS category, ei.description, ei.amount_base, ei.is_billable
                         FROM expense_items ei JOIN expense_categories ec USING (expense_category_id)
                        WHERE ei.expense_report_id = :r""", {"r": int(rid)}), money_cols=["amount_base"])
        c1, c2 = st.columns([1, 2])
        if c1.button("✅ Approve & post to ledger", type="primary"):
            run_action("CALL sp_approve_expense_report(:r, :a)", {"r": int(rid), "a": me()},
                       success="Claim approved and posted to the general ledger.")
        with c2.form("reject_claim"):
            reason = st.text_input("Reason for rejection")
            if st.form_submit_button("❌ Reject") and reason:
                run_action("""UPDATE expense_reports SET status = 'rejected', rejection_reason = :why
                               WHERE expense_report_id = :r""", {"r": int(rid), "why": reason}, success="Claim rejected.")
