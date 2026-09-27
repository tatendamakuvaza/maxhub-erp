"""Fixed assets - register (IAS 16 / IAS 38 / IAS 40), assignments, depreciation, maintenance, insurance, disposals."""
from datetime import date, timedelta

import plotly.express as px
import streamlit as st

from auth import can, require
from db import query, run_action, scalar
from ui import BRAND, GOLD, me, page_header, table

require("page.assets")
page_header(":material/inventory_2: Fixed assets", "Land & buildings, vehicles, IT, forensic lab equipment, software and investment property")

reg = query("SELECT * FROM v_fixed_asset_register ORDER BY asset_tag")
live = reg[~reg.status.isin(["disposed", "written_off"])]
dep_ytd = scalar("""SELECT COALESCE(SUM(amount), 0) FROM asset_depreciation WHERE period_end >= date_trunc('year', CURRENT_DATE)""")
c1, c2, c3, c4 = st.columns(4)
c1.metric("Assets in use", len(live), border=True)
c2.metric("Cost / valuation", f"${live.gross.sum():,.0f}", border=True)
c3.metric("Carrying amount", f"${live.carrying_amount.sum():,.0f}", border=True)
c4.metric("Depreciation this year", f"${dep_ytd:,.0f}", border=True)

tabs = st.tabs(["📋 Register", "📊 By category", "👤 Assignments", "🔧 Maintenance & insurance", "🏢 Properties & valuations",
                "⚙️ Depreciation run", "🗑️ Disposals", "➕ New asset"])

# ------------------------------------------------------------------ register
with tabs[0]:
    f1, f2, f3, f4 = st.columns(4)
    cat = f1.multiselect("Category", sorted(reg.category.unique()))
    off = f2.multiselect("Office", sorted(reg.office.dropna().unique()))
    stat = f3.multiselect("Status", sorted(reg.status.unique()), default=[s for s in ["in_use", "under_construction", "idle"] if s in set(reg.status)])
    q = f4.text_input("Search tag / name / custodian / serial")
    v = reg.copy()
    if cat: v = v[v.category.isin(cat)]
    if off: v = v[v.office.isin(off)]
    if stat: v = v[v.status.isin(stat)]
    if q: v = v[v.apply(lambda r: q.lower() in " ".join(map(str, r.values)).lower(), axis=1)]
    st.caption(f"{len(v)} assets · carrying amount ${v.carrying_amount.sum():,.0f}")
    table(v[["asset_tag", "name", "category", "status", "office", "department", "custodian", "serial_number", "registration_number",
             "acquisition_date", "gross", "accumulated_depreciation", "carrying_amount", "monthly_depreciation", "warranty_expiry"]],
          money_cols=["gross", "accumulated_depreciation", "carrying_amount", "monthly_depreciation"], height=420)
    st.download_button("⬇️ Download register (CSV)", v.to_csv(index=False), "fixed_asset_register.csv", "text/csv")

# ------------------------------------------------------------------ by category
with tabs[1]:
    by = live.groupby(["category", "standard", "measurement_model"], as_index=False).agg(
        assets=("asset_id", "count"), gross=("gross", "sum"), accumulated_depreciation=("accumulated_depreciation", "sum"),
        carrying_amount=("carrying_amount", "sum"))
    a, b = st.columns([3, 2])
    with a:
        table(by, money_cols=["gross", "accumulated_depreciation", "carrying_amount"])
        pol = query("""SELECT c.name AS category, c.standard, c.measurement_model, c.depreciation_method,
                              c.useful_life_months / 12.0 AS life_years, c.residual_value_pct, c.tax_wear_tear_rate_pct AS zimra_wear_tear_pct
                         FROM asset_categories c ORDER BY c.code""")
        st.markdown("##### Accounting policies")
        table(pol)
    with b:
        fig = px.pie(by, names="category", values="carrying_amount", hole=0.45,
                     color_discrete_sequence=[BRAND, GOLD, "#1FA3D8", "#8A9BB3", "#2E6DB4", "#E0C58E", "#5B6F8F", "#B0892F", "#7FC4E6", "#34495E"])
        fig.update_layout(height=420, margin=dict(t=10, b=10))
        st.plotly_chart(fig, width="stretch")

