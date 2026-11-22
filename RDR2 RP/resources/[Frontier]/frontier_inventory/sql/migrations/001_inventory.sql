CREATE TABLE IF NOT EXISTS frontier_inventory_items (
    id VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    owner_resource VARCHAR(96) NOT NULL,
    definition TEXT NOT NULL,
    grams INT UNSIGNED NOT NULL,
    max_stack INT UNSIGNED NOT NULL,
    CONSTRAINT ck_fi_definition CHECK (JSON_VALID(definition)),
    CONSTRAINT ck_fi_item_limits CHECK (grams BETWEEN 1 AND 1000000 AND max_stack BETWEEN 1 AND 10000)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS frontier_inventory_containers (
    id VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    kind ENUM('player','storage','ground') NOT NULL,
    slot_limit SMALLINT UNSIGNED NOT NULL,
    weight_limit INT UNSIGNED NOT NULL,
    revision INT UNSIGNED NOT NULL DEFAULT 0,
    label VARCHAR(100) NULL,
    access_ace VARCHAR(128) NULL,
    x DOUBLE NULL, y DOUBLE NULL, z DOUBLE NULL,
    bucket INT UNSIGNED NULL,
    distance_limit DOUBLE NULL,
    expires_at DATETIME NULL,
    KEY ix_fi_ground (kind, bucket, expires_at),
    CONSTRAINT ck_fi_container_limits CHECK (slot_limit BETWEEN 1 AND 200 AND weight_limit BETWEEN 1 AND 100000000)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS frontier_inventory_slots (
    container_id VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    slot SMALLINT UNSIGNED NOT NULL,
    item_id VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    quantity INT UNSIGNED NOT NULL,
    metadata TEXT NOT NULL,
    instance_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
    PRIMARY KEY (container_id, slot),
    UNIQUE KEY uq_fi_instance (instance_id),
    CONSTRAINT fk_fi_container FOREIGN KEY (container_id) REFERENCES frontier_inventory_containers(id) ON DELETE CASCADE,
    CONSTRAINT fk_fi_item FOREIGN KEY (item_id) REFERENCES frontier_inventory_items(id),
    CONSTRAINT ck_fi_slot CHECK (slot BETWEEN 1 AND 200 AND quantity BETWEEN 1 AND 10000 AND OCTET_LENGTH(metadata) <= 8192 AND JSON_VALID(metadata))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS frontier_inventory_receipts (
    request_key VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    actor VARCHAR(100) NOT NULL,
    fingerprint TEXT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed BOOLEAN NOT NULL DEFAULT FALSE,
    KEY ix_fi_receipt_age (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP PROCEDURE IF EXISTS frontier_inventory_commit_v1;
DELIMITER //
CREATE PROCEDURE frontier_inventory_commit_v1(
    IN p_key VARCHAR(80), IN p_actor VARCHAR(100), IN p_fingerprint TEXT, IN p_changes MEDIUMTEXT
)
SQL SECURITY INVOKER
commit_request: BEGIN
    DECLARE v_actor VARCHAR(100);
    DECLARE v_fingerprint TEXT;
    DECLARE v_completed BOOLEAN;
    DECLARE v_i INT DEFAULT 0;
    DECLARE v_count INT;
    DECLARE v_id VARCHAR(80);
    DECLARE v_previous VARCHAR(80) DEFAULT '';
    DECLARE v_revision INT UNSIGNED;
    DECLARE v_slots INT UNSIGNED;
    DECLARE v_weight INT UNSIGNED;
    DECLARE v_entries MEDIUMTEXT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

    SET v_count = JSON_LENGTH(p_changes);
    IF v_count IS NULL OR v_count NOT BETWEEN 1 AND 2 THEN
        SELECT 'invalid_request' AS code;
        LEAVE commit_request;
    END IF;

    START TRANSACTION;
    INSERT INTO frontier_inventory_receipts (request_key, actor, fingerprint)
    VALUES (p_key, p_actor, p_fingerprint) ON DUPLICATE KEY UPDATE request_key = request_key;
    SELECT actor, fingerprint, completed INTO v_actor, v_fingerprint, v_completed FROM frontier_inventory_receipts
        WHERE request_key = p_key FOR UPDATE;
    IF BINARY v_actor <> BINARY p_actor OR BINARY v_fingerprint <> BINARY p_fingerprint THEN
        ROLLBACK;
        SELECT 'request_conflict' AS code;
        LEAVE commit_request;
    END IF;
    IF v_completed THEN
        COMMIT;
        SELECT 'ok' AS code, 1 AS replayed;
        LEAVE commit_request;
    END IF;

    WHILE v_i < v_count DO
        SET v_id = JSON_UNQUOTE(JSON_EXTRACT(p_changes, CONCAT('$[', v_i, '].id')));
        IF BINARY v_id <= BINARY v_previous THEN
            ROLLBACK;
            SELECT 'invalid_request' AS code;
            LEAVE commit_request;
        END IF;
        SET v_previous = v_id;
        SET v_revision = NULL;
        SELECT revision, slot_limit, weight_limit INTO v_revision, v_slots, v_weight
        FROM frontier_inventory_containers
        WHERE id = v_id AND (expires_at IS NULL OR expires_at > UTC_TIMESTAMP()) FOR UPDATE;
        IF v_revision IS NULL OR v_revision <> JSON_EXTRACT(p_changes, CONCAT('$[', v_i, '].revision')) THEN
            ROLLBACK;
            SELECT 'conflict' AS code;
            LEAVE commit_request;
        END IF;
        DELETE FROM frontier_inventory_slots WHERE container_id = v_id;
        SET v_i = v_i + 1;
    END WHILE;

    SET v_i = 0;
    WHILE v_i < v_count DO
        SET v_id = JSON_UNQUOTE(JSON_EXTRACT(p_changes, CONCAT('$[', v_i, '].id')));
        SET v_entries = JSON_EXTRACT(p_changes, CONCAT('$[', v_i, '].entries'));
        IF JSON_TYPE(v_entries) = 'OBJECT' AND JSON_LENGTH(v_entries) = 0 THEN SET v_entries = '[]'; END IF;
        SELECT slot_limit, weight_limit INTO v_slots, v_weight FROM frontier_inventory_containers WHERE id = v_id;
        INSERT INTO frontier_inventory_slots (container_id, slot, item_id, quantity, metadata, instance_id)
        SELECT v_id, j.slot, j.item, j.quantity, j.metadata, NULLIF(j.instance, '')
        FROM JSON_TABLE(v_entries, '$[*]' COLUMNS (
            slot INT PATH '$.slot', item VARCHAR(48) PATH '$.item', quantity INT PATH '$.quantity',
            metadata VARCHAR(8192) PATH '$.metadata', instance VARCHAR(36) PATH '$.instance'
        )) j;
        IF EXISTS (
            SELECT 1 FROM frontier_inventory_slots s JOIN frontier_inventory_items i ON i.id = s.item_id
            WHERE s.container_id = v_id AND (s.slot > v_slots OR s.quantity > i.max_stack
                OR (i.max_stack = 1 AND s.instance_id IS NULL) OR (i.max_stack > 1 AND s.instance_id IS NOT NULL))
        ) OR (SELECT COALESCE(SUM(s.quantity * i.grams), 0)
            FROM frontier_inventory_slots s JOIN frontier_inventory_items i ON i.id = s.item_id
            WHERE s.container_id = v_id) > v_weight THEN
            ROLLBACK;
            SELECT 'capacity' AS code;
            LEAVE commit_request;
        END IF;
        IF JSON_LENGTH(v_entries) = 0 AND EXISTS (
            SELECT 1 FROM frontier_inventory_containers WHERE id = v_id AND kind = 'ground'
        ) THEN
            DELETE FROM frontier_inventory_containers WHERE id = v_id;
        ELSE
            UPDATE frontier_inventory_containers SET revision = revision + 1 WHERE id = v_id;
        END IF;
        SET v_i = v_i + 1;
    END WHILE;
    UPDATE frontier_inventory_receipts SET completed = TRUE WHERE request_key = p_key;
    COMMIT;
    SELECT 'ok' AS code, 0 AS replayed;
END//
DELIMITER ;
