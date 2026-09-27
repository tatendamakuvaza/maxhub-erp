"""Payroll - monthly runs for Zimbabwe and the branches, payslips, statutory deductions, PAYE calculator."""
import plotly.express as px
import streamlit as st

from auth import can, require
from db import query, run_action, scalar
from ui import BRAND, GOLD, me, money, page_header, table

require("page.payroll")
page_header(":material/payments: Payroll", "Zimbabwe (PAYE, AIDS levy, NSSA, ZIMDEF) and branch payrolls (SARS, KRA, HMRC, UAE)")

runs = query("SELECT * FROM v_payroll_summary ORDER BY period_start DESC, country_code")
latest = runs[runs.status.isin(["approved", "paid"])].period_start.max()
cur = runs[runs.period_start == latest]
c1, c2, c3, c4, c5 = st.columns(5)
c1.metric("Headcount paid", int(cur.employee_count.sum()), border=True, help=f"{latest:%B %Y}" if latest is not None else None)
c2.metric("Gross pay (USD)", f"${cur.gross_usd.sum():,.0f}", border=True)
c3.metric("PAYE + AIDS levy", f"${(cur.income_tax_usd.sum() + cur.aids_levy_usd.sum()):,.0f}", border=True)
c4.metric("NSSA / social security", f"${cur.social_security_usd.sum():,.0f}", border=True)
c5.metric("Net pay", f"${cur.net_pay_usd.sum():,.0f}", border=True)

tab_runs, tab_slips, tab_trend, tab_calc = st.tabs(["🗂️ Payroll runs", "🧾 Payslips", "📈 Cost trend", "🧮 PAYE calculator"])

with tab_runs:
    table(runs[["run_number", "country_code", "period_start", "pay_date", "currency_code", "status", "employee_count", "gross_usd",
                "income_tax_usd", "aids_levy_usd", "social_security_usd", "zimdef_usd", "net_pay_usd", "employer_cost_usd"]],
          money_cols=["gross_usd", "income_tax_usd", "aids_levy_usd", "social_security_usd", "zimdef_usd", "net_pay_usd", "employer_cost_usd"],
          height=330)
    drafts = runs[runs.status == "draft"]
    approved = runs[runs.status == "approved"]
    if can("payroll.run"):
        a, b = st.columns(2)
        with a.container(border=True):
            st.markdown("**Approve a draft run** - posts salaries, PAYE, NSSA, ZIMDEF, pension & medical to the ledger")
            if drafts.empty:
                st.caption("No draft runs.")
            else:
                rid = st.selectbox("Draft run", drafts.payroll_run_id, format_func=lambda i: drafts.set_index("payroll_run_id").run_number[i])
                if st.button("Approve & post", type="primary"):
                    run_action("SELECT fn_approve_payroll(:r, :e, :u)",
                               {"r": int(rid), "e": me(), "u": st.session_state["app_user_id"]}, success="Payroll approved and posted to the ledger.")
        with b.container(border=True):
            st.markdown("**Pay net salaries** from the branch's bank account")
            if approved.empty:
                st.caption("No approved runs waiting for payment.")
            else:
                rid = st.selectbox("Approved run", approved.payroll_run_id, format_func=lambda i: approved.set_index("payroll_run_id").run_number[i])
                banks = query("SELECT bank_account_id, name || ' (' || currency_code || ')' AS label FROM bank_accounts WHERE account_type IN ('current','fca') ORDER BY 1")
                bank = st.selectbox("Bank", banks.bank_account_id, format_func=lambda i: banks.set_index("bank_account_id").label[i])
                if st.button("Pay salaries", type="primary"):
                    run_action("SELECT fn_pay_payroll(:r, :b, :u)",
                               {"r": int(rid), "b": int(bank), "u": st.session_state["app_user_id"]}, success="Net salaries paid.")
        with st.expander("➕ Create a payroll run"):
            x, y = st.columns(2)
            ctry = x.selectbox("Country", ["ZW", "ZA", "KE", "GB", "AE"])
            month = y.date_input("Month")
            if st.button("Create run"):
                run_action("SELECT fn_run_payroll(:c, :m, NULL, :u)",
                           {"c": ctry, "m": month.replace(day=1), "u": st.session_state["app_user_id"]}, success="Payroll run created - review it, then approve.")

