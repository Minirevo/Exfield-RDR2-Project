-- Apply with the server stopped. Use a permanent definer with access to the Economy tables.
DROP PROCEDURE IF EXISTS frontier_economy_apply_v1;
DROP PROCEDURE IF EXISTS frontier_economy_provision_v1;
DELIMITER //
CREATE PROCEDURE frontier_economy_apply_v1 (
    IN p_actor VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin,
    IN p_key VARCHAR(96) CHARACTER SET ascii COLLATE ascii_bin,
    IN p_kind VARCHAR(8) CHARACTER SET ascii COLLATE ascii_bin,
    IN p_debit BIGINT UNSIGNED,
    IN p_credit BIGINT UNSIGNED,
    IN p_amount BIGINT UNSIGNED,
    IN p_reason VARCHAR(255) CHARACTER SET utf8mb4,
    IN p_reference VARCHAR(128) CHARACTER SET utf8mb4,
    IN p_metadata TEXT CHARACTER SET utf8mb4,
    IN p_currency CHAR(3) CHARACTER SET ascii COLLATE ascii_bin
)
SQL SECURITY DEFINER
apply_request: BEGIN
    DECLARE v_id BIGINT UNSIGNED;
    DECLARE v_hash BINARY(32);
    DECLARE v_existing_hash BINARY(32);
    DECLARE v_completed BOOLEAN;
    DECLARE v_first_id BIGINT UNSIGNED;
    DECLARE v_second_id BIGINT UNSIGNED;
    DECLARE v_first_balance BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_second_balance BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_debit_balance BIGINT UNSIGNED;
    DECLARE v_credit_balance BIGINT UNSIGNED;
    DECLARE v_time DATETIME(6);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_amount IS NULL OR p_amount < 1 OR p_amount > 9000000000000 THEN
        SELECT 'invalid_amount' AS code;
        LEAVE apply_request;
    END IF;
    IF p_currency IS NULL OR p_currency <> 'USD'
        OR p_kind IS NULL OR p_debit IS NULL OR p_credit IS NULL
        OR NOT ((p_kind = 'credit' AND p_debit = 0 AND p_credit > 0)
            OR (p_kind = 'debit' AND p_debit > 0 AND p_credit = 0)
            OR (p_kind = 'transfer' AND p_debit > 0 AND p_credit > 0 AND p_debit <> p_credit)) THEN
        SELECT 'invalid_account' AS code;
        LEAVE apply_request;
    END IF;
    IF p_metadata IS NULL OR OCTET_LENGTH(p_metadata) > 4096 OR NOT JSON_VALID(p_metadata) THEN
        SELECT 'invalid_metadata' AS code;
        LEAVE apply_request;
    END IF;

    -- Length-prefix free text so concatenated fields cannot collide across boundaries.
    SET v_hash = UNHEX(SHA2(CONCAT(p_kind, ':', p_debit, ':', p_credit, ':', p_amount, ':',
        OCTET_LENGTH(p_reason), ':', p_reason, OCTET_LENGTH(p_reference), ':', p_reference,
        OCTET_LENGTH(p_metadata), ':', p_metadata, p_currency), 256));

    START TRANSACTION;

    -- Claim the idempotency key before locking accounts. A concurrent replay waits
    -- for this transaction to commit or roll back.
    INSERT INTO frontier_economy_operations (actor, request_key, fingerprint, kind, reason, reference_text, metadata_json)
    VALUES (p_actor, p_key, v_hash, p_kind, p_reason, p_reference, p_metadata)
    ON DUPLICATE KEY UPDATE id = id;

    SELECT id, fingerprint, completed INTO v_id, v_existing_hash, v_completed
    FROM frontier_economy_operations
    WHERE actor = p_actor AND request_key = p_key
    FOR UPDATE;

    IF v_existing_hash <> v_hash THEN
        ROLLBACK;
        SELECT 'idempotency_conflict' AS code;
        LEAVE apply_request;
    END IF;
    IF v_completed THEN
        COMMIT;
        SELECT 'ok' AS code, CAST(v_id AS CHAR) AS operation_id, 1 AS replayed;
        LEAVE apply_request;
    END IF;

    -- Always acquire row locks in account ID order, even for opposing transfers.
    SET v_first_id = IF(p_debit = 0 OR p_credit = 0, GREATEST(p_debit, p_credit), LEAST(p_debit, p_credit));
    SET v_second_id = IF(p_kind = 'transfer', GREATEST(p_debit, p_credit), 0);
    SELECT balance_minor INTO v_first_balance
    FROM frontier_economy_accounts WHERE id = v_first_id AND currency = p_currency FOR UPDATE;

    IF v_second_id <> 0 THEN
        SELECT balance_minor INTO v_second_balance
        FROM frontier_economy_accounts WHERE id = v_second_id AND currency = p_currency FOR UPDATE;
    END IF;
    IF v_first_balance IS NULL OR (v_second_id <> 0 AND v_second_balance IS NULL) THEN
        ROLLBACK;
        SELECT 'account_not_found' AS code;
        LEAVE apply_request;
    END IF;

    SET v_debit_balance = IF(p_debit = v_first_id, v_first_balance, v_second_balance);
    SET v_credit_balance = IF(p_credit = v_first_id, v_first_balance, v_second_balance);
    IF p_debit <> 0 AND v_debit_balance < p_amount THEN
        ROLLBACK;
        SELECT 'insufficient_funds' AS code;
        LEAVE apply_request;
    END IF;
    IF p_credit <> 0 AND v_credit_balance > 9000000000000 - p_amount THEN
        ROLLBACK;
        SELECT 'balance_limit' AS code;
        LEAVE apply_request;
    END IF;

    SET v_time = UTC_TIMESTAMP(6);
    IF p_debit <> 0 THEN
        UPDATE frontier_economy_accounts SET balance_minor = v_debit_balance - p_amount WHERE id = p_debit;
        INSERT INTO frontier_economy_ledger (
            operation_id, account_id, related_account_id, entry_type, amount_minor,
            currency, balance_before, balance_after, created_at
        ) VALUES (
            v_id, p_debit, NULLIF(p_credit, 0), 'debit', p_amount,
            p_currency, v_debit_balance, v_debit_balance - p_amount, v_time
        );
    END IF;
    IF p_credit <> 0 THEN
        UPDATE frontier_economy_accounts SET balance_minor = v_credit_balance + p_amount WHERE id = p_credit;
        INSERT INTO frontier_economy_ledger (
            operation_id, account_id, related_account_id, entry_type, amount_minor,
            currency, balance_before, balance_after, created_at
        ) VALUES (
            v_id, p_credit, NULLIF(p_debit, 0), 'credit', p_amount,
            p_currency, v_credit_balance, v_credit_balance + p_amount, v_time
        );
    END IF;

    UPDATE frontier_economy_operations SET completed = TRUE WHERE id = v_id;
    COMMIT;
    SELECT 'ok' AS code, CAST(v_id AS CHAR) AS operation_id, 0 AS replayed;
END//

CREATE PROCEDURE frontier_economy_provision_v1 (
    IN p_character VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin
)
SQL SECURITY DEFINER
BEGIN
    IF p_character IS NULL OR p_character NOT REGEXP '^[A-Za-z0-9_-]+
 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid Frontier character identifier';
    END IF;

    INSERT INTO frontier_economy_accounts (owner_type, owner_id, account_type)
    VALUES ('character', p_character, 'cash'), ('character', p_character, 'bank')
    ON DUPLICATE KEY UPDATE id = id;
END//
DELIMITER ;
