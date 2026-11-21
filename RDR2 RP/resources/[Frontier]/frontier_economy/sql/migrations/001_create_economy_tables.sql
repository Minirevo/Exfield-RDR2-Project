-- Apply to the RedM schema with a migration account. MySQL 8.0.16+ or MariaDB 10.6+.
CREATE TABLE IF NOT EXISTS frontier_economy_accounts (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    owner_type VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    owner_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_type VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    currency CHAR(3) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'USD',
    balance_minor BIGINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    UNIQUE KEY uq_frontier_economy_owner_account (owner_type, owner_id, account_type, currency),
    CONSTRAINT ck_frontier_economy_balance CHECK (balance_minor <= 9000000000000),
    CONSTRAINT ck_frontier_economy_currency CHECK (currency = 'USD')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS frontier_economy_operations (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    actor VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    request_key VARCHAR(96) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    fingerprint BINARY(32) NOT NULL,
    kind ENUM('credit', 'debit', 'transfer') NOT NULL,
    reason VARCHAR(255) NOT NULL,
    reference_text VARCHAR(128) NOT NULL,
    metadata_json TEXT NOT NULL,
    completed BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (id),
    UNIQUE KEY uq_frontier_economy_request (actor, request_key),
    CONSTRAINT ck_frontier_economy_metadata CHECK (JSON_VALID(metadata_json))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS frontier_economy_ledger (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    operation_id BIGINT UNSIGNED NOT NULL,
    account_id BIGINT UNSIGNED NOT NULL,
    related_account_id BIGINT UNSIGNED NULL,
    entry_type ENUM('credit', 'debit') NOT NULL,
    amount_minor BIGINT UNSIGNED NOT NULL,
    currency CHAR(3) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    balance_before BIGINT UNSIGNED NOT NULL,
    balance_after BIGINT UNSIGNED NOT NULL,
    created_at DATETIME(6) NOT NULL,
    PRIMARY KEY (id),
    KEY ix_frontier_economy_history (account_id, id),
    UNIQUE KEY uq_frontier_economy_entry (operation_id, account_id),
    CONSTRAINT fk_frontier_economy_operation FOREIGN KEY (operation_id) REFERENCES frontier_economy_operations (id),
    CONSTRAINT fk_frontier_economy_account FOREIGN KEY (account_id) REFERENCES frontier_economy_accounts (id),
    CONSTRAINT fk_frontier_economy_related FOREIGN KEY (related_account_id) REFERENCES frontier_economy_accounts (id),
    CONSTRAINT ck_frontier_economy_entry CHECK (
        amount_minor BETWEEN 1 AND 9000000000000
        AND balance_before <= 9000000000000 AND balance_after <= 9000000000000
        AND ((entry_type = 'credit' AND balance_after = balance_before + amount_minor)
          OR (entry_type = 'debit' AND balance_before = balance_after + amount_minor))
        AND currency = 'USD'
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
