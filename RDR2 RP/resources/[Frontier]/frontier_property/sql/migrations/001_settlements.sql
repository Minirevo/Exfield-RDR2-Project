-- Fresh v2 state, intentionally independent of the removed legacy schema.
CREATE TABLE IF NOT EXISTS frontier_property_v2_state (
 id TINYINT UNSIGNED PRIMARY KEY, revision BIGINT UNSIGNED NOT NULL DEFAULT 0,
 payload LONGTEXT NOT NULL CHECK (JSON_VALID(payload))
) ENGINE=InnoDB;
INSERT IGNORE INTO frontier_property_v2_state (id,payload)
VALUES (1,'{"settlements":{},"jobs":{},"nextBucket":1500000000}');
