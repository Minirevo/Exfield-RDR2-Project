INSERT INTO frontier_character_identities (id,provider,provider_character_id,created_at,updated_at)
VALUES (CONCAT('f_',REPEAT('a',32)),'vorp','ownerA',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
       (CONCAT('f_',REPEAT('b',32)),'vorp','tenantB',UTC_TIMESTAMP(),UTC_TIMESTAMP());
SET @a=CONCAT('f_',REPEAT('a',32)),@b=CONCAT('f_',REPEAT('b',32));
INSERT INTO frontier_properties (property_type,status,label,exterior_x,exterior_y,exterior_z,interior_key)
VALUES ('building','active','Existing',10,20,30,'house');
INSERT INTO frontier_property_ownership VALUES (1,'character',@a,10000);
INSERT INTO frontier_property_rentals (property_id,tenant_id,account_id,landlord_bank_id,price_cents,duration_seconds,allow_furnish,state,ends_at)
VALUES (1,@b,2,1,100,3600,1,'active',UTC_TIMESTAMP()+INTERVAL 1 HOUR);
INSERT INTO frontier_property_furniture (property_id,lease_id,owner_id,model_key,x,y,z,heading,account_id,price_cents,radius,state)
VALUES (1,1,@b,'bett',1,1,1,0,2,25,.5,'placed'),(1,NULL,@a,'truhe',4,4,4,0,1,25,.5,'placed');
CALL frontier_property_furniture_manage_v1(1,1,@a,'store',1,1,1,0);
CALL frontier_property_furniture_manage_v1(1,1,@b,'move',4,4,4,90);
CALL frontier_property_furniture_manage_v1(1,1,@b,'move',2,2,2,90);
CALL frontier_property_manage_v1(1,@a,'permission','',@b,'furnish_move',0);
CALL frontier_property_furniture_manage_v1(1,1,@b,'move',3,3,3,90);
CALL frontier_property_furniture_manage_v1(1,1,@b,'store',2,2,2,90);
SELECT CONCAT(state,':',heading) FROM frontier_property_furniture WHERE id=1;
