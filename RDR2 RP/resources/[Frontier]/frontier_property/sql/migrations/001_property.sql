CREATE TABLE IF NOT EXISTS frontier_properties (
    id VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    label VARCHAR(96) NOT NULL,
    property_type VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    market_id VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NULL,
    price_minor BIGINT UNSIGNED NOT NULL,
    rent_minor BIGINT UNSIGNED NOT NULL DEFAULT 0,
    x DOUBLE NOT NULL,
    y DOUBLE NOT NULL,
    z DOUBLE NOT NULL,
    bucket INT NOT NULL DEFAULT 0,
    state ENUM('available','purchasing','owned') NOT NULL DEFAULT 'available',
    owner_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    purchase_bank BIGINT UNSIGNED NULL,
    purchase_key VARCHAR(96) CHARACTER SET ascii COLLATE ascii_bin NULL,
    purchased_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY ix_frontier_properties_owner (owner_id,state),
    KEY ix_frontier_properties_state (state,id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS frontier_property_members (
    property_id VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    character_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    role ENUM('manager','employee') NOT NULL DEFAULT 'employee',
    granted_by VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (property_id,character_id),
    KEY ix_frontier_property_member_character (character_id),
    CONSTRAINT fk_frontier_property_member_property
        FOREIGN KEY (property_id) REFERENCES frontier_properties(id) ON DELETE CASCADE
) ENGINE=InnoDB;
