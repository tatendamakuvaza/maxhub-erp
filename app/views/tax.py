"""Tax compliance - ZIMRA (VAT, PAYE, QPDs, WHT), NSSA, ZIMDEF and branch taxes (SARS, KRA, HMRC, FTA)."""
from datetime import date

import plotly.express as px
import streamlit as st

from auth import can, require
from db import query, run_action, scalar
from ui import BRAND, GOLD, md, me, page_header, table

require("page.tax")
page_header(":material/gavel: Tax compliance", "ZIMRA · NSSA · ZIMDEF · SARS · KRA · HMRC · UAE FTA - returns, payments & deadlines")

cal = query("SELECT * FROM v_tax_calendar ORDER BY due_date DESC")
upcoming = cal[(cal.status != "paid") & (cal.status != "cancelled")].sort_values("due_date")
paid_ytd = cal[(cal.status == "paid") & (cal.paid_date.astype(str) >= f"{date.today().year}-01-01")]

c1, c2, c3, c4 = st.columns(4)
c1.metric("Open returns", len(upcoming), border=True)
c2.metric("Overdue", int((upcoming.status == "overdue").sum()), border=True, delta_color="inverse")
nxt = upcoming.iloc[0] if not upcoming.empty else None
c3.metric("Next deadline", f"{nxt.due_date:%d %b}" if nxt is not None else "–", delta=nxt.return_number if nxt is not None else None,
          delta_color="off", border=True)
c4.metric("Paid to authorities this year", f"${paid_ytd.amount_paid.sum():,.0f}", border=True)

tabs = st.tabs(["📅 Calendar & returns", "🧾 VAT", "👥 PAYE / NSSA / ZIMDEF", "🏢 Corporate tax & QPDs",
                "✂️ Withholding tax & clearances", "📚 Rates & tables"])

# ------------------------------------------------------------------ calendar
with tabs[0]:
    f1, f2 = st.columns(2)
    auth_f = f1.multiselect("Authority", sorted(cal.authority_code.unique()))
    stat_f = f2.multiselect("Status", ["draft", "filed", "overdue", "paid"], default=["draft", "filed", "overdue"])
    view = cal.copy()
    if auth_f:
        view = view[view.authority_code.isin(auth_f)]
    if stat_f:
        view = view[view.status.isin(stat_f)]
    table(view[["return_number", "tax_name", "authority_code", "return_form", "office", "period_start", "period_end",
                "due_date", "days_to_due", "amount_due", "amount_paid", "status", "filed_date", "paid_date", "acknowledgement_ref"]],
          money_cols=["amount_due", "amount_paid"], height=380 if len(view) > 10 else None)

    if can("tax.manage"):
        st.markdown("##### Prepare, file and pay")
        a, b = st.columns(2)
        with a.container(border=True):
            st.markdown("**Prepare returns for a month**")
            month = st.date_input("Month (any day in it)", date(date.today().year, date.today().month, 1), key="taxm")
            x, y = st.columns(2)
            if x.button("Prepare VAT7", icon=":material/calculate:"):
                run_action("SELECT fn_prepare_vat_return(:m, :e)",
                           {"m": month, "e": me()}, success="VAT return prepared from the ledger - see the calendar.")
            if y.button("Prepare P2 / P4 / ZIMDEF", icon=":material/calculate:"):
                run_action("SELECT fn_prepare_payroll_returns(:m, :e)", {"m": month, "e": me()},
                           success="{result} payroll return(s) prepared from approved payroll runs.")
        with b.container(border=True):
            st.markdown("**File or pay a return**")
            open_r = upcoming[upcoming.status.isin(["draft", "filed", "overdue"])]
            if open_r.empty:
                st.info("Nothing open.")
            else:
                rid = st.selectbox("Return", open_r.tax_return_id,
                                   format_func=lambda i: f"{open_r.set_index('tax_return_id').return_number[i]} - "
                                                         f"${open_r.set_index('tax_return_id').amount_due[i]:,.2f} due "
                                                         f"{open_r.set_index('tax_return_id').due_date[i]:%d %b}")
                banks = query("SELECT bank_account_id, name || ' (' || currency_code || ')' AS label FROM bank_accounts WHERE is_active ORDER BY bank_account_id")
                bank = st.selectbox("Pay from", banks.bank_account_id, format_func=lambda i: banks.set_index("bank_account_id").label[i])
                x, y = st.columns(2)
                if x.button("Mark as filed", icon=":material/upload_file:"):
                    run_action("SELECT fn_file_tax_return(:r, CURRENT_DATE)", {"r": int(rid)}, success="Return filed.")
                if y.button("Pay now", type="primary", icon=":material/payments:"):
                    run_action("SELECT fn_pay_tax_return(:r, :b, CURRENT_DATE)",
                               {"r": int(rid), "b": int(bank)}, success="Return paid and posted to the ledger.")

