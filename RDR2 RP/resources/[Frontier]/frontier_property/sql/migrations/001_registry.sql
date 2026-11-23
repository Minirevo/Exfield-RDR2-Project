CREATE TABLE IF NOT EXISTS frontier_properties (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    property_type ENUM('building', 'land', 'constructed') NOT NULL,
    status ENUM('active', 'inactive') NOT NULL DEFAULT 'inactive',
    label VARCHAR(120) NOT NULL,
    exterior_x DOUBLE NOT NULL,
    exterior_y DOUBLE NOT NULL,
    exterior_z DOUBLE NOT NULL,
    interior_key VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    estimated_value_cents BIGINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS frontier_property_ownership (
    property_id BIGINT UNSIGNED NOT NULL,
    party_type ENUM('character', 'business', 'government') NOT NULL,
    party_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    share_bps SMALLINT UNSIGNED NOT NULL,
    CONSTRAINT ck_frontier_property_share CHECK (share_bps BETWEEN 1 AND 10000),
    PRIMARY KEY (property_id, party_type, party_id),
    KEY ix_frontier_property_owner (party_type, party_id),
    CONSTRAINT fk_frontier_property_owner FOREIGN KEY (property_id) REFERENCES frontier_properties (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS frontier_property_permissions (
    property_id BIGINT UNSIGNED NOT NULL,
    character_id CHAR(34) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    permission_key ENUM('enter', 'furnish', 'use_facility', 'construct', 'manage_access') NOT NULL,
    allow_access BOOLEAN NOT NULL,
    CONSTRAINT ck_frontier_property_allow CHECK (allow_access IN (0, 1)),
    PRIMARY KEY (property_id, character_id, permission_key),
    CONSTRAINT fk_frontier_property_permission FOREIGN KEY (property_id) REFERENCES frontier_properties (id),
    CONSTRAINT fk_frontier_property_character FOREIGN KEY (character_id) REFERENCES frontier_character_identities (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS frontier_property_facilities (
    property_id BIGINT UNSIGNED NOT NULL,
    facility_key VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    source_key VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    PRIMARY KEY (property_id, facility_key, source_key),
    CONSTRAINT fk_frontier_property_facility FOREIGN KEY (property_id) REFERENCES frontier_properties (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
