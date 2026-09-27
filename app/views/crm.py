"""Clients & CRM - client master data, contacts, leads, opportunities and activities."""
from datetime import date, timedelta

import pandas as pd
import streamlit as st

from db import query, run_action
from ui import md, me, page_header, short_money, table, empty_note
from auth import can, require

require("page.crm")
page_header(":material/handshake: Clients & CRM", "Clients, contacts, sales pipeline and activities")

STAGES = ["qualification", "needs_analysis", "proposal", "negotiation", "won", "lost"]
DEFAULT_PROB = {"qualification": 10, "needs_analysis": 25, "proposal": 50, "negotiation": 70, "won": 100, "lost": 0}
NEXT_CLIENT_CODE = """(SELECT 'C' || lpad((COALESCE(MAX(substring(client_code FROM 2)::int), 0) + 1)::text, 3, '0')
                         FROM clients WHERE client_code ~ '^C[0-9]+$')"""

employees = query("SELECT employee_id, first_name || ' ' || last_name AS name FROM employees WHERE status='active' ORDER BY 2")
emp = dict(zip(employees.employee_id, employees.name))
industries = query("SELECT industry_id, name FROM industries ORDER BY name")
ind = dict(zip(industries.industry_id, industries.name))

tab_pipe, tab_clients, tab_leads, tab_act = st.tabs(["📈 Pipeline", "🏢 Clients", "🧲 Leads", "🗓️ Activities"])

# ======================================================================= PIPELINE
with tab_pipe:
    opps = query("""
        SELECT o.opportunity_id, o.opportunity_code, o.name, c.legal_name AS client, o.stage::text AS stage,
               o.probability_pct, o.estimated_value, o.weighted_value, o.currency_code, o.expected_close_date,
               e.first_name || ' ' || e.last_name AS owner
          FROM opportunities o JOIN clients c ON c.client_id = o.client_id
          LEFT JOIN employees e ON e.employee_id = o.owner_id
         ORDER BY o.expected_close_date""")
    open_stages = STAGES[:4]
    cols = st.columns(len(open_stages))
    for col, stage in zip(cols, open_stages):
        subset = opps[opps.stage == stage]
        col.markdown(f"**{stage.replace('_', ' ').title()}** · {len(subset)}")
        for _, o in subset.iterrows():
            with col.container(border=True):
                st.markdown(f"**{o['name']}**  \n{o.client}")
                close = f"{o.expected_close_date:%d %b %Y}" if pd.notna(o.expected_close_date) else "no date"
                st.caption(f"{o.currency_code} {o.estimated_value:,.0f} · {o.probability_pct:.0f}% · "
                           f"close {close}  \n👤 {o.owner}")
    won = opps[(opps.stage == "won") & (opps.currency_code == "USD")].estimated_value.sum()
    lost = opps[(opps.stage == "lost") & (opps.currency_code == "USD")].estimated_value.sum()
    st.caption(md(f"Won (USD): {short_money(won)} · Lost (USD): {short_money(lost)} · ") +
               f"Win rate by value: {100 * won / (won + lost) if won + lost else 0:.0f}%")

    c1, c2 = st.columns(2)
    with c1.form("move_opp"):
        st.markdown("**Move an opportunity**")
        oid = st.selectbox("Opportunity", opps.opportunity_id,
                           format_func=lambda i: (lambda r: f"{r.opportunity_code} — {r['name']} ({r.stage})")(
                               opps.set_index("opportunity_id").loc[i]))
        stage = st.selectbox("New stage", STAGES)
        lost_reason = st.text_input("Lost reason (required if lost)")
        if st.form_submit_button("Update stage", type="primary"):
            run_action("""UPDATE opportunities SET stage = CAST(:s AS opportunity_stage), probability_pct = :p,
                                 lost_reason = NULLIF(:lr, ''),
                                 actual_close_date = CASE WHEN :s IN ('won','lost') THEN CURRENT_DATE END
                           WHERE opportunity_id = :o""",
                       {"s": stage, "p": DEFAULT_PROB[stage], "lr": lost_reason, "o": int(oid)},
                       success="Opportunity moved to {}.".format(stage.replace("_", " ")))

    clients = query("SELECT client_id, legal_name FROM clients WHERE status <> 'blacklisted' ORDER BY 2")
    lines = query("SELECT service_line_id, name FROM service_lines ORDER BY name")
    with c2.form("new_opp", clear_on_submit=True):
        st.markdown("**New opportunity**")
        oname = st.text_input("Opportunity name *")
        a, b = st.columns(2)
        ocl = a.selectbox("Client", clients.client_id, format_func=lambda i: clients.set_index("client_id").legal_name[i])
        osl = b.selectbox("Service line", lines.service_line_id, format_func=lambda i: lines.set_index("service_line_id").name[i])
        a, b, c = st.columns(3)
        oval = a.number_input("Estimated value", min_value=0.0, step=5000.0)
        ocur = b.selectbox("Currency", ["USD", "ZAR", "ZWG"])
        oclose = c.date_input("Expected close", date.today() + timedelta(days=60))
        if st.form_submit_button("Add opportunity") and oname:
            run_action("""INSERT INTO opportunities (opportunity_code, client_id, name, service_line_id, estimated_value,
                                 currency_code, expected_close_date, owner_id)
                          VALUES ((SELECT 'OPP-' || lpad((COUNT(*) + 1)::text, 3, '0') FROM opportunities),
                                  :c, :n, :sl, :v, :cur, :d, :o)""",
                       {"c": int(ocl), "n": oname, "sl": int(osl), "v": oval, "cur": ocur, "d": oclose, "o": me()},
                       success="Opportunity added to the pipeline.")

