"""Leases & loans - IFRS 16 lessee leases (branch offices), lessor leases (tenants), borrowings."""
from datetime import date

import plotly.express as px
import streamlit as st

from auth import can, require
from db import query, run_action, scalar
from ui import BRAND, GOLD, page_header, table

require("page.leases")
page_header(":material/real_estate_agent: Leases & loans", "IFRS 16 right-of-use assets and lease liabilities · tenants of Maxhub House · CBZ mortgage loan")

reg = query("SELECT * FROM v_lease_register ORDER BY role DESC, lease_number")
lessee = reg[(reg.role == "lessee") & reg.exemption.isna()]
liab = -(scalar("SELECT fn_account_balance('2700', CURRENT_DATE) + fn_account_balance('2705', CURRENT_DATE)") or 0)
rou = scalar("SELECT fn_account_balance('1600', CURRENT_DATE) + fn_account_balance('1601', CURRENT_DATE) + "
             "fn_account_balance('1610', CURRENT_DATE) + fn_account_balance('1611', CURRENT_DATE)") or 0
loan = -(scalar("SELECT fn_account_balance('2800', CURRENT_DATE)") or 0)
c1, c2, c3, c4 = st.columns(4)
c1.metric("Leases on balance sheet", len(lessee[lessee.status == "active"]), border=True)
c2.metric("Lease liabilities", f"${liab:,.0f}", border=True)
c3.metric("Right-of-use assets", f"${rou:,.0f}", border=True)
c4.metric("CBZ mortgage loan", f"${loan:,.0f}", border=True)

tabs = st.tabs(["🏢 Lessee leases (IFRS 16)", "📈 Schedule", "⚙️ Monthly posting", "🔑 Tenants (lessor)", "🏦 Borrowings", "🟡 Exempt leases"])

with tabs[0]:
    table(lessee[["lease_number", "description", "office", "currency_code", "commencement_date", "end_date", "months_remaining",
                  "payment_amount", "discount_rate_pct", "liability_lease_ccy", "liability_usd", "rou_carrying_usd", "landlord", "status"]],
          money_cols=["liability_usd", "rou_carrying_usd"], num_cols=["payment_amount", "liability_lease_ccy"])
    st.caption("Liability = present value of remaining rent at the incremental borrowing rate. Foreign-currency liabilities "
               "(ZAR, KES, GBP, AED) are re-measured to the month-end rate (IAS 21); ROU assets stay at the historical rate.")
    if can("lease.manage"):
        with st.expander("➕ Add a new lease"):
            offs = query("SELECT office_id, name FROM offices ORDER BY office_id")
            lords = query("SELECT vendor_id, name FROM vendors WHERE vendor_type = 'landlord' ORDER BY name")
            with st.form("lease", clear_on_submit=True):
                x, y = st.columns(2)
                no = x.text_input("Lease number *", f"LSE-NEW-{date.today():%y%m}")
                desc = y.text_input("Description *")
                x, y, z = st.columns(3)
                off = x.selectbox("Office", offs.office_id, format_func=lambda i: offs.set_index("office_id").name[i])
                lord = y.selectbox("Landlord", lords.vendor_id, format_func=lambda i: lords.set_index("vendor_id").name[i])
                cur = z.selectbox("Currency", ["USD", "ZAR", "KES", "GBP", "AED"])
                x, y, z = st.columns(3)
                start = x.date_input("Commencement", date.today().replace(day=1))
                term = y.number_input("Term (months)", 1, 240, 36)
                pay = z.number_input("Monthly rent (lease currency)", 0.0, step=100.0)
                x, y = st.columns(2)
                ibr = x.number_input("Incremental borrowing rate %", 0.0, 50.0, 12.0)
                esc = y.number_input("Annual escalation %", 0.0, 30.0, 0.0)
                if st.form_submit_button("Create & recognise", type="primary") and no and desc and pay > 0:
                    run_action("""WITH l AS (INSERT INTO leases (lease_number, description, office_id, vendor_id, currency_code, commencement_date,
                                                                  end_date, term_months, payment_amount, discount_rate_pct, annual_escalation_pct)
                                             VALUES (:n, :d, :o, :v, :c, :s, (CAST(:s AS DATE) + make_interval(months => :t) - INTERVAL '1 day')::DATE,
                                                     :t, :p, :r, :e) RETURNING lease_id)
                                  SELECT lease_id FROM l""",
                               {"n": no, "d": desc, "o": int(off), "v": int(lord), "c": cur, "s": start, "t": int(term), "p": pay,
                                "r": ibr, "e": esc},
                               success="Lease {result} saved as draft - click 'Recognise' below to post it.")
        drafts = reg[(reg.status == "draft") & (reg.role == "lessee")]
        if not drafts.empty:
            lid = st.selectbox("Draft lease to recognise", drafts.lease_id, format_func=lambda i: drafts.set_index("lease_id").lease_number[i])
            if st.button("Recognise lease (Dr ROU asset / Cr lease liability)", type="primary"):
                run_action("SELECT fn_recognise_lease(:l, :u)",
                           {"l": int(lid), "u": st.session_state["app_user_id"]}, success="Lease recognised - right-of-use asset and lease liability posted.")

