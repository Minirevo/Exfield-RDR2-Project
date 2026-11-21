-- With both Frontier resources stopped. Existing accounts came from VORP characters.
CREATE TABLE IF NOT EXISTS frontier_economy_identity_cutover (
    id TINYINT UNSIGNED NOT NULL PRIMARY KEY,
    completed_at DATETIME(6) NOT NULL,
    CONSTRAINT ck_frontier_economy_cutover CHECK (id = 1)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS frontier_economy_owner_upgrade (
    account_id BIGINT UNSIGNED NOT NULL PRIMARY KEY,
    old_owner_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    new_owner_id CHAR(34) CHARACTER SET ascii COLLATE ascii_bin NOT NULL
) ENGINE=InnoDB;

DROP PROCEDURE IF EXISTS frontier_economy_upgrade_owners;
DELIMITER //
CREATE PROCEDURE frontier_economy_upgrade_owners()
upgrade_owners: BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
    IF EXISTS (SELECT 1 FROM frontier_economy_identity_cutover WHERE id = 1) THEN
        COMMIT;
        LEAVE upgrade_owners;
    END IF;
    IF EXISTS (SELECT 1 FROM frontier_economy_owner_upgrade) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Existing owner audit entries without a cutover marker';
    END IF;

    IF EXISTS (
        SELECT 1 FROM frontier_economy_accounts a
        WHERE a.owner_type = 'character'
          AND (a.owner_id NOT REGEXP '^[1-9][0-9]*$'
            OR (SELECT COUNT(*) FROM characters c
                WHERE CAST(c.charidentifier AS CHAR CHARACTER SET ascii) COLLATE ascii_bin = a.owner_id) <> 1)
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Unresolved or ambiguous legacy Economy owner; see preflight query';
    END IF;

    -- Generate one identity per legacy character. Preserve identities already resolved by Core.
    INSERT INTO frontier_character_identities
        (id, provider, provider_character_id, account_identifier, created_at, updated_at)
    SELECT CONCAT('f_', REPLACE(UUID(), '-', '')), 'vorp', legacy.owner_id, NULLIF(c.identifier, ''),
           UTC_TIMESTAMP(6), UTC_TIMESTAMP(6)
    FROM (SELECT DISTINCT owner_id FROM frontier_economy_accounts WHERE owner_type = 'character') legacy
    JOIN characters c ON CAST(c.charidentifier AS CHAR CHARACTER SET ascii) COLLATE ascii_bin = legacy.owner_id
    ON DUPLICATE KEY UPDATE id = frontier_character_identities.id;

    IF EXISTS (
        SELECT 1 FROM frontier_economy_accounts a
        JOIN characters c ON CAST(c.charidentifier AS CHAR CHARACTER SET ascii) COLLATE ascii_bin = a.owner_id
        LEFT JOIN frontier_character_identities i ON i.provider = 'vorp' AND i.provider_character_id = a.owner_id
        WHERE a.owner_type = 'character'
          AND (i.id IS NULL OR (i.account_identifier IS NOT NULL
             AND NOT (BINARY i.account_identifier <=> BINARY NULLIF(c.identifier, ''))))
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Conflicting Frontier identity mapping or account identifier';
    END IF;

    INSERT INTO frontier_economy_owner_upgrade (account_id, old_owner_id, new_owner_id)
    SELECT a.id, a.owner_id, i.id
    FROM frontier_economy_accounts a
    JOIN frontier_character_identities i ON i.provider = 'vorp' AND i.provider_character_id = a.owner_id
    WHERE a.owner_type = 'character';

    IF (SELECT COUNT(*) FROM frontier_economy_owner_upgrade) <>
       (SELECT COUNT(*) FROM frontier_economy_accounts WHERE owner_type = 'character') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Incomplete Frontier Economy owner mapping';
    END IF;

    UPDATE frontier_economy_accounts a
    JOIN frontier_economy_owner_upgrade m ON m.account_id = a.id AND m.old_owner_id = a.owner_id
    SET a.owner_id = m.new_owner_id
    WHERE a.owner_type = 'character';

    INSERT INTO frontier_economy_identity_cutover (id, completed_at) VALUES (1, UTC_TIMESTAMP(6));
    COMMIT;
END//
DELIMITER ;
CALL frontier_economy_upgrade_owners();
DROP PROCEDURE frontier_economy_upgrade_owners;