# ------------------------------------------------------------------ assignments
with tabs[2]:
    asg = query("""SELECT fa.asset_tag, fa.name, e.first_name || ' ' || e.last_name AS employee, d.name AS department,
                          aa.assigned_date, aa.condition_out
                     FROM asset_assignments aa JOIN fixed_assets fa USING (asset_id) JOIN employees e ON e.employee_id = aa.employee_id
                     LEFT JOIN departments d ON d.department_id = e.department_id
                    WHERE aa.returned_date IS NULL ORDER BY aa.assigned_date DESC""")
    table(asg, height=350)
    if can("asset.manage"):
        c1, c2 = st.columns(2)
        with c1.form("assign", clear_on_submit=True):
            st.markdown("**Assign an asset**")
            free = query("""SELECT asset_id, asset_tag || ' - ' || name AS label FROM fixed_assets fa
                             WHERE status = 'in_use' AND NOT EXISTS (SELECT 1 FROM asset_assignments aa WHERE aa.asset_id = fa.asset_id AND aa.returned_date IS NULL)
                             ORDER BY asset_tag""")
            ppl = query("SELECT employee_id, first_name || ' ' || last_name AS name FROM employees WHERE status = 'active' ORDER BY 2")
            aid = st.selectbox("Asset", free.asset_id, format_func=lambda i: free.set_index("asset_id").label[i]) if not free.empty else None
            eid = st.selectbox("Employee", ppl.employee_id, format_func=lambda i: ppl.set_index("employee_id").name[i])
            if st.form_submit_button("Assign") and aid:
                run_action("""WITH a AS (INSERT INTO asset_assignments (asset_id, employee_id, assigned_date, condition_out)
                                         VALUES (:a, :e, CURRENT_DATE, 'Good') RETURNING asset_id)
                              UPDATE fixed_assets SET custodian_employee_id = :e WHERE asset_id IN (SELECT asset_id FROM a)""",
                           {"a": int(aid), "e": int(eid)}, success="Asset assigned.")
        with c2.form("return", clear_on_submit=True):
            st.markdown("**Return an asset**")
            out = query("""SELECT aa.assignment_id, fa.asset_tag || ' - ' || e.first_name || ' ' || e.last_name AS label
                             FROM asset_assignments aa JOIN fixed_assets fa USING (asset_id) JOIN employees e ON e.employee_id = aa.employee_id
                            WHERE aa.returned_date IS NULL ORDER BY fa.asset_tag""")
            rid = st.selectbox("Assignment", out.assignment_id, format_func=lambda i: out.set_index("assignment_id").label[i]) if not out.empty else None
            cond = st.text_input("Condition on return", "Good")
            if st.form_submit_button("Record return") and rid:
                run_action("UPDATE asset_assignments SET returned_date = CURRENT_DATE, condition_in = :c WHERE assignment_id = :i",
                           {"c": cond, "i": int(rid)}, success="Return recorded.")

# ------------------------------------------------------------------ maintenance & insurance
with tabs[3]:
    a, b = st.columns(2)
    with a:
        st.markdown("##### Service & repair history")
        mt = query("""SELECT m.service_date, fa.asset_tag, fa.name, m.maintenance_type, m.description, v.name AS vendor, m.cost,
                             m.odometer_km, m.next_due_date
                        FROM asset_maintenance m JOIN fixed_assets fa USING (asset_id) LEFT JOIN vendors v ON v.vendor_id = m.vendor_id
                       ORDER BY m.service_date DESC""")
        table(mt, money_cols=["cost"], height=320)
        due = mt[(mt.next_due_date.astype(str) <= str(date.today() + timedelta(days=30)))].drop_duplicates("asset_tag")
        if not due.empty:
            st.warning(f"{len(due)} asset(s) have a service due within 30 days.")
        if can("asset.manage"):
            with st.form("maint", clear_on_submit=True):
                assets = query("SELECT asset_id, asset_tag || ' - ' || name AS label FROM fixed_assets WHERE status <> 'disposed' ORDER BY asset_tag")
                x, y = st.columns(2)
                aid = x.selectbox("Asset", assets.asset_id, format_func=lambda i: assets.set_index("asset_id").label[i])
                typ = y.selectbox("Type", ["service", "repair", "inspection", "upgrade", "licence_renewal"])
                desc = st.text_input("Description")
                x, y = st.columns(2)
                cost = x.number_input("Cost (USD)", 0.0, step=50.0)
                nxt = y.date_input("Next due", date.today() + timedelta(days=180))
                if st.form_submit_button("Log maintenance") and desc:
                    run_action("""INSERT INTO asset_maintenance (asset_id, service_date, maintenance_type, description, cost, next_due_date)
                                  VALUES (:a, CURRENT_DATE, :t, :d, :c, :n)""", {"a": int(aid), "t": typ, "d": desc, "c": cost, "n": nxt},
                               success="Maintenance logged.")
    with b:
        st.markdown("##### Insurance policies")
        ins = query("""SELECT p.policy_number, p.cover_type, v.name AS insurer, p.sum_insured, p.annual_premium, p.start_date, p.end_date,
                              p.excess_amount, (SELECT COUNT(*) FROM fixed_assets fa WHERE fa.insurance_policy_id = p.policy_id) AS assets_linked
                         FROM insurance_policies p LEFT JOIN vendors v ON v.vendor_id = p.insurer_vendor_id ORDER BY p.policy_number""")
        table(ins, money_cols=["sum_insured", "annual_premium", "excess_amount"])

