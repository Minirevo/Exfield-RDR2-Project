-- Run against a disposable schema after Economy migrations 001,002,006.
-- SQL assertions fail the test process; no production data is used.
DROP PROCEDURE IF EXISTS fb_test_assert;
DELIMITER //
CREATE PROCEDURE fb_test_assert(IN p_ok BOOLEAN,IN p_msg VARCHAR(128))
BEGIN IF p_ok IS NULL OR p_ok=0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT=p_msg;END IF;END//
DELIMITER ;
INSERT INTO frontier_economy_accounts(owner_type,owner_id,account_type,balance_minor) VALUES
 ('business','test_business','bank',10000),('character','test_a','bank',100),('character','test_b','bank',200);
SET @from=(SELECT id FROM frontier_economy_accounts WHERE owner_id='test_business');
SET @a=(SELECT id FROM frontier_economy_accounts WHERE owner_id='test_a');
SET @b=(SELECT id FROM frontier_economy_accounts WHERE owner_id='test_b');
SET @pay=CONCAT('[[',@a,',3000],[',@b,',2000]]');
SET @k='business:00000000000000000000000000000001:batch';
CALL frontier_economy_business_batch_v1(@k,@from,1000,@pay,0);
CALL fb_test_assert((SELECT balance_minor=5000 FROM frontier_economy_accounts WHERE id=@from),'initial debit mismatch');
CALL fb_test_assert((SELECT balance_minor=3100 FROM frontier_economy_accounts WHERE id=@a),'first shareholder mismatch');
CALL fb_test_assert((SELECT balance_minor=2200 FROM frontier_economy_accounts WHERE id=@b),'second shareholder mismatch');
-- Simulate crash after the Economy commit but before the Business job is finalized.
CALL frontier_economy_business_batch_v1(@k,@from,1000,@pay,0);
CALL fb_test_assert((SELECT balance_minor=5000 FROM frontier_economy_accounts WHERE id=@from),'retry charged twice');
CALL fb_test_assert((SELECT COUNT(*)=3 FROM frontier_economy_ledger l JOIN frontier_economy_operations o ON l.operation_id=o.id WHERE o.request_key=@k),'duplicate ledger entries');
CALL frontier_economy_business_batch_v1(@k,@from,1000,CONCAT('[[',@a,',1]]'),0);
CALL fb_test_assert((SELECT balance_minor=3100 FROM frontier_economy_accounts WHERE id=@a),'conflicting replay changed account');
-- Insufficient funds/reserve must be all-or-nothing.
CALL frontier_economy_business_batch_v1('business:00000000000000000000000000000002:batch',@from,1000,@pay,0);
CALL fb_test_assert((SELECT balance_minor=5000 FROM frontier_economy_accounts WHERE id=@from),'reserve violated');
CALL fb_test_assert((SELECT balance_minor=3100 FROM frontier_economy_accounts WHERE id=@a),'partial payout');
-- Recipient overflow must also leave all accounts unchanged.
UPDATE frontier_economy_accounts SET balance_minor=9000000000000 WHERE id=@b;
CALL frontier_economy_business_batch_v1('business:00000000000000000000000000000003:batch',@from,0,CONCAT('[[',@a,',100],[',@b,',100]]'),0);
CALL fb_test_assert((SELECT balance_minor=5000 FROM frontier_economy_accounts WHERE id=@from),'overflow debited company');
CALL fb_test_assert((SELECT balance_minor=3100 FROM frontier_economy_accounts WHERE id=@a),'overflow partially credited');
-- A skipped wage remains skipped even after the company receives money.
SET @w='business:00000000000000000000000000000004:batch';
SET @wage=CONCAT('[[',@a,',6000]]');
CALL frontier_economy_business_batch_v1(@w,@from,0,@wage,1);
CALL fb_test_assert((SELECT completed AND JSON_UNQUOTE(JSON_EXTRACT(metadata_json,'$.result'))='insufficient_funds' FROM frontier_economy_operations WHERE request_key=@w),'skip not persisted');
CALL frontier_economy_apply_v1('test','replenish','credit',0,@from,10000,'test replenishment','','{}','USD');
CALL frontier_economy_business_batch_v1(@w,@from,0,@wage,1);
CALL fb_test_assert((SELECT balance_minor=15000 FROM frontier_economy_accounts WHERE id=@from),'skipped wage paid on retry');
CALL fb_test_assert((SELECT balance_minor=3100 FROM frontier_economy_accounts WHERE id=@a),'skipped wage retroactively credited');
-- A new wage must debit only once.
SET @new='business:00000000000000000000000000000005:batch';
CALL frontier_economy_business_batch_v1(@new,@from,0,@wage,1);
CALL frontier_economy_business_batch_v1(@new,@from,0,@wage,1);
CALL fb_test_assert((SELECT balance_minor=9000 FROM frontier_economy_accounts WHERE id=@from),'new wage not exactly once');
CALL fb_test_assert((SELECT balance_minor=9100 FROM frontier_economy_accounts WHERE id=@a),'wage credit mismatch');
SELECT 'financial recovery assertions passed' AS result;
DROP PROCEDURE fb_test_assert;
