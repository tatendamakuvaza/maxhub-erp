"""Timesheets - log weekly time, submit, and approve your team's timesheets."""
from datetime import date, timedelta

import pandas as pd
import streamlit as st

from db import query, run_action
from ui import has_role, me, monday, page_header, table, empty_note
from auth import can, require

require("page.timesheets")
page_header(":material/schedule: Timesheets", "Log your hours, submit weekly, approve your team")

tab_my, tab_approve, tab_compliance = st.tabs(["📝 My timesheet", "✔️ Approvals", "📋 Compliance"])

STATUS_BADGE = {"draft": "🟦 Draft", "submitted": "🟨 Submitted", "approved": "🟩 Approved", "rejected": "🟥 Rejected"}

# ======================================================================= MY TIMESHEET
def render_my_timesheet():
    picked = st.date_input("Week containing", date.today(), help="Timesheets run Monday to Sunday")
    week = monday(picked)
    days = [week + timedelta(days=i) for i in range(7)]
    st.markdown(f"### Week of {week:%d %b %Y} – {days[-1]:%d %b %Y}")

    ts = query("SELECT * FROM timesheets WHERE employee_id = :e AND week_start_date = :w", {"e": me(), "w": week})

    if ts.empty:
        st.info("You have no timesheet for this week yet.")
        if st.button("➕ Start timesheet for this week", type="primary"):
            run_action("INSERT INTO timesheets (employee_id, week_start_date) VALUES (:e, :w)",
                       {"e": me(), "w": week}, success="Timesheet created - now add your hours.")
        return

    ts = ts.iloc[0]
    ts_id = int(ts.timesheet_id)
    editable = ts.status in ("draft", "rejected")

    c1, c2, c3 = st.columns(3)
    c1.metric("Status", STATUS_BADGE[ts.status])
    c2.metric("Total hours", f"{ts.total_hours:.1f}")
    c3.metric("Billable hours", f"{query('SELECT COALESCE(SUM(hours),0) h FROM time_entries WHERE timesheet_id=:t AND is_billable', {'t': ts_id}).h[0]:.1f}")
    if ts.status == "rejected" and ts.rejection_reason:
        st.error(f"Rejected: {ts.rejection_reason}")

    entries = query("""
        SELECT te.time_entry_id, te.work_date, COALESCE(p.project_code, 'Internal') AS project,
               COALESCE(t.name, '') AS task, te.activity_code, te.hours, te.is_billable, te.bill_rate,
               te.billable_amount, te.description, (te.invoice_line_id IS NOT NULL) AS invoiced
          FROM time_entries te
          LEFT JOIN projects p ON p.project_id = te.project_id
          LEFT JOIN tasks t    ON t.task_id = te.task_id
         WHERE te.timesheet_id = :t ORDER BY te.work_date, project""", {"t": ts_id})

    if not entries.empty:
        # weekly grid: rows = project/activity, columns = days
        grid = entries.assign(day=pd.to_datetime(entries.work_date).dt.strftime("%a %d"),
                              line=entries.project + " · " + entries.activity_code)
        pivot = grid.pivot_table(index="line", columns="day", values="hours", aggfunc="sum", fill_value=0)
        pivot = pivot.reindex(columns=[d.strftime("%a %d") for d in days], fill_value=0)
        pivot["Total"] = pivot.sum(axis=1)
        pivot.loc["Daily total"] = pivot.sum()
        st.dataframe(pivot.style.format("{:.1f}"), width="stretch")
        with st.expander("Entry details"):
            table(entries.drop(columns=["time_entry_id"]), money_cols=["bill_rate", "billable_amount"])
    else:
        st.caption("No hours logged yet.")

    if editable:
        st.markdown("#### Add hours")
        my_projects = query("""
            SELECT p.project_id, p.project_code || ' — ' || p.name AS label, p.is_internal
              FROM project_members m JOIN projects p ON p.project_id = m.project_id
             WHERE m.employee_id = :e AND p.status IN ('active','planned')
               AND :w + 6 >= m.start_date AND :w <= COALESCE(m.end_date, 'infinity'::date)
             ORDER BY p.is_internal, p.project_code""", {"e": me(), "w": week})
        options = [None] + my_projects.project_id.tolist()
        labels = dict(zip(my_projects.project_id, my_projects.label))
        proj = st.selectbox("Project", options, format_func=lambda i: "🏢 Non-project time (admin, leave …)" if i is None else labels[i])
        tasks = query("SELECT task_id, name FROM tasks WHERE project_id = :p AND status <> 'done' ORDER BY name",
                      {"p": int(proj) if proj else -1})
        activities = query("SELECT activity_code, name FROM activity_codes ORDER BY activity_code")

        with st.form("add_time", clear_on_submit=True):
            c1, c2, c3, c4 = st.columns([2, 2, 1, 1])
            wdate = c1.selectbox("Day", days, format_func=lambda d: d.strftime("%A %d %b"),
                                 index=min(date.today().weekday(), 4) if week == monday(date.today()) else 0)
            if proj:
                task = c2.selectbox("Task", [None] + tasks.task_id.tolist(),
                                    format_func=lambda i: "—" if i is None else tasks.set_index("task_id").name[i])
                activity = "CLIENT" if not bool(my_projects.set_index("project_id").is_internal[proj]) else "BD"
            else:
                task = None
                activity = c2.selectbox("Activity", activities.activity_code,
                                        format_func=lambda a: activities.set_index("activity_code").name[a])
            hours = c3.number_input("Hours", min_value=0.25, max_value=24.0, value=8.0, step=0.25)
            billable = c4.checkbox("Billable", value=proj is not None)
            desc = st.text_input("What did you work on?")
            if st.form_submit_button("Add entry", type="primary"):
                run_action("""INSERT INTO time_entries (timesheet_id, employee_id, project_id, task_id, activity_code,
                                                        work_date, hours, is_billable, description)
                              VALUES (:t, :e, :p, :tk, :a, :d, :h, :b, :desc)""",
                           {"t": ts_id, "e": me(), "p": int(proj) if proj else None, "tk": int(task) if task else None,
                            "a": activity, "d": wdate, "h": hours, "b": billable, "desc": desc},
                           success="Hours added.")

        c1, c2 = st.columns(2)
        with c1:
            if not entries.empty:
                with st.form("del_time"):
                    del_id = st.selectbox("Remove an entry", entries.time_entry_id,
                                          format_func=lambda i: (lambda r: f"{r.work_date:%a %d} · {r.project} · {r.hours}h")(
                                              entries.set_index("time_entry_id").loc[i]))
                    if st.form_submit_button("🗑️ Delete entry"):
                        run_action("DELETE FROM time_entries WHERE time_entry_id = :i", {"i": int(del_id)},
                                   success="Entry deleted.")
        with c2:
            st.write("")
            if st.button("📤 Submit timesheet for approval", type="primary", disabled=entries.empty, width="stretch"):
                run_action("CALL sp_submit_timesheet(:t)", {"t": ts_id}, success="Timesheet submitted to your manager.")
    else:
        st.info("This timesheet is locked. Ask your manager to reject it if you need to make changes.")


