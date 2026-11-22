ALTER TABLE frontier_trade_requests
    ADD COLUMN IF NOT EXISTS settled_quantity INT UNSIGNED NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS active_contract CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
    ADD COLUMN IF NOT EXISTS base_quote_minor BIGINT UNSIGNED NULL,
    ADD COLUMN IF NOT EXISTS quote_minor BIGINT UNSIGNED NULL,
    ADD COLUMN IF NOT EXISTS next_quote_at DATETIME NULL,
    ADD COLUMN IF NOT EXISTS spent_minor BIGINT UNSIGNED NOT NULL DEFAULT 0,
    ADD INDEX IF NOT EXISTS ix_trade_quote (state,next_quote_at,id);

CREATE TABLE IF NOT EXISTS frontier_trade_price_history (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    request_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    market_id VARCHAR(48) NOT NULL,
    item_id VARCHAR(48) NOT NULL,
    price_minor BIGINT UNSIGNED NOT NULL,
    quoted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (request_id) REFERENCES frontier_trade_requests(id),
    KEY ix_trade_price_market (market_id,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS frontier_trade_contracts (
    id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    request_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    seller_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    seller_bank BIGINT UNSIGNED NOT NULL,
    unit_minor BIGINT UNSIGNED NOT NULL,
    due_at DATETIME NOT NULL,
    active_delivery CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
    state ENUM('active','expired','cancelled','closed') NOT NULL DEFAULT 'active',
    FOREIGN KEY (request_id) REFERENCES frontier_trade_requests(id),
    KEY ix_trade_contract_due (state,due_at,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS frontier_trade_deliveries (
    id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    contract_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    quantity INT UNSIGNED NOT NULL CHECK (quantity > 0),
    state ENUM('stock','payment','complete','rejected') NOT NULL DEFAULT 'stock',
    retry_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    claimed_at DATETIME NULL,
    FOREIGN KEY (contract_id) REFERENCES frontier_trade_contracts(id),
    KEY ix_trade_delivery_jobs (state,retry_at,id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP PROCEDURE IF EXISTS frontier_trade_contract_v1;
DROP TRIGGER IF EXISTS frontier_trade_record_price;
DELIMITER //
CREATE PROCEDURE frontier_trade_contract_v1(IN p_action VARCHAR(12), IN p_id CHAR(36),
    IN p_parent CHAR(36), IN p_actor VARCHAR(64), IN p_value BIGINT UNSIGNED, IN p_quote BIGINT UNSIGNED)
operation: BEGIN
    DECLARE v_request CHAR(36);
    DECLARE v_contract CHAR(36);
    DECLARE v_done INT UNSIGNED;
    DECLARE v_total INT UNSIGNED;
    DECLARE v_qty INT UNSIGNED;
    DECLARE v_spent BIGINT UNSIGNED;
    DECLARE v_unit BIGINT UNSIGNED;
    DECLARE v_budget BIGINT UNSIGNED;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    IF p_action = 'accept' THEN
        UPDATE frontier_trade_requests SET active_contract = p_id
        WHERE id = p_parent AND state = 'open' AND active_contract IS NULL AND buyer_id <> p_actor
          AND expires_at > UTC_TIMESTAMP() AND settled_quantity < quantity
          AND (p_quote = 0 OR COALESCE(quote_minor, price_minor) = p_quote);
        IF ROW_COUNT() <> 1 THEN ROLLBACK; SELECT 'unavailable' AS code; LEAVE operation; END IF;
        INSERT INTO frontier_trade_contracts(id, request_id, seller_id, seller_bank, unit_minor, due_at)
        SELECT p_id, id, p_actor, p_value, COALESCE(quote_minor, price_minor), LEAST(expires_at, DATE_ADD(UTC_TIMESTAMP(), INTERVAL 12 HOUR))
        FROM frontier_trade_requests WHERE id = p_parent;
    ELSEIF p_action = 'deliver' THEN
        UPDATE frontier_trade_contracts c JOIN frontier_trade_requests r ON r.id = c.request_id
        SET c.active_delivery = p_id
        WHERE c.id = p_parent AND c.seller_id = p_actor AND c.state = 'active'
          AND c.active_delivery IS NULL AND r.active_contract = c.id AND r.state = 'open'
          AND c.due_at > UTC_TIMESTAMP() AND r.expires_at > UTC_TIMESTAMP()
          AND p_value BETWEEN 1 AND r.quantity - r.settled_quantity;
        IF ROW_COUNT() <> 1 THEN ROLLBACK; SELECT 'unavailable' AS code; LEAVE operation; END IF;
        INSERT INTO frontier_trade_deliveries(id, contract_id, quantity) VALUES(p_id,p_parent,p_value);
    ELSEIF p_action IN ('complete','reject') THEN
        SELECT r.id, c.id, r.settled_quantity, r.quantity, d.quantity, r.spent_minor, c.unit_minor, r.budget_minor
        INTO v_request, v_contract, v_done, v_total, v_qty, v_spent, v_unit, v_budget
        FROM frontier_trade_deliveries d JOIN frontier_trade_contracts c ON c.id = d.contract_id
        JOIN frontier_trade_requests r ON r.id = c.request_id
        WHERE d.id = p_id AND c.active_delivery = d.id AND r.active_contract = c.id
          AND d.state = IF(p_action = 'complete','payment','stock') FOR UPDATE;
        IF v_request IS NULL THEN ROLLBACK; SELECT 'unavailable' AS code; LEAVE operation; END IF;
        IF p_action = 'complete' THEN
            SET v_done = v_done + v_qty, v_spent = v_spent + v_qty * v_unit;
        END IF;
        UPDATE frontier_trade_deliveries SET state = IF(p_action = 'complete','complete','rejected') WHERE id = p_id;
        UPDATE frontier_trade_contracts SET active_delivery = NULL,
          state = IF(v_done = v_total,'closed','active') WHERE id = v_contract;
        UPDATE frontier_trade_requests SET settled_quantity = v_done, spent_minor = v_spent, retry_at = UTC_TIMESTAMP(),
          active_contract = IF(v_done = v_total,NULL,v_contract),
          state = IF(v_done = v_total,IF(v_spent < v_budget,'refund','closed'),'open') WHERE id = v_request;
    ELSEIF p_action IN ('expire','cancel') THEN
        UPDATE frontier_trade_contracts c JOIN frontier_trade_requests r ON r.id = c.request_id
        SET c.state = IF(p_action='expire','expired','cancelled'), r.active_contract = NULL
        WHERE c.id = p_id AND c.state = 'active'
          AND ((p_action='expire' AND c.due_at <= UTC_TIMESTAMP())
            OR (p_action='cancel' AND p_actor IN (c.seller_id,r.buyer_id)))
          AND c.active_delivery IS NULL AND r.active_contract = c.id;
        IF ROW_COUNT() = 0 THEN ROLLBACK; SELECT 'unavailable' AS code; LEAVE operation; END IF;
    ELSE
        ROLLBACK; SELECT 'unavailable' AS code; LEAVE operation;
    END IF;
    COMMIT;
    SELECT 'ok' AS code;
END//
CREATE TRIGGER frontier_trade_record_price AFTER UPDATE ON frontier_trade_requests
FOR EACH ROW
BEGIN
    IF NEW.state = 'open' AND (OLD.state = 'funding' OR NOT (OLD.quote_minor <=> NEW.quote_minor)) THEN
        INSERT INTO frontier_trade_price_history(request_id,market_id,item_id,price_minor)
        VALUES(NEW.id,NEW.market_id,NEW.item_id,COALESCE(NEW.quote_minor,NEW.price_minor));
    END IF;
END//
DELIMITER ;