with tabs[1]:
    if lessee.empty:
        st.info("No leases.")
    else:
        lid = st.selectbox("Lease", lessee.lease_id, format_func=lambda i: f"{lessee.set_index('lease_id').lease_number[i]} - "
                                                                          f"{lessee.set_index('lease_id').description[i]}")
        sch = query("""SELECT period_no, period_date, opening_liability, payment, interest, principal, closing_liability,
                              rou_depreciation, is_posted FROM lease_schedule WHERE lease_id = :l ORDER BY period_no""", {"l": int(lid)})
        fig = px.area(sch, x="period_date", y="closing_liability", color_discrete_sequence=[BRAND],
                      labels={"closing_liability": "Liability (lease currency)", "period_date": ""})
        fig.update_layout(height=280, margin=dict(t=10, b=10))
        st.plotly_chart(fig, width="stretch")
        table(sch, num_cols=["opening_liability", "payment", "interest", "principal", "closing_liability", "rou_depreciation"], height=350)

with tabs[2]:
    posted = query("""SELECT to_char(s.period_date, 'YYYY-MM') AS month, COUNT(*) AS leases_posted
                        FROM lease_schedule s JOIN leases l USING (lease_id)
                       WHERE s.is_posted AND s.journal_entry_id IS NOT NULL GROUP BY 1 ORDER BY 1 DESC LIMIT 12""")
    table(posted)
    if can("lease.manage"):
        m = st.date_input("Month to post", date.today().replace(day=1))
        if st.button("Post lease interest, depreciation & rent for this month", type="primary"):
            run_action("SELECT fn_post_lease_month(:m, :u)", {"m": m, "u": st.session_state["app_user_id"]},
                       success="{result} lease(s) posted.")
        st.caption("Posts (1) FX re-measurement, (2) Dr interest expense / Cr lease interest payable and Dr ROU depreciation, "
                   "(3) the rent payment split into interest and principal. Months already posted are skipped.")

with tabs[3]:
    ten = reg[reg.role == "lessor"]
    table(ten[["lease_number", "description", "tenant_name", "commencement_date", "end_date", "months_remaining", "payment_amount", "status"]],
          money_cols=["payment_amount"])
    rent = scalar("SELECT COALESCE(SUM(credit - debit), 0) FROM journal_lines jl JOIN journal_entries je USING (journal_entry_id) "
                  "WHERE jl.account_id = (SELECT fn_account_id('4500')) AND je.entry_date >= date_trunc('year', CURRENT_DATE)")
    st.metric("Rental income this year (investing category)", f"${rent:,.0f}")
    st.caption("Operating leases of floors 5-6 of Maxhub House. Under IFRS 18 rental income from investment property is classified in the investing category.")

with tabs[4]:
    loans = query("SELECT loan_number, lender, purpose, principal, interest_rate_pct, drawdown_date, term_months, monthly_instalment, security, status FROM borrowings")
    table(loans, money_cols=["principal", "monthly_instalment"])
    ls = query("""SELECT period_no, due_date, opening_balance, instalment, interest, principal, closing_balance, is_posted
                    FROM loan_schedule WHERE due_date BETWEEN CURRENT_DATE - 365 AND CURRENT_DATE + 365 ORDER BY period_no""")
    table(ls, money_cols=["opening_balance", "instalment", "interest", "principal", "closing_balance"], height=320)

with tabs[5]:
    ex = reg[reg.exemption.notna()]
    table(ex[["lease_number", "description", "office", "exemption", "commencement_date", "end_date", "payment_amount", "status"]],
          money_cols=["payment_amount"])
    st.caption("IFRS 16.5-8: short-term leases (12 months or less) and leases of low-value assets are expensed straight-line (account 6100).")
