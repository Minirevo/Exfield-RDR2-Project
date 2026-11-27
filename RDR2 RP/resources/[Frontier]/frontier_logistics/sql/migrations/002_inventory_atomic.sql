-- Separate logistics-only routine. Existing inventory_commit_v1 remains unchanged.
DELIMITER //
DROP PROCEDURE IF EXISTS frontier_inventory_logistics_commit_v1//
CREATE PROCEDURE frontier_inventory_logistics_commit_v1(
    IN p_key VARCHAR(80),
    IN p_actor VARCHAR(100),
    IN p_fingerprint TEXT,
    IN p_changes MEDIUMTEXT
)
SQL SECURITY INVOKER

commit_request: BEGIN

    DECLARE v_actor VARCHAR(100);
    DECLARE v_fingerprint TEXT;
    DECLARE v_completed BOOLEAN;

    DECLARE v_i INT DEFAULT 0;
    DECLARE v_j INT DEFAULT 0;

    DECLARE v_count INT;
    DECLARE v_entry_count INT;

    DECLARE v_id VARCHAR(80);
    DECLARE v_previous VARCHAR(80) DEFAULT '';

    DECLARE v_revision INT UNSIGNED;
    DECLARE v_slots INT UNSIGNED;
    DECLARE v_weight INT UNSIGNED;

    DECLARE v_entries MEDIUMTEXT;
    DECLARE v_entry MEDIUMTEXT;

    DECLARE v_slot INT;
    DECLARE v_item VARCHAR(48);
    DECLARE v_quantity INT;
    DECLARE v_metadata MEDIUMTEXT;
    DECLARE v_metadata_json MEDIUMTEXT;
    DECLARE v_instance VARCHAR(36);

    DECLARE v_item_grams INT UNSIGNED;
    DECLARE v_item_max_stack INT UNSIGNED;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;


    /* Validate request JSON */
    IF p_key IS NULL OR p_actor IS NULL OR p_fingerprint IS NULL
       OR p_changes IS NULL
       OR JSON_VALID(p_changes) = 0
       OR JSON_TYPE(p_changes) <> 'ARRAY' THEN

        SELECT 'invalid_request' AS code;
        LEAVE commit_request;
    END IF;


    SET v_count = JSON_LENGTH(p_changes);

    IF v_count IS NULL OR v_count NOT BETWEEN 1 AND 16 THEN
        SELECT 'invalid_request' AS code;
        LEAVE commit_request;
    END IF;


    START TRANSACTION;


    /* Create or lock idempotency receipt */
    INSERT INTO frontier_inventory_receipts (
        request_key,
        actor,
        fingerprint
    )
    VALUES (
        p_key,
        p_actor,
        p_fingerprint
    )
    ON DUPLICATE KEY UPDATE request_key = request_key;


    SELECT actor, fingerprint, completed
    INTO v_actor, v_fingerprint, v_completed
    FROM frontier_inventory_receipts
    WHERE request_key = p_key
    FOR UPDATE;


    /* Prevent reusing a request key for another operation */
    IF BINARY v_actor <> BINARY p_actor
       OR BINARY v_fingerprint <> BINARY p_fingerprint THEN

        ROLLBACK;
        SELECT 'request_conflict' AS code;
        LEAVE commit_request;
    END IF;


    /* Return successful replay */
    IF v_completed THEN
        COMMIT;
        SELECT 'ok' AS code, 1 AS replayed;
        LEAVE commit_request;
    END IF;


    /* Lock containers in sorted order and validate revisions */
    SET v_i = 0;
    SET v_previous = '';

    WHILE v_i < v_count DO

        SET v_id = JSON_UNQUOTE(
            JSON_EXTRACT(p_changes, CONCAT('$[', v_i, '].id'))
        );

        IF v_id IS NULL OR BINARY v_id <= BINARY v_previous THEN
            ROLLBACK;
            SELECT 'invalid_request' AS code;
            LEAVE commit_request;
        END IF;

        SET v_previous = v_id;
        SET v_revision = NULL;

        SELECT revision, slot_limit, weight_limit
        INTO v_revision, v_slots, v_weight
        FROM frontier_inventory_containers
        WHERE id = v_id
          AND (expires_at IS NULL OR expires_at > UTC_TIMESTAMP())
        FOR UPDATE;


        IF v_revision IS NULL
           OR v_revision <> JSON_EXTRACT(
               p_changes,
               CONCAT('$[', v_i, '].revision')
           ) THEN

            ROLLBACK;
            SELECT 'conflict' AS code;
            LEAVE commit_request;
        END IF;


        DELETE FROM frontier_inventory_slots
        WHERE container_id = v_id;

        SET v_i = v_i + 1;

    END WHILE;


    /* Rebuild each container's slots */
    SET v_i = 0;

    WHILE v_i < v_count DO

        SET v_id = JSON_UNQUOTE(
            JSON_EXTRACT(p_changes, CONCAT('$[', v_i, '].id'))
        );

        SET v_entries = JSON_EXTRACT(
            p_changes,
            CONCAT('$[', v_i, '].entries')
        );


        /* Empty object is accepted as an empty inventory */
        IF JSON_TYPE(v_entries) = 'OBJECT'
           AND JSON_LENGTH(v_entries) = 0 THEN

            SET v_entries = '[]';

        END IF;


        /* Entries must be an array */
        IF v_entries IS NULL
           OR JSON_TYPE(v_entries) <> 'ARRAY'
           OR JSON_VALID(v_entries) = 0 THEN

            ROLLBACK;
            SELECT 'invalid_request' AS code;
            LEAVE commit_request;
        END IF;


        SELECT slot_limit, weight_limit
        INTO v_slots, v_weight
        FROM frontier_inventory_containers
        WHERE id = v_id;


        SET v_entry_count = JSON_LENGTH(v_entries);
        SET v_j = 0;


        /* Validate and insert each slot */
        WHILE v_j < v_entry_count DO

            SET v_entry = JSON_EXTRACT(
                v_entries,
                CONCAT('$[', v_j, ']')
            );


            SET v_slot = JSON_EXTRACT(v_entry, '$.slot');

            SET v_item = JSON_UNQUOTE(
                JSON_EXTRACT(v_entry, '$.item')
            );

            SET v_quantity = JSON_EXTRACT(
                v_entry,
                '$.quantity'
            );

            SET v_metadata_json = JSON_EXTRACT(
                v_entry,
                '$.metadata'
            );

            SET v_instance = JSON_UNQUOTE(
                JSON_EXTRACT(v_entry, '$.instance')
            );


            /* Default metadata */
            IF v_metadata_json IS NULL THEN

                SET v_metadata = '{}';

            ELSEIF JSON_TYPE(v_metadata_json) = 'STRING' THEN

                SET v_metadata = JSON_UNQUOTE(v_metadata_json);

            ELSE

                SET v_metadata = v_metadata_json;

            END IF;


            /* Basic entry validation */
            IF JSON_TYPE(v_entry) <> 'OBJECT'
               OR v_slot IS NULL
               OR v_slot < 1
               OR v_slot > v_slots
               OR v_item IS NULL
               OR v_quantity IS NULL
               OR v_quantity < 1
               OR v_quantity > 10000
               OR v_metadata IS NULL
               OR JSON_VALID(v_metadata) = 0
               OR OCTET_LENGTH(v_metadata) > 8192 THEN

                ROLLBACK;
                SELECT 'invalid_request' AS code;
                LEAVE commit_request;
            END IF;


            /* Check item definition */
            SET v_item_grams = NULL;

            SELECT grams, max_stack
            INTO v_item_grams, v_item_max_stack
            FROM frontier_inventory_items
            WHERE id = v_item;


            IF v_item_grams IS NULL THEN

                ROLLBACK;
                SELECT 'invalid_item' AS code;
                LEAVE commit_request;
            END IF;


            /* Validate stack and instance rules */
            IF v_quantity > v_item_max_stack
               OR (v_item_max_stack = 1 AND v_instance IS NULL)
               OR (v_item_max_stack > 1 AND v_instance IS NOT NULL) THEN

                ROLLBACK;
                SELECT 'invalid_request' AS code;
                LEAVE commit_request;
            END IF;


            /* Insert the slot */
            INSERT INTO frontier_inventory_slots (
                container_id,
                slot,
                item_id,
                quantity,
                metadata,
                instance_id
            )
            VALUES (
                v_id,
                v_slot,
                v_item,
                v_quantity,
                v_metadata,
                NULLIF(v_instance, '')
            );


            SET v_j = v_j + 1;

        END WHILE;


        /* Capacity validation */
        IF (
            SELECT COUNT(*)
            FROM frontier_inventory_slots
            WHERE container_id = v_id
        ) > v_slots

        OR (
            SELECT COALESCE(SUM(s.quantity * i.grams), 0)
            FROM frontier_inventory_slots s
            JOIN frontier_inventory_items i
              ON i.id = s.item_id
            WHERE s.container_id = v_id
        ) > v_weight THEN

            ROLLBACK;
            SELECT 'capacity' AS code;
            LEAVE commit_request;
        END IF;


        /* Delete empty ground drops */
        IF v_entry_count = 0
           AND EXISTS (
               SELECT 1
               FROM frontier_inventory_containers
               WHERE id = v_id
                 AND kind = 'ground'
           ) THEN

            DELETE FROM frontier_inventory_containers
            WHERE id = v_id;

        ELSE

            UPDATE frontier_inventory_containers
            SET revision = revision + 1
            WHERE id = v_id;

        END IF;


        SET v_i = v_i + 1;

    END WHILE;


    /* Mark request complete */
    UPDATE frontier_inventory_receipts
    SET completed = TRUE
    WHERE request_key = p_key;


    COMMIT;


    SELECT 'ok' AS code, 0 AS replayed;

END//

DELIMITER ;
