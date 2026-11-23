INSERT INTO frontier_character_identities (id,provider,provider_character_id,created_at,updated_at)
VALUES (CONCAT('f_',REPEAT('a',32)),'vorp','testA',UTC_TIMESTAMP(),UTC_TIMESTAMP()),(CONCAT('f_',REPEAT('b',32)),'vorp','testB',UTC_TIMESTAMP(),UTC_TIMESTAMP());
SET @a=CONCAT('f_',REPEAT('a',32)), @b=CONCAT('f_',REPEAT('b',32));
SET @p='[{"x":1,"y":2,"z":3},{"x":20,"y":2,"z":3},{"x":20,"y":20,"z":3}]';
CALL frontier_land_reserve_v1(0,@a,'test',@p,171,200,1);
CALL frontier_land_reserve_v1(0,@b,'test',@p,171,200,2);
CALL frontier_land_reserve_v1(1,@a,'test',@p,171,200,1);
CALL frontier_land_finish_v1(1,1);
CALL frontier_land_finish_v1(1,1);
SELECT CONCAT('active=',COUNT(*)) FROM frontier_properties WHERE status='active';
SELECT CONCAT('owner=',share_bps) FROM frontier_property_ownership WHERE party_id=@a;
CALL frontier_land_reserve_v1(1,@b,'test',@p,171,200,2);
CALL frontier_land_finish_v1(2,0);
SELECT CONCAT('second=',state) FROM frontier_land_claims WHERE id=2;
SELECT CONCAT('revision=',revision) FROM frontier_land_revision WHERE id=1;
