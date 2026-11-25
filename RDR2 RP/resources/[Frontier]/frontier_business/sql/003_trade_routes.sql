-- Routes are retained for replay/audit even after a fixture or company is archived.
CREATE TABLE IF NOT EXISTS fb_trade_routes (
 reference_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
 company_id CHAR(32) NOT NULL,
 fixture_id CHAR(32) NOT NULL,
 created BIGINT UNSIGNED NOT NULL,
 PRIMARY KEY(reference_id,company_id),
 INDEX(fixture_id),
 FOREIGN KEY(company_id) REFERENCES fb_companies(id)
) ENGINE=InnoDB;