# ======================================================================= CLIENTS
with tab_clients:
    cl = query("""
        SELECT c.client_id, c.client_code, c.legal_name, i.name AS industry, c.status::text AS status, c.city,
               c.currency_code, c.payment_terms_days AS terms,
               e.first_name || ' ' || e.last_name AS account_manager,
               COALESCE((SELECT SUM(balance_due) FROM invoices v WHERE v.client_id = c.client_id
                          AND v.status IN ('issued','partially_paid','overdue')), 0) AS outstanding,
               (SELECT COUNT(*) FROM projects p WHERE p.client_id = c.client_id AND p.status = 'active') AS active_projects
          FROM clients c LEFT JOIN industries i ON i.industry_id = c.industry_id
          LEFT JOIN employees e ON e.employee_id = c.account_manager_id
         ORDER BY c.client_code""")
    table(cl.drop(columns=["client_id"]), money_cols=["outstanding"])

    cid = st.selectbox("Client details", cl.client_id,
                       format_func=lambda i: cl.set_index("client_id").legal_name[i])
    a, b = st.columns(2)
    with a:
        st.markdown("**Contacts**")
        table(query("""SELECT first_name || ' ' || last_name AS name, job_title, email, phone,
                              is_primary AS primary, is_billing_contact AS billing
                         FROM client_contacts WHERE client_id = :c ORDER BY is_primary DESC""", {"c": int(cid)}))
        with st.form("add_contact", clear_on_submit=True):
            x, y = st.columns(2)
            fn = x.text_input("First name *"); ln = y.text_input("Last name *")
            x, y = st.columns(2)
            jt = x.text_input("Job title"); em = y.text_input("Email")
            ph = x.text_input("Phone"); billing = y.checkbox("Billing contact")
            if st.form_submit_button("Add contact") and fn and ln:
                run_action("""INSERT INTO client_contacts (client_id, first_name, last_name, job_title, email, phone, is_billing_contact)
                              VALUES (:c, :f, :l, :j, :e, :p, :b)""",
                           {"c": int(cid), "f": fn, "l": ln, "j": jt, "e": em, "p": ph, "b": billing}, success="Contact added.")
    with b:
        st.markdown("**Projects**")
        table(query("""SELECT project_code, name, status::text AS status, start_date, planned_end_date
                         FROM projects WHERE client_id = :c ORDER BY start_date DESC""", {"c": int(cid)}))
        st.markdown("**Invoices**")
        table(query("""SELECT invoice_number, invoice_date, due_date, status::text AS status, total_amount, balance_due
                         FROM invoices WHERE client_id = :c ORDER BY invoice_date DESC""", {"c": int(cid)}),
              money_cols=["total_amount", "balance_due"])

    with st.expander("➕ Add a new client"):
        with st.form("new_client", clear_on_submit=True):
            x, y, z = st.columns(3)
            legal = x.text_input("Legal name *")
            trading = y.text_input("Trading name")
            industry = z.selectbox("Industry", industries.industry_id, format_func=ind.get)
            x, y, z = st.columns(3)
            email = x.text_input("Billing email")
            phone = y.text_input("Phone")
            city = z.text_input("City", "Harare")
            x, y, z = st.columns(3)
            country = x.selectbox("Country", ["ZW", "ZA", "BW", "GB"])
            currency = y.selectbox("Billing currency", ["USD", "ZWG", "ZAR"])
            terms = z.number_input("Payment terms (days)", 0, 120, 30)
            manager = st.selectbox("Account manager", employees.employee_id, format_func=emp.get)
            status = st.radio("Status", ["prospect", "active"], horizontal=True)
            if st.form_submit_button("Create client", type="primary") and legal:
                run_action(f"""INSERT INTO clients (client_code, legal_name, trading_name, industry_id, status, billing_email,
                                      phone, city, country_code, currency_code, payment_terms_days, account_manager_id)
                               VALUES ({NEXT_CLIENT_CODE}, :l, :t, :i, CAST(:s AS client_status), :e, :p, :city, :cc, :cur, :terms, :am)
                               RETURNING client_code""",
                           {"l": legal, "t": trading, "i": int(industry), "s": status, "e": email, "p": phone, "city": city,
                            "cc": country, "cur": currency, "terms": terms, "am": int(manager)},
                           success="Client {result} created.")

