CREATE TABLE IF NOT EXISTS frontier_trade_requests (
    id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    buyer_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    bank_id BIGINT UNSIGNED NOT NULL,
    market_id VARCHAR(48) NOT NULL,
    item_id VARCHAR(48) NOT NULL,
    quantity INT UNSIGNED NOT NULL,
    price_minor BIGINT UNSIGNED NOT NULL,
    budget_minor BIGINT UNSIGNED NOT NULL,
    state ENUM('funding','open','refund','closed','rejected') NOT NULL,
    expires_at DATETIME NOT NULL,
    retry_at DATETIME NOT NULL,
    attempts INT UNSIGNED NOT NULL DEFAULT 0,
    last_error VARCHAR(64) NULL,
    CHECK (quantity BETWEEN 1 AND 1000 AND price_minor BETWEEN 1 AND 10000
        AND budget_minor = quantity * price_minor),
    KEY ix_trade_job (state, retry_at, id),
    KEY ix_trade_expiry (state, expires_at, id),
    KEY ix_trade_market (market_id, state, expires_at, id),
    KEY ix_trade_buyer (buyer_id, state)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
