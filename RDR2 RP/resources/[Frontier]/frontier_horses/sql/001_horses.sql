CREATE TABLE IF NOT EXISTS `frontier_horses` (
 `id` VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 `owner_type` VARCHAR(16) NOT NULL,
 `owner_id` VARCHAR(64) NOT NULL,
 `stable` VARCHAR(32) NOT NULL,
 `status` VARCHAR(16) NOT NULL DEFAULT 'stored',
 `model` VARCHAR(80) NOT NULL,
 `name` VARCHAR(64) NOT NULL,
 `record` LONGTEXT NOT NULL,
 `updated` BIGINT UNSIGNED NOT NULL,
 KEY `horse_owner` (`owner_type`,`owner_id`),
 KEY `horse_stable` (`stable`,`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS `frontier_horse_orders` (
 `id` CHAR(36) PRIMARY KEY,
 `actor` VARCHAR(64) NOT NULL,
 `kind` VARCHAR(16) NOT NULL,
 `state` VARCHAR(16) NOT NULL,
 `account` BIGINT UNSIGNED NOT NULL DEFAULT 0,
 `amount` INT UNSIGNED NOT NULL DEFAULT 0,
 `payload` LONGTEXT NOT NULL,
 `created` BIGINT UNSIGNED NOT NULL,
 KEY `horse_order_state` (`state`,`created`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
-- Run after Logistics 001; preserves all existing numeric VORP horse assignments.
ALTER TABLE `fl_harnesses` MODIFY COLUMN `horse_id` VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL;
