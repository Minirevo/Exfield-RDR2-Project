CREATE TABLE IF NOT EXISTS frontier_property_finance (
    property_id BIGINT UNSIGNED PRIMARY KEY,
    debt_cents BIGINT UNSIGNED NOT NULL DEFAULT 0,
    FOREIGN KEY (property_id) REFERENCES frontier_properties(id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS frontier_property_sales (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    property_id BIGINT UNSIGNED NOT NULL,
    buyer_id CHAR(34) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    buyer_bank_id BIGINT UNSIGNED NULL,
    price_cents BIGINT UNSIGNED NOT NULL,
    assumed_lease_id BIGINT UNSIGNED NULL,
    state ENUM('offered','reserved','complete','declined','cancelled') NOT NULL DEFAULT 'offered',
    retry_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY ix_frontier_sale_work (state,retry_at,id),
    KEY ix_frontier_sale_property (property_id,state),
    FOREIGN KEY (property_id) REFERENCES frontier_properties(id),
    FOREIGN KEY (buyer_id) REFERENCES frontier_character_identities(id),
    FOREIGN KEY (assumed_lease_id) REFERENCES frontier_property_rentals(id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS frontier_property_sale_approvals (
    sale_id BIGINT UNSIGNED NOT NULL,
    owner_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    share_bps SMALLINT UNSIGNED NOT NULL,
    bank_id BIGINT UNSIGNED NULL,
    paid BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (sale_id,owner_id),
    FOREIGN KEY (sale_id) REFERENCES frontier_property_sales(id)
) ENGINE=InnoDB;

DELIMITER $$
CREATE OR REPLACE PROCEDURE frontier_sale_offer_v1(
    IN target BIGINT UNSIGNED, IN seller CHAR(34), IN buyer CHAR(34), IN price BIGINT UNSIGNED)
BEGIN
    DECLARE estate BIGINT UNSIGNED DEFAULT NULL;
    DECLARE offer BIGINT UNSIGNED DEFAULT NULL;
    DECLARE lease BIGINT UNSIGNED DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT id INTO estate FROM frontier_properties WHERE id=target AND status='active' FOR UPDATE;
    IF estate IS NOT NULL
      AND COALESCE((SELECT debt_cents FROM frontier_property_finance WHERE property_id=target),0)=0
      AND EXISTS (SELECT 1 FROM frontier_property_ownership WHERE property_id=target
        AND party_type='character' AND party_id=seller)
      AND NOT EXISTS (SELECT 1 FROM frontier_property_ownership WHERE property_id=target
        AND (party_type<>'character' OR party_id=buyer))
      AND (SELECT SUM(share_bps) FROM frontier_property_ownership WHERE property_id=target)=10000
      AND NOT EXISTS (SELECT 1 FROM frontier_property_rentals WHERE property_id=target AND state='reserved')
      AND NOT EXISTS (SELECT 1 FROM frontier_property_sales WHERE property_id=target AND state='reserved') THEN
        SELECT MAX(id) INTO lease FROM frontier_property_rentals WHERE property_id=target
            AND state='active' AND ends_at>UTC_TIMESTAMP();
        UPDATE frontier_property_sales SET state='cancelled' WHERE property_id=target AND state='offered';
        INSERT INTO frontier_property_sales (property_id,buyer_id,price_cents,assumed_lease_id)
            VALUES (target,buyer,price,lease);
        SET offer=LAST_INSERT_ID();
        INSERT INTO frontier_property_sale_approvals (sale_id,owner_id,share_bps)
            SELECT offer,party_id,share_bps FROM frontier_property_ownership WHERE property_id=target;
    END IF;
    COMMIT;
    SELECT offer AS id;
END$$

CREATE OR REPLACE PROCEDURE frontier_sale_reserve_v1(
    IN offer BIGINT UNSIGNED, IN buyer CHAR(34), IN bank BIGINT UNSIGNED, IN consent BOOLEAN)
BEGIN
    DECLARE target BIGINT UNSIGNED DEFAULT NULL;
    DECLARE estate BIGINT UNSIGNED DEFAULT NULL;
    DECLARE lease BIGINT UNSIGNED DEFAULT NULL;
    DECLARE accepted BOOLEAN DEFAULT FALSE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT MAX(property_id) INTO target FROM frontier_property_sales WHERE id=offer AND buyer_id=buyer;
    SELECT id INTO estate FROM frontier_properties WHERE id=target AND status='active' FOR UPDATE;
    SELECT MAX(id) INTO lease FROM frontier_property_rentals WHERE property_id=target
        AND state='active' AND ends_at>UTC_TIMESTAMP();
    IF estate IS NOT NULL AND COALESCE((SELECT debt_cents FROM frontier_property_finance
        WHERE property_id=target),0)=0
      AND NOT EXISTS (SELECT 1 FROM frontier_property_rentals WHERE property_id=target AND state='reserved')
      AND NOT EXISTS (SELECT 1 FROM frontier_property_sales WHERE property_id=target AND state='reserved')
      AND NOT EXISTS (SELECT 1 FROM frontier_property_furniture WHERE property_id=target AND state='pending')
      AND NOT EXISTS (SELECT 1 FROM frontier_property_sale_approvals WHERE sale_id=offer AND bank_id IS NULL)
      AND NOT EXISTS (SELECT 1 FROM frontier_property_ownership o
        LEFT JOIN frontier_property_sale_approvals a ON a.sale_id=offer AND a.owner_id=o.party_id AND a.share_bps=o.share_bps
        WHERE o.property_id=target AND (o.party_type<>'character' OR a.owner_id IS NULL))
      AND (SELECT COUNT(*) FROM frontier_property_ownership WHERE property_id=target)
        =(SELECT COUNT(*) FROM frontier_property_sale_approvals WHERE sale_id=offer) THEN
        UPDATE frontier_property_sales SET state='reserved',buyer_bank_id=bank
            WHERE id=offer AND state='offered' AND (lease <=> assumed_lease_id)
              AND (lease IS NULL OR consent=TRUE);
        SET accepted=ROW_COUNT()=1;
    END IF;
    COMMIT;
    SELECT accepted AS accepted;
END$$

CREATE OR REPLACE PROCEDURE frontier_sale_finish_v1(IN offer BIGINT UNSIGNED)
BEGIN
    DECLARE target BIGINT UNSIGNED DEFAULT NULL;
    DECLARE estate BIGINT UNSIGNED DEFAULT NULL;
    DECLARE buyer CHAR(34);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT MAX(property_id) INTO target FROM frontier_property_sales WHERE id=offer;
    SELECT id INTO estate FROM frontier_properties WHERE id=target FOR UPDATE;
    SELECT buyer_id INTO buyer FROM frontier_property_sales WHERE id=offer AND state='reserved' FOR UPDATE;
    IF estate IS NOT NULL AND buyer IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM frontier_property_sale_approvals WHERE sale_id=offer AND paid=0
    ) THEN
        DELETE FROM frontier_property_ownership WHERE property_id=target;
        INSERT INTO frontier_property_ownership VALUES (target,'character',buyer,10000);
        DELETE FROM frontier_property_private_offers WHERE property_id=target;
        DELETE FROM frontier_property_permissions WHERE property_id=target;
        UPDATE frontier_property_furniture SET state='recovery'
            WHERE property_id=target AND state='placed' AND lease_id IS NULL;
        UPDATE frontier_property_sales SET state='complete' WHERE id=offer;
    END IF;
    COMMIT;
END$$

CREATE OR REPLACE TRIGGER frontier_property_sale_rental_guard BEFORE INSERT ON frontier_property_rentals
FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM frontier_property_sales WHERE property_id=NEW.property_id AND state='reserved') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Sale in progress';
    END IF;
END$$

CREATE OR REPLACE TRIGGER frontier_property_sale_furniture_guard BEFORE INSERT ON frontier_property_furniture
FOR EACH ROW
BEGIN
    IF EXISTS (SELECT 1 FROM frontier_property_sales WHERE property_id=NEW.property_id AND state='reserved') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Sale in progress';
    END IF;
END$$
DELIMITER ;
