"""Billing - create invoices from time or milestones, issue them, receive payments, track receivables."""
from datetime import date, timedelta
from html import escape

import streamlit as st

from db import query, run_action, scalar
from ui import has_role, money, page_header, table, empty_note
from auth import can, require

require("page.billing")
page_header(":material/request_quote: Billing", "Invoices, payments and receivables")

tab_inv, tab_new, tab_pay, tab_ar = st.tabs(["📄 Invoices", "➕ Create invoice", "💵 Receive payment", "⏳ Receivables"])
STATUSES = ["draft", "issued", "partially_paid", "paid", "overdue", "void"]
can_issue = can("invoice.issue")


def invoice_html(inv_id: int) -> str:
    """Build a printable HTML invoice (open in a browser → Print → Save as PDF)."""
    firm = query("SELECT * FROM firm_settings").iloc[0]
    inv = query("""SELECT i.*, c.legal_name, c.address_line1, c.city, c.vat_number AS client_vat, p.name AS project
                     FROM invoices i JOIN clients c USING (client_id) LEFT JOIN projects p USING (project_id)
                    WHERE i.invoice_id = :i""", {"i": inv_id}).iloc[0]
    lines = query("SELECT * FROM invoice_lines WHERE invoice_id = :i ORDER BY line_no", {"i": inv_id})
    rows = "".join(
        f"<tr><td>{escape(r.description)}</td><td class='n'>{r.quantity:,.2f} {r.unit}</td>"
        f"<td class='n'>{r.unit_price:,.2f}</td><td class='n'>{r.line_net:,.2f}</td></tr>" for _, r in lines.iterrows())
    return f"""<!doctype html><html><head><meta charset="utf-8"><title>{inv.invoice_number}</title>
<style>body{{font-family:Segoe UI,Arial,sans-serif;margin:40px;color:#222}} h1{{color:#0E2C52;margin:0}}
table{{width:100%;border-collapse:collapse;margin-top:20px}} th{{background:#0E2C52;color:#fff;text-align:left;padding:8px}}
td{{padding:8px;border-bottom:1px solid #ddd}} .n{{text-align:right}} .tot td{{font-weight:bold;border:none}}
.head{{display:flex;justify-content:space-between}} small{{color:#666}}</style></head><body>
<div class="head"><div><h1>{escape(firm.legal_name)}</h1><small>{escape(firm.address or '')}<br>
VAT: {firm.vat_number or '-'} · TIN: {firm.tax_number or '-'}<br>{firm.email or ''} · {firm.phone or ''}</small></div>
<div style="text-align:right"><h2 style="margin:0">TAX INVOICE</h2><b>{inv.invoice_number}</b><br>
Date: {inv.invoice_date:%d %b %Y}<br>Due: {inv.due_date:%d %b %Y}</div></div>
<p><b>Bill to:</b><br>{escape(inv.legal_name)}<br>{escape(inv.address_line1 or '')} {escape(inv.city or '')}<br>
VAT: {inv.client_vat or '-'}</p><p><b>Engagement:</b> {escape(inv.project or '-')}<br><small>{escape(inv.notes or '')}</small></p>
<table><tr><th>Description</th><th class="n">Qty</th><th class="n">Rate</th><th class="n">Amount ({inv.currency_code})</th></tr>
{rows}
<tr class="tot"><td colspan="3" class="n">Subtotal</td><td class="n">{inv.subtotal:,.2f}</td></tr>
<tr class="tot"><td colspan="3" class="n">VAT</td><td class="n">{inv.tax_amount:,.2f}</td></tr>
<tr class="tot"><td colspan="3" class="n">TOTAL</td><td class="n">{inv.currency_code} {inv.total_amount:,.2f}</td></tr>
<tr class="tot"><td colspan="3" class="n">Paid</td><td class="n">{inv.amount_paid:,.2f}</td></tr>
<tr class="tot"><td colspan="3" class="n">BALANCE DUE</td><td class="n">{inv.currency_code} {inv.balance_due:,.2f}</td></tr></table>
<p><small>Please pay within terms quoting the invoice number. Thank you for your business.</small></p></body></html>"""