with tab_slips:
    if not can("payroll.view_all"):
        st.info("You can see your own payslips on the Home page.")
    else:
        rid = st.selectbox("Run", runs.payroll_run_id, format_func=lambda i: runs.set_index("payroll_run_id").run_number[i], key="slips")
        slips = query("""SELECT e.employee_number AS no, e.first_name || ' ' || e.last_name AS employee, d.name AS department,
                                p.currency_code AS ccy, p.basic_pay, p.allowances, p.gross_pay, p.nssa_employee, p.pension, p.taxable_income,
                                p.paye_tax, p.medical_aid_credit, p.aids_levy, p.medical_aid, p.net_pay,
                                p.employer_nssa, p.employer_wcif, p.employer_zimdef, p.employer_pension, p.employer_medical, p.employer_cost
                           FROM payslips p JOIN employees e USING (employee_id) LEFT JOIN departments d ON d.department_id = e.department_id
                          WHERE p.payroll_run_id = :r ORDER BY e.employee_number""", {"r": int(rid)})
        q = st.text_input("🔎 Search employee")
        if q:
            slips = slips[slips.employee.str.lower().str.contains(q.lower())]
        table(slips, num_cols=[c for c in slips.columns if c not in ("no", "employee", "department", "ccy")], height=450)
        st.download_button("⬇️ Download payroll register (CSV)", slips.to_csv(index=False), f"payroll_{rid}.csv", "text/csv")

with tab_trend:
    tr = query("""SELECT period_start AS month, country_code, gross_usd, employer_cost_usd FROM v_payroll_summary
                   WHERE status IN ('approved','paid') ORDER BY 1""")
    fig = px.bar(tr, x="month", y="employer_cost_usd", color="country_code", labels={"employer_cost_usd": "Employer cost (USD)", "month": ""},
                 color_discrete_sequence=[BRAND, GOLD, "#1FA3D8", "#8A9BB3", "#2E6DB4"])
    fig.update_layout(height=380, margin=dict(t=10, b=10), legend=dict(orientation="h", y=1.1))
    st.plotly_chart(fig, width="stretch")

with tab_calc:
    st.markdown("Try the Zimbabwe payroll rules exactly as the database applies them (USD, monthly).")
    x, y, z = st.columns(3)
    gross = x.number_input("Gross monthly pay (USD)", 0.0, 50000.0, 1500.0, step=50.0)
    pension = y.number_input("Pension contribution (USD)", 0.0, 5000.0, 60.0, step=10.0)
    medical = z.number_input("Medical aid contribution (USD)", 0.0, 2000.0, 50.0, step=10.0)
    r = query("""WITH s AS (SELECT LEAST(:g, COALESCE(fn_stat_amount('ZW','NSSA_CEILING',CURRENT_DATE), 700)) * fn_stat_rate('ZW','NSSA_EE',CURRENT_DATE) / 100 AS nssa),
                      t AS (SELECT nssa, GREATEST(:g - nssa - LEAST(:p, COALESCE(fn_stat_amount('ZW','PENSION_CAP',CURRENT_DATE), 450)), 0) AS taxable FROM s),
                      p AS (SELECT nssa, taxable, fn_calc_paye(taxable, CURRENT_DATE) AS paye_before, round(:m * 0.5, 2) AS credit FROM t)
                 SELECT round(nssa, 2) AS nssa, taxable, paye_before, LEAST(credit, paye_before) AS credit,
                        paye_before - LEAST(credit, paye_before) AS paye,
                        round((paye_before - LEAST(credit, paye_before)) * 0.03, 2) AS aids_levy FROM p""",
              {"g": gross, "p": pension, "m": medical}).iloc[0]
    net = gross - r.nssa - pension - r.paye - r.aids_levy - medical
    a, b, c, d = st.columns(4)
    a.metric("NSSA (4.5%, capped)", money(r.nssa), border=True)
    b.metric("Taxable income", money(r.taxable), border=True)
    c.metric("PAYE after medical credit", money(r.paye), border=True)
    d.metric("AIDS levy (3%)", money(r.aids_levy), border=True)
    st.success(f"**Net pay: {money(net)}**".replace("$", "\\$"))
    st.caption("Uses the ZIMRA USD tax table and statutory rates stored in the database (Tax page → Rates & tables).")