# ------------------------------------------------------------------ properties
with tabs[4]:
    pr = query("""SELECT property_code, name, city, use_type, stand_number, title_deed_number, land_size_sqm, building_size_sqm,
                         lettable_area_sqm, council FROM properties ORDER BY property_code""")
    table(pr)
    val = query("""SELECT r.valuation_date, fa.asset_tag, fa.name, r.valuation_type, r.valuer, r.carrying_before, r.fair_value,
                          r.surplus_deficit, r.to_oci, r.to_profit_or_loss, r.deferred_tax, r.fair_value_level
                     FROM asset_revaluations r JOIN fixed_assets fa USING (asset_id) ORDER BY r.valuation_date DESC, fa.asset_tag""")
    st.markdown("##### Valuations (IAS 16 revaluation model · IAS 40 fair value model · IFRS 13 hierarchy)")
    table(val, money_cols=["carrying_before", "fair_value", "surplus_deficit", "to_oci", "to_profit_or_loss", "deferred_tax"])
    st.caption("Maxhub House: floors 1-4 are owner-occupied (IAS 16, revaluation model); floors 5-6 are let to tenants and are "
               "investment property (IAS 40, fair value through profit or loss). Mount Pleasant land is held for the future campus.")
    if can("depreciation.run"):
        with st.expander("Record a new valuation"):
            rv = query("""SELECT fa.asset_id, fa.asset_tag || ' - ' || fa.name AS label FROM fixed_assets fa JOIN asset_categories c USING (asset_category_id)
                           WHERE c.measurement_model <> 'cost' AND fa.status <> 'disposed' ORDER BY 2""")
            with st.form("reval"):
                aid = st.selectbox("Asset", rv.asset_id, format_func=lambda i: rv.set_index("asset_id").label[i])
                x, y = st.columns(2)
                fv = x.number_input("Fair value (USD)", 0.0, step=10000.0)
                vd = y.date_input("Valuation date", date.today())
                valuer = st.text_input("Valuer", "Knight Frank Zimbabwe (independent valuers)")
                if st.form_submit_button("Post valuation", type="primary") and fv > 0:
                    run_action("SELECT fn_revalue_asset(:a, :d, :f, :v, 3::SMALLINT, :u)",
                               {"a": int(aid), "d": vd, "f": fv, "v": valuer, "u": st.session_state["app_user_id"]},
                               success="Valuation posted to the ledger.")

# ------------------------------------------------------------------ depreciation
with tabs[5]:
    runs = query("""SELECT d.period_end, COUNT(*) AS assets, SUM(d.amount) AS depreciation, je.entry_number
                      FROM asset_depreciation d LEFT JOIN journal_entries je USING (journal_entry_id)
                     GROUP BY d.period_end, je.entry_number ORDER BY d.period_end DESC""")
    table(runs, money_cols=["depreciation"], height=300)
    if can("depreciation.run"):
        pe = st.date_input("Month-end to depreciate", date.today().replace(day=1) - timedelta(days=1) if date.today().day < 28 else date.today())
        if st.button("Run depreciation", type="primary", icon=":material/play_arrow:"):
            run_action("SELECT CASE WHEN fn_run_depreciation(:d, :u) IS NULL THEN 'nothing to post (already depreciated)' ELSE 'journal posted' END",
                       {"d": pe, "u": st.session_state["app_user_id"]}, success="Depreciation run complete: {result}.")
        st.caption("Straight-line over useful life (revalued buildings over remaining life); full month in the month of acquisition. "
                   "Running the same month twice posts nothing.")

