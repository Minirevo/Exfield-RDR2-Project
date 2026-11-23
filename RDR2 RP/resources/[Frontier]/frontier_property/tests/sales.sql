INSERT INTO frontier_character_identities (id,provider,provider_character_id,created_at,updated_at)
VALUES (CONCAT('f_',REPEAT('a',32)),'vorp','ownerA',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
(CONCAT('f_',REPEAT('b',32)),'vorp','ownerB',UTC_TIMESTAMP(),UTC_TIMESTAMP()),
(CONCAT('f_',REPEAT('c',32)),'vorp','buyerC',UTC_TIMESTAMP(),UTC_TIMESTAMP());
SET @a=CONCAT('f_',REPEAT('a',32)), @b=CONCAT('f_',REPEAT('b',32)), @c=CONCAT('f_',REPEAT('c',32));
INSERT INTO frontier_properties (id,property_type,status,label,exterior_x,exterior_y,exterior_z,interior_key)
VALUES (1,'building','active','Test',1,2,3,'test');
INSERT INTO frontier_property_ownership VALUES (1,'character',@a,6000),(1,'character',@b,4000);
INSERT INTO frontier_property_rentals (property_id,tenant_id,account_id,price_cents,duration_seconds,allow_furnish,state,ends_at)
VALUES (1,@b,2,100,3600,1,'active',UTC_TIMESTAMP()+INTERVAL 1 HOUR);
CALL frontier_sale_offer_v1(1,@a,@c,2000);
UPDATE frontier_property_sale_approvals SET bank_id=1 WHERE owner_id=@a;
CALL frontier_sale_reserve_v1(1,@c,3,1);
UPDATE frontier_property_sale_approvals SET bank_id=2 WHERE owner_id=@b;
CALL frontier_sale_reserve_v1(1,@c,3,0);
INSERT INTO frontier_property_finance VALUES (1,200);
CALL frontier_sale_reserve_v1(1,@c,3,1);
UPDATE frontier_property_finance SET debt_cents=0 WHERE property_id=1;
CALL frontier_sale_reserve_v1(1,@c,3,1);
CALL frontier_sale_finish_v1(1);
SELECT state FROM frontier_property_sales WHERE id=1;
UPDATE frontier_property_sale_approvals SET paid=1 WHERE sale_id=1;
CALL frontier_sale_finish_v1(1);
CALL frontier_sale_finish_v1(1);
SELECT CONCAT(party_id=@c,':',share_bps) FROM frontier_property_ownership;
SELECT CONCAT(s.state,':',r.state) FROM frontier_property_sales s
JOIN frontier_property_rentals r ON r.id=s.assumed_lease_id;