# ======================================================================= INVOICES
with tab_inv:
    sel = st.multiselect("Status", STATUSES, default=["draft", "issued", "partially_paid", "overdue", "paid"])
    inv = query("""
        SELECT i.invoice_id, i.invoice_number, c.legal_name AS client, p.project_code AS project,
               i.invoice_date, i.due_date, i.status::text AS status, i.currency_code AS cur,
               i.subtotal, i.tax_amount, i.total_amount, i.amount_paid, i.balance_due
          FROM invoices i JOIN clients c ON c.client_id = i.client_id
          LEFT JOIN projects p ON p.project_id = i.project_id
         WHERE i.status::text = ANY(:s) ORDER BY i.invoice_id DESC""", {"s": sel or STATUSES})
    if not empty_note(inv, "No invoices yet - create one in the 'Create invoice' tab."):
        table(inv.drop(columns=["invoice_id"]),
              money_cols=["subtotal", "tax_amount", "total_amount", "amount_paid", "balance_due"])

        iid = st.selectbox("Open invoice", inv.invoice_id,
                           format_func=lambda i: (lambda r: f"{r.invoice_number} — {r.client} — {r.status}")(
                               inv.set_index("invoice_id").loc[i]))
        row = inv.set_index("invoice_id").loc[iid]
        table(query("""SELECT line_no, line_type, description, quantity, unit, unit_price, discount_pct, line_net, tax_amount
                         FROM invoice_lines WHERE invoice_id = :i ORDER BY line_no""", {"i": int(iid)}),
              money_cols=["unit_price", "line_net", "tax_amount"])
        pays = query("""SELECT p.payment_number, p.payment_date, p.method::text AS method, p.reference, a.amount
                          FROM payment_allocations a JOIN payments p USING (payment_id)
                         WHERE a.invoice_id = :i ORDER BY p.payment_date""", {"i": int(iid)})
        if not pays.empty:
            st.markdown("**Payments received**")
            table(pays, money_cols=["amount"])

        c1, c2, c3 = st.columns(3)
        c1.download_button("🖨️ Download printable invoice", invoice_html(int(iid)),
                           file_name=f"{row.invoice_number}.html", mime="text/html", width="stretch")
        if row.status == "draft":
            if c2.button("✅ Issue & post to ledger", type="primary", disabled=not can_issue, width="stretch",
                         help=None if can_issue else "Finance or partner role required"):
                run_action("SELECT fn_issue_invoice(:i, :u)", {"i": int(iid), "u": st.session_state.get("app_user_id")},
                           success=f"Invoice {row.invoice_number} issued and posted (journal #{{result}}).")
            if c3.button("🗑️ Delete draft", width="stretch"):
                run_action("""WITH m AS (UPDATE contract_milestones SET invoice_id = NULL WHERE invoice_id = :i)
                              DELETE FROM invoices WHERE invoice_id = :i AND status = 'draft'""",
                           {"i": int(iid)}, success="Draft deleted - its time and expenses are unbilled again.")

# ======================================================================= CREATE
with tab_new:
    mode = st.radio("Invoice type", ["From approved time & expenses (T&M)", "Fixed-fee milestone"], horizontal=True)
    if mode.startswith("From"):
        wip = query("""
            SELECT p.project_id, p.project_code || ' — ' || p.name AS label,
                   COALESCE(SUM(te.billable_amount), 0) AS wip, MIN(te.work_date) AS first_day, MAX(te.work_date) AS last_day
              FROM projects p
              LEFT JOIN time_entries te ON te.project_id = p.project_id AND te.is_billable AND te.invoice_line_id IS NULL
                   AND EXISTS (SELECT 1 FROM timesheets ts WHERE ts.timesheet_id = te.timesheet_id AND ts.status = 'approved')
             WHERE p.billing_type IN ('time_and_materials','retainer') AND NOT p.is_internal AND p.status IN ('active','completed')
             GROUP BY p.project_id ORDER BY p.project_code""")
        if not empty_note(wip, "No time & materials projects."):
            table(wip.drop(columns=["project_id"]).rename(columns={"wip": "unbilled_time"}), money_cols=["unbilled_time"])
            with st.form("gen_invoice"):
                pid = st.selectbox("Project", wip.project_id, format_func=lambda i: wip.set_index("project_id").label[i])
                c1, c2, c3 = st.columns(3)
                today = date.today()
                pfrom = c1.date_input("Work from", today.replace(day=1) - timedelta(days=62))
                pto = c2.date_input("Work to", today)
                idate = c3.date_input("Invoice date", today)
                c1, c2 = st.columns(2)
                tax = c1.selectbox("VAT", query("SELECT code FROM tax_rates WHERE is_active ORDER BY code").code, index=None,
                                   placeholder="ZW-VAT (default)")
                exp = c2.checkbox("Include rechargeable expenses", True)
                if st.form_submit_button("Create draft invoice", type="primary"):
                    run_action("SELECT fn_generate_invoice_from_time(:p, :f, :t, :d, :tax, :e, :u)",
                               {"p": int(pid), "f": pfrom, "t": pto, "d": idate, "tax": tax or "ZW-VAT", "e": exp,
                                "u": st.session_state.get("app_user_id")},
                               success="Draft invoice created (id {result}). Review it in the Invoices tab, then issue it.")
    else:
        ms = query("""
            SELECT m.milestone_id, c.contract_number, cl.legal_name AS client, m.seq, m.name, m.due_date, m.amount,
                   m.status, i.invoice_number
              FROM contract_milestones m JOIN contracts c USING (contract_id) JOIN clients cl USING (client_id)
              LEFT JOIN invoices i ON i.invoice_id = m.invoice_id
             ORDER BY c.contract_number, m.seq""")
        if not empty_note(ms, "No milestone contracts."):
            table(ms.drop(columns=["milestone_id"]), money_cols=["amount"])
            c1, c2 = st.columns(2)
            pending = ms[ms.status == "pending"]
            with c1.form("achieve"):
                st.markdown("**1. Mark milestone achieved**")
                if pending.empty:
                    st.caption("No pending milestones.")
                    st.form_submit_button("Mark achieved", disabled=True)
                else:
                    mid = st.selectbox("Milestone", pending.milestone_id,
                                       format_func=lambda i: (lambda r: f"{r.contract_number} #{r.seq} {r['name']}")(pending.set_index("milestone_id").loc[i]))
                    if st.form_submit_button("Mark achieved"):
                        run_action("UPDATE contract_milestones SET status='achieved', achieved_date=CURRENT_DATE WHERE milestone_id=:m",
                                   {"m": int(mid)}, success="Milestone marked as achieved.")
            ready = ms[(ms.status == "achieved") & ms.invoice_number.isna()]
            with c2.form("inv_ms"):
                st.markdown("**2. Invoice an achieved milestone**")
                if ready.empty:
                    st.caption("No achieved milestones waiting to be invoiced.")
                    st.form_submit_button("Create invoice", disabled=True)
                else:
                    mid = st.selectbox("Milestone", ready.milestone_id,
                                       format_func=lambda i: (lambda r: f"{r.contract_number} #{r.seq} {r['name']} — ${r.amount:,.0f}")(ready.set_index("milestone_id").loc[i]))
                    if st.form_submit_button("Create draft invoice", type="primary"):
                        run_action("SELECT fn_invoice_milestone(:m, CURRENT_DATE, 'ZW-VAT', :u)",
                                   {"m": int(mid), "u": st.session_state.get("app_user_id")},
                                   success="Draft milestone invoice created (id {result}).")

