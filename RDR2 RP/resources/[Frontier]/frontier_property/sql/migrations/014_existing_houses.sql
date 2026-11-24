CREATE TABLE IF NOT EXISTS frontier_property_houses (
    property_id BIGINT UNSIGNED NOT NULL PRIMARY KEY,
    house_key VARCHAR(32) NOT NULL,
    public_access TINYINT(1) NOT NULL DEFAULT 0,
    CONSTRAINT fk_frontier_existing_house_property FOREIGN KEY (property_id)
        REFERENCES frontier_properties(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS frontier_property_house_returns (
    character_id CHAR(34) NOT NULL PRIMARY KEY,
    x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL, heading DOUBLE NOT NULL
) ENGINE=InnoDB;
