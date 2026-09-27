"""Home - every employee's personal workspace: my week, approvals, notices, assets, payslips."""
from datetime import date

import streamlit as st

from auth import can
from db import query, run_action, scalar
from ui import md, me, monday, money, page_header, table

emp = me()
first = st.session_state["employee_name"].split()[0]
page_header(f":material/home: Good day, {first}", f"{st.session_state['job_title']} · {st.session_state['department']} · "
                                                  f"{st.session_state['office']}")

# ------------------------------------------------------------------ my numbers
week = monday(date.today())
hours = scalar("SELECT COALESCE(total_hours, 0) FROM timesheets WHERE employee_id = :e AND week_start_date = :w", {"e": emp, "w": week})
ts_status = scalar("SELECT status::text FROM timesheets WHERE employee_id = :e AND week_start_date = :w", {"e": emp, "w": week})
leave_left = scalar("""SELECT COALESCE(SUM(lb.remaining_days), 0) FROM leave_balances lb JOIN leave_types lt USING (leave_type_id)
                        WHERE lb.employee_id = :e AND lt.code = 'AL' AND lb.leave_year = extract(year FROM CURRENT_DATE)""", {"e": emp})
unread = scalar("SELECT COUNT(*) FROM message_recipients WHERE recipient_id = :e AND read_at IS NULL AND NOT is_archived", {"e": emp})
approvals = scalar("""
    SELECT (SELECT COUNT(*) FROM timesheets t JOIN employees e USING (employee_id) WHERE t.status = 'submitted' AND e.manager_id = :e)
         + (SELECT COUNT(*) FROM expense_reports r JOIN employees e USING (employee_id) WHERE r.status = 'submitted' AND e.manager_id = :e)
         + (SELECT COUNT(*) FROM leave_requests l WHERE l.status = 'submitted' AND l.approver_id = :e)""", {"e": emp})

c1, c2, c3, c4 = st.columns(4)
c1.metric("My hours this week", f"{float(hours or 0):g} h", delta=(ts_status or "not started").replace("_", " "), delta_color="off", border=True)
c2.metric("Annual leave left", f"{float(leave_left or 0):g} days", border=True)
c3.metric("Unread messages", unread, border=True)
c4.metric("Waiting for my approval", approvals, border=True,
          help="Timesheets, expense claims and leave requests from people who report to you")

left, right = st.columns([3, 2])

# ------------------------------------------------------------------ notices
with left:
    st.subheader("📢 Company notices")
    notes = query("""SELECT announcement_id, title, body, category, author, publish_at, is_pinned, is_read
                       FROM v_employee_announcements WHERE employee_id = :e
                      ORDER BY is_pinned DESC, publish_at DESC LIMIT 6""", {"e": emp})
    if notes.empty:
        st.info("No notices right now.")
    for _, n in notes.iterrows():
        with st.container(border=True):
            pin = "📌 " if n.is_pinned else ""
            new = " :red-badge[new]" if not n.is_read else ""
            st.markdown(f"**{pin}{md(n.title)}**{new}  \n:small[{n.category.replace('_', ' ').title()} · {n.author} · "
                        f"{n.publish_at:%d %b %Y}]")
            st.markdown(md(n.body))
            if not n.is_read and st.button("Mark as read", key=f"ann{n.announcement_id}", type="tertiary"):
                run_action("INSERT INTO announcement_reads (announcement_id, employee_id) VALUES (:a, :e) ON CONFLICT DO NOTHING",
                           {"a": int(n.announcement_id), "e": emp}, success="Marked as read.")

# ------------------------------------------------------------------ calendar, my team
with right:
    st.subheader("🗓️ Coming up")
    ev = query("""SELECT to_char(starts_at AT TIME ZONE 'Africa/Harare', 'DD Mon') AS date, title, event_type AS type, location
                    FROM calendar_events WHERE starts_at >= CURRENT_DATE - 1 ORDER BY starts_at LIMIT 6""")
    table(ev)
    if approvals:
        st.warning(f"You have **{approvals}** item(s) to approve - see *Timesheets*, *Expenses* and *People & leave*.", icon="✅")
    mgr = query("""SELECT m.first_name || ' ' || m.last_name AS manager, m.email, m.work_phone_ext AS ext
                     FROM employees e JOIN employees m ON m.employee_id = e.manager_id WHERE e.employee_id = :e""", {"e": emp})
    if not mgr.empty:
        st.caption(f"Your manager: **{mgr.manager[0]}** · {mgr.email[0]} · ext {mgr.ext[0]}")

# ------------------------------------------------------------------ my equipment & payslips
st.divider()
a, b = st.columns(2)
with a:
    st.subheader("💻 Equipment assigned to me")
    my_assets = query("""SELECT fa.asset_tag, fa.name, fa.serial_number, aa.assigned_date
                           FROM asset_assignments aa JOIN fixed_assets fa USING (asset_id)
                          WHERE aa.employee_id = :e AND aa.returned_date IS NULL ORDER BY aa.assigned_date""", {"e": emp})
    if my_assets.empty:
        st.info("No company equipment is registered to you.")
    else:
        table(my_assets)
        st.caption("Lost or damaged equipment? Report it to facilities@maxhub.co.zw or IT Support.")
with b:
    st.subheader("🧾 My payslips")
    slips = query("""SELECT to_char(r.period_start, 'Mon YYYY') AS month, p.currency_code AS ccy, p.gross_pay, p.paye_tax + p.aids_levy AS tax,
                            p.nssa_employee AS social_security, p.pension, p.medical_aid, p.net_pay, r.status
                       FROM payslips p JOIN payroll_runs r USING (payroll_run_id)
                      WHERE p.employee_id = :e ORDER BY r.period_start DESC LIMIT 12""", {"e": emp})
    if slips.empty:
        st.info("No payslips yet.")
    else:
        latest = slips.iloc[0]
        st.metric(f"Net pay {latest.month}", money(latest.net_pay, latest.ccy))
        table(slips, num_cols=["gross_pay", "tax", "social_security", "pension", "medical_aid", "net_pay"])

if can("report.financial"):
    st.divider()
    rev = scalar("""SELECT COALESCE(SUM(amount), 0) FROM v_income_statement_monthly
                     WHERE account_type = 'revenue' AND extract(year FROM month_start) = extract(year FROM CURRENT_DATE)""")
    st.caption(f"Firm revenue year-to-date: **{money(rev)}** - see *Financial statements* for the IFRS 18 view.")
