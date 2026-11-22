-- Run in a disposable schema after migration 001.
SET @owner='f_owner', @other='f_other';
SET @id='00000000-0000-0000-0000-000000000001';
SET @second='00000000-0000-0000-0000-000000000002';
INSERT INTO frontier_production_businesses(owner_id,bank_id) VALUES(@owner,1),(@other,2);
CALL frontier_production_start_v1(@id,@owner,'bake','npc',1,'[]','bread',2,300,17,2);
CALL frontier_production_employee_v1(@owner,'hire');
CALL frontier_production_start_v1(@id,@owner,'bake','npc',1,'[]','bread',2,300,17,2);
CALL frontier_production_start_v1(@id,@owner,'bake','npc',1,'[]','bread',2,300,17,2);
CALL frontier_production_start_v1(@id,@other,'bake','player',1,'[]','bread',2,300,0,2);
CALL frontier_production_start_v1(@second,@owner,'bake','npc',1,'[]','bread',2,300,17,2);
CALL frontier_production_employee_v1(@owner,'dismiss');
SELECT CONCAT('jobs=',COUNT(*)) FROM frontier_production_jobs WHERE owner_id=@owner;
UPDATE frontier_production_jobs SET state='complete' WHERE id=@id;
CALL frontier_production_employee_v1(@owner,'dismiss');
SELECT CONCAT('employee=',employee) FROM frontier_production_businesses WHERE owner_id=@owner;
