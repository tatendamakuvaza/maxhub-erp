"""Projects - portfolio list, project detail, tasks, team, risks and status reports."""
from datetime import date, timedelta

import pandas as pd
import plotly.graph_objects as go
import streamlit as st

from db import query, run_action
from ui import BRAND, has_role, me, page_header, rag_style, table, empty_note
from auth import can, require

require("page.projects")
page_header(":material/folder_open: Projects", "Engagements, tasks, staffing and delivery governance")

STATUSES = ["planned", "active", "on_hold", "completed", "cancelled"]
TASK_STATUSES = ["todo", "in_progress", "review", "done", "blocked"]
PRIORITIES = ["low", "medium", "high", "critical"]

employees = query("""SELECT employee_id, first_name || ' ' || last_name AS name FROM employees
                      WHERE status = 'active' ORDER BY name""")
emp_names = dict(zip(employees.employee_id, employees.name))

# ------------------------------------------------------------------ new project
with st.expander("➕ Create a new project", expanded=False):
    if not can("project.manage"):
        st.warning("Only project managers and partners can create projects.")
    else:
        clients = query("SELECT client_id, legal_name FROM clients WHERE status IN ('active','prospect') ORDER BY 2")
        lines = query("SELECT service_line_id, name FROM service_lines WHERE is_active ORDER BY name")
        contracts = query("SELECT contract_id, contract_number || ' - ' || title AS label, client_id FROM contracts ORDER BY 1")
        with st.form("new_project", clear_on_submit=True):
            c1, c2, c3 = st.columns(3)
            code = c1.text_input("Project code *", placeholder="P26-004")
            name = c2.text_input("Project name *")
            client = c3.selectbox("Client *", clients.client_id, format_func=lambda i: clients.set_index("client_id").legal_name[i])
            c1, c2, c3 = st.columns(3)
            contract = c1.selectbox("Contract (optional)", [None] + contracts.contract_id.tolist(),
                                    format_func=lambda i: "— none —" if i is None else contracts.set_index("contract_id").label[i])
            sline = c2.selectbox("Service line", lines.service_line_id, format_func=lambda i: lines.set_index("service_line_id").name[i])
            billing = c3.selectbox("Billing type", ["time_and_materials", "fixed_fee", "milestone", "retainer"])
            c1, c2, c3 = st.columns(3)
            pm = c1.selectbox("Project manager", employees.employee_id, format_func=emp_names.get)
            partner = c2.selectbox("Engagement partner", employees.employee_id, format_func=emp_names.get)
            priority = c3.selectbox("Priority", PRIORITIES, index=1)
            c1, c2, c3, c4 = st.columns(4)
            start = c1.date_input("Start date", date.today())
            end = c2.date_input("Planned end", date.today() + timedelta(days=90))
            bhours = c3.number_input("Budget hours", min_value=0.0, step=10.0)
            bfees = c4.number_input("Budget fees (USD)", min_value=0.0, step=1000.0)
            desc = st.text_area("Description")
            if st.form_submit_button("Create project", type="primary"):
                if not code or not name:
                    st.error("Project code and name are required.")
                else:
                    run_action("""
                        INSERT INTO projects (project_code, name, description, client_id, contract_id, service_line_id,
                               project_manager_id, engagement_partner_id, billing_type, priority, start_date,
                               planned_end_date, budget_hours, budget_fees, status)
                        VALUES (:code, :name, :desc, :client, :contract, :sl, :pm, :ptr, CAST(:bt AS contract_type),
                                CAST(:pri AS priority_level), :start, :end, :bh, :bf, 'active')""",
                        dict(code=code.strip(), name=name.strip(), desc=desc, client=int(client),
                             contract=int(contract) if contract else None, sl=int(sline), pm=int(pm), ptr=int(partner),
                             bt=billing, pri=priority, start=start, end=end, bh=bhours, bf=bfees),
                        success=f"Project {code} created. Add team members in the Team tab so they can log time.")

