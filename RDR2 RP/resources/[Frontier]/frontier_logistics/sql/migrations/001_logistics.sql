-- Additive migration: existing VORP and Frontier records are not modified.
CREATE TABLE IF NOT EXISTS fl_wagons (
 id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 owner_type ENUM('character','company') NOT NULL,
 owner_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 name VARCHAR(60) NOT NULL,
 model VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 state ENUM('stored','world','wreck_pending','destroyed') NOT NULL DEFAULT 'stored',
 locked TINYINT NOT NULL DEFAULT 0,
 stolen TINYINT NOT NULL DEFAULT 0,
 quality TINYINT UNSIGNED NOT NULL DEFAULT 50,
 condition_value TINYINT UNSIGNED NOT NULL DEFAULT 100,
 x DOUBLE NOT NULL DEFAULT 0,y DOUBLE NOT NULL DEFAULT 0,z DOUBLE NOT NULL DEFAULT 0,heading DOUBLE NOT NULL DEFAULT 0,
 updated_at BIGINT UNSIGNED NOT NULL,
 KEY ix_owner(owner_type,owner_id),KEY ix_state(state)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS fl_harnesses (
 horse_id INT NOT NULL PRIMARY KEY,
 wagon_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 slot_no TINYINT UNSIGNED NOT NULL,
 character_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 provider_id VARCHAR(64) NOT NULL,
 model VARCHAR(80) NOT NULL,
 UNIQUE KEY ix_slot(wagon_id,slot_no)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS fl_jobs (
 id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 kind VARCHAR(24) NOT NULL,
 actor VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 wagon_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT '',
 state VARCHAR(24) NOT NULL,
 payload MEDIUMTEXT NOT NULL CHECK(JSON_VALID(payload)),
 issue VARCHAR(255) NOT NULL DEFAULT '',
 created_at BIGINT UNSIGNED NOT NULL,
 KEY ix_job_wagon(wagon_id,state), KEY ix_job_state(state,created_at)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS fl_crates (
 id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 wagon_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 x DOUBLE NOT NULL,y DOUBLE NOT NULL,z DOUBLE NOT NULL,
 state ENUM('pending','available','empty') NOT NULL DEFAULT 'pending',
 created_at BIGINT UNSIGNED NOT NULL
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS fl_contracts (
 id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 customer_type ENUM('character','company') NOT NULL,
 customer_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 customer_bank BIGINT UNSIGNED NOT NULL,
 carrier_type ENUM('character','company') NULL,
 carrier_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
 carrier_bank BIGINT UNSIGNED NULL,
 carrier_actor VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
 wagon_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NULL,
 origin_id VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 destination_id VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 reward INT UNSIGNED NOT NULL,
 payload MEDIUMTEXT NOT NULL CHECK(JSON_VALID(payload)),
 state VARCHAR(24) NOT NULL,
 deadline BIGINT UNSIGNED NOT NULL,
 issue VARCHAR(255) NOT NULL DEFAULT '',
 created_at BIGINT UNSIGNED NOT NULL,
 KEY ix_contract_state(state,deadline),KEY ix_contract_wagon(wagon_id,state)
) ENGINE=InnoDB;
