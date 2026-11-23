INSERT INTO frontier_character_identities (id,provider,provider_character_id,created_at,updated_at)
VALUES (CONCAT('f_',REPEAT('a',32)),'vorp','ownerA',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
       (CONCAT('f_',REPEAT('b',32)),'vorp','helperB',UTC_TIMESTAMP(),UTC_TIMESTAMP());
SET @a=CONCAT('f_',REPEAT('a',32)),@b=CONCAT('f_',REPEAT('b',32));
INSERT INTO frontier_properties (property_type,status,label,exterior_x,exterior_y,exterior_z,interior_key)
VALUES ('building','active','Existing',10,20,30,'house'),('land','active','Land',100,200,300,NULL);
INSERT INTO frontier_property_ownership VALUES (1,'character',@a,10000),(2,'character',@b,10000);
CALL frontier_property_manage_v1(1,@b,'rename','Forbidden','','',0);
CALL frontier_property_manage_v1(1,@a,'rename','Wolf''s Rest','','',0);
CALL frontier_property_manage_v1(2,@b,'rename','wolf''s rest','','',0);
CALL frontier_property_manage_v1(1,@a,'permission','',@b,'construct',1);
CALL frontier_property_manage_v1(1,@a,'permission','',@b,'construct',0);
SELECT CONCAT(property_id,':',allow_access) FROM frontier_property_permissions;
SELECT CONCAT(id,':',label) FROM frontier_properties WHERE id=1;
