INSERT INTO frontier_character_identities (id,provider,provider_character_id,created_at,updated_at)
VALUES (CONCAT('f_',REPEAT('a',32)),'vorp','ownerA',UTC_TIMESTAMP(),UTC_TIMESTAMP());
SET @a=CONCAT('f_',REPEAT('a',32));
INSERT INTO frontier_properties (id,property_type,status,label,exterior_x,exterior_y,exterior_z,interior_key)
VALUES (1,'building','active','Test',1,2,3,'test'),(2,'building','active','Test 2',1,2,3,'test');
INSERT INTO frontier_property_ownership VALUES (1,'character',@a,10000),(2,'character',@a,10000);
CALL frontier_property_furniture_place_v1(1,@a,'bed',1,2,3,90,2,0,1,50,1);
CALL frontier_property_furniture_place_v1(1,@a,'bed',1,2,3,90,2,0,1,50,1);
UPDATE frontier_property_furniture SET state='recovery' WHERE id=1;
CALL frontier_property_furniture_place_v1(2,@a,'bed',5,6,7,90,2,1,0,0,1);
CALL frontier_property_furniture_place_v1(2,@a,'bed',9,6,7,90,2,1,0,0,1);
SELECT CONCAT(property_id,':',state,':',price_cents) FROM frontier_property_furniture;
