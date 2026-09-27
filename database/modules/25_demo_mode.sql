/* =====================================================================================
   25. PUBLIC DEMO MODE
   -------------------------------------------------------------------------------------
   When the ERP is put online as a PUBLIC DEMO, many strangers share the same demo
   log-ins (tendai.moyo, blessing.marufu ...). Without protection, one visitor could
   change a demo password, disable the CEO's login or remove the IT Manager's admin role
   and lock everybody else out.

   Demo mode (security_policy.demo_mode = TRUE) protects the accounts flagged
   app_users.demo_protected:
     * their password, username, e-mail and active status cannot be changed
     * they never lock after wrong passwords (handled in fn_login)
     * their manual roles cannot be removed
     * HR cannot terminate / move / re-grade the employees behind them
     * the security policy page is read-only
   Everything else (timesheets, invoices, journals, payroll ...) still works, so visitors
   can try the whole system. Reset the demo at any time by re-running maxhub_erp.sql.

   GOING LIVE FOR REAL USE:  UPDATE erp.security_policy SET demo_mode = FALSE;
   (and hide/remove the demo accounts - see docs/DEPLOY_ONLINE.md)
   ===================================================================================== */

CREATE OR REPLACE FUNCTION fn_demo_mode() RETURNS BOOLEAN
LANGUAGE sql STABLE SET search_path = erp, public AS $$
    SELECT COALESCE((SELECT demo_mode FROM security_policy WHERE policy_id = 1), FALSE);
$$;

-- app_users: shared demo logins keep their password & status
CREATE OR REPLACE FUNCTION fn_demo_guard_app_users() RETURNS trigger
LANGUAGE plpgsql SET search_path = erp, public AS $$
BEGIN
    IF NOT OLD.demo_protected OR NOT fn_demo_mode() THEN
        RETURN NEW;
    END IF;
    IF NEW.password_hash        IS DISTINCT FROM OLD.password_hash
    OR NEW.username             IS DISTINCT FROM OLD.username
    OR NEW.email                IS DISTINCT FROM OLD.email
    OR NEW.is_active            IS DISTINCT FROM OLD.is_active
    OR NEW.must_change_password IS DISTINCT FROM OLD.must_change_password
    OR NEW.demo_protected       IS DISTINCT FROM OLD.demo_protected THEN
        RAISE EXCEPTION 'Public demo: "%" is a shared demo account, so its password and status cannot be changed. '
                        'Try this on one of the other 160 staff accounts instead.', OLD.username;
    END IF;
    NEW.failed_logins := 0;              -- demo accounts never lock
    NEW.locked_until  := NULL;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_demo_guard_app_users BEFORE UPDATE ON app_users
    FOR EACH ROW EXECUTE FUNCTION fn_demo_guard_app_users();

CREATE OR REPLACE FUNCTION fn_demo_guard_app_users_delete() RETURNS trigger
LANGUAGE plpgsql SET search_path = erp, public AS $$
BEGIN
    IF OLD.demo_protected AND fn_demo_mode() THEN
        RAISE EXCEPTION 'Public demo: "%" is a shared demo account and cannot be deleted.', OLD.username;
    END IF;
    RETURN OLD;
END $$;
CREATE TRIGGER trg_demo_guard_app_users_delete BEFORE DELETE ON app_users
    FOR EACH ROW EXECUTE FUNCTION fn_demo_guard_app_users_delete();

-- user_roles: manual roles of demo accounts cannot be removed
-- (automatic roles are deleted & re-inserted by fn_sync_user_roles, so they are allowed)
CREATE OR REPLACE FUNCTION fn_demo_guard_user_roles() RETURNS trigger
LANGUAGE plpgsql SET search_path = erp, public AS $$
BEGIN
    IF OLD.source = 'manual' AND fn_demo_mode()
       AND EXISTS (SELECT 1 FROM app_users u WHERE u.user_id = OLD.user_id AND u.demo_protected) THEN
        RAISE EXCEPTION 'Public demo: roles of the shared demo accounts cannot be removed.';
    END IF;
    RETURN OLD;
END $$;
CREATE TRIGGER trg_demo_guard_user_roles BEFORE DELETE ON user_roles
    FOR EACH ROW EXECUTE FUNCTION fn_demo_guard_user_roles();

-- employees: HR cannot terminate / move / re-grade the people behind the demo logins
CREATE OR REPLACE FUNCTION fn_demo_guard_employees() RETURNS trigger
LANGUAGE plpgsql SET search_path = erp, public AS $$
BEGIN
    IF (NEW.status, NEW.department_id, NEW.job_grade_id) IS DISTINCT FROM (OLD.status, OLD.department_id, OLD.job_grade_id)
       AND fn_demo_mode()
       AND EXISTS (SELECT 1 FROM app_users u WHERE u.employee_id = OLD.employee_id AND u.demo_protected) THEN
        RAISE EXCEPTION 'Public demo: % % uses a shared demo login, so their status, department and grade are locked. '
                        'Try this on another employee.', OLD.first_name, OLD.last_name;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_demo_guard_employees BEFORE UPDATE OF status, department_id, job_grade_id ON employees
    FOR EACH ROW EXECUTE FUNCTION fn_demo_guard_employees();

-- security policy: read-only while in demo mode (switching demo mode OFF is always allowed)
CREATE OR REPLACE FUNCTION fn_demo_guard_security_policy() RETURNS trigger
LANGUAGE plpgsql SET search_path = erp, public AS $$
BEGIN
    IF OLD.demo_mode AND NEW.demo_mode THEN
        RAISE EXCEPTION 'Public demo: the security policy is read-only.';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_demo_guard_security_policy BEFORE UPDATE ON security_policy
    FOR EACH ROW EXECUTE FUNCTION fn_demo_guard_security_policy();
