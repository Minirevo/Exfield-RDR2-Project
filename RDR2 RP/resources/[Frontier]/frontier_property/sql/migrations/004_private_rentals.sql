CREATE TABLE IF NOT EXISTS frontier_property_private_offers (
    property_id BIGINT UNSIGNED PRIMARY KEY,
    landlord_id CHAR(34) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    bank_id BIGINT UNSIGNED NOT NULL,
    price_cents BIGINT UNSIGNED NOT NULL,
    duration_seconds INT UNSIGNED NOT NULL,
    allow_furnish BOOLEAN NOT NULL,
    offer_version CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    FOREIGN KEY (property_id) REFERENCES frontier_properties(id),
    FOREIGN KEY (landlord_id) REFERENCES frontier_character_identities(id)
) ENGINE=InnoDB;
ALTER TABLE frontier_property_rentals
    ADD COLUMN IF NOT EXISTS landlord_bank_id BIGINT UNSIGNED NULL;

DELIMITER $$
CREATE OR REPLACE PROCEDURE frontier_property_rent_offer_v1(
    IN target BIGINT UNSIGNED, IN landlord CHAR(34), IN bank BIGINT UNSIGNED,
    IN price BIGINT UNSIGNED, IN duration_secs INT UNSIGNED, IN furniture BOOLEAN
)
BEGIN
    DECLARE building BIGINT UNSIGNED DEFAULT NULL;
    DECLARE accepted BOOLEAN DEFAULT FALSE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT id INTO building FROM frontier_properties WHERE id=target AND status='active'
        AND property_type='building' AND interior_key IS NOT NULL FOR UPDATE;
    IF building IS NOT NULL AND EXISTS (
        SELECT 1 FROM frontier_property_ownership WHERE property_id=target
        AND party_type='character' AND party_id=landlord AND share_bps=10000
    ) THEN
        INSERT INTO frontier_property_private_offers
          (property_id,landlord_id,bank_id,price_cents,duration_seconds,allow_furnish,offer_version)
        VALUES (target,landlord,bank,price,duration_secs,furniture,UUID())
        ON DUPLICATE KEY UPDATE landlord_id=VALUES(landlord_id),bank_id=VALUES(bank_id),
          price_cents=VALUES(price_cents),duration_seconds=VALUES(duration_seconds),
          allow_furnish=VALUES(allow_furnish),offer_version=VALUES(offer_version);
        SET accepted=TRUE;
    END IF;
    COMMIT;
    SELECT accepted AS accepted;
END$$

CREATE OR REPLACE PROCEDURE frontier_property_private_rent_v1(
    IN target BIGINT UNSIGNED, IN tenant CHAR(34), IN bank BIGINT UNSIGNED, IN quoted_version CHAR(36)
)
BEGIN
    DECLARE building BIGINT UNSIGNED DEFAULT NULL;
    DECLARE rental BIGINT UNSIGNED DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT id INTO building FROM frontier_properties WHERE id=target AND status='active'
        AND property_type='building' AND interior_key IS NOT NULL FOR UPDATE;
    IF building IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM frontier_property_rentals WHERE property_id=target
            AND (state='reserved' OR (state='active' AND ends_at>UTC_TIMESTAMP()))
    ) THEN
        INSERT INTO frontier_property_rentals
          (property_id,tenant_id,account_id,landlord_bank_id,price_cents,duration_seconds,allow_furnish)
        SELECT target,tenant,bank,offer.bank_id,offer.price_cents,offer.duration_seconds,offer.allow_furnish
        FROM frontier_property_private_offers offer
        JOIN frontier_property_ownership owner ON owner.property_id=offer.property_id
            AND owner.party_type='character' AND owner.party_id=offer.landlord_id AND owner.share_bps=10000
        WHERE offer.property_id=target AND offer.offer_version=quoted_version AND offer.landlord_id<>tenant;
        IF ROW_COUNT()=1 THEN SET rental=LAST_INSERT_ID(); END IF;
    END IF;
    COMMIT;
    SELECT rental AS id;
END$$
DELIMITER ;
