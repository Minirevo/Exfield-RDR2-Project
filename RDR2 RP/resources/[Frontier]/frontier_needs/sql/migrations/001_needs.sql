CREATE TABLE IF NOT EXISTS frontier_needs_state (
 character_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 hunger SMALLINT UNSIGNED NOT NULL DEFAULT 1000,
 thirst SMALLINT UNSIGNED NOT NULL DEFAULT 1000,
 energy SMALLINT UNSIGNED NOT NULL DEFAULT 1000,
 updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
 CHECK (hunger<=1000 AND thirst<=1000 AND energy<=1000)
) ENGINE=InnoDB;

-- A pre-commit outbox. Effects are eligible only after the matching
-- inventory receipt exists and is completed. Never trust a client event.
CREATE TABLE IF NOT EXISTS frontier_needs_consumptions (
 request_key VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 character_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 item VARCHAR(48) NOT NULL,
 actor VARCHAR(100) NOT NULL,
 fingerprint TEXT NOT NULL,
 hunger SMALLINT UNSIGNED NOT NULL,
 thirst SMALLINT UNSIGNED NOT NULL,
 energy SMALLINT UNSIGNED NOT NULL,
 applied BOOLEAN NOT NULL DEFAULT FALSE,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 KEY idx_needs_pending (applied,created_at)
) ENGINE=InnoDB;