# ------------------------------------------------------------------ portfolio list
status_filter = st.multiselect("Status", STATUSES, default=["planned", "active", "on_hold"])
projects = query("""
    SELECT p.project_id, p.project_code, p.name, COALESCE(c.legal_name, 'Internal') AS client, p.status::text AS status,
           p.billing_type::text AS billing, pm.first_name || ' ' || pm.last_name AS manager,
           p.start_date, p.planned_end_date, p.completion_pct, p.budget_hours, p.budget_fees
      FROM projects p
      LEFT JOIN clients c    ON c.client_id = p.client_id
      LEFT JOIN employees pm ON pm.employee_id = p.project_manager_id
     WHERE p.status::text = ANY(:st)
     ORDER BY p.is_internal, p.project_code""", {"st": status_filter or STATUSES})

if empty_note(projects, "No projects match the filter."):
    st.stop()

table(projects.drop(columns=["project_id"]), money_cols=["budget_fees"], pct_cols=["completion_pct"])

st.divider()
labels = dict(zip(projects.project_id, projects.project_code + " — " + projects.name))
pid = st.selectbox("🔎 Open project", projects.project_id, format_func=labels.get)
proj = query("SELECT * FROM projects WHERE project_id = :p", {"p": int(pid)}).iloc[0]
fin = query("SELECT * FROM v_project_financials WHERE project_id = :p", {"p": int(pid)})

tab_over, tab_tasks, tab_team, tab_risk, tab_status = st.tabs(
    ["📈 Overview", "✅ Tasks", "👥 Team", "⚠️ Risks & issues", "🚦 Status reports"])

# ------------------------------------------------------------------ overview
with tab_over:
    if not fin.empty:
        f = fin.iloc[0]
        c1, c2, c3, c4, c5 = st.columns(5)
        c1.metric("Hours used", f"{f.actual_hours:,.0f} / {f.budget_hours:,.0f}", f"{f.hours_burn_pct or 0:.0f}% burn",
                  delta_color="off", border=True)
        c2.metric("Revenue earned", f"${f.revenue_earned:,.0f}", border=True)
        c3.metric("Invoiced", f"${f.invoiced_net:,.0f}", border=True)
        c4.metric("Unbilled WIP", f"${f.unbilled_wip:,.0f}", border=True)
        c5.metric("Gross margin", f"${f.gross_margin:,.0f}", f"{f.gross_margin_pct or 0:.1f}%", border=True)

        fig = go.Figure()
        fig.add_bar(name="Budget", x=["Fees", "Cost"], y=[f.budget_fees, proj.budget_cost], marker_color="#BDC3C7")
        fig.add_bar(name="Actual", x=["Fees", "Cost"],
                    y=[f.revenue_earned, f.labour_cost + f.expense_cost + f.subcontractor_cost], marker_color=BRAND)
        fig.update_layout(barmode="group", height=280, margin=dict(t=10, b=10), legend=dict(orientation="h", y=1.15))
        st.plotly_chart(fig, width="stretch")
    else:
        st.info("Internal project - no financials.")

    st.markdown("**Phases**")
    table(query("""SELECT seq, name, start_date, end_date, budget_hours, budget_fees, status::text AS status
                     FROM project_phases WHERE project_id = :p ORDER BY seq""", {"p": int(pid)}),
          money_cols=["budget_fees"])

    with st.form("update_project"):
        st.markdown("**Update progress**")
        c1, c2 = st.columns(2)
        new_status = c1.selectbox("Status", STATUSES, index=STATUSES.index(proj.status))
        new_pct = c2.slider("Completion %", 0, 100, int(proj.completion_pct))
        if st.form_submit_button("Save progress"):
            run_action("UPDATE projects SET status = CAST(:s AS project_status), completion_pct = :c WHERE project_id = :p",
                       {"s": new_status, "c": new_pct, "p": int(pid)}, success="Project updated.")

