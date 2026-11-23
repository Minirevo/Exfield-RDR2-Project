INSERT INTO frontier_character_identities (id,provider,provider_character_id,created_at,updated_at)
VALUES (CONCAT('f_',REPEAT('a',32)),'vorp','ownerA',UTC_TIMESTAMP(),UTC_TIMESTAMP());
SET @a=CONCAT('f_',REPEAT('a',32));
INSERT INTO frontier_properties (id,property_type,status,label,exterior_x,exterior_y,exterior_z,interior_key,estimated_value_cents)
VALUES (1,'building','active','Test',1,2,3,'test',100000);
INSERT INTO frontier_property_ownership VALUES (1,'character',@a,10000);
CALL frontier_upkeep_accrue_v1(1,100,86400);
UPDATE frontier_property_finance SET next_due=UTC_TIMESTAMP()-INTERVAL 1 DAY WHERE property_id=1;
CALL frontier_upkeep_accrue_v1(1,100,86400);
CALL frontier_upkeep_accrue_v1(1,100,86400);
SELECT debt_cents FROM frontier_property_finance WHERE property_id=1;
CALL frontier_upkeep_reserve_v1(1,@a,7,2000);
CALL frontier_foreclosure_open_v1(1,1000,0,3000,5000,8);
SELECT COUNT(*) FROM frontier_property_foreclosures;
CALL frontier_upkeep_finish_v1(1,1);
CALL frontier_upkeep_finish_v1(1,1);
SELECT debt_cents FROM frontier_property_finance WHERE property_id=1;
UPDATE frontier_property_finance SET debt_cents=20000,debt_since=UTC_TIMESTAMP()-INTERVAL 2 DAY WHERE property_id=1;
CALL frontier_foreclosure_open_v1(1,1000,86400,3000,5000,8);
CALL frontier_foreclosure_open_v1(1,1000,86400,3000,5000,8);
SELECT CONCAT(deduction_cents,':',debt_paid_cents,':',debt_forgiven_cents,':',state_penalty_cents,':',owner_payout_cents)
FROM frontier_property_foreclosures WHERE id=1;
CALL frontier_foreclosure_finish_v1(1);
SELECT state FROM frontier_property_foreclosures WHERE id=1;
UPDATE frontier_property_foreclosures SET treasury_paid=1 WHERE id=1;
UPDATE frontier_property_foreclosure_payees SET paid=1 WHERE foreclosure_id=1;
CALL frontier_foreclosure_finish_v1(1);
CALL frontier_foreclosure_finish_v1(1);
SELECT CONCAT(state,':',(SELECT COUNT(*) FROM frontier_property_ownership)) FROM frontier_property_foreclosures;
