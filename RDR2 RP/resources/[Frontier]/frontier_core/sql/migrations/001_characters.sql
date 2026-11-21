CREATE TABLE IF NOT EXISTS frontier_character_identities (
    id CHAR(34) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    provider VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    provider_character_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_identifier VARCHAR(128) NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (provider, provider_character_id),
    UNIQUE KEY uq_frontier_character_id (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS frontier_character_data (
    character_id CHAR(34) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    firstname VARCHAR(96) NULL,
    lastname VARCHAR(96) NULL,
    full_name VARCHAR(193) NULL,
    date_of_birth DATE NULL,
    gender VARCHAR(48) NULL,
    metadata_json TEXT NOT NULL,
    attributes_json TEXT NOT NULL,
    version INT UNSIGNED NOT NULL DEFAULT 1,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    PRIMARY KEY (character_id),
    CONSTRAINT fk_frontier_character_data FOREIGN KEY (character_id)
        REFERENCES frontier_character_identities (id),
    CONSTRAINT ck_frontier_character_metadata CHECK (JSON_VALID(metadata_json)),
    CONSTRAINT ck_frontier_character_attributes CHECK (JSON_VALID(attributes_json))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
