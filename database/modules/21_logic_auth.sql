
/* =====================================================================================
   21. AUTHENTICATION & AUTHORISATION LOGIC
   -------------------------------------------------------------------------------------
   fn_login(login, password, ip, agent)  -> ('ok' | 'invalid' | 'locked' | 'inactive', user_id, message)
   fn_create_session / fn_validate_session / fn_logout
   fn_set_password / fn_change_password / fn_admin_reset_password / fn_unlock_user
   fn_sync_user_roles  (department + grade -> roles)      fn_has_permission
   Passwords are hashed with bcrypt: crypt(password, gen_salt('bf', cost)).
   ===================================================================================== */

-- Returns NULL when the password is acceptable, otherwise the reason it is not
CREATE OR REPLACE FUNCTION fn_password_policy_error(p_password TEXT) RETURNS TEXT
LANGUAGE plpgsql STABLE AS $$
DECLARE pol security_policy%ROWTYPE;
BEGIN
    SELECT * INTO pol FROM security_policy WHERE policy_id = 1;
    IF p_password IS NULL OR length(p_password) < pol.min_password_length THEN
        RETURN format('Password must be at least %s characters long', pol.min_password_length);
    END IF;
    IF pol.require_upper  AND p_password !~ '[A-Z]'        THEN RETURN 'Password needs at least one capital letter'; END IF;
    IF pol.require_lower  AND p_password !~ '[a-z]'        THEN RETURN 'Password needs at least one small letter'; END IF;
    IF pol.require_digit  AND p_password !~ '[0-9]'        THEN RETURN 'Password needs at least one number'; END IF;
    IF pol.require_symbol AND p_password !~ '[^A-Za-z0-9]' THEN RETURN 'Password needs at least one symbol, e.g. ! @ # $'; END IF;
    RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION fn_hash_password(p_password TEXT) RETURNS TEXT
LANGUAGE sql VOLATILE AS $$
    SELECT crypt(p_password, gen_salt('bf', (SELECT bcrypt_cost FROM security_policy WHERE policy_id = 1)));
$$;

-- Set a new password (policy + history checks). p_must_change = TRUE for temporary passwords.
CREATE OR REPLACE FUNCTION fn_set_password(p_user_id BIGINT, p_new_password TEXT, p_must_change BOOLEAN DEFAULT FALSE)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_err TEXT; v_keep SMALLINT; v_hash TEXT;
BEGIN
    v_err := fn_password_policy_error(p_new_password);
    IF v_err IS NOT NULL THEN RAISE EXCEPTION '%', v_err; END IF;

    SELECT password_history_count INTO v_keep FROM security_policy WHERE policy_id = 1;
    IF EXISTS (SELECT 1 FROM (SELECT password_hash FROM password_history WHERE user_id = p_user_id
                              ORDER BY changed_at DESC LIMIT v_keep) h
                WHERE crypt(p_new_password, h.password_hash) = h.password_hash) THEN
        RAISE EXCEPTION 'You cannot re-use one of your last % passwords', v_keep;
    END IF;

    v_hash := fn_hash_password(p_new_password);
    UPDATE app_users SET password_hash = v_hash, password_changed_at = now(),
                         must_change_password = p_must_change, failed_logins = 0, locked_until = NULL
     WHERE user_id = p_user_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'User % not found', p_user_id; END IF;
    INSERT INTO password_history (user_id, password_hash, changed_at) VALUES (p_user_id, v_hash, clock_timestamp());
END $$;

