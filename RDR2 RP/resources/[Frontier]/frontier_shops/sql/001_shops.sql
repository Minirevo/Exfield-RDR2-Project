CREATE TABLE IF NOT EXISTS `frontier_shops_orders` (
    `id` CHAR(36) PRIMARY KEY,
    `character_id` VARCHAR(64) NOT NULL,
    `shop` VARCHAR(48) NOT NULL,
    `mode` VARCHAR(8) NOT NULL,
    `state` VARCHAR(16) NOT NULL,
    `account` BIGINT UNSIGNED NOT NULL,
    `total` INT UNSIGNED NOT NULL,
    `lines` MEDIUMTEXT NOT NULL,
    `issue` VARCHAR(128) DEFAULT NULL,
    `receipt` VARCHAR(64) DEFAULT NULL,
    `created` BIGINT UNSIGNED NOT NULL,
    KEY `shop_worker` (`character_id`, `created`),
    KEY `shop_recovery` (`state`, `created`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
