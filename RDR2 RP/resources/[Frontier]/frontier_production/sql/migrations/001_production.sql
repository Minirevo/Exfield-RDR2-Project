CREATE TABLE IF NOT EXISTS frontier_production_businesses (
    owner_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    bank_id BIGINT UNSIGNED NOT NULL,
    employee ENUM('none','hired','unpaid') NOT NULL DEFAULT 'none'
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS frontier_production_jobs (
    id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
    owner_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    recipe VARCHAR(48) NOT NULL,
    mode ENUM('player','npc') NOT NULL,
    batches INT UNSIGNED NOT NULL,
    materials TEXT NOT NULL CHECK (JSON_VALID(materials)),
    output_item VARCHAR(48) NOT NULL,
    output_units INT UNSIGNED NOT NULL,
    duration_seconds INT UNSIGNED NOT NULL,
    remaining_seconds INT UNSIGNED NOT NULL,
    wage_minor BIGINT UNSIGNED NOT NULL,
    state ENUM('reserve','wage','unpaid','return','running','output','complete','cancelled','rejected') NOT NULL DEFAULT 'reserve',
    checkpoint DATETIME NULL,
    completes_at DATETIME NULL,
    retry_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (owner_id) REFERENCES frontier_production_businesses(owner_id),
    KEY ix_production_due (state,retry_at,id), KEY ix_production_owner (owner_id,state)
) ENGINE=InnoDB;

DROP PROCEDURE IF EXISTS frontier_production_start_v1;
DROP PROCEDURE IF EXISTS frontier_production_employee_v1;
DELIMITER //
CREATE PROCEDURE frontier_production_start_v1(IN p_id CHAR(36), IN p_owner VARCHAR(64),
    IN p_recipe VARCHAR(48), IN p_mode VARCHAR(8), IN p_batches INT,
    IN p_materials TEXT, IN p_output VARCHAR(48), IN p_units INT, IN p_seconds INT,
    IN p_wage BIGINT, IN p_limit INT)
start_job: BEGIN
    DECLARE v_employee VARCHAR(8);
    DECLARE v_existing VARCHAR(64);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT employee INTO v_employee FROM frontier_production_businesses WHERE owner_id=p_owner FOR UPDATE;
    SELECT owner_id INTO v_existing FROM frontier_production_jobs WHERE id=p_id;
    IF v_existing IS NOT NULL THEN
        COMMIT;
        SELECT IF(v_existing=p_owner AND EXISTS (
            SELECT 1 FROM frontier_production_jobs WHERE id=p_id AND recipe=p_recipe
                 AND mode=p_mode AND batches=p_batches
        ),'ok','conflict') AS code;
        LEAVE start_job;
    END IF;
    IF v_employee IS NULL OR p_mode NOT IN ('player','npc')
       OR (p_mode='npc' AND v_employee<>'hired')
       OR (SELECT COUNT(*) FROM frontier_production_jobs WHERE owner_id=p_owner
           AND state NOT IN ('complete','cancelled','rejected'))>=p_limit
       OR (p_mode='npc' AND EXISTS (SELECT 1 FROM frontier_production_jobs WHERE owner_id=p_owner
           AND mode='npc' AND state NOT IN ('complete','cancelled','rejected'))) THEN
        ROLLBACK; SELECT 'unavailable' AS code; LEAVE start_job;
    END IF;
    INSERT INTO frontier_production_jobs
       (id,owner_id,recipe,mode,batches,materials,output_item,output_units,duration_seconds,remaining_seconds,wage_minor,retry_at,created_at)
    VALUES(p_id,p_owner,p_recipe,p_mode,p_batches,p_materials,p_output,p_units,p_seconds,p_seconds,p_wage,UTC_TIMESTAMP(),UTC_TIMESTAMP());
    COMMIT; SELECT 'ok' AS code;
END//
CREATE PROCEDURE frontier_production_employee_v1(IN p_owner VARCHAR(64), IN p_action VARCHAR(8))
employee_action: BEGIN
    DECLARE v_employee VARCHAR(8);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT employee INTO v_employee FROM frontier_production_businesses WHERE owner_id=p_owner FOR UPDATE;
    IF v_employee IS NULL OR p_action NOT IN ('hire','dismiss') THEN
        ROLLBACK; SELECT 'unavailable' AS code; LEAVE employee_action;
    END IF;
    IF p_action='hire' AND v_employee='none' THEN
        UPDATE frontier_production_businesses SET employee='hired' WHERE owner_id=p_owner;
    ELSEIF p_action='dismiss' AND v_employee<>'none' THEN
        IF EXISTS (SELECT 1 FROM frontier_production_jobs WHERE owner_id=p_owner AND mode='npc'
            AND state NOT IN ('complete','cancelled','rejected')) THEN
            ROLLBACK; SELECT 'unavailable' AS code; LEAVE employee_action;
        END IF;
        UPDATE frontier_production_businesses SET employee='none' WHERE owner_id=p_owner;
    END IF;
    COMMIT; SELECT 'ok' AS code;
END//
DELIMITER ;