# ======================================================================= LEADS
with tab_leads:
    leads = query("""SELECT l.lead_id, l.company_name, l.contact_name, l.email, l.source, i.name AS industry,
                            l.estimated_value, l.status, e.first_name || ' ' || e.last_name AS owner, l.created_at::date AS created
                       FROM leads l LEFT JOIN industries i ON i.industry_id = l.industry_id
                       LEFT JOIN employees e ON e.employee_id = l.owner_id ORDER BY l.created_at DESC""")
    table(leads.drop(columns=["lead_id"]), money_cols=["estimated_value"])
    a, b = st.columns(2)
    with a.form("new_lead", clear_on_submit=True):
        st.markdown("**New lead**")
        company = st.text_input("Company *")
        contact = st.text_input("Contact person")
        lemail = st.text_input("Email")
        x, y = st.columns(2)
        source = x.selectbox("Source", ["Referral", "Website", "Event", "Tender", "Cold call", "LinkedIn"])
        lval = y.number_input("Estimated value (USD)", min_value=0.0, step=5000.0)
        lind = st.selectbox("Industry", industries.industry_id, format_func=ind.get, key="lead_ind")
        if st.form_submit_button("Add lead") and company:
            run_action("""INSERT INTO leads (company_name, contact_name, email, source, industry_id, estimated_value, owner_id)
                          VALUES (:c, :n, :e, :s, :i, :v, :o)""",
                       {"c": company, "n": contact, "e": lemail, "s": source, "i": int(lind), "v": lval, "o": me()},
                       success="Lead added.")
    open_leads = leads[~leads.status.isin(["converted", "disqualified"])]
    with b.form("convert_lead"):
        st.markdown("**Convert lead → client**")
        if open_leads.empty:
            st.caption("No open leads.")
            st.form_submit_button("Convert", disabled=True)
        else:
            lid = st.selectbox("Lead", open_leads.lead_id, format_func=lambda i: open_leads.set_index("lead_id").company_name[i])
            if st.form_submit_button("Convert to client", type="primary"):
                run_action(f"""WITH new_client AS (
                                   INSERT INTO clients (client_code, legal_name, industry_id, status, account_manager_id, lead_source)
                                   SELECT {NEXT_CLIENT_CODE}, company_name, industry_id, 'prospect', owner_id, source
                                     FROM leads WHERE lead_id = :l
                                   RETURNING client_id, client_code)
                               UPDATE leads SET status = 'converted', converted_client_id = (SELECT client_id FROM new_client)
                                WHERE lead_id = :l
                               RETURNING (SELECT client_code FROM new_client)""",
                           {"l": int(lid)}, success="Lead converted - new client {result} created.")

# ======================================================================= ACTIVITIES
with tab_act:
    acts = query("""SELECT a.activity_date::date AS date, a.activity_type, a.subject, c.legal_name AS client,
                           e.first_name || ' ' || e.last_name AS by, a.follow_up_date
                      FROM crm_activities a LEFT JOIN clients c ON c.client_id = a.client_id
                      JOIN employees e ON e.employee_id = a.employee_id ORDER BY a.activity_date DESC LIMIT 50""")
    if not empty_note(acts, "No activities logged yet."):
        table(acts)
    with st.form("log_activity", clear_on_submit=True):
        st.markdown("**Log an activity**")
        x, y, z = st.columns(3)
        atype = x.selectbox("Type", ["call", "email", "meeting", "presentation", "note"])
        aclient = y.selectbox("Client", clients.client_id, format_func=lambda i: clients.set_index("client_id").legal_name[i], key="act_client")
        follow = z.date_input("Follow-up date", date.today() + timedelta(days=7))
        subject = st.text_input("Subject *")
        details = st.text_area("Notes")
        if st.form_submit_button("Log activity") and subject:
            run_action("""INSERT INTO crm_activities (activity_type, subject, details, client_id, employee_id, follow_up_date)
                          VALUES (:t, :s, :d, :c, :e, :f)""",
                       {"t": atype, "s": subject, "d": details, "c": int(aclient), "e": me(), "f": follow},
                       success="Activity logged.")