# ------------------------------------------------------------------ disposals
with tabs[6]:
    dis = query("""SELECT d.disposal_date, fa.asset_tag, fa.name, d.disposal_type, d.proceeds, d.carrying_amount, d.gain_loss, d.buyer, je.entry_number
                     FROM asset_disposals d JOIN fixed_assets fa USING (asset_id) LEFT JOIN journal_entries je ON je.journal_entry_id = d.journal_entry_id
                    ORDER BY d.disposal_date DESC""")
    table(dis, money_cols=["proceeds", "carrying_amount", "gain_loss"])
    if can("depreciation.run"):
        with st.form("dispose"):
            st.markdown("**Dispose of an asset**")
            cand = query("SELECT asset_id, asset_tag || ' - ' || name AS label FROM fixed_assets WHERE status IN ('in_use','idle','held_for_sale') ORDER BY asset_tag")
            banks = query("SELECT bank_account_id, name FROM bank_accounts WHERE currency_code = 'USD' ORDER BY bank_account_id")
            aid = st.selectbox("Asset", cand.asset_id, format_func=lambda i: cand.set_index("asset_id").label[i])
            x, y, z = st.columns(3)
            proceeds = x.number_input("Proceeds (USD)", 0.0, step=100.0)
            dtype = y.selectbox("Type", ["sale", "scrap", "donation", "theft", "trade_in"])
            bank = z.selectbox("Proceeds to", banks.bank_account_id, format_func=lambda i: banks.set_index("bank_account_id").name[i])
            buyer = st.text_input("Buyer / reason")
            if st.form_submit_button("Dispose", type="primary"):
                run_action("SELECT fn_dispose_asset(:a, CURRENT_DATE, :p, :b, :buyer, :t, :e, :u)",
                           {"a": int(aid), "p": proceeds, "b": int(bank), "buyer": buyer, "t": dtype, "e": me(), "u": st.session_state["app_user_id"]},
                           success="Asset disposed - cost, depreciation and gain/loss posted.")

# ------------------------------------------------------------------ new asset
with tabs[7]:
    if not can("asset.manage"):
        st.info("Only Facilities, IT and Finance can register assets.")
    else:
        st.caption("Normally assets are created from the supplier bill. Use this for donated assets or corrections.")
        cats = query("SELECT asset_category_id, name FROM asset_categories ORDER BY code")
        offs = query("SELECT office_id, name FROM offices ORDER BY office_id")
        depts = query("SELECT department_id, name FROM departments ORDER BY name")
        with st.form("newasset", clear_on_submit=True):
            x, y = st.columns(2)
            tag = x.text_input("Asset tag *", f"MXH-NEW-{date.today():%y%m%d}")
            name = y.text_input("Description *")
            x, y, z = st.columns(3)
            cat = x.selectbox("Category", cats.asset_category_id, format_func=lambda i: cats.set_index("asset_category_id").name[i])
            off = y.selectbox("Office", offs.office_id, format_func=lambda i: offs.set_index("office_id").name[i])
            dep = z.selectbox("Department", depts.department_id, format_func=lambda i: depts.set_index("department_id").name[i])
            x, y, z = st.columns(3)
            cost = x.number_input("Cost (USD) *", 0.0, step=100.0)
            acq = y.date_input("Acquired", date.today())
            serial = z.text_input("Serial number")
            if st.form_submit_button("Register asset", type="primary") and tag and name and cost > 0:
                run_action("""INSERT INTO fixed_assets (asset_tag, name, asset_category_id, office_id, department_id, serial_number,
                                                        acquisition_date, available_for_use_date, cost, insured_value)
                              VALUES (:t, :n, :c, :o, :d, :s, :a, :a, :cost, :cost)""",
                           {"t": tag, "n": name, "c": int(cat), "o": int(off), "d": int(dep), "s": serial, "a": acq, "cost": cost},
                           success="Asset registered (remember to post the purchase via a supplier bill or journal).")
