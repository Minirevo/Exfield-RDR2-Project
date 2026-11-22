CREATE TABLE IF NOT EXISTS frontier_trade_offers (
    id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    seller_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    seller_bank BIGINT UNSIGNED NOT NULL,
    market_id VARCHAR(48) NOT NULL,
    item_id VARCHAR(48) NOT NULL,
    quantity INT UNSIGNED NOT NULL,
    available INT UNSIGNED NOT NULL,
    unit_minor BIGINT UNSIGNED NOT NULL,
    expires_at DATETIME NOT NULL,
    retry_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    active_sale CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
    state ENUM('stock','open','return','closed','rejected') NOT NULL DEFAULT 'stock',
    CHECK (quantity BETWEEN 1 AND 1000 AND available <= quantity AND unit_minor BETWEEN 1 AND 10000),
    KEY ix_market (market_id,state,expires_at,id),
    KEY ix_offer_jobs (state,retry_at,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS frontier_trade_sales (
    id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    offer_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    buyer_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    buyer_bank BIGINT UNSIGNED NOT NULL,
    quantity INT UNSIGNED NOT NULL CHECK (quantity BETWEEN 1 AND 1000),
    state ENUM('stock','payment','reverse','complete','rejected') NOT NULL DEFAULT 'stock',
    claimed_at DATETIME NULL,
    retry_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (offer_id) REFERENCES frontier_trade_offers(id),
    KEY ix_sale_jobs (state,retry_at,id),
    KEY ix_sale_buyer (buyer_id,claimed_at,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP PROCEDURE IF EXISTS frontier_trade_sale_v1;
DELIMITER //
CREATE PROCEDURE frontier_trade_sale_v1(IN p_action VARCHAR(12), IN p_id CHAR(36),
    IN p_offer CHAR(36), IN p_actor VARCHAR(64), IN p_bank BIGINT UNSIGNED, IN p_quantity INT UNSIGNED)
operation: BEGIN
    DECLARE v_offer CHAR(36);
    DECLARE v_left INT UNSIGNED;
    DECLARE v_quantity INT UNSIGNED;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    IF p_action = 'buy' THEN
        UPDATE frontier_trade_offers SET active_sale = p_id
        WHERE id=p_offer AND state='open' AND active_sale IS NULL AND seller_id<>p_actor
          AND expires_at>UTC_TIMESTAMP() AND p_quantity BETWEEN 1 AND available;
        IF ROW_COUNT() <> 1 THEN ROLLBACK; SELECT 'unavailable' AS code; LEAVE operation; END IF;
        INSERT INTO frontier_trade_sales(id,offer_id,buyer_id,buyer_bank,quantity)
        VALUES(p_id,p_offer,p_actor,p_bank,p_quantity);
    ELSEIF p_action IN ('complete','reject') THEN
        SELECT o.id,o.available,s.quantity INTO v_offer,v_left,v_quantity
        FROM frontier_trade_sales s JOIN frontier_trade_offers o ON o.id=s.offer_id
        WHERE s.id=p_id AND o.active_sale=s.id AND o.state='open'
          AND ((p_action='complete' AND s.state='payment') OR (p_action='reject' AND s.state='reverse'))
        FOR UPDATE;
        IF v_offer IS NULL THEN ROLLBACK; SELECT 'unavailable' AS code; LEAVE operation; END IF;
        IF p_action='complete' THEN SET v_left=v_left-v_quantity; END IF;
        UPDATE frontier_trade_sales SET state=IF(p_action='complete','complete','rejected') WHERE id=p_id;
        UPDATE frontier_trade_offers SET active_sale=NULL,available=v_left,
            state=IF(v_left=0,'closed','open') WHERE id=v_offer;
    ELSE
        ROLLBACK; SELECT 'unavailable' AS code; LEAVE operation;
    END IF;
    COMMIT;
    SELECT 'ok' AS code;
END//
DELIMITER ;
