INSERT INTO frontier_character_identities (id,provider,provider_character_id,created_at,updated_at)
VALUES (CONCAT('f_',REPEAT('a',32)),'vorp','builderA',UTC_TIMESTAMP(),UTC_TIMESTAMP());
SET @a=CONCAT('f_',REPEAT('a',32));
INSERT INTO frontier_properties (id,property_type,status,label,exterior_x,exterior_y,exterior_z)
VALUES (1,'land','active','Test',1,2,3);
INSERT INTO frontier_property_ownership VALUES (1,'character',@a,10000);
CALL frontier_build_action_v1(1,@a,0,'shed','p_shed',1,1,2,3,0,1,0,'',0,500);
CALL frontier_build_action_v1(1,@a,0,'shed','p_shed',1,1,2,3,0,1,0,'',0,500);
INSERT INTO frontier_property_finance VALUES (1,50);
CALL frontier_build_action_v1(1,@a,1,'','',0,0,0,0,0,0,1,'wood',2,0);
UPDATE frontier_property_finance SET debt_cents=0 WHERE property_id=1;
CALL frontier_build_action_v1(1,@a,1,'','',0,0,0,0,0,0,1,'wood',2,0);
CALL frontier_build_action_v1(1,@a,1,'','',0,0,0,0,0,0,1,'wood',2,0);
CALL frontier_build_finish_v1(1,1);
CALL frontier_build_finish_v1(1,1);
SELECT CONCAT(state,':',stage) FROM frontier_property_construction WHERE id=1;
