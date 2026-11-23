CREATE TABLE IF NOT EXISTS frontier_property_names (
    property_id BIGINT UNSIGNED PRIMARY KEY,
    display_name VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    UNIQUE KEY uq_frontier_display_name (display_name),
    FOREIGN KEY (property_id) REFERENCES frontier_properties(id)
) ENGINE=InnoDB;

ALTER TABLE frontier_property_permissions
    MODIFY COLUMN permission_key ENUM('enter','furnish','use_facility','construct','manage_access','furnish_move','furnish_remove') NOT NULL;

DELIMITER $
CREATE OR REPLACE PROCEDURE frontier_property_manage_v1(
    IN target BIGINT UNSIGNED, IN owner CHAR(34), IN action_key VARCHAR(16),
    IN new_label VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
    IN grantee CHAR(34), IN capability VARCHAR(32), IN allowed BOOLEAN
)
manage: BEGIN
    DECLARE estate BIGINT UNSIGNED DEFAULT NULL;
    DECLARE changed BOOLEAN DEFAULT FALSE;
    DECLARE duplicate_name BOOLEAN DEFAULT FALSE;
    DECLARE EXIT HANDLER FOR 1062 BEGIN ROLLBACK; SELECT 'duplicate_name' AS result; END;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT id INTO estate FROM frontier_properties WHERE id=target AND status='active' FOR UPDATE;
    IF estate IS NOT NULL AND EXISTS (
        SELECT 1 FROM frontier_property_ownership WHERE property_id=target
        AND party_type='character' AND party_id=owner
    ) AND NOT EXISTS (
        SELECT 1 FROM frontier_property_sales WHERE property_id=target AND state='reserved'
    ) THEN
        IF action_key='rename' AND CHAR_LENGTH(TRIM(new_label)) BETWEEN 3 AND 64 THEN
            SET duplicate_name=EXISTS(SELECT 1 FROM frontier_properties WHERE id<>target
                AND label COLLATE utf8mb4_unicode_ci=TRIM(new_label));
            IF NOT duplicate_name THEN
                DELETE FROM frontier_property_names WHERE property_id=target;
                INSERT INTO frontier_property_names (property_id,display_name) VALUES (target,TRIM(new_label));
                UPDATE frontier_properties SET label=TRIM(new_label) WHERE id=target;
                SET changed=TRUE;
            END IF;
        ELSEIF action_key='permission' AND capability IN ('enter','construct','furnish','use_facility','furnish_move','furnish_remove')
            AND grantee<>owner AND allowed IN (0,1)
            AND EXISTS (SELECT 1 FROM frontier_character_identities WHERE id=grantee)
            AND NOT EXISTS (SELECT 1 FROM frontier_property_ownership WHERE property_id=target
                AND party_type='character' AND party_id=grantee) THEN
            INSERT INTO frontier_property_permissions (property_id,character_id,permission_key,allow_access)
                VALUES (target,grantee,capability,allowed)
                ON DUPLICATE KEY UPDATE allow_access=VALUES(allow_access);
            SET changed=TRUE;
        ELSEIF action_key='unlist' THEN
            DELETE FROM frontier_property_private_offers WHERE property_id=target AND landlord_id=owner;
            SET changed=ROW_COUNT()=1;
        END IF;
    END IF;
    COMMIT;
    SELECT CASE WHEN changed THEN 'ok' WHEN duplicate_name THEN 'duplicate_name' ELSE 'denied' END AS result;
END$$

-- Existing contracts continue to run. Only new state-funded reservations are forbidden.
CREATE OR REPLACE TRIGGER frontier_property_private_rent_only BEFORE INSERT ON frontier_property_rentals
FOR EACH ROW
BEGIN
    IF NEW.landlord_bank_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='New government rentals are disabled';
    END IF;
END$$
DELIMITER ;
