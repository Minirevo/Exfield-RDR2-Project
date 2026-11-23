CREATE TABLE IF NOT EXISTS frontier_property_rentals (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    property_id BIGINT UNSIGNED NOT NULL,
    tenant_id CHAR(34) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_id BIGINT UNSIGNED NOT NULL,
    price_cents BIGINT UNSIGNED NOT NULL,
    duration_seconds INT UNSIGNED NOT NULL,
    allow_furnish BOOLEAN NOT NULL,
    state ENUM('reserved','active','expired','declined') NOT NULL DEFAULT 'reserved',
    ends_at DATETIME NULL,
    retry_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY ix_frontier_rental_property (property_id,state,ends_at),
    KEY ix_frontier_rental_worker (state,retry_at,id),
    KEY ix_frontier_rental_tenant (tenant_id,id),
    FOREIGN KEY (property_id) REFERENCES frontier_properties(id),
    FOREIGN KEY (tenant_id) REFERENCES frontier_character_identities(id)
) ENGINE=InnoDB;

DELIMITER $$
CREATE OR REPLACE PROCEDURE frontier_property_rent_reserve_v1(
    IN target BIGINT UNSIGNED, IN tenant CHAR(34), IN bank BIGINT UNSIGNED,
    IN price BIGINT UNSIGNED, IN duration_secs INT UNSIGNED, IN furniture BOOLEAN
)
BEGIN
    DECLARE building BIGINT UNSIGNED DEFAULT NULL;
    DECLARE rental BIGINT UNSIGNED DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT id INTO building FROM frontier_properties
      WHERE id=target AND status='active' AND property_type='building' AND interior_key IS NOT NULL
      FOR UPDATE;
    IF building IS NOT NULL
        AND EXISTS (SELECT 1 FROM frontier_property_ownership WHERE property_id=target
            AND party_type='government' AND share_bps=10000)
        AND NOT EXISTS (SELECT 1 FROM frontier_property_rentals WHERE property_id=target
            AND (state='reserved' OR (state='active' AND ends_at>UTC_TIMESTAMP()))) THEN
        INSERT INTO frontier_property_rentals (property_id,tenant_id,account_id,price_cents,
            duration_seconds,allow_furnish)
        VALUES (target,tenant,bank,price,duration_secs,furniture);
        SET rental=LAST_INSERT_ID();
    END IF;
    COMMIT;
    SELECT rental AS id;
END$$
DELIMITER ;