# ------------------------------------------------------------------ tasks
with tab_tasks:
    tasks = query("""
        SELECT t.task_id, t.name AS task, ph.name AS phase, e.first_name || ' ' || e.last_name AS assignee,
               t.status::text AS status, t.priority::text AS priority, t.estimated_hours, t.due_date,
               COALESCE((SELECT SUM(hours) FROM time_entries te WHERE te.task_id = t.task_id), 0) AS hours_logged
          FROM tasks t
          LEFT JOIN project_phases ph ON ph.phase_id = t.phase_id
          LEFT JOIN employees e       ON e.employee_id = t.assignee_id
         WHERE t.project_id = :p ORDER BY ph.seq NULLS LAST, t.due_date""", {"p": int(pid)})
    if not tasks.empty:
        c = st.columns(len(TASK_STATUSES))
        for i, s in enumerate(TASK_STATUSES):
            c[i].metric(s.replace("_", " ").title(), int((tasks.status == s).sum()))
        table(tasks.drop(columns=["task_id"]))

        with st.form("task_status"):
            c1, c2, c3 = st.columns([3, 2, 1])
            tid = c1.selectbox("Task", tasks.task_id, format_func=lambda i: tasks.set_index("task_id").task[i])
            ns = c2.selectbox("New status", TASK_STATUSES)
            c3.write(""); c3.write("")
            if c3.form_submit_button("Update"):
                run_action("""UPDATE tasks SET status = CAST(:s AS task_status),
                                     completed_at = CASE WHEN :s = 'done' THEN now() END
                               WHERE task_id = :t""", {"s": ns, "t": int(tid)}, success="Task updated.")
    else:
        st.info("No tasks yet.")

    phases = query("SELECT phase_id, name FROM project_phases WHERE project_id = :p ORDER BY seq", {"p": int(pid)})
    members = query("""SELECT DISTINCT e.employee_id, e.first_name || ' ' || e.last_name AS name
                         FROM project_members m JOIN employees e USING (employee_id) WHERE m.project_id = :p""", {"p": int(pid)})
    with st.form("new_task", clear_on_submit=True):
        st.markdown("**Add task**")
        c1, c2, c3 = st.columns([3, 2, 2])
        tname = c1.text_input("Task name *")
        tphase = c2.selectbox("Phase", [None] + phases.phase_id.tolist(),
                              format_func=lambda i: "—" if i is None else phases.set_index("phase_id").name[i])
        tassignee = c3.selectbox("Assignee", [None] + members.employee_id.tolist(),
                                 format_func=lambda i: "—" if i is None else members.set_index("employee_id").name[i])
        c1, c2, c3 = st.columns(3)
        tprio = c1.selectbox("Priority", PRIORITIES, index=1)
        test = c2.number_input("Estimated hours", min_value=0.0, step=1.0)
        tdue = c3.date_input("Due date", date.today() + timedelta(days=14))
        if st.form_submit_button("Add task", type="primary"):
            if not tname:
                st.error("Task name is required.")
            else:
                run_action("""INSERT INTO tasks (project_id, phase_id, name, assignee_id, priority, estimated_hours, due_date)
                              VALUES (:p, :ph, :n, :a, CAST(:pr AS priority_level), :e, :d)""",
                           {"p": int(pid), "ph": int(tphase) if tphase else None, "n": tname,
                            "a": int(tassignee) if tassignee else None, "pr": tprio, "e": test, "d": tdue},
                           success="Task added.")

# ------------------------------------------------------------------ team
with tab_team:
    team = query("""
        SELECT e.first_name || ' ' || e.last_name AS name, jg.name AS grade, m.project_role,
               COALESCE(m.bill_rate, e.default_bill_rate) AS bill_rate, m.allocation_pct, m.start_date, m.end_date,
               COALESCE((SELECT SUM(hours) FROM time_entries te WHERE te.project_id = m.project_id
                          AND te.employee_id = m.employee_id), 0) AS hours_logged
          FROM project_members m
          JOIN employees e ON e.employee_id = m.employee_id
          LEFT JOIN job_grades jg ON jg.job_grade_id = e.job_grade_id
         WHERE m.project_id = :p ORDER BY jg.level DESC""", {"p": int(pid)})
    table(team, money_cols=["bill_rate"], pct_cols=["allocation_pct"])
    st.caption("Bill rate shown is the override or the employee default - the contract's rate card is applied when time is logged.")

    with st.form("add_member", clear_on_submit=True):
        st.markdown("**Add team member**")
        c1, c2, c3 = st.columns(3)
        memp = c1.selectbox("Employee", employees.employee_id, format_func=emp_names.get)
        mrole = c2.text_input("Role", "Consultant")
        malloc = c3.slider("Allocation %", 0, 100, 50)
        c1, c2, c3 = st.columns(3)
        mrate = c1.number_input("Bill rate override (0 = use rate card)", min_value=0.0, step=5.0)
        mstart = c2.date_input("From", proj.start_date)
        mend = c3.date_input("To", proj.planned_end_date if pd.notna(proj.planned_end_date) else date.today() + timedelta(days=90))
        if st.form_submit_button("Add to team", type="primary"):
            run_action("""INSERT INTO project_members (project_id, employee_id, project_role, bill_rate, start_date, end_date, allocation_pct)
                          VALUES (:p, :e, :r, NULLIF(:b, 0), :s, :en, :a)""",
                       {"p": int(pid), "e": int(memp), "r": mrole, "b": mrate, "s": mstart, "en": mend, "a": malloc},
                       success=f"{emp_names[memp]} added to the team.")

