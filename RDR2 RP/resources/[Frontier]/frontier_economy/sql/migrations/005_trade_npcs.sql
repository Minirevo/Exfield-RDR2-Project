DROP PROCEDURE IF EXISTS frontier_economy_provision_trade_npc;
DELIMITER //
CREATE PROCEDURE frontier_economy_provision_trade_npc(IN p_owner VARCHAR(48))
SQL SECURITY DEFINER
BEGIN
    IF p_owner IS NULL OR p_owner NOT REGEXP '^npc_[a-z0-9_]+$' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Invalid NPC owner';
    END IF;
    INSERT INTO frontier_economy_accounts(owner_type,owner_id,account_type,currency)
    VALUES('trade_npc',p_owner,'bank','USD') ON DUPLICATE KEY UPDATE id=id;
END//
DELIMITER ;
