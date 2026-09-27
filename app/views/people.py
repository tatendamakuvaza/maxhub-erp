"""People & Leave - staff directory, leave requests, skills and resource capacity."""
from datetime import date, timedelta

import plotly.express as px
import streamlit as st

from db import query, run_action, scalar
from ui import has_role, me, page_header, table, empty_note
from auth import can, require

require("page.people")
page_header(":material/groups: People & Leave", "Directory, leave management, skills and capacity")

tab_dir, tab_leave, tab_skills, tab_cap = st.tabs(["📇 Directory", "🌴 Leave", "🧠 Skills", "📅 Capacity"])

# ------------------------------------------------------------------ directory
with tab_dir:
    staff = query("""
        SELECT e.employee_number AS no, e.first_name || ' ' || e.last_name AS name, e.job_title, jg.name AS grade,
               d.name AS department, sl.name AS service_line, o.name AS office,
               m.first_name || ' ' || m.last_name AS manager, e.email, e.phone, e.hire_date, e.status::text AS status
          FROM employees e
          LEFT JOIN job_grades jg   ON jg.job_grade_id = e.job_grade_id
          LEFT JOIN departments d   ON d.department_id = e.department_id
          LEFT JOIN service_lines sl ON sl.service_line_id = e.service_line_id
          LEFT JOIN offices o       ON o.office_id = e.office_id
          LEFT JOIN employees m     ON m.employee_id = e.manager_id
         ORDER BY jg.level DESC NULLS LAST, name""")
    c1, c2, c3 = st.columns(3)
    c1.metric("Headcount", len(staff[staff.status == "active"]), border=True)
    c2.metric("Fee earners", scalar("SELECT COUNT(*) FROM employees WHERE is_billable AND status='active'"), border=True)
    c3.metric("Offices", staff.office.nunique(), border=True)
    search = st.text_input("🔎 Search by name, title or office")
    if search:
        mask = staff.apply(lambda r: search.lower() in " ".join(map(str, r.values)).lower(), axis=1)
        staff = staff[mask]
    table(staff)

    if can("employee.manage"):
        with st.expander("➕ Add employee (HR)"):
            grades = query("SELECT job_grade_id, name, default_bill_rate, default_cost_rate FROM job_grades ORDER BY level")
            depts = query("SELECT department_id, name FROM departments ORDER BY name")
            offices = query("SELECT office_id, name FROM offices ORDER BY name")
            mgrs = query("SELECT employee_id, first_name || ' ' || last_name AS name FROM employees WHERE status='active' ORDER BY 2")
            with st.form("new_emp", clear_on_submit=True):
                a, b, c = st.columns(3)
                fn = a.text_input("First name *"); ln = b.text_input("Last name *"); em = c.text_input("Email *")
                a, b, c = st.columns(3)
                title = a.text_input("Job title")
                grade = b.selectbox("Grade", grades.job_grade_id, format_func=lambda i: grades.set_index("job_grade_id").name[i])
                hire = c.date_input("Hire date", date.today())
                a, b, c = st.columns(3)
                dept = a.selectbox("Department", depts.department_id, format_func=lambda i: depts.set_index("department_id").name[i])
                office = b.selectbox("Office", offices.office_id, format_func=lambda i: offices.set_index("office_id").name[i])
                mgr = c.selectbox("Manager", mgrs.employee_id, format_func=lambda i: mgrs.set_index("employee_id").name[i])
                if st.form_submit_button("Add employee", type="primary") and fn and ln and em:
                    run_action("""
                        INSERT INTO employees (employee_number, first_name, last_name, email, job_title, job_grade_id, hire_date,
                                               department_id, office_id, manager_id, cost_rate_hourly, default_bill_rate)
                        SELECT 'E' || lpad((COALESCE(MAX(substring(employee_number FROM 2)::int), 0) + 1)::text, 3, '0'),
                               :fn, :ln, :em, :t, :g, :h, :d, :o, :m,
                               (SELECT default_cost_rate FROM job_grades WHERE job_grade_id = :g),
                               (SELECT default_bill_rate FROM job_grades WHERE job_grade_id = :g)
                          FROM employees WHERE employee_number ~ '^E[0-9]+$'
                        RETURNING employee_number""",
                        {"fn": fn, "ln": ln, "em": em, "t": title, "g": int(grade), "h": hire, "d": int(dept),
                         "o": int(office), "m": int(mgr)}, success="Employee {result} added.")

