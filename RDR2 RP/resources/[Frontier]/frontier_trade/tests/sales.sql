-- Run only in a fresh disposable schema after Trade migration 003.
SET @o='00000000-0000-0000-0000-000000000001', @s='00000000-0000-0000-0000-000000000002', @t='00000000-0000-0000-0000-000000000003';
INSERT INTO frontier_trade_offers (id,seller_id,seller_bank,market_id,item_id,quantity,available,unit_minor,expires_at,state)
VALUES (@o,'seller',22,'valentine','bread',10,10,25,UTC_TIMESTAMP()+INTERVAL 1 DAY,'open');
CALL frontier_trade_sale_v1('buy',@s,@o,'seller',22,4);
CALL frontier_trade_sale_v1('buy',@s,@o,'buyer',11,4);
CALL frontier_trade_sale_v1('buy',@t,@o,'another',33,4);
UPDATE frontier_trade_sales SET state='payment' WHERE id=@s;
CALL frontier_trade_sale_v1('complete',@s,'','',0,0);
CALL frontier_trade_sale_v1('complete',@s,'','',0,0);
SELECT CONCAT('remaining=',available) FROM frontier_trade_offers WHERE id=@o;
CALL frontier_trade_sale_v1('buy',@t,@o,'another',33,6);
UPDATE frontier_trade_sales SET state='reverse' WHERE id=@t;
CALL frontier_trade_sale_v1('reject',@t,'','',0,0);
SELECT CONCAT('after-rejection=',available,':',IF(active_sale IS NULL,'released','locked')) FROM frontier_trade_offers WHERE id=@o;
