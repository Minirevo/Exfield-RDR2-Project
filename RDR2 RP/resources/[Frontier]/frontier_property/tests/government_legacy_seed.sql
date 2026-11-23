INSERT INTO frontier_character_identities (id,provider,provider_character_id,created_at,updated_at)
VALUES (CONCAT('f_',REPEAT('a',32)),'vorp','legacy',UTC_TIMESTAMP(),UTC_TIMESTAMP());
SET @a=CONCAT('f_',REPEAT('a',32));
INSERT INTO frontier_properties (id,property_type,status,label,exterior_x,exterior_y,exterior_z,interior_key)
VALUES (1,'building','active','Legacy',1,2,3,'legacy'),(2,'building','active','Unused',10,20,30,'unused');
INSERT INTO frontier_property_ownership VALUES (1,'government','catalogue',10000),(2,'government','catalogue',10000);
CALL frontier_property_rent_reserve_v2(1,@a,1,100,3600,1,25);
