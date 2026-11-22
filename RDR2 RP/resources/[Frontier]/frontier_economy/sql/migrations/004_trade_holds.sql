-- Use a persistent Economy procedure definer with INSERT/UPDATE on Economy accounts.
DROP PROCEDURE IF EXISTS frontier_economy_provision_trade_hold;
DELIMITER //
CREATE PROCEDURE frontier_economy_provision_trade_hold(
    IN p_reference CHAR(36) CHARACTER SET ascii COLLATE ascii_bin
)
SQL SECURITY DEFINER
BEGIN
    IF p_reference IS NULL OR p_reference NOT REGEXP '^[a-f0-9-]{36}$' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid trade hold reference';
    END IF;
    INSERT INTO frontier_economy_accounts (owner_type, owner_id, account_type, currency)
    VALUES ('trade_hold', p_reference, 'escrow', 'USD') ON DUPLICATE KEY UPDATE id = id;
END//
DELIMITER ;
