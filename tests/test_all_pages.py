"""Logs in as each demo user and renders every page that user may see.
Run from the project folder:  python tests/test_all_pages.py   (needs the database loaded and .env set)"""
import sys, time
from streamlit.testing.v1 import AppTest
from pathlib import Path
APP = str(Path(__file__).resolve().parent.parent / "app" / "app.py")
USERS = ["tawanda.gumbo", "tendai.moyo", "blessing.marufu", "memory.nkomo", "chipo.sibanda",
         "nyasha.mutasa", "kudakwashe.banda", "tapiwa.mlambo", "munyaradzi.mandaza"]
PAGES = {"page.home": "views/home.py", "page.comms": "views/comms.py", "acct": "views/account.py", "page.dashboard": "views/dashboard.py",
         "page.projects": "views/projects.py", "page.timesheets": "views/timesheets.py", "page.expenses": "views/expenses.py",
         "page.crm": "views/crm.py", "page.billing": "views/billing.py", "page.finance": "views/finance.py",
         "page.reports": "views/reports.py", "page.tax": "views/tax.py", "page.assets": "views/assets.py",
         "page.leases": "views/leases.py", "page.people": "views/people.py", "page.payroll": "views/payroll.py", "page.admin": "views/admin.py"}
only = sys.argv[1:] or USERS
bad = 0
for user in only:
    at = AppTest.from_file(APP, default_timeout=120)
    at.run()
    assert not at.exception, at.exception
    at.text_input[0].input(user); at.text_input[1].input("Maxhub@2026")
    at.button[0].click().run()
    if at.exception or "permissions" not in at.session_state:
        print("LOGIN FAILED", user, at.exception, [e.value for e in at.error]); bad += 1; continue
    perms = at.session_state["permissions"]
    for perm, page in PAGES.items():
        if perm not in ("acct", "page.home") and perm not in perms:
            continue
        t = time.time()
        at.switch_page(page).run()
        errs = [e.value for e in at.error]
        if at.exception or errs:
            bad += 1
            print(f"FAIL {user:20s} {page:22s}", at.exception[0].value if at.exception else "", errs[:2])
        else:
            ttl = at.title[0].value if len(at.title) else "(no title)"; print(f"ok   {user:20s} {page:22s} {time.time()-t:5.1f}s  {ttl[:60]}  tabs={len(at.tabs)} df={len(at.dataframe)}")
print("FAILURES:", bad)
