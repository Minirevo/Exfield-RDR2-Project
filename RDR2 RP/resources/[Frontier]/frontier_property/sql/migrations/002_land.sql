CREATE TABLE IF NOT EXISTS frontier_land_revision (
    id TINYINT UNSIGNED PRIMARY KEY,
    revision BIGINT UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB;
INSERT IGNORE INTO frontier_land_revision (id) VALUES (1);

CREATE TABLE IF NOT EXISTS frontier_land_claims (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    character_id CHAR(34) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    zone_key VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    polygon_json LONGTEXT NOT NULL CHECK (JSON_VALID(polygon_json)),
    area_m2 DOUBLE NOT NULL,
    price_cents BIGINT UNSIGNED NOT NULL,
    account_id BIGINT UNSIGNED NOT NULL,
    state ENUM('reserved','owned','declined') NOT NULL DEFAULT 'reserved',
    property_id BIGINT UNSIGNED NULL,
    retry_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY ix_frontier_land_work (state,retry_at,id),
    FOREIGN KEY (character_id) REFERENCES frontier_character_identities (id),
    FOREIGN KEY (property_id) REFERENCES frontier_properties (id)
) ENGINE=InnoDB;

DELIMITER $$
CREATE OR REPLACE PROCEDURE frontier_land_reserve_v1(
    IN expected_revision BIGINT UNSIGNED, IN actor CHAR(34), IN zone VARCHAR(64),
    IN polygon LONGTEXT, IN area DOUBLE, IN price BIGINT UNSIGNED, IN bank BIGINT UNSIGNED
)
BEGIN
    DECLARE current_revision BIGINT UNSIGNED;
    DECLARE claim_id BIGINT UNSIGNED DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT revision INTO current_revision FROM frontier_land_revision WHERE id=1 FOR UPDATE;
    IF current_revision = expected_revision AND NOT EXISTS (
        SELECT 1 FROM frontier_land_claims WHERE character_id=actor AND state='reserved'
    ) THEN
        INSERT INTO frontier_land_claims (character_id,zone_key,polygon_json,area_m2,price_cents,account_id)
        VALUES (actor,zone,polygon,area,price,bank);
        SET claim_id = LAST_INSERT_ID();
        UPDATE frontier_land_revision SET revision=revision+1 WHERE id=1;
    END IF;
    COMMIT;
    SELECT claim_id AS id;
END$$

CREATE OR REPLACE PROCEDURE frontier_land_finish_v1(IN claim BIGINT UNSIGNED, IN paid BOOLEAN)
BEGIN
    DECLARE revision_lock BIGINT UNSIGNED;
    DECLARE claim_state VARCHAR(16);
    DECLARE owner_id CHAR(34);
    DECLARE zone VARCHAR(64);
    DECLARE coords LONGTEXT;
    DECLARE cost BIGINT UNSIGNED;
    DECLARE new_property BIGINT UNSIGNED;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT revision INTO revision_lock FROM frontier_land_revision WHERE id=1 FOR UPDATE;
    SELECT state,character_id,zone_key,polygon_json,price_cents
      INTO claim_state,owner_id,zone,coords,cost FROM frontier_land_claims WHERE id=claim FOR UPDATE;
    IF claim_state='reserved' AND paid THEN
        INSERT INTO frontier_properties (property_type,status,label,exterior_x,exterior_y,exterior_z,estimated_value_cents)
        VALUES ('land','active',CONCAT('Grundstück ',zone),
            JSON_EXTRACT(coords,'$[0].x'),JSON_EXTRACT(coords,'$[0].y'),JSON_EXTRACT(coords,'$[0].z'),cost);
        SET new_property=LAST_INSERT_ID();
        INSERT INTO frontier_property_ownership VALUES (new_property,'character',owner_id,10000);
        UPDATE frontier_land_claims SET state='owned',property_id=new_property WHERE id=claim;
    ELSEIF claim_state='reserved' THEN
        UPDATE frontier_land_claims SET state='declined' WHERE id=claim;
        UPDATE frontier_land_revision SET revision=revision+1 WHERE id=1;
    END IF;
    COMMIT;
END$$
DELIMITER ;