-- Self-service change: the old password must be correct
CREATE OR REPLACE FUNCTION fn_change_password(p_user_id BIGINT, p_old_password TEXT, p_new_password TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_hash TEXT;
BEGIN
    SELECT password_hash INTO v_hash FROM app_users WHERE user_id = p_user_id AND is_active;
    IF v_hash IS NULL OR crypt(p_old_password, v_hash) <> v_hash THEN
        RAISE EXCEPTION 'Your current password is not correct';
    END IF;
    IF p_old_password = p_new_password THEN
        RAISE EXCEPTION 'The new password must be different from the current one';
    END IF;
    PERFORM fn_set_password(p_user_id, p_new_password, FALSE);
END $$;

-- Log-in. Never raises for bad credentials (so the attempt is always logged); returns a status.
CREATE OR REPLACE FUNCTION fn_login(p_login TEXT, p_password TEXT, p_ip TEXT DEFAULT NULL, p_agent TEXT DEFAULT NULL)
RETURNS TABLE (status TEXT, user_id BIGINT, message TEXT)
LANGUAGE plpgsql AS $$
DECLARE
    u   app_users%ROWTYPE;
    pol security_policy%ROWTYPE;
    v_ok BOOLEAN;
    v_demo BOOLEAN;                     -- shared public-demo account: never locks
BEGIN
    SELECT * INTO pol FROM security_policy WHERE policy_id = 1;
    SELECT * INTO u FROM app_users a
     WHERE lower(a.username) = lower(trim(p_login)) OR lower(a.email) = lower(trim(p_login))
     LIMIT 1;
    v_demo := FOUND AND pol.demo_mode AND u.demo_protected;

    IF NOT FOUND THEN
        PERFORM crypt(COALESCE(p_password, ''), gen_salt('bf', pol.bcrypt_cost));   -- same delay as a real check
        INSERT INTO login_attempts (username_tried, success, failure_reason, ip_address, user_agent)
        VALUES (left(COALESCE(p_login, ''), 150), FALSE, 'unknown_user', p_ip, left(p_agent, 300));
        RETURN QUERY SELECT 'invalid'::TEXT, NULL::BIGINT, 'Incorrect username or password.'::TEXT;
        RETURN;
    END IF;

    IF NOT u.is_active THEN
        INSERT INTO login_attempts (username_tried, user_id, success, failure_reason, ip_address, user_agent)
        VALUES (p_login, u.user_id, FALSE, 'inactive', p_ip, left(p_agent, 300));
        RETURN QUERY SELECT 'inactive'::TEXT, u.user_id, 'This account has been disabled. Please contact IT Support (itsupport@maxhub.co.zw).'::TEXT;
        RETURN;
    END IF;

    IF u.locked_until IS NOT NULL AND u.locked_until > now() THEN
        INSERT INTO login_attempts (username_tried, user_id, success, failure_reason, ip_address, user_agent)
        VALUES (p_login, u.user_id, FALSE, 'locked', p_ip, left(p_agent, 300));
        RETURN QUERY SELECT 'locked'::TEXT, u.user_id,
            format('Account locked after too many wrong passwords. Try again after %s or ask IT Support to unlock it.',
                   to_char(u.locked_until AT TIME ZONE 'Africa/Harare', 'HH24:MI'));
        RETURN;
    END IF;

    v_ok := crypt(COALESCE(p_password, ''), u.password_hash) = u.password_hash;

    IF v_ok THEN
        UPDATE app_users a SET failed_logins = 0, locked_until = NULL, last_login_at = now(), last_login_ip = p_ip
         WHERE a.user_id = u.user_id;
        INSERT INTO login_attempts (username_tried, user_id, success, ip_address, user_agent)
        VALUES (p_login, u.user_id, TRUE, p_ip, left(p_agent, 300));
        RETURN QUERY SELECT 'ok'::TEXT, u.user_id,
            CASE WHEN u.must_change_password THEN 'Please choose a new password.'
                 WHEN v_demo THEN 'Welcome back!'
                 WHEN u.password_changed_at < now() - make_interval(days => pol.password_max_age_days)
                      THEN 'Your password is older than ' || pol.password_max_age_days || ' days - please change it.'
                 ELSE 'Welcome back!' END;
        RETURN;
    END IF;

    IF v_demo THEN
        INSERT INTO login_attempts (username_tried, user_id, success, failure_reason, ip_address, user_agent)
        VALUES (p_login, u.user_id, FALSE, 'wrong_password', p_ip, left(p_agent, 300));
        RETURN QUERY SELECT 'invalid'::TEXT, NULL::BIGINT,
            'Incorrect username or password. (Demo password: see "Demo accounts" below.)'::TEXT;
        RETURN;
    END IF;

    UPDATE app_users a
       SET failed_logins = a.failed_logins + 1,
           locked_until  = CASE WHEN a.failed_logins + 1 >= pol.max_failed_logins
                                THEN now() + make_interval(mins => pol.lockout_minutes) END
     WHERE a.user_id = u.user_id
    RETURNING * INTO u;
    INSERT INTO login_attempts (username_tried, user_id, success, failure_reason, ip_address, user_agent)
    VALUES (p_login, u.user_id, FALSE, 'wrong_password', p_ip, left(p_agent, 300));

    IF u.locked_until IS NOT NULL THEN
        RETURN QUERY SELECT 'locked'::TEXT, u.user_id,
            format('Too many wrong passwords - the account is locked for %s minutes.', pol.lockout_minutes);
    ELSE
        RETURN QUERY SELECT 'invalid'::TEXT, NULL::BIGINT,
            format('Incorrect username or password. %s attempt(s) left before the account is locked.',
                   pol.max_failed_logins - u.failed_logins);
    END IF;
END $$;

-- Sessions: the app keeps the random token, the database only keeps its SHA-256 hash
CREATE OR REPLACE FUNCTION fn_create_session(p_user_id BIGINT, p_ip TEXT DEFAULT NULL) RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE v_token TEXT := encode(gen_random_bytes(32), 'hex');
BEGIN
    INSERT INTO user_sessions (user_id, token_hash, expires_at, ip_address)
    VALUES (p_user_id, encode(digest(v_token, 'sha256'), 'hex'),
            now() + make_interval(hours => (SELECT session_hours FROM security_policy WHERE policy_id = 1)), p_ip);
    RETURN v_token;
END $$;

CREATE OR REPLACE FUNCTION fn_validate_session(p_token TEXT) RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE v_user BIGINT;
BEGIN
    UPDATE user_sessions s SET last_seen_at = now()
      FROM app_users u
     WHERE s.token_hash = encode(digest(p_token, 'sha256'), 'hex')
       AND s.revoked_at IS NULL AND s.expires_at > now()
       AND u.user_id = s.user_id AND u.is_active
    RETURNING s.user_id INTO v_user;
    RETURN v_user;                      -- NULL => session expired / revoked / user disabled
END $$;

CREATE OR REPLACE FUNCTION fn_logout(p_token TEXT) RETURNS VOID
LANGUAGE sql AS $$
    UPDATE user_sessions SET revoked_at = now(), revoke_reason = 'logout'
     WHERE token_hash = encode(digest(p_token, 'sha256'), 'hex') AND revoked_at IS NULL;
$$;

-- Administrator actions ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_admin_reset_password(p_admin_user_id BIGINT, p_target_user_id BIGINT, p_temp_password TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_email TEXT;
BEGIN
    IF NOT fn_has_permission(p_admin_user_id, 'user.manage') THEN
        RAISE EXCEPTION 'You do not have permission to reset passwords';
    END IF;
    PERFORM fn_set_password(p_target_user_id, p_temp_password, TRUE);
    UPDATE user_sessions SET revoked_at = now(), revoke_reason = 'password_reset'
     WHERE user_id = p_target_user_id AND revoked_at IS NULL;
    SELECT email INTO v_email FROM app_users WHERE user_id = p_target_user_id;
    INSERT INTO email_outbox (to_address, subject, body, template_code, related_entity, related_id)
    VALUES (v_email, 'Your Maxhub ERP password was reset',
            'IT Support has reset your password. Log in with the temporary password you were given and choose a new one.',
            'password_reset', 'app_user', p_target_user_id);
END $$;

CREATE OR REPLACE FUNCTION fn_unlock_user(p_admin_user_id BIGINT, p_target_user_id BIGINT) RETURNS VOID
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT fn_has_permission(p_admin_user_id, 'user.manage') THEN
        RAISE EXCEPTION 'You do not have permission to unlock accounts';
    END IF;
    UPDATE app_users SET failed_logins = 0, locked_until = NULL WHERE user_id = p_target_user_id;
END $$;

-- Permissions ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_user_permissions(p_user_id BIGINT) RETURNS SETOF TEXT
LANGUAGE sql STABLE AS $$
    SELECT DISTINCT p.code
      FROM user_roles ur
      JOIN role_permissions rp ON rp.role_id = ur.role_id
      JOIN permissions p       ON p.permission_id = rp.permission_id
      JOIN app_users u         ON u.user_id = ur.user_id AND u.is_active
     WHERE ur.user_id = p_user_id;
$$;

CREATE OR REPLACE FUNCTION fn_has_permission(p_user_id BIGINT, p_permission TEXT) RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM fn_user_permissions(p_user_id) x WHERE x = p_permission);
$$;

-- Give a user the roles their department & grade call for (keeps manual roles)
CREATE OR REPLACE FUNCTION fn_sync_user_roles(p_user_id BIGINT) RETURNS INTEGER
LANGUAGE plpgsql AS $$
DECLARE v_count INTEGER;
BEGIN
    DELETE FROM user_roles WHERE user_id = p_user_id AND source = 'auto';
    INSERT INTO user_roles (user_id, role_id, source)
    SELECT DISTINCT u.user_id, r.role_id, 'auto'
      FROM app_users u
      JOIN employees e              ON e.employee_id = u.employee_id
      LEFT JOIN job_grades g        ON g.job_grade_id = e.job_grade_id
      JOIN department_role_rules r  ON (r.department_id IS NULL OR r.department_id = e.department_id)
                                   AND COALESCE(g.level, 0) BETWEEN r.min_grade_level AND r.max_grade_level
     WHERE u.user_id = p_user_id
    ON CONFLICT (user_id, role_id) DO NOTHING;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END $$;

CREATE OR REPLACE FUNCTION fn_app_user_after_insert() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM fn_sync_user_roles(NEW.user_id);
    RETURN NULL;
END $$;
CREATE TRIGGER trg_app_users_roles AFTER INSERT ON app_users
    FOR EACH ROW EXECUTE FUNCTION fn_app_user_after_insert();

-- Moving department / grade changes the automatic roles; leaving the firm disables the login
CREATE OR REPLACE FUNCTION fn_employee_access_sync() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_user BIGINT;
BEGIN
    SELECT user_id INTO v_user FROM app_users WHERE employee_id = NEW.employee_id;
    IF v_user IS NULL THEN RETURN NULL; END IF;
    IF NEW.status = 'terminated' AND OLD.status IS DISTINCT FROM 'terminated' THEN
        UPDATE app_users SET is_active = FALSE WHERE user_id = v_user;
        UPDATE user_sessions SET revoked_at = now(), revoke_reason = 'terminated'
         WHERE user_id = v_user AND revoked_at IS NULL;
    END IF;
    IF (NEW.department_id, NEW.job_grade_id) IS DISTINCT FROM (OLD.department_id, OLD.job_grade_id) THEN
        PERFORM fn_sync_user_roles(v_user);
    END IF;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_employees_access_sync AFTER UPDATE OF department_id, job_grade_id, status ON employees
    FOR EACH ROW EXECUTE FUNCTION fn_employee_access_sync();

-- HR onboarding: create a login for a new employee with a temporary password
CREATE OR REPLACE FUNCTION fn_create_user_for_employee(p_employee_id BIGINT, p_temp_password TEXT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE v_emp employees%ROWTYPE; v_user BIGINT; v_err TEXT;
BEGIN
    SELECT * INTO v_emp FROM employees WHERE employee_id = p_employee_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Employee % not found', p_employee_id; END IF;
    IF EXISTS (SELECT 1 FROM app_users WHERE employee_id = p_employee_id) THEN
        RAISE EXCEPTION '% already has a login', v_emp.first_name || ' ' || v_emp.last_name;
    END IF;
    v_err := fn_password_policy_error(p_temp_password);
    IF v_err IS NOT NULL THEN RAISE EXCEPTION '%', v_err; END IF;
    INSERT INTO app_users (employee_id, username, email, password_hash, must_change_password)
    VALUES (p_employee_id, lower(split_part(v_emp.email, '@', 1)), v_emp.email, fn_hash_password(p_temp_password), TRUE)
    RETURNING user_id INTO v_user;
    INSERT INTO email_outbox (to_address, subject, body, template_code, related_entity, related_id)
    VALUES (v_emp.email, 'Welcome to Maxhub - your ERP login',
            format('Hi %s, your Maxhub ERP username is %s. Use the temporary password from HR; you will be asked to change it.',
                   v_emp.first_name, lower(split_part(v_emp.email, '@', 1))),
            'welcome', 'app_user', v_user);
    RETURN v_user;
END $$;
