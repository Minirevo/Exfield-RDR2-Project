CREATE TABLE IF NOT EXISTS frontier_property_catalogue (
    catalogue_key VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    property_id BIGINT UNSIGNED NULL UNIQUE,
    FOREIGN KEY (property_id) REFERENCES frontier_properties(id)
) ENGINE=InnoDB;

DELIMITER $$
CREATE OR REPLACE PROCEDURE frontier_property_seed_v1(
    IN code VARCHAR(48), IN title VARCHAR(120), IN interior VARCHAR(64),
    IN px DOUBLE, IN py DOUBLE, IN pz DOUBLE, IN valuation BIGINT UNSIGNED
)
BEGIN
    DECLARE selected BIGINT UNSIGNED DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    INSERT IGNORE INTO frontier_property_catalogue (catalogue_key) VALUES (code);
    SELECT property_id INTO selected FROM frontier_property_catalogue WHERE catalogue_key=code FOR UPDATE;
    IF selected IS NULL AND NOT EXISTS (
        SELECT 1 FROM frontier_properties p WHERE p.interior_key=interior
            OR (POW(p.exterior_x-px,2)+POW(p.exterior_y-py,2)<100 AND ABS(p.exterior_z-pz)<4)
    ) THEN
        INSERT INTO frontier_properties (property_type,status,label,exterior_x,exterior_y,exterior_z,interior_key,estimated_value_cents)
        VALUES ('building','active',title,px,py,pz,interior,valuation);
        SET selected=LAST_INSERT_ID();
        INSERT INTO frontier_property_ownership VALUES (selected,'government','catalogue',10000);
        UPDATE frontier_property_catalogue SET property_id=selected WHERE catalogue_key=code;
    END IF;
    COMMIT;
    SELECT selected AS id;
END$$
DELIMITER ;
