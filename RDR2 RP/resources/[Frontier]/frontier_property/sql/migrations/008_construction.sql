CREATE TABLE IF NOT EXISTS frontier_property_construction (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    property_id BIGINT UNSIGNED NOT NULL,
    blueprint VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL, heading DOUBLE NOT NULL,
    radius DOUBLE NOT NULL,
    stage SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    stage_count SMALLINT UNSIGNED NOT NULL,
    model_name VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    state ENUM('building','complete','seized') NOT NULL DEFAULT 'building',
    value_cents BIGINT UNSIGNED NOT NULL DEFAULT 0,
    KEY ix_frontier_construction_estate (property_id,state),
    FOREIGN KEY (property_id) REFERENCES frontier_properties(id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS frontier_property_build_jobs (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    site_id BIGINT UNSIGNED NOT NULL,
    stage SMALLINT UNSIGNED NOT NULL,
    character_id CHAR(34) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    item_key VARCHAR(48) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    item_count INT UNSIGNED NOT NULL,
    state ENUM('pending','done','declined') NOT NULL DEFAULT 'pending',
    retry_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY ix_frontier_construction_work (state,retry_at,id),
    FOREIGN KEY (site_id) REFERENCES frontier_property_construction(id),
    FOREIGN KEY (character_id) REFERENCES frontier_character_identities(id)
) ENGINE=InnoDB;

DELIMITER $$
CREATE OR REPLACE PROCEDURE frontier_build_action_v1(
    IN target BIGINT UNSIGNED, IN actor CHAR(34), IN site BIGINT UNSIGNED,
    IN plan VARCHAR(48), IN model VARCHAR(64), IN total_stages SMALLINT UNSIGNED,
    IN px DOUBLE, IN py DOUBLE, IN pz DOUBLE, IN rotation DOUBLE, IN clearance DOUBLE,
    IN expected_stage SMALLINT UNSIGNED, IN material VARCHAR(48), IN quantity INT UNSIGNED,
    IN valuation BIGINT UNSIGNED
)
BEGIN
    DECLARE estate BIGINT UNSIGNED DEFAULT NULL;
    DECLARE result_id BIGINT UNSIGNED DEFAULT NULL;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT id INTO estate FROM frontier_properties WHERE id=target AND status='active' FOR UPDATE;
    IF estate IS NOT NULL
        AND COALESCE((SELECT debt_cents FROM frontier_property_finance WHERE property_id=target),0)=0
        AND NOT EXISTS (SELECT 1 FROM frontier_property_rentals WHERE property_id=target
            AND (state='reserved' OR (state='active' AND ends_at>UTC_TIMESTAMP())))
        AND NOT EXISTS (SELECT 1 FROM frontier_property_sales WHERE property_id=target AND state='reserved')
        AND NOT EXISTS (SELECT 1 FROM frontier_property_permissions WHERE property_id=target AND character_id=actor
            AND permission_key='construct' AND allow_access=0)
        AND (EXISTS (SELECT 1 FROM frontier_property_ownership WHERE property_id=target
            AND party_type='character' AND party_id=actor)
          OR (site>0 AND EXISTS (SELECT 1 FROM frontier_property_permissions WHERE property_id=target
            AND character_id=actor AND permission_key='construct' AND allow_access=1))) THEN
        IF site=0 AND NOT EXISTS (SELECT 1 FROM frontier_property_construction WHERE property_id=target
            AND state<>'seized' AND POW(x-px,2)+POW(y-py,2)<POW(radius+clearance,2))
          AND (SELECT COUNT(*) FROM frontier_property_construction WHERE property_id=target
            AND state<>'seized')<20 THEN
            INSERT INTO frontier_property_construction
                (property_id,blueprint,model_name,stage_count,x,y,z,heading,radius,value_cents)
            VALUES (target,plan,model,total_stages,px,py,pz,rotation,clearance,valuation);
            SET result_id=LAST_INSERT_ID();
        ELSEIF site>0 AND EXISTS (SELECT 1 FROM frontier_property_construction WHERE id=site
            AND property_id=target AND state='building' AND stage=expected_stage)
          AND NOT EXISTS (SELECT 1 FROM frontier_property_build_jobs WHERE site_id=site AND state='pending') THEN
            INSERT INTO frontier_property_build_jobs (site_id,stage,character_id,item_key,item_count)
                VALUES (site,expected_stage,actor,material,quantity);
            SET result_id=LAST_INSERT_ID();
        END IF;
    END IF;
    COMMIT;
    SELECT result_id AS id;
END$$

CREATE OR REPLACE PROCEDURE frontier_build_finish_v1(IN job BIGINT UNSIGNED, IN consumed BOOLEAN)
BEGIN
    DECLARE site BIGINT UNSIGNED DEFAULT NULL;
    DECLARE stage_number SMALLINT UNSIGNED;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT site_id,stage INTO site,stage_number FROM frontier_property_build_jobs
        WHERE id=job AND state='pending' FOR UPDATE;
    IF site IS NOT NULL AND consumed THEN
        UPDATE frontier_property_construction SET state=IF(stage=stage_count,'complete','building'),stage=stage+1
            WHERE id=site AND state='building' AND stage=stage_number;
        IF ROW_COUNT()<>1 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Construction stage changed'; END IF;
    END IF;
    IF site IS NOT NULL THEN
        UPDATE frontier_property_build_jobs SET state=IF(consumed,'done','declined') WHERE id=job;
    END IF;
    COMMIT;
END$$

CREATE OR REPLACE TRIGGER frontier_property_construction_sale_guard BEFORE UPDATE ON frontier_property_sales
FOR EACH ROW
BEGIN
    IF OLD.state='offered' AND NEW.state='reserved' AND EXISTS (
        SELECT 1 FROM frontier_property_construction WHERE property_id=NEW.property_id AND state='building'
    ) THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Incomplete construction'; END IF;
END$$
DELIMITER ;