with tab_my:
    render_my_timesheet()

# ======================================================================= APPROVALS
with tab_approve:
    pending = query("""
        SELECT ts.timesheet_id, e.first_name || ' ' || e.last_name AS employee, ts.week_start_date,
               ts.total_hours, ts.submitted_at,
               COALESCE((SELECT SUM(hours) FROM time_entries x WHERE x.timesheet_id = ts.timesheet_id AND x.is_billable), 0) AS billable_hours
          FROM timesheets ts JOIN employees e ON e.employee_id = ts.employee_id
         WHERE ts.status = 'submitted' AND ts.employee_id <> :me
           AND (e.manager_id = :me OR :senior)
         ORDER BY ts.week_start_date, employee""", {"me": me(), "senior": can("timesheet.approve_all")})
    if not empty_note(pending, "🎉 No timesheets waiting for your approval."):
        table(pending.drop(columns=["timesheet_id"]))
        tid = st.selectbox("Review timesheet", pending.timesheet_id,
                           format_func=lambda i: (lambda r: f"{r.employee} — week of {r.week_start_date:%d %b}")(
                               pending.set_index("timesheet_id").loc[i]))
        table(query("""SELECT te.work_date, COALESCE(p.project_code, 'Internal') AS project, te.activity_code,
                              te.hours, te.is_billable, te.description
                         FROM time_entries te LEFT JOIN projects p ON p.project_id = te.project_id
                        WHERE te.timesheet_id = :t ORDER BY te.work_date""", {"t": int(tid)}))
        c1, c2 = st.columns([1, 2])
        if c1.button("✅ Approve", type="primary", width="stretch"):
            run_action("CALL sp_approve_timesheet(:t, :a)", {"t": int(tid), "a": me()}, success="Timesheet approved.")
        with c2.form("reject"):
            reason = st.text_input("Reason for rejection")
            if st.form_submit_button("❌ Reject"):
                if not reason:
                    st.error("Please give a reason.")
                else:
                    run_action("CALL sp_reject_timesheet(:t, :a, :r)", {"t": int(tid), "a": me(), "r": reason},
                               success="Timesheet sent back to the employee.")

# ======================================================================= COMPLIANCE
with tab_compliance:
    comp = query("SELECT * FROM v_timesheet_compliance ORDER BY week_start_date DESC, employee_name")
    if not empty_note(comp):
        summary = comp.pivot_table(index="employee_name", columns="week_start_date", values="timesheet_status",
                                   aggfunc="first")
        summary.columns = [f"{c:%d %b}" for c in summary.columns]
        icons = {"approved": "🟩", "submitted": "🟨", "draft": "🟦", "rejected": "🟥", "missing": "⬜ missing"}
        st.dataframe(summary.map(lambda v: icons.get(v, v)), width="stretch")
        st.caption("Last four complete weeks. 🟩 approved · 🟨 submitted · 🟦 draft · 🟥 rejected · ⬜ missing")
