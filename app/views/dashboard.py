"""Dashboard - firm-wide KPIs and charts."""
import plotly.express as px
import streamlit as st

from db import query, scalar
from ui import BRAND, CYAN, GOLD, page_header, rag_style, short_money, table
from auth import can, require

require("page.dashboard")
page_header(":material/space_dashboard: Dashboard", "Firm performance at a glance")

# ------------------------------------------------------------------ KPIs
revenue_ytd = scalar("""
    SELECT COALESCE(SUM(amount), 0) FROM v_income_statement_monthly
     WHERE account_type = 'revenue' AND extract(year FROM month_start) = extract(year FROM CURRENT_DATE)""")
expenses_ytd = scalar("""
    SELECT COALESCE(SUM(amount), 0) FROM v_income_statement_monthly
     WHERE account_type = 'expense' AND extract(year FROM month_start) = extract(year FROM CURRENT_DATE)""")
ar = scalar("SELECT COALESCE(SUM(balance_due), 0) FROM v_ar_aging WHERE currency_code = 'USD'")
overdue = scalar("SELECT COALESCE(SUM(balance_due), 0) FROM v_ar_aging WHERE days_overdue > 0 AND currency_code = 'USD'")
wip = scalar("SELECT COALESCE(SUM(unbilled_wip), 0) FROM v_project_financials WHERE status = 'active'")
active_projects = scalar("SELECT COUNT(*) FROM projects WHERE status = 'active' AND NOT is_internal")
# open pipeline converted to USD using the latest exchange rate
pipeline = scalar("""
    SELECT COALESCE(SUM(o.weighted_value * COALESCE(fx.rate, 1)), 0)
      FROM opportunities o
      LEFT JOIN LATERAL (SELECT rate FROM exchange_rates x
                          WHERE x.from_currency = o.currency_code AND x.to_currency = 'USD'
                          ORDER BY rate_date DESC LIMIT 1) fx ON TRUE
     WHERE o.stage NOT IN ('won', 'lost')""")
# utilisation of the last COMPLETE month (the current month is still being booked)
util = query("""SELECT u.*, COALESCE(d.name, 'Other') AS practice
                  FROM v_employee_utilization_monthly u
                  JOIN employees e ON e.employee_id = u.employee_id
                  LEFT JOIN departments d ON d.department_id = e.department_id
                 WHERE u.month_start = (SELECT MAX(month_start) FROM v_employee_utilization_monthly
                                         WHERE month_start < date_trunc('month', CURRENT_DATE))""")
avg_util = util["utilization_pct"].mean() if not util.empty else 0

c1, c2, c3, c4, c5, c6 = st.columns(6)
c1.metric("Revenue YTD", short_money(revenue_ytd), border=True)
c2.metric("Net profit YTD", short_money(revenue_ytd - expenses_ytd), border=True,
          help="Revenue minus expenses posted to the general ledger")
c3.metric("Receivables", short_money(ar), delta=f"{short_money(overdue)} overdue",
          delta_color="inverse" if overdue else "off", border=True)
c4.metric("Unbilled WIP", short_money(wip), border=True, help="Work done but not yet invoiced")
c5.metric("Weighted pipeline", short_money(pipeline), border=True)
c6.metric("Avg utilisation", f"{avg_util:.0f}%", help="Billable hours ÷ available hours, latest month",
          border=True)

st.write("")

# ------------------------------------------------------------------ row 1: revenue & utilisation
left, right = st.columns(2)

with left:
    st.subheader("Revenue vs expenses by month")
    pl = query("""
        SELECT to_char(month_start, 'Mon YYYY') AS month, month_start, account_type, SUM(amount) AS amount
          FROM v_income_statement_monthly GROUP BY 1, 2, 3 ORDER BY 2""")
    if pl.empty:
        st.info("No posted revenue yet - issue an invoice on the Billing page.")
    else:
        fig = px.bar(pl, x="month", y="amount", color="account_type", barmode="group",
                     color_discrete_map={"revenue": BRAND, "expense": GOLD},
                     labels={"amount": "USD", "month": "", "account_type": ""})
        fig.update_layout(height=340, margin=dict(t=10, b=10), legend=dict(orientation="h", y=1.1))
        st.plotly_chart(fig, width="stretch")