# ------------------------------------------------------------------ VAT
with tabs[1]:
    vat = query("""SELECT to_char(period_start, 'YYYY-MM') AS month, gross_amount AS output_vat, credits_amount AS input_vat,
                          amount_due AS net_payable, status::text AS status
                     FROM tax_returns WHERE tax_code = 'VAT' ORDER BY period_start""")
    fig = px.bar(vat, x="month", y=["output_vat", "input_vat"], barmode="group", color_discrete_sequence=[BRAND, GOLD],
                 labels={"value": "USD", "month": "", "variable": ""})
    fig.update_layout(height=320, margin=dict(t=10, b=10), legend=dict(orientation="h", y=1.1))
    st.plotly_chart(fig, width="stretch")
    table(vat.sort_values("month", ascending=False), money_cols=["output_vat", "input_vat", "net_payable"], height=300)
    st.caption("Standard rate 15.5%. Services exported to non-residents are zero-rated. Every tax invoice is fiscalised through "
               "ZIMRA FDMS - see the fiscal number on each invoice on the Billing page.")
    fdms = query("""SELECT invoice_number, invoice_date, fiscal_invoice_number, fiscal_verification_code, total_amount
                      FROM invoices WHERE fiscal_invoice_number IS NOT NULL ORDER BY invoice_date DESC LIMIT 10""")
    with st.expander("Latest fiscalised invoices (FDMS)"):
        table(fdms, money_cols=["total_amount"])

# ------------------------------------------------------------------ payroll taxes
with tabs[2]:
    ps = query("""SELECT to_char(period_start, 'YYYY-MM') AS month, SUM(income_tax_usd) AS paye, SUM(aids_levy_usd) AS aids_levy,
                         SUM(social_security_usd) AS nssa_social, SUM(wcif_other_usd) AS wcif_other, SUM(zimdef_usd) AS zimdef
                    FROM v_payroll_summary WHERE country_code = 'ZW' AND status IN ('approved','paid') GROUP BY 1 ORDER BY 1""")
    fig = px.bar(ps, x="month", y=["paye", "aids_levy", "nssa_social", "wcif_other", "zimdef"],
                 labels={"value": "USD", "month": "", "variable": ""},
                 color_discrete_sequence=[BRAND, "#8A9BB3", GOLD, "#1FA3D8", "#2E6DB4"])
    fig.update_layout(height=320, margin=dict(t=10, b=10), legend=dict(orientation="h", y=1.1))
    st.plotly_chart(fig, width="stretch")
    table(ps.sort_values("month", ascending=False), money_cols=["paye", "aids_levy", "nssa_social", "wcif_other", "zimdef"], height=300)
    st.caption("P2 (PAYE + 3% AIDS levy) and NSSA P4 are due by the 10th of the following month. NSSA: 4.5% employee + 4.5% employer "
               "on insurable earnings up to USD 700 a month, plus employer WCIF. ZIMDEF: 1% of the wage bill.")

