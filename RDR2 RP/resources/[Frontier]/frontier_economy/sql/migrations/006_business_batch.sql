-- Atomic, replay-safe multi-recipient business transfers. Apply after Economy 001-005.
DROP PROCEDURE IF EXISTS frontier_economy_business_batch_v1;
DELIMITER //
CREATE PROCEDURE frontier_economy_business_batch_v1(
 IN p_key VARCHAR(96) CHARACTER SET ascii COLLATE ascii_bin,
 IN p_debit BIGINT UNSIGNED,
 IN p_reserve BIGINT UNSIGNED,
 IN p_payments MEDIUMTEXT,
 IN p_skip BOOLEAN
)
SQL SECURITY DEFINER
batch: BEGIN
 DECLARE v_op BIGINT UNSIGNED;
 DECLARE v_hash BINARY(32);
 DECLARE v_old_hash BINARY(32);
 DECLARE v_complete BOOLEAN;
 DECLARE v_metadata TEXT;
 DECLARE v_count INT;
 DECLARE v_i INT DEFAULT 0;
 DECLARE v_id BIGINT UNSIGNED;
 DECLARE v_previous BIGINT UNSIGNED DEFAULT 0;
 DECLARE v_amount BIGINT UNSIGNED;
 DECLARE v_total BIGINT UNSIGNED DEFAULT 0;
 DECLARE v_balance BIGINT UNSIGNED;
 DECLARE v_credit BIGINT UNSIGNED;
 DECLARE v_failure VARCHAR(32) DEFAULT NULL;
 DECLARE v_time DATETIME(6);
 DECLARE v_kind VARCHAR(24);
 DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
 IF p_key IS NULL OR p_key NOT REGEXP '^business:[a-f0-9]{32}:batch$'
    OR p_debit IS NULL OR p_debit=0 OR p_reserve IS NULL OR p_reserve>9000000000000
    OR p_payments IS NULL OR JSON_VALID(p_payments)=0 OR p_skip IS NULL OR p_skip NOT IN (0,1) THEN
  SELECT 'invalid_request' AS code; LEAVE batch;
 END IF;
 IF JSON_TYPE(p_payments)<>'ARRAY' THEN SELECT 'invalid_request' AS code; LEAVE batch; END IF;
 SET v_count=JSON_LENGTH(p_payments);
 IF v_count NOT BETWEEN 1 AND 10000 OR (p_skip=1 AND (v_count<>1 OR p_reserve<>0)) THEN
  SELECT 'invalid_request' AS code; LEAVE batch;
 END IF;
 -- Validate the complete ordered payload before claiming the idempotency key.
 WHILE v_i<v_count DO
  IF JSON_TYPE(JSON_EXTRACT(p_payments,CONCAT('$[',v_i,']')))<>'ARRAY'
      OR JSON_LENGTH(JSON_EXTRACT(p_payments,CONCAT('$[',v_i,']')))<>2
      OR JSON_TYPE(JSON_EXTRACT(p_payments,CONCAT('$[',v_i,'][0]')))<>'INTEGER'
      OR JSON_TYPE(JSON_EXTRACT(p_payments,CONCAT('$[',v_i,'][1]')))<>'INTEGER' THEN
   SELECT 'invalid_request' AS code; LEAVE batch;
  END IF;
  SET v_id=CAST(JSON_UNQUOTE(JSON_EXTRACT(p_payments,CONCAT('$[',v_i,'][0]'))) AS UNSIGNED);
  SET v_amount=CAST(JSON_UNQUOTE(JSON_EXTRACT(p_payments,CONCAT('$[',v_i,'][1]'))) AS UNSIGNED);
  IF v_id<=v_previous OR v_id=p_debit OR v_id>9007199254740991 OR v_amount NOT BETWEEN 1 AND 9000000000000
     OR v_total>9000000000000-v_amount THEN SELECT 'invalid_request' AS code; LEAVE batch; END IF;
  SET v_previous=v_id,v_total=v_total+v_amount,v_i=v_i+1;
 END WHILE;
 SET v_hash=UNHEX(SHA2(CONCAT(p_debit,':',p_reserve,':',p_skip,':',p_payments),256));
 START TRANSACTION;
 INSERT INTO frontier_economy_operations(actor,request_key,fingerprint,kind,reason,reference_text,metadata_json)
 VALUES('resource:frontier_business',p_key,v_hash,'transfer','Frontier business batch',p_key,'{}')
 ON DUPLICATE KEY UPDATE id=id;
 SELECT id,fingerprint,completed,metadata_json INTO v_op,v_old_hash,v_complete,v_metadata
 FROM frontier_economy_operations WHERE actor='resource:frontier_business' AND request_key=p_key FOR UPDATE;
 IF v_old_hash<>v_hash THEN ROLLBACK;SELECT 'idempotency_conflict' AS code;LEAVE batch;END IF;
 IF v_complete THEN
  COMMIT;
  SELECT COALESCE(JSON_UNQUOTE(JSON_EXTRACT(v_metadata,'$.result')),'ok') AS code,CAST(v_op AS CHAR) AS operation_id,1 AS replayed;
  LEAVE batch;
 END IF;
 SET v_balance=NULL,v_kind=NULL;
 SELECT balance_minor,owner_type INTO v_balance,v_kind FROM frontier_economy_accounts
 WHERE id=p_debit AND account_type='bank' AND currency='USD' FOR UPDATE;
 IF v_balance IS NULL OR v_kind<>'business' THEN ROLLBACK;SELECT 'invalid_account' AS code;LEAVE batch;END IF;
 IF v_balance<v_total+p_reserve THEN SET v_failure='insufficient_funds';END IF;
 -- Lock and validate every recipient before any balance changes. Deadlocks roll back for safe retry.
 SET v_i=0;
 WHILE v_i<v_count AND v_failure IS NULL DO
  SET v_id=CAST(JSON_UNQUOTE(JSON_EXTRACT(p_payments,CONCAT('$[',v_i,'][0]'))) AS UNSIGNED);
  SET v_amount=CAST(JSON_UNQUOTE(JSON_EXTRACT(p_payments,CONCAT('$[',v_i,'][1]'))) AS UNSIGNED);
  SET v_credit=NULL;
  SELECT balance_minor INTO v_credit FROM frontier_economy_accounts
  WHERE id=v_id AND owner_type='character' AND account_type='bank' AND currency='USD' FOR UPDATE;
  IF v_credit IS NULL THEN SET v_failure='invalid_account';
  ELSEIF v_credit>9000000000000-v_amount THEN SET v_failure='balance_limit';END IF;
  SET v_i=v_i+1;
 END WHILE;
 IF v_failure IS NOT NULL THEN
  -- A rejected wage is a terminal, durable result, not a debt that can be paid on later replay.
  IF p_skip=1 AND v_failure IN ('insufficient_funds','balance_limit') THEN
   UPDATE frontier_economy_operations SET completed=TRUE,metadata_json=JSON_OBJECT('result',v_failure) WHERE id=v_op;
   COMMIT;SELECT v_failure AS code,CAST(v_op AS CHAR) AS operation_id,0 AS replayed;
  ELSE
   ROLLBACK;SELECT v_failure AS code;
  END IF;
  LEAVE batch;
 END IF;
 SET v_time=UTC_TIMESTAMP(6);
 UPDATE frontier_economy_accounts SET balance_minor=v_balance-v_total WHERE id=p_debit;
 INSERT INTO frontier_economy_ledger(operation_id,account_id,related_account_id,entry_type,amount_minor,currency,balance_before,balance_after,created_at)
 VALUES(v_op,p_debit,NULL,'debit',v_total,'USD',v_balance,v_balance-v_total,v_time);
 SET v_i=0;
 WHILE v_i<v_count DO
  SET v_id=CAST(JSON_UNQUOTE(JSON_EXTRACT(p_payments,CONCAT('$[',v_i,'][0]'))) AS UNSIGNED);
  SET v_amount=CAST(JSON_UNQUOTE(JSON_EXTRACT(p_payments,CONCAT('$[',v_i,'][1]'))) AS UNSIGNED);
  SELECT balance_minor INTO v_credit FROM frontier_economy_accounts WHERE id=v_id FOR UPDATE;
  UPDATE frontier_economy_accounts SET balance_minor=v_credit+v_amount WHERE id=v_id;
  INSERT INTO frontier_economy_ledger(operation_id,account_id,related_account_id,entry_type,amount_minor,currency,balance_before,balance_after,created_at)
  VALUES(v_op,v_id,p_debit,'credit',v_amount,'USD',v_credit,v_credit+v_amount,v_time);
  SET v_i=v_i+1;
 END WHILE;
 UPDATE frontier_economy_operations SET completed=TRUE,metadata_json=JSON_OBJECT('result','ok') WHERE id=v_op;
 COMMIT;
 SELECT 'ok' AS code,CAST(v_op AS CHAR) AS operation_id,0 AS replayed;
END//
DELIMITER ;
