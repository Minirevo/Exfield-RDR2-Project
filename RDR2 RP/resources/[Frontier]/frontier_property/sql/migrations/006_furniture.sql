CREATE TABLE IF NOT EXISTS frontier_property_furniture (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    property_id BIGINT UNSIGNED NOT NULL,
    lease_id BIGINT UNSIGNED NULL,
    owner_id CHAR(34) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    model_key VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL, heading DOUBLE NOT NULL,
    account_id BIGINT UNSIGNED NOT NULL,
    price_cents BIGINT UNSIGNED NOT NULL,
    retry_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    radius DOUBLE NOT NULL,
    state ENUM('pending','placed','recovery','void') NOT NULL DEFAULT 'pending',
    KEY ix_frontier_furniture_property (property_id,state),
    KEY ix_frontier_furniture_work (state,retry_at,id),
    KEY ix_frontier_furniture_owner (owner_id,state),
    FOREIGN KEY (property_id) REFERENCES frontier_properties(id),
    FOREIGN KEY (lease_id) REFERENCES frontier_property_rentals(id),
    FOREIGN KEY (owner_id) REFERENCES frontier_character_identities(id)
) ENGINE=InnoDB;

DELIMITER $$
CREATE OR REPLACE PROCEDURE frontier_property_furniture_place_v1(
    IN target BIGINT UNSIGNED, IN actor CHAR(34), IN model VARCHAR(48),
    IN px DOUBLE, IN py DOUBLE, IN pz DOUBLE, IN rotation DOUBLE,
    IN capacity INT UNSIGNED, IN recovered BIGINT UNSIGNED,
    IN bank BIGINT UNSIGNED, IN price BIGINT UNSIGNED, IN clearance DOUBLE
)
BEGIN
    DECLARE building BIGINT UNSIGNED DEFAULT NULL;
    DECLARE lease BIGINT UNSIGNED DEFAULT NULL;
    DECLARE furnishing BIGINT UNSIGNED DEFAULT NULL;
    DECLARE permitted BOOLEAN DEFAULT FALSE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT id INTO building FROM frontier_properties WHERE id=target AND status='active'
        AND interior_key IS NOT NULL FOR UPDATE;
    IF building IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM frontier_property_permissions WHERE property_id=target AND character_id=actor
            AND permission_key='furnish' AND allow_access=0
    ) THEN
        SELECT MAX(id) INTO lease FROM frontier_property_rentals
            WHERE property_id=target AND tenant_id=actor AND state='active'
                AND ends_at>UTC_TIMESTAMP() AND allow_furnish=1;
        SET permitted = lease IS NOT NULL OR EXISTS (
            SELECT 1 FROM frontier_property_ownership WHERE property_id=target
                AND party_type='character' AND party_id=actor
        );
        IF permitted AND NOT EXISTS (SELECT 1 FROM frontier_property_furniture
            WHERE property_id=target AND state IN ('pending','placed')
            AND POW(x-px,2)+POW(y-py,2)+POW(z-pz,2) < POW(radius+clearance,2))
          AND (SELECT COUNT(*) FROM frontier_property_furniture
            WHERE property_id=target AND state IN ('pending','placed')) < capacity THEN
            IF recovered > 0 THEN
                UPDATE frontier_property_furniture SET property_id=target,lease_id=lease,
                    x=px,y=py,z=pz,heading=rotation,radius=clearance,state='placed'
                WHERE id=recovered AND owner_id=actor AND state='recovery' AND model_key=model;
                IF ROW_COUNT()=1 THEN SET furnishing=recovered; END IF;
            ELSE
                INSERT INTO frontier_property_furniture (property_id,lease_id,owner_id,model_key,x,y,z,heading,account_id,price_cents,radius)
                VALUES (target,lease,actor,model,px,py,pz,rotation,bank,price,clearance);
                SET furnishing=LAST_INSERT_ID();
            END IF;
        END IF;
    END IF;
    COMMIT;
    SELECT furnishing AS id;
END$$
DELIMITER ;
