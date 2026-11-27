-- Apply after 001_production.sql. No legacy data is changed.
CREATE TABLE IF NOT EXISTS frontier_production_stations (
 id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 plot_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 owner_type ENUM('character','company') NOT NULL,
 owner_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 grantor VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 input_stock VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT '',
 output_stock VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT '',
 employee TINYINT UNSIGNED NOT NULL DEFAULT 0,
 KEY ix_station_plot(plot_id), KEY ix_station_input(input_stock), KEY ix_station_output(output_stock)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS frontier_production_station_jobs (
 id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 station_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 actor VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 mode ENUM('manual','npc') NOT NULL,
 state VARCHAR(16) NOT NULL DEFAULT 'queued',
 payload MEDIUMTEXT NOT NULL CHECK (JSON_VALID(payload)),
 due_at BIGINT UNSIGNED NOT NULL DEFAULT 0,
 retry_at BIGINT UNSIGNED NOT NULL DEFAULT 0,
 created_at BIGINT UNSIGNED NOT NULL,
 issue VARCHAR(100) NOT NULL DEFAULT '',
 KEY ix_station_jobs(station_id,state,created_at,id),
 KEY ix_station_due(state,retry_at),
 KEY ix_station_actor(actor,state)
) ENGINE=InnoDB;
