-- Use only with resources stopped and before new character accounts are provisioned.
DROP PROCEDURE IF EXISTS frontier_economy_rollback_owners;
DELIMITER //
CREATE PROCEDURE frontier_economy_rollback_owners()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    START TRANSACTION;
    IF NOT EXISTS (SELECT 1 FROM frontier_economy_identity_cutover WHERE id = 1)
       OR EXISTS (
           SELECT 1 FROM frontier_economy_accounts a
           LEFT JOIN frontier_economy_owner_upgrade m ON m.account_id = a.id AND m.new_owner_id = a.owner_id
           WHERE a.owner_type = 'character' AND m.account_id IS NULL
       ) OR EXISTS (
           SELECT 1 FROM frontier_economy_owner_upgrade m
           LEFT JOIN frontier_economy_accounts a
               ON a.id = m.account_id AND a.owner_type = 'character' AND a.owner_id = m.new_owner_id
           WHERE a.id IS NULL
       ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Rollback requires the original migrated account set and owner IDs';
    END IF;

    UPDATE frontier_economy_accounts a
    JOIN frontier_economy_owner_upgrade m ON m.account_id = a.id
    SET a.owner_id = m.old_owner_id;
    DELETE FROM frontier_economy_identity_cutover WHERE id = 1;
    DELETE FROM frontier_economy_owner_upgrade;
    COMMIT;
END//
DELIMITER ;
CALL frontier_economy_rollback_owners();
DROP PROCEDURE frontier_economy_rollback_owners;
