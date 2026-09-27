"""Messages & notices - internal inbox, compose, announcements, staff directory, mailing lists."""
import streamlit as st

from auth import can, require
from db import query, run_action, scalar
from ui import md, me, page_header, table

require("page.comms")
emp = me()
page_header(":material/mail: Messages & notices", "Internal mail, company announcements and the staff directory (@maxhub.co.zw)")

tab_in, tab_new, tab_sent, tab_ann, tab_dir, tab_lists = st.tabs(
    ["📥 Inbox", "✉️ New message", "📤 Sent", "📢 Announcements", "📇 Staff directory", "👥 Mailing lists"])

# ------------------------------------------------------------------ inbox
with tab_in:
    inbox = query("""SELECT message_id, sent_at, sender, subject, body, priority, read_at, via_list
                       FROM v_inbox WHERE recipient_id = :e AND NOT is_archived ORDER BY sent_at DESC LIMIT 100""", {"e": emp})
    if inbox.empty:
        st.info("Your inbox is empty.")
    else:
        unread = inbox.read_at.isna().sum()
        st.caption(f"{len(inbox)} message(s), {unread} unread")
        for _, m in inbox.iterrows():
            flag = "🔴 " if m.priority == "high" else ""
            bold = "**" if m.read_at is None or str(m.read_at) == "NaT" else ""
            label = f"{flag}{bold}{md(m.subject)}{bold} — {m.sender} · {m.sent_at:%d %b %H:%M}"
            with st.expander(label):
                if m.via_list:
                    st.caption(f"Sent to {m.via_list}")
                st.markdown(md(m.body))
                b1, b2, _ = st.columns([1, 1, 4])
                if (m.read_at is None or str(m.read_at) == "NaT") and b1.button("Mark read", key=f"r{m.message_id}"):
                    run_action("UPDATE message_recipients SET read_at = now() WHERE message_id = :m AND recipient_id = :e",
                               {"m": int(m.message_id), "e": emp}, success="Marked as read.")
                if b2.button("Archive", key=f"a{m.message_id}"):
                    run_action("UPDATE message_recipients SET is_archived = TRUE, read_at = COALESCE(read_at, now()) "
                               "WHERE message_id = :m AND recipient_id = :e", {"m": int(m.message_id), "e": emp}, success="Archived.")

# ------------------------------------------------------------------ compose
with tab_new:
    people = query("""SELECT employee_id, first_name || ' ' || last_name || ' <' || email || '>' AS label
                        FROM employees WHERE status = 'active' AND employee_id <> :e ORDER BY first_name""", {"e": emp})
    lists = query("SELECT list_id, display_name || ' <' || address || '>' AS label, is_all_staff FROM mailing_lists "
                  "WHERE list_type = 'distribution' ORDER BY is_all_staff DESC, display_name")
    if not can("message.all_staff"):
        lists = lists[~lists.is_all_staff]
    with st.form("compose", clear_on_submit=True):
        to = st.multiselect("To (people)", people.employee_id, format_func=lambda i: people.set_index("employee_id").label[i])
        lst = st.selectbox("…or a mailing list", [None] + lists.list_id.tolist(),
                           format_func=lambda i: "— none —" if i is None else lists.set_index("list_id").label[i])
        subject = st.text_input("Subject *")
        body = st.text_area("Message *", height=150)
        prio = st.radio("Priority", ["normal", "high", "low"], horizontal=True)
        if st.form_submit_button("Send", type="primary", icon=":material/send:"):
            if not subject or not body or (not to and lst is None):
                st.error("Add at least one recipient, a subject and a message.")
            else:
                run_action("""
                    WITH m AS (INSERT INTO internal_messages (sender_id, subject, body, priority, sent_to_list_id)
                               VALUES (:s, :sub, :b, :p, :l) RETURNING message_id),
                    recips AS (
                        SELECT unnest(CAST(:to AS BIGINT[])) AS employee_id
                        UNION
                        SELECT e.employee_id FROM employees e, mailing_lists ml
                         WHERE ml.list_id = :l AND e.status = 'active'
                           AND (ml.is_all_staff OR e.department_id = ml.department_id OR e.office_id = ml.office_id
                                OR e.employee_id IN (SELECT employee_id FROM mailing_list_members WHERE list_id = ml.list_id)))
                    INSERT INTO message_recipients (message_id, recipient_id)
                    SELECT m.message_id, r.employee_id FROM m, recips r WHERE r.employee_id <> :s
                    RETURNING (SELECT COUNT(*) FROM recips)""",
                           {"s": emp, "sub": subject, "b": body, "p": prio, "l": lst, "to": [int(x) for x in to]},
                           success="Message sent to {result} people.")