with right:
    st.subheader("Utilisation by practice")
    if util.empty:
        st.info("No approved timesheets yet.")
    else:
        u = (util.groupby("practice", as_index=False)
                 .agg(billable_hours=("billable_hours", "sum"), capacity_hours=("capacity_hours", "sum"),
                      target=("target_utilization_pct", "mean"), people=("employee_id", "count")))
        u["utilization_pct"] = (100 * u.billable_hours / u.capacity_hours).round(1)
        u = u.sort_values("utilization_pct")
        fig = px.bar(u, x="utilization_pct", y="practice", orientation="h", text="utilization_pct",
                     color_discrete_sequence=[BRAND], labels={"utilization_pct": "%", "practice": ""},
                     hover_data=["people", "billable_hours", "capacity_hours"])
        fig.add_scatter(x=u["target"], y=u["practice"], mode="markers",
                        marker=dict(symbol="line-ns", size=22, line=dict(width=3, color=GOLD)), name="Target")
        fig.update_layout(height=340, margin=dict(t=10, b=10), legend=dict(orientation="h", y=1.1))
        st.plotly_chart(fig, width="stretch")
        st.caption(f"{util['month_start'].iloc[0]:%B %Y} (last complete month) · gold marker = average target · "
                   f"{len(util)} fee earners")

# ------------------------------------------------------------------ row 2: pipeline & AR ageing
left, right = st.columns(2)

with left:
    st.subheader("Sales pipeline")
    pipe = query("""
        SELECT stage::text AS stage, COUNT(*) AS deals, SUM(estimated_value) AS value
          FROM opportunities WHERE stage NOT IN ('won','lost') AND currency_code = 'USD'
         GROUP BY stage ORDER BY stage""")   # enums sort in pipeline order
    if pipe.empty:
        st.info("No open opportunities.")
    else:
        fig = px.funnel(pipe, x="value", y="stage", color_discrete_sequence=[CYAN])
        fig.update_layout(height=300, margin=dict(t=10, b=10))
        st.plotly_chart(fig, width="stretch")

with right:
    st.subheader("Receivables ageing")
    aging = query("""
        SELECT SUM(current_due) AS "Current", SUM(days_1_30) AS "1-30", SUM(days_31_60) AS "31-60",
               SUM(days_61_90) AS "61-90", SUM(days_over_90) AS "90+"
          FROM v_ar_aging WHERE currency_code = 'USD'""").melt(var_name="bucket", value_name="amount")
    aging["amount"] = aging["amount"].fillna(0)
    fig = px.bar(aging, x="bucket", y="amount", color="bucket",
                 color_discrete_sequence=["#27AE60", "#F1C40F", "#E67E22", "#E74C3C", "#8E0000"],
                 labels={"amount": "USD", "bucket": "Days overdue"})
    fig.update_layout(height=300, margin=dict(t=10, b=10), showlegend=False)
    st.plotly_chart(fig, width="stretch")

# ------------------------------------------------------------------ row 3: project health
st.subheader("Project health")
health = query("""
    SELECT project_code AS "Code", project_name AS "Project", project_manager AS "PM",
           overall_rag AS "Overall", schedule_rag AS "Schedule", budget_rag AS "Budget",
           completion_pct AS "Complete %", hours_burn_pct AS "Hours burn %",
           gross_margin_pct AS "Margin %", open_risks AS "Risks", open_issues AS "Issues",
           overdue_deliverables AS "Overdue deliverables"
      FROM v_project_health WHERE project_code NOT LIKE 'INT-%' ORDER BY project_code""")
st.dataframe(rag_style(health, ["Overall", "Schedule", "Budget"]), width="stretch", hide_index=True)

st.subheader("Project profitability")
fin = query("""SELECT project_code, project_name, client, billing_type, budget_fees, revenue_earned,
                      invoiced_net, unbilled_wip, labour_cost, expense_cost + subcontractor_cost AS other_costs,
                      gross_margin, gross_margin_pct
                 FROM v_project_financials ORDER BY project_code""")
table(fin, money_cols=["budget_fees", "revenue_earned", "invoiced_net", "unbilled_wip",
                       "labour_cost", "other_costs", "gross_margin"], pct_cols=["gross_margin_pct"])
