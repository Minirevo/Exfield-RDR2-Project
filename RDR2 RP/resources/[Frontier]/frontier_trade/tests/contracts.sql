-- Run in a fresh disposable schema after Trade 001 and 002.
SET @request = '00000000-0000-0000-0000-000000000001';
SET @contract = '00000000-0000-0000-0000-000000000002';
SET @first = '00000000-0000-0000-0000-000000000003';
SET @second = '00000000-0000-0000-0000-000000000004';
SET @other = '00000000-0000-0000-0000-000000000005';
INSERT INTO frontier_trade_requests
(id,buyer_id,bank_id,market_id,item_id,quantity,price_minor,budget_minor,state,expires_at,retry_at)
VALUES (@request,'buyer',1,'valentine','bread',10,25,250,'open',UTC_TIMESTAMP()+INTERVAL 1 DAY,UTC_TIMESTAMP());
CALL frontier_trade_contract_v1('accept',@contract,@request,'seller',2,0);
CALL frontier_trade_contract_v1('accept',@other,@request,'other',3,0);
CALL frontier_trade_contract_v1('deliver',@first,@contract,'other',4,0);
CALL frontier_trade_contract_v1('deliver',@first,@contract,'seller',4,0);
CALL frontier_trade_contract_v1('deliver',@second,@contract,'seller',2,0);
UPDATE frontier_trade_deliveries SET state='payment' WHERE id=@first;
CALL frontier_trade_contract_v1('complete',@first,'','',0,0);
CALL frontier_trade_contract_v1('complete',@first,'','',0,0);
SELECT CONCAT('partial:', settled_quantity, ':', state) FROM frontier_trade_requests WHERE id=@request;
CALL frontier_trade_contract_v1('deliver',@second,@contract,'seller',7,0);
CALL frontier_trade_contract_v1('deliver',@second,@contract,'seller',6,0);
UPDATE frontier_trade_deliveries SET state='payment' WHERE id=@second;
CALL frontier_trade_contract_v1('complete',@second,'','',0,0);
SELECT CONCAT('final:', settled_quantity, ':', state) FROM frontier_trade_requests WHERE id=@request;

INSERT INTO frontier_trade_requests
(id,buyer_id,bank_id,market_id,item_id,quantity,price_minor,budget_minor,state,expires_at,retry_at)
VALUES (@other,'buyer',1,'valentine','bread',10,25,250,'open',UTC_TIMESTAMP()+INTERVAL 1 DAY,UTC_TIMESTAMP());
CALL frontier_trade_contract_v1('accept',@first,@other,'seller',2,0);
UPDATE frontier_trade_contracts SET due_at=UTC_TIMESTAMP()-INTERVAL 1 SECOND WHERE id=@first;
CALL frontier_trade_contract_v1('expire',@first,'','',0,0);
SELECT CONCAT('expired:', c.state, ':', IF(r.active_contract IS NULL,'released','locked'))
FROM frontier_trade_contracts c JOIN frontier_trade_requests r ON r.id=c.request_id WHERE c.id=@first;

UPDATE frontier_trade_requests SET base_quote_minor=10,quote_minor=10,state='funding' WHERE id=@other;
UPDATE frontier_trade_requests SET state='open' WHERE id=@other;
UPDATE frontier_trade_requests SET quote_minor=12 WHERE id=@other;
CALL frontier_trade_contract_v1('accept',@second,@other,'seller',2,10);
CALL frontier_trade_contract_v1('accept',@second,@other,'seller',2,12);
SELECT CONCAT('quote:',unit_minor,':', (SELECT COUNT(*) FROM frontier_trade_price_history WHERE request_id=@other)) FROM frontier_trade_contracts WHERE id=@second;
CALL frontier_trade_contract_v1('deliver',@other,@second,'seller',10,0);
UPDATE frontier_trade_deliveries SET state='payment' WHERE id=@other;
CALL frontier_trade_contract_v1('complete',@other,'','',0,0);
SELECT CONCAT('refund:',budget_minor-spent_minor,':',state) FROM frontier_trade_requests WHERE id=@other;
