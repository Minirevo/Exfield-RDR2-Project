-- Frontier Property relational storage. Fresh installation; old prototype is not read automatically.
CREATE TABLE IF NOT EXISTS fp_meta (id TINYINT PRIMARY KEY, revision BIGINT UNSIGNED NOT NULL DEFAULT 0, next_bucket INT UNSIGNED NOT NULL);
INSERT IGNORE INTO fp_meta VALUES (1,0,1500000000);
CREATE TABLE IF NOT EXISTS fp_settlements (
 id CHAR(32) PRIMARY KEY, name VARCHAR(60) NOT NULL, x DOUBLE NOT NULL,y DOUBLE NOT NULL,z DOUBLE NOT NULL,
 radius INT UNSIGNED NOT NULL, primary_owner VARCHAR(64) NOT NULL, status VARCHAR(16) NOT NULL, map_public BOOLEAN NOT NULL DEFAULT FALSE,
 INDEX fp_location(status,x,y)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS fp_owners (
 settlement_id CHAR(32) NOT NULL,character_id VARCHAR(64) NOT NULL,
 PRIMARY KEY(settlement_id,character_id),INDEX(character_id),
 FOREIGN KEY(settlement_id) REFERENCES fp_settlements(id) ON DELETE CASCADE
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS fp_permissions (
 settlement_id CHAR(32) NOT NULL,character_id VARCHAR(64) NOT NULL,rights_json LONGTEXT NOT NULL CHECK(JSON_VALID(rights_json)),
 PRIMARY KEY(settlement_id,character_id),INDEX(character_id),
 FOREIGN KEY(settlement_id) REFERENCES fp_settlements(id) ON DELETE CASCADE
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS fp_camps (
 settlement_id CHAR(32) PRIMARY KEY, storage_id VARCHAR(48) NOT NULL UNIQUE,
 FOREIGN KEY(settlement_id) REFERENCES fp_settlements(id) ON DELETE CASCADE
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS fp_buildings (
 id CHAR(32) PRIMARY KEY,settlement_id CHAR(32) NOT NULL,exterior VARCHAR(48) NOT NULL,
 x DOUBLE NOT NULL,y DOUBLE NOT NULL,z DOUBLE NOT NULL,heading DOUBLE NOT NULL,radius DOUBLE NOT NULL,
 complete BOOLEAN NOT NULL,locked BOOLEAN NOT NULL,asset_value BIGINT UNSIGNED NOT NULL,
 INDEX(settlement_id),FOREIGN KEY(settlement_id) REFERENCES fp_settlements(id) ON DELETE CASCADE
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS fp_interiors (
 building_id CHAR(32) PRIMARY KEY,template_id VARCHAR(48) NOT NULL,routing_bucket INT UNSIGNED NOT NULL UNIQUE,capacity INT UNSIGNED NOT NULL,
 FOREIGN KEY(building_id) REFERENCES fp_buildings(id) ON DELETE CASCADE
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS fp_furniture (
 id CHAR(32) PRIMARY KEY,building_id CHAR(32) NOT NULL,item_id VARCHAR(48) NOT NULL,x DOUBLE NOT NULL,y DOUBLE NOT NULL,z DOUBLE NOT NULL,heading DOUBLE NOT NULL,
 INDEX(building_id),FOREIGN KEY(building_id) REFERENCES fp_interiors(building_id) ON DELETE CASCADE
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS fp_construction (
 building_id CHAR(32) PRIMARY KEY,stage_no INT UNSIGNED NOT NULL,progress_seconds INT UNSIGNED NOT NULL,
 FOREIGN KEY(building_id) REFERENCES fp_buildings(id) ON DELETE CASCADE
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS fp_stages (
 building_id CHAR(32) NOT NULL,stage_no INT UNSIGNED NOT NULL,label VARCHAR(80) NOT NULL,seconds INT UNSIGNED NOT NULL,tools_json LONGTEXT NOT NULL CHECK(JSON_VALID(tools_json)),
 PRIMARY KEY(building_id,stage_no),FOREIGN KEY(building_id) REFERENCES fp_construction(building_id) ON DELETE CASCADE
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS fp_materials (
 building_id CHAR(32) NOT NULL,stage_no INT UNSIGNED NOT NULL,item_id VARCHAR(48) NOT NULL,required_qty INT UNSIGNED NOT NULL,delivered_qty INT UNSIGNED NOT NULL,
 PRIMARY KEY(building_id,stage_no,item_id),FOREIGN KEY(building_id,stage_no) REFERENCES fp_stages(building_id,stage_no) ON DELETE CASCADE
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS fp_taxes (
 settlement_id CHAR(32) PRIMARY KEY,debt BIGINT UNSIGNED NOT NULL,next_tax BIGINT UNSIGNED NOT NULL,overdue BIGINT UNSIGNED NULL,
 FOREIGN KEY(settlement_id) REFERENCES fp_settlements(id) ON DELETE CASCADE
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS fp_listings (
 settlement_id CHAR(32) PRIMARY KEY,price BIGINT UNSIGNED NOT NULL,active BOOLEAN NOT NULL,
 FOREIGN KEY(settlement_id) REFERENCES fp_settlements(id) ON DELETE CASCADE,INDEX(active,price)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS fp_approvals (
 settlement_id CHAR(32) NOT NULL,character_id VARCHAR(64) NOT NULL,PRIMARY KEY(settlement_id,character_id),
 FOREIGN KEY(settlement_id) REFERENCES fp_listings(settlement_id) ON DELETE CASCADE
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS fp_operations (
 id CHAR(32) PRIMARY KEY,kind VARCHAR(32) NOT NULL,settlement_id CHAR(32) NULL,payload LONGTEXT NOT NULL CHECK(JSON_VALID(payload)), INDEX(settlement_id)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS fp_visits (
 character_id VARCHAR(64) PRIMARY KEY,settlement_id CHAR(32) NOT NULL,building_id CHAR(32) NOT NULL,x DOUBLE NOT NULL,y DOUBLE NOT NULL,z DOUBLE NOT NULL,
 INDEX(building_id)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS fp_history (
 id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,operation_id CHAR(32) NOT NULL UNIQUE,settlement_id CHAR(32) NULL,kind VARCHAR(32) NOT NULL,
 details LONGTEXT NOT NULL CHECK(JSON_VALID(details)),created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,INDEX(settlement_id,kind)
) ENGINE=InnoDB;
