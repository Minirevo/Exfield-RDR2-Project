INSERT INTO frontier_character_identities (id,provider,provider_character_id,created_at,updated_at)
VALUES (CONCAT('f_',REPEAT('a',32)),'vorp','tenantA',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
       (CONCAT('f_',REPEAT('b',32)),'vorp','tenantB',UTC_TIMESTAMP(),UTC_TIMESTAMP());
SET @a=CONCAT('f_',REPEAT('a',32)), @b=CONCAT('f_',REPEAT('b',32));
INSERT INTO frontier_properties (id,property_type,status,label,exterior_x,exterior_y,exterior_z,interior_key)
VALUES (1,'building','active','Test',1,2,3,'test'),(2,'land','active','Land',1,2,3,NULL);
INSERT INTO frontier_property_ownership VALUES (1,'government','state',10000),(2,'government','state',10000);
CALL frontier_property_rent_reserve_v1(1,@a,1,200,3600,1);
CALL frontier_property_rent_reserve_v1(1,@b,2,200,3600,0);
CALL frontier_property_rent_reserve_v1(2,@b,2,200,3600,0);
UPDATE frontier_property_rentals SET state='active',ends_at=UTC_TIMESTAMP()+INTERVAL 1 HOUR WHERE id=1;
CALL frontier_property_rent_reserve_v1(1,@b,2,200,3600,0);
UPDATE frontier_property_rentals SET ends_at=UTC_TIMESTAMP()-INTERVAL 1 SECOND WHERE id=1;
CALL frontier_property_rent_reserve_v1(1,@b,2,200,3600,0);
SELECT CONCAT('furnish=',allow_furnish) FROM frontier_property_rentals WHERE id=1;