# ------------------------------------------------------------------ sent
with tab_sent:
    sent = query("""SELECT m.sent_at, m.subject, m.priority, COUNT(r.recipient_id) AS recipients,
                           COUNT(r.read_at) AS read_by
                      FROM internal_messages m LEFT JOIN message_recipients r USING (message_id)
                     WHERE m.sender_id = :e GROUP BY m.message_id ORDER BY m.sent_at DESC""", {"e": emp})
    table(sent) if not sent.empty else st.info("You have not sent any messages yet.")

# ------------------------------------------------------------------ announcements
with tab_ann:
    ann = query("""SELECT publish_at, title, category, audience, author, is_pinned, is_read, body
                     FROM v_employee_announcements WHERE employee_id = :e ORDER BY is_pinned DESC, publish_at DESC""", {"e": emp})
    table(ann.drop(columns=["body"]))
    if can("announcement.publish"):
        with st.expander("➕ Publish an announcement"):
            depts = query("SELECT department_id, name FROM departments ORDER BY name")
            offices = query("SELECT office_id, name FROM offices ORDER BY name")
            with st.form("ann", clear_on_submit=True):
                title = st.text_input("Title *")
                body = st.text_area("Text *")
                a, b, c = st.columns(3)
                cat = a.selectbox("Category", ["general", "hr", "it", "finance", "compliance", "event", "health_safety"])
                aud = b.selectbox("Audience", ["all", "department", "office"])
                pinned = c.checkbox("Pin to the top")
                dept = st.selectbox("Department (if audience = department)", depts.department_id,
                                    format_func=lambda i: depts.set_index("department_id").name[i])
                off = st.selectbox("Office (if audience = office)", offices.office_id,
                                   format_func=lambda i: offices.set_index("office_id").name[i])
                if st.form_submit_button("Publish", type="primary") and title and body:
                    run_action("""INSERT INTO announcements (title, body, category, audience, department_id, office_id, author_id, is_pinned)
                                  VALUES (:t, :b, :c, :a, CASE WHEN :a = 'department' THEN CAST(:d AS BIGINT) END,
                                          CASE WHEN :a = 'office' THEN CAST(:o AS BIGINT) END, :e, :p)""",
                               {"t": title, "b": body, "c": cat, "a": aud, "d": int(dept), "o": int(off), "e": emp, "p": pinned},
                               success="Announcement published.")

# ------------------------------------------------------------------ directory
with tab_dir:
    d = query("SELECT full_name, job_title, department, office, email, work_phone_ext AS ext, mobile_phone, manager FROM v_staff_directory ORDER BY full_name")
    q = st.text_input("🔎 Search name, department, office or e-mail")
    if q:
        d = d[d.apply(lambda r: q.lower() in " ".join(map(str, r.values)).lower(), axis=1)]
    st.caption(f"{len(d)} people")
    table(d, height=450)

# ------------------------------------------------------------------ mailing lists
with tab_lists:
    ml = query("""SELECT ml.address, ml.display_name, ml.list_type,
                         CASE WHEN ml.is_all_staff THEN (SELECT COUNT(*) FROM employees WHERE status = 'active')
                              WHEN ml.department_id IS NOT NULL THEN (SELECT COUNT(*) FROM employees e WHERE e.department_id = ml.department_id AND status = 'active')
                              WHEN ml.office_id IS NOT NULL THEN (SELECT COUNT(*) FROM employees e WHERE e.office_id = ml.office_id AND status = 'active')
                              ELSE (SELECT COUNT(*) FROM mailing_list_members m WHERE m.list_id = ml.list_id) END AS members,
                         e.first_name || ' ' || e.last_name AS owner, ml.description
                    FROM mailing_lists ml LEFT JOIN employees e ON e.employee_id = ml.owner_employee_id ORDER BY ml.list_type, ml.address""")
    table(ml, height=450)
    domain = scalar("SELECT email_domain FROM firm_settings")
    queued = scalar("SELECT COUNT(*) FROM email_outbox WHERE status = 'queued'")
    st.caption(f"E-mail domain: @{domain} · System e-mails waiting to be sent: {queued}")