# ------------------------------------------------------------------ leave
with tab_leave:
    st.markdown("#### My leave balances")
    bal = query("""SELECT leave_type, entitled_days, carried_forward_days, taken_days, remaining_days
                      FROM v_leave_balances WHERE employee_number =
                           (SELECT employee_number FROM employees WHERE employee_id = :e)
                       AND leave_year = extract(year FROM CURRENT_DATE)""", {"e": me()})
    if not bal.empty:
        cols = st.columns(len(bal))
        for col, (_, r) in zip(cols, bal.iterrows()):
            col.metric(r.leave_type, f"{r.remaining_days:g} days left", f"{r.taken_days:g} taken", delta_color="off", border=True)

    types = query("SELECT leave_type_id, name FROM leave_types ORDER BY leave_type_id")
    with st.form("leave_req", clear_on_submit=True):
        st.markdown("#### Request leave")
        a, b, c = st.columns(3)
        lt = a.selectbox("Type", types.leave_type_id, format_func=lambda i: types.set_index("leave_type_id").name[i])
        start = b.date_input("From", date.today() + timedelta(days=14))
        end = c.date_input("To", date.today() + timedelta(days=18))
        reason = st.text_input("Reason")
        st.caption("Working days are calculated automatically (weekends and public holidays excluded).")
        if st.form_submit_button("Submit request", type="primary"):
            run_action("""INSERT INTO leave_requests (employee_id, leave_type_id, start_date, end_date, days_requested, reason, status)
                          VALUES (:e, :t, :s, :en, fn_working_days(:s, :en), :r, 'submitted')
                          RETURNING days_requested""",
                       {"e": me(), "t": int(lt), "s": start, "en": end, "r": reason},
                       success="Leave request for {result} working day(s) sent to your manager.")

    st.markdown("#### My requests")
    table(query("""SELECT lt.name AS type, lr.start_date, lr.end_date, lr.days_requested, lr.status::text AS status, lr.reason
                     FROM leave_requests lr JOIN leave_types lt USING (leave_type_id)
                    WHERE lr.employee_id = :e ORDER BY lr.start_date DESC""", {"e": me()}))

    pending = query("""
        SELECT lr.leave_request_id, e.first_name || ' ' || e.last_name AS employee, lt.name AS type,
               lr.start_date, lr.end_date, lr.days_requested, lr.reason
          FROM leave_requests lr JOIN employees e USING (employee_id) JOIN leave_types lt USING (leave_type_id)
         WHERE lr.status = 'submitted' AND lr.employee_id <> :me AND (e.manager_id = :me OR :hr)""",
        {"me": me(), "hr": can("leave.approve_all")})
    st.markdown("#### Waiting for my approval")
    if not empty_note(pending, "No leave requests to approve."):
        table(pending.drop(columns=["leave_request_id"]))
        rid = st.selectbox("Request", pending.leave_request_id,
                           format_func=lambda i: (lambda r: f"{r.employee} · {r.type} · {r.start_date:%d %b}–{r.end_date:%d %b}")(
                               pending.set_index("leave_request_id").loc[i]))
        a, b = st.columns(2)
        if a.button("✅ Approve", type="primary", width="stretch"):
            run_action("UPDATE leave_requests SET status='approved', approver_id=:a WHERE leave_request_id=:r",
                       {"a": me(), "r": int(rid)}, success="Leave approved - balance updated.")
        if b.button("❌ Reject", width="stretch"):
            run_action("UPDATE leave_requests SET status='rejected', approver_id=:a, decided_at=now() WHERE leave_request_id=:r",
                       {"a": me(), "r": int(rid)}, success="Leave rejected.")

# ------------------------------------------------------------------ skills
with tab_skills:
    sk = query("""SELECT e.first_name || ' ' || e.last_name AS name, s.name AS skill, es.proficiency
                    FROM employee_skills es JOIN employees e USING (employee_id) JOIN skills s USING (skill_id)""")
    if not empty_note(sk):
        matrix = sk.pivot_table(index="name", columns="skill", values="proficiency", fill_value=0)
        fig = px.imshow(matrix, color_continuous_scale="Blues", aspect="auto", text_auto=True,
                        labels=dict(color="Proficiency (1-5)"))
        fig.update_layout(height=420, margin=dict(t=10))
        st.plotly_chart(fig, width="stretch")
    st.markdown("**Certifications expiring in the next 90 days**")
    exp = query("SELECT * FROM v_expiring_certifications ORDER BY days_left")
    if not empty_note(exp, "No certifications expiring soon."):
        table(exp)

# ------------------------------------------------------------------ capacity
with tab_cap:
    cap = query("SELECT employee_name, week_start_date, planned_load_pct, planned_hours, available_hours, breakdown FROM v_resource_capacity")
    if not empty_note(cap, "No resource plans yet."):
        cap["week"] = cap.week_start_date.apply(lambda d: d.strftime("%d %b"))
        heat = cap.pivot_table(index="employee_name", columns="week", values="planned_load_pct", fill_value=0)
        heat = heat[sorted(heat.columns, key=lambda w: cap[cap.week == w].week_start_date.iloc[0])]
        fig = px.imshow(heat, color_continuous_scale=["#D4EDDA", "#FFF3CD", "#F8D7DA"], zmin=0, zmax=120,
                        text_auto=".0f", aspect="auto", labels=dict(color="Load %"))
        fig.update_layout(height=380, margin=dict(t=10))
        st.plotly_chart(fig, width="stretch")
        st.caption("Planned load per week (% of standard hours). Green = spare capacity, red = over-allocated.")
        table(cap.drop(columns=["week"]), pct_cols=["planned_load_pct"])
