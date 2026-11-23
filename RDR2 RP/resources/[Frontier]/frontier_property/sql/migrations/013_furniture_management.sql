DELIMITER $$
CREATE OR REPLACE PROCEDURE frontier_property_furniture_manage_v1(
    IN target BIGINT UNSIGNED, IN piece BIGINT UNSIGNED, IN actor CHAR(34), IN action_key VARCHAR(16),
    IN px DOUBLE, IN py DOUBLE, IN pz DOUBLE, IN rotation DOUBLE)
BEGIN
    DECLARE estate BIGINT UNSIGNED DEFAULT NULL;
    DECLARE object_radius DOUBLE DEFAULT NULL;
    DECLARE capability VARCHAR(32);
    DECLARE result BOOLEAN DEFAULT FALSE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    START TRANSACTION;
    SELECT id INTO estate FROM frontier_properties WHERE id=target AND status='active' FOR UPDATE;
    SET capability=IF(action_key='store','furnish_remove','furnish_move');
    IF estate IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM frontier_property_sales WHERE property_id=target AND state='reserved'
    ) AND NOT EXISTS (SELECT 1 FROM frontier_property_permissions WHERE property_id=target
        AND character_id=actor AND permission_key=capability AND allow_access=0) THEN
        SELECT f.radius INTO object_radius FROM frontier_property_furniture f
          WHERE f.id=piece AND f.property_id=target AND f.owner_id=actor AND f.state='placed'
          AND (EXISTS (SELECT 1 FROM frontier_property_ownership WHERE property_id=target
            AND party_type='character' AND party_id=actor)
          OR EXISTS (SELECT 1 FROM frontier_property_rentals WHERE id=f.lease_id AND tenant_id=actor
            AND state='active' AND ends_at>UTC_TIMESTAMP() AND allow_furnish=1)
          OR EXISTS (SELECT 1 FROM frontier_property_permissions WHERE property_id=target
            AND character_id=actor AND permission_key=capability AND allow_access=1))
          FOR UPDATE;
        IF object_radius IS NOT NULL THEN
            IF action_key='store' THEN
                UPDATE frontier_property_furniture SET state='recovery' WHERE id=piece;
                SET result=TRUE;
            ELSEIF action_key='move' AND NOT EXISTS (SELECT 1 FROM frontier_property_furniture
                WHERE id<>piece AND property_id=target AND state IN ('placed','pending')
                AND POW(x-px,2)+POW(y-py,2)+POW(z-pz,2)<POW(radius+object_radius,2)) THEN
                UPDATE frontier_property_furniture SET x=px,y=py,z=pz,heading=rotation WHERE id=piece;
                SET result=TRUE;
            END IF;
        END IF;
    END IF;
    COMMIT;
    SELECT result AS accepted;
END$$
DELIMITER ;
