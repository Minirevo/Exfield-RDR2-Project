CREATE TABLE IF NOT EXISTS frontier_medical_operations (
 request_key VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 patient VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 life INT UNSIGNED NOT NULL,
 doctor VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 region VARCHAR(24) NOT NULL,
 procedure_id VARCHAR(24) NOT NULL,
 fingerprint TEXT NOT NULL,
 outcome VARCHAR(16) NOT NULL DEFAULT 'pending',
 expires_at BIGINT UNSIGNED NOT NULL,
 applied BOOLEAN NOT NULL DEFAULT FALSE,
 xp_due BOOLEAN NOT NULL DEFAULT FALSE,
 xp_awarded BOOLEAN NOT NULL DEFAULT FALSE,
 testing BOOLEAN NOT NULL DEFAULT FALSE,
 KEY idx_med_operations_pending(applied,expires_at),
 KEY idx_med_operations_patient(patient,applied),
 KEY idx_med_operations_xp(xp_due,xp_awarded)
) ENGINE=InnoDB;
