ALTER TABLE frontier_property_private_offers
    ADD COLUMN IF NOT EXISTS deposit_cents BIGINT UNSIGNED NOT NULL DEFAULT 0;
ALTER TABLE frontier_property_rentals
    ADD COLUMN IF NOT EXISTS deposit_cents BIGINT UNSIGNED NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS deposit_refunded BOOLEAN NOT NULL DEFAULT FALSE,
    ADD INDEX IF NOT EXISTS ix_frontier_rental_refund (state,deposit_refunded,retry_at,id);

DELIMITER $$
CREATE OR REPLACE PROCEDURE frontier_property_rent_reserve_v2(
    IN target BIGINT UNSIGNED, IN tenant CHAR(34), IN bank BIGINT UNSIGNED,
    IN price BIGINT UNSIGNED, IN duration_secs INT UNSIGNED, IN furniture BOOLEAN, IN deposit BIGINT UNSIGNED
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
            duration_seconds,allow_furnish,deposit_cents)
        VALUES (target,tenant,bank,price,duration_secs,furniture,deposit);
        SET rental=LAST_INSERT_ID();
    END IF;
    COMMIT;
    SELECT rental AS id;
END$$
DELIMITER ;

DELIMITER $$
CREATE OR REPLACE PROCEDURE frontier_property_rent_offer_v2(
    IN target BIGINT UNSIGNED, IN landlord CHAR(34), IN bank BIGINT UNSIGNED,
    IN price BIGINT UNSIGNED, IN duration_secs INT UNSIGNED, IN furniture BOOLEAN, IN deposit BIGINT UNSIGNED
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
          (property_id,landlord_id,bank_id,price_cents,duration_seconds,allow_furnish,offer_version,deposit_cents)
        VALUES (target,landlord,bank,price,duration_secs,furniture,UUID(),deposit)
        ON DUPLICATE KEY UPDATE landlord_id=VALUES(landlord_id),bank_id=VALUES(bank_id),
          price_cents=VALUES(price_cents),duration_seconds=VALUES(duration_seconds),
          allow_furnish=VALUES(allow_furnish),offer_version=VALUES(offer_version),deposit_cents=VALUES(deposit_cents);
        SET accepted=TRUE;
    END IF;
    COMMIT;
    SELECT accepted AS accepted;
END$$

CREATE OR REPLACE PROCEDURE frontier_property_private_rent_v2(
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
          (property_id,tenant_id,account_id,landlord_bank_id,price_cents,duration_seconds,allow_furnish,deposit_cents)
        SELECT target,tenant,bank,offer.bank_id,offer.price_cents,offer.duration_seconds,offer.allow_furnish,offer.deposit_cents
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
