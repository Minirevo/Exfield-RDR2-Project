-- Additive source mapping for physical fulfillment. Existing delivery and escrow procedures remain unchanged.
CREATE TABLE IF NOT EXISTS ft_wagon_deliveries (
 delivery_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
 wagon_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 seller_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 destination_id CHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 KEY ix_wagon_delivery(wagon_id)
) ENGINE=InnoDB;
