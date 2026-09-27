/* =====================================================================================
   37. SWITCH ON PUBLIC DEMO MODE (demo data only - not part of maxhub_erp_schema.sql)
   -------------------------------------------------------------------------------------
   The nine showcase log-ins listed on the log-in page are shared by everyone who tries
   the online demo, so they are protected (see module 25).
   For a private / real installation run:   UPDATE erp.security_policy SET demo_mode = FALSE;
   ===================================================================================== */
UPDATE app_users SET demo_protected = TRUE
 WHERE username IN ('tendai.moyo', 'blessing.marufu', 'memory.nkomo', 'chipo.sibanda', 'tawanda.gumbo',
                    'nyasha.mutasa', 'kudakwashe.banda', 'tapiwa.mlambo', 'munyaradzi.mandaza');

DO $$ BEGIN
    IF (SELECT COUNT(*) FROM app_users WHERE demo_protected) <> 9 THEN
        RAISE EXCEPTION 'Expected 9 demo accounts to protect';
    END IF;
END $$;

UPDATE security_policy SET demo_mode = TRUE WHERE policy_id = 1;
