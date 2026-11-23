INSERT INTO frontier_character_identities (id,provider,provider_character_id,created_at,updated_at)
VALUES (CONCAT('f_',REPEAT('a',32)),'vorp','landlordA',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
       (CONCAT('f_',REPEAT('b',32)),'vorp','tenantB',UTC_TIMESTAMP(),UTC_TIMESTAMP());
SET @a=CONCAT('f_',REPEAT('a',32)), @b=CONCAT('f_',REPEAT('b',32));
INSERT INTO frontier_properties (id,property_type,status,label,exterior_x,exterior_y,exterior_z,interior_key)
VALUES (1,'building','active','Test',1,2,3,'test');
INSERT INTO frontier_property_ownership VALUES (1,'character',@a,10000);
CALL frontier_property_rent_offer_v1(1,@b,2,300,3600,1);
CALL frontier_property_rent_offer_v1(1,@a,1,200,3600,1);
SET @v=(SELECT offer_version FROM frontier_property_private_offers WHERE property_id=1);
CALL frontier_property_rent_offer_v1(1,@a,1,250,3600,0);
CALL frontier_property_private_rent_v1(1,@b,2,@v);
SET @v=(SELECT offer_version FROM frontier_property_private_offers WHERE property_id=1);
CALL frontier_property_private_rent_v1(1,@a,1,@v);
CALL frontier_property_private_rent_v1(1,@b,2,@v);
CALL frontier_property_private_rent_v1(1,@b,2,@v);
SELECT CONCAT(landlord_bank_id,':',account_id,':',price_cents,':',allow_furnish) FROM frontier_property_rentals;