# ------------------------------------------------------------------ corporate tax
with tabs[3]:
    q = query("""SELECT return_number, due_date, amount_due, amount_paid, status::text AS status, paid_date, notes
                   FROM tax_returns WHERE tax_code IN ('CIT_QPD','CIT_FINAL') ORDER BY due_date DESC""")
    table(q, money_cols=["amount_due", "amount_paid"])
    st.caption("Corporate income tax 24% plus AIDS levy of 3% of the tax (effective 24.72%). QPDs: 25 March 10%, 25 June 25%, "
               "25 September 30%, 20 December 35% of the estimated annual tax. Final self-assessment ITF12C by 30 April.")
    br = query("""SELECT return_number, t.tax_code, o.name AS branch, amount_due, status::text AS status, paid_date
                    FROM tax_returns t LEFT JOIN offices o USING (office_id) WHERE t.tax_code IN ('ZA_CIT','KE_CIT','GB_CT','AE_CT')""")
    st.markdown("##### Branch corporate taxes")
    table(br, money_cols=["amount_due"])
    st.caption("Branches pay local tax: SARS 27%, KRA 30% (branch rate), HMRC 25%, UAE 9% above AED 375,000. Double-tax relief is claimed in Zimbabwe.")

# ------------------------------------------------------------------ WHT & clearances
with tabs[4]:
    a, b = st.columns(2)
    with a:
        st.markdown("##### Withholding tax deducted from suppliers")
        w = query("""SELECT w.deduction_date, v.name AS supplier, w.wht_type, w.gross_amount, w.rate_pct, w.wht_amount
                       FROM withholding_tax_deductions w JOIN vendors v USING (vendor_id) ORDER BY w.deduction_date DESC""")
        table(w, money_cols=["gross_amount", "wht_amount"], height=350)
    with b:
        st.markdown("##### Supplier tax clearance (ITF263)")
        v = query("""SELECT vendor_code, name, vendor_type, tax_clearance_expiry,
                            CASE WHEN NOT is_resident THEN 'non-resident'
                                 WHEN vendor_type IN ('government','utility') THEN 'exempt'
                                 WHEN tax_clearance_expiry IS NULL OR tax_clearance_expiry < CURRENT_DATE THEN '⚠️ withhold 30%'
                                 ELSE 'valid' END AS clearance
                       FROM vendors WHERE is_active ORDER BY 5, 2""")
        table(v, height=350)
        comp = query("SELECT certificate_no, issue_date, expiry_date FROM tax_clearance_certificates WHERE holder_type = 'company'")
        if not comp.empty:
            st.success(md(f"Maxhub's own ITF263: **{comp.certificate_no[0]}**, valid to {comp.expiry_date[0]:%d %b %Y} - "
                          "clients must not withhold 30% from our invoices."))

# ------------------------------------------------------------------ rates
with tabs[5]:
    st.markdown("##### Statutory rates (edit these when the law changes - no code changes needed)")
    table(query("""SELECT country_code, rate_code, description, rate_pct, amount, currency_code, effective_from, source_note
                     FROM statutory_rates ORDER BY country_code DESC, rate_code"""), height=330)
    a, b = st.columns(2)
    with a:
        st.markdown("##### ZIMRA PAYE table (USD, monthly)")
        table(query("""SELECT effective_from, lower_limit, upper_limit, rate_pct, deduct_amount AS less
                         FROM paye_tax_bands WHERE effective_from = (SELECT max(effective_from) FROM paye_tax_bands) ORDER BY lower_limit"""))
    with b:
        st.markdown("##### VAT / sales-tax codes")
        table(query("SELECT code, name, rate_percent, gl_account_code FROM tax_rates ORDER BY code"))
    st.caption("⚠️ Rates are demo values based on published 2025/2026 figures - always confirm against current ZIMRA and NSSA public notices.")