# ======================================================================= PAYMENTS
with tab_pay:
    clients = query("""SELECT c.client_id, c.legal_name, COALESCE(SUM(i.balance_due), 0) AS outstanding
                         FROM clients c LEFT JOIN invoices i ON i.client_id = c.client_id
                              AND i.status IN ('issued','partially_paid','overdue')
                        GROUP BY c.client_id ORDER BY outstanding DESC, c.legal_name""")
    banks = query("SELECT bank_account_id, name || ' (' || bank_name || ', ' || currency_code || ')' AS label FROM bank_accounts WHERE is_active")
    with st.form("receive"):
        c1, c2 = st.columns(2)
        cid = c1.selectbox("Client", clients.client_id,
                           format_func=lambda i: (lambda r: f"{r.legal_name} — owes {money(r.outstanding)}")(clients.set_index("client_id").loc[i]))
        bank = c2.selectbox("Into bank account", banks.bank_account_id, format_func=lambda i: banks.set_index("bank_account_id").label[i])
        c1, c2, c3, c4 = st.columns(4)
        amount = c1.number_input("Amount received", min_value=0.01, value=1000.0, step=100.0)
        pdate = c2.date_input("Date received", date.today())
        method = c3.selectbox("Method", ["bank_transfer", "rtgs", "mobile_money", "cash", "card", "cheque"])
        ref = c4.text_input("Reference")
        st.caption("The payment is posted to the ledger and automatically applied to the client's oldest unpaid invoices.")
        if st.form_submit_button("Record payment", type="primary", disabled=not can_issue):
            run_action("SELECT fn_record_client_payment(:c, :a, :b, :d, CAST(:m AS payment_method), :r)",
                       {"c": int(cid), "a": amount, "b": int(bank), "d": pdate, "m": method, "r": ref},
                       success="Payment recorded and allocated.")
    st.markdown("**Recent payments**")
    table(query("""SELECT p.payment_number, p.payment_date, c.legal_name AS client, p.method::text AS method, p.reference,
                          p.amount, p.amount - COALESCE((SELECT SUM(amount) FROM payment_allocations a WHERE a.payment_id = p.payment_id), 0) AS unallocated
                     FROM payments p JOIN clients c USING (client_id) ORDER BY p.payment_id DESC LIMIT 20"""),
          money_cols=["amount", "unallocated"])

# ======================================================================= RECEIVABLES
with tab_ar:
    total = scalar("SELECT COALESCE(SUM(balance_due), 0) FROM v_ar_aging WHERE currency_code='USD'")
    st.metric("Total outstanding (USD)", money(total))
    st.markdown("**By client**")
    table(query("SELECT * FROM v_client_ar_summary ORDER BY total_outstanding DESC"),
          money_cols=["total_outstanding", "current_due", "days_1_30", "days_31_60", "days_61_90", "days_over_90"])
    st.markdown("**Open invoices**")
    table(query("""SELECT invoice_number, client, invoice_date, due_date, days_overdue, total_amount, amount_paid, balance_due
                     FROM v_ar_aging ORDER BY days_overdue DESC"""),
          money_cols=["total_amount", "amount_paid", "balance_due"])
    if st.button("🔄 Flag overdue invoices now"):
        run_action("SELECT fn_mark_overdue_invoices()", success="{result} invoice(s) marked overdue.")