# ------------------------------------------------------------------ risks & issues
with tab_risk:
    c1, c2 = st.columns(2)
    with c1:
        st.markdown("**Risk register**")
        table(query("""SELECT title, probability AS p, impact AS i, risk_score AS score, status, mitigation
                         FROM project_risks WHERE project_id = :p ORDER BY risk_score DESC""", {"p": int(pid)}))
        with st.form("add_risk", clear_on_submit=True):
            rt = st.text_input("New risk *")
            a, b = st.columns(2)
            rp = a.slider("Probability", 1, 5, 3)
            ri = b.slider("Impact", 1, 5, 3)
            rm = st.text_area("Mitigation", height=70)
            if st.form_submit_button("Add risk") and rt:
                run_action("""INSERT INTO project_risks (project_id, title, probability, impact, mitigation, owner_id)
                              VALUES (:p, :t, :pr, :im, :m, :o)""",
                           {"p": int(pid), "t": rt, "pr": rp, "im": ri, "m": rm, "o": me()}, success="Risk logged.")
    with c2:
        st.markdown("**Issue log**")
        table(query("""SELECT i.title, i.priority::text AS priority, i.status, i.raised_date,
                              a.first_name || ' ' || a.last_name AS assigned_to
                         FROM project_issues i LEFT JOIN employees a ON a.employee_id = i.assigned_to
                        WHERE i.project_id = :p ORDER BY i.raised_date DESC""", {"p": int(pid)}))
        with st.form("add_issue", clear_on_submit=True):
            it = st.text_input("New issue *")
            a, b = st.columns(2)
            ip = a.selectbox("Priority", PRIORITIES, index=1)
            ia = b.selectbox("Assign to", employees.employee_id, format_func=emp_names.get)
            if st.form_submit_button("Log issue") and it:
                run_action("""INSERT INTO project_issues (project_id, title, priority, raised_by, assigned_to)
                              VALUES (:p, :t, CAST(:pr AS priority_level), :rb, :a)""",
                           {"p": int(pid), "t": it, "pr": ip, "rb": me(), "a": int(ia)}, success="Issue logged.")

# ------------------------------------------------------------------ status reports
with tab_status:
    reports = query("""SELECT report_date, overall_rag AS overall, schedule_rag AS schedule, budget_rag AS budget,
                              scope_rag AS scope, summary
                         FROM project_status_reports WHERE project_id = :p ORDER BY report_date DESC""", {"p": int(pid)})
    if not reports.empty:
        st.dataframe(rag_style(reports, ["overall", "schedule", "budget", "scope"]), width="stretch", hide_index=True)
    with st.form("add_status", clear_on_submit=True):
        st.markdown("**New weekly status report**")
        c = st.columns(5)
        rdate = c[0].date_input("Report date", date.today())
        rags = [c[i + 1].selectbox(lbl, ["G", "A", "R"]) for i, lbl in enumerate(["Overall", "Schedule", "Budget", "Scope"])]
        summary = st.text_area("Summary *")
        nxt = st.text_area("Next steps")
        if st.form_submit_button("Publish report", type="primary") and summary:
            run_action("""INSERT INTO project_status_reports (project_id, report_date, overall_rag, schedule_rag,
                                 budget_rag, scope_rag, summary, next_steps, author_id)
                          VALUES (:p, :d, :o, :s, :b, :sc, :sum, :n, :a)""",
                       {"p": int(pid), "d": rdate, "o": rags[0], "s": rags[1], "b": rags[2], "sc": rags[3],
                        "sum": summary, "n": nxt, "a": me()}, success="Status report published.")
