-- Company adapter to the existing market, contracts, escrow and inventory workers.
-- No parallel market or synthetic character inventory.
local core,inventory=exports.frontier_core,exports.frontier_inventory
local Q,S,U=MySQL.query.await,MySQL.single.await,MySQL.update.await
local cfg=TradeConfig
local function id(v) return type(v)=='string' and #v==36 and v:match('^[a-f0-9-]+$') end
local function integer(v,lo,hi) return type(v)=='number' and v%1==0 and v>=lo and v<=hi end
local function farmSaleAllowed(id,item) return not cfg.Agricultural[item] or exports.frontier_business:VerifyLicense('company',id,'agriculture') end
local function allowedCaller() return GetInvokingResource()=='frontier_business' end
local function fresh() return MySQL.scalar.await('SELECT UUID()') end
local function procedure(name,a,ref,parent,actor,value,quote)
 local rows=Q('CALL '..name..'(?,?,?,?,?,?)',{a,ref,parent or '',actor or '',value or 0,quote or 0})
 return rows and rows[1] and rows[1][1] and rows[1][1].code=='ok'
end
local function contract(a,ref,parent,actor,value,quote) return procedure('frontier_trade_contract_v1',a,ref,parent,actor,value,quote) end
local function sale(a,ref,parent,actor,bank,qty) return procedure('frontier_trade_sale_v1',a,ref,parent,actor,bank,qty) end
local function route(ref,company,fixture)
 U('INSERT INTO fb_trade_routes(reference_id,company_id,fixture_id,created) VALUES(?,?,?,?)',{ref,company,fixture,os.time()})
end
local function routeFor(ref,company)
 return MySQL.scalar.await('SELECT fixture_id FROM fb_trade_routes WHERE reference_id=? AND company_id=?',{ref,company})
end
local function active(actor)
 local b=S('SELECT status FROM fb_companies WHERE id=?',{actor});return not b or b.status=='active'
end
local function fixture(src,company,fid,permission,physical)
 if type(fid)~='string' then return false end
 return exports.frontier_business:AuthorizeTradeFixture(src,company,fid,permission,physical)
end
local function claim(src,company,ref,kind,physical)
 local row
 if kind=='delivery' then
  row=S([[SELECT d.id,d.quantity,d.claimed_at,r.item_id,r.id AS route_id FROM frontier_trade_deliveries d
   JOIN frontier_trade_contracts c ON c.id=d.contract_id JOIN frontier_trade_requests r ON r.id=c.request_id
   WHERE d.id=? AND r.buyer_id=? AND d.state='complete']],{ref,company})
 else
  row=S([[SELECT s.id,s.quantity,s.claimed_at,o.item_id,s.id AS route_id FROM frontier_trade_sales s
   JOIN frontier_trade_offers o ON o.id=s.offer_id WHERE s.id=? AND s.buyer_id=? AND s.state='complete']],{ref,company})
 end
 if not row then return false,'Purchase unavailable' end
 if row.claimed_at then return true,'Already collected' end
 local fid=routeFor(row.route_id,company)
 if not fid or physical and not fixture(src,company,fid,'deposit',true) then return false,'Approach the authorized destination storage' end
 local ok,e=inventory:ClaimTradeDelivery(row.id,company,row.item_id,tonumber(row.quantity))
 if not ok then return false,e end
 if kind=='delivery' then U('UPDATE frontier_trade_deliveries SET claimed_at=UTC_TIMESTAMP() WHERE id=? AND claimed_at IS NULL',{ref})
 else U('UPDATE frontier_trade_sales SET claimed_at=UTC_TIMESTAMP() WHERE id=? AND claimed_at IS NULL',{ref}) end
 return true,'Collected'
end
exports('BusinessAction',function(src,company,action,d)
 if not allowedCaller() or type(d)~='table' then return false,'Forbidden' end
 local who=core:GetPlayerCharacterId(src);if not who then return false,'No character' end
 local bank=exports.frontier_business:GetCompanyAccount(company,who,'trade')
 -- Shareholders may recover purchases during the liquidation window, but cannot open new orders.
 if action=='claimDelivery' or action=='claimSale' then
  if not id(d.id) then return false,'Invalid reference' end
  return claim(src,company,d.id,action=='claimDelivery' and 'delivery' or 'sale',true)
 end
 if not bank or not active(company) then return false,'No trade permission' end
 local ref,ok
 if action=='request' or action=='offer' then
  if not cfg.Markets[d.market] or not cfg.Products[d.item] or not integer(d.quantity,1,math.min(cfg.MaxQuantity,1000)) or not integer(d.price,1,math.min(cfg.MaxUnitMinor,10000)) then return false,'Invalid market, product, quantity or price' end
  local cap=d.cap or d.price
  if not integer(cap,d.price,math.min(cfg.MaxUnitMinor,10000)) then return false,'Invalid maximum price' end
  if action=='offer' and not farmSaleAllowed(company,d.item) then return false,'Agriculture license required' end
  local known,def=inventory:GetTradeItemDefinition(d.item);if not known or not def.transferable then return false,'Item not tradeable' end
  if not fixture(src,company,d.fixture,action=='offer' and 'retrieve' or 'deposit',action=='offer') then return false,'Invalid or inaccessible stock location' end
  ref=fresh();route(ref,company,d.fixture)
  if action=='request' then
   U([[INSERT INTO frontier_trade_requests(id,buyer_id,bank_id,market_id,item_id,quantity,price_minor,budget_minor,state,expires_at,retry_at,base_quote_minor,quote_minor,next_quote_at)
     VALUES(?,?,?,?,?,?,?,?,'funding',DATE_ADD(UTC_TIMESTAMP(),INTERVAL ? HOUR),UTC_TIMESTAMP(),?,?,DATE_ADD(UTC_TIMESTAMP(),INTERVAL ? HOUR))]],
     {ref,company,bank,d.market,d.item,d.quantity,cap,d.quantity*cap,cfg.LifetimeHours,d.price,d.price,cfg.EscalationHours})
  else
   U([[INSERT INTO frontier_trade_offers(id,seller_id,seller_bank,market_id,item_id,quantity,available,unit_minor,expires_at)
     VALUES(?,?,?,?,?,?,?,?,DATE_ADD(UTC_TIMESTAMP(),INTERVAL ? HOUR))]],{ref,company,bank,d.market,d.item,d.quantity,d.quantity,d.price,cfg.LifetimeHours})
  end
  return true,ref
 end
 if not id(d.id) then return false,'Invalid reference' end
 if action=='accept' then
  local r=S("SELECT buyer_id,item_id FROM frontier_trade_requests WHERE id=? AND state='open'",{d.id})
  if not r or not active(r.buyer_id) or not farmSaleAllowed(company,r.item_id) then return false,'Request unavailable or agriculture license required' end
  ref=fresh();ok=contract('accept',ref,d.id,company,bank,0)
 elseif action=='deliver' then
  if not integer(d.quantity,1,1000) or not fixture(src,company,d.fixture,'retrieve',true) then return false,'Invalid delivery or stock location' end
  local r=S([[SELECT r.buyer_id,r.item_id FROM frontier_trade_contracts c JOIN frontier_trade_requests r ON r.id=c.request_id WHERE c.id=? AND c.seller_id=? AND c.state='active']],{d.id,company})
  if not r or not active(r.buyer_id) or not farmSaleAllowed(company,r.item_id) then return false,'Contract unavailable or agriculture license required' end
  ref=fresh();route(ref,company,d.fixture);ok=contract('deliver',ref,d.id,company,d.quantity)
 elseif action=='buy' then
  if not integer(d.quantity,1,1000) or not fixture(src,company,d.fixture,'deposit',false) then return false,'Invalid purchase or destination' end
  local r=S("SELECT seller_id FROM frontier_trade_offers WHERE id=? AND state='open'",{d.id})
  if not r or not active(r.seller_id) then return false,'Offer unavailable' end
  ref=fresh();route(ref,company,d.fixture);ok=sale('buy',ref,d.id,company,bank,d.quantity)
 elseif action=='cancelContract' then ok=contract('cancel',d.id,nil,company);ref=d.id
 elseif action=='cancelRequest' then ok=U("UPDATE frontier_trade_requests SET state='refund',retry_at=UTC_TIMESTAMP(),attempts=0 WHERE id=? AND buyer_id=? AND state='open' AND active_contract IS NULL",{d.id,company})==1;ref=d.id
 elseif action=='cancelOffer' then ok=U("UPDATE frontier_trade_offers SET state='return',retry_at=UTC_TIMESTAMP() WHERE id=? AND seller_id=? AND state='open' AND active_sale IS NULL",{d.id,company})==1;ref=d.id
 else return false,'Unknown trade action' end
 return ok==true,ok and ref or 'Operation unavailable'
end)
exports('BusinessSnapshot',function(company)
 if not allowedCaller() then return end
 return {markets=cfg.Markets,products=cfg.Products,
 requests=Q([[SELECT id,market_id,item_id,quantity-settled_quantity AS remaining,COALESCE(quote_minor,price_minor) AS price,state,buyer_id,active_contract FROM frontier_trade_requests WHERE (state='open' AND expires_at>UTC_TIMESTAMP()) OR buyer_id=? ORDER BY expires_at DESC LIMIT 100]],{company}),
 offers=Q([[SELECT id,market_id,item_id,available,unit_minor AS price,state,seller_id,active_sale FROM frontier_trade_offers WHERE (state='open' AND expires_at>UTC_TIMESTAMP()) OR seller_id=? ORDER BY expires_at DESC LIMIT 100]],{company}),
 contracts=Q([[SELECT c.id,c.seller_id,r.buyer_id,c.state,c.active_delivery,r.item_id,r.quantity-r.settled_quantity AS remaining,c.unit_minor AS price FROM frontier_trade_contracts c JOIN frontier_trade_requests r ON r.id=c.request_id WHERE c.seller_id=? OR r.buyer_id=? ORDER BY c.due_at DESC LIMIT 60]],{company,company}),
 deliveries=Q([[SELECT d.id,d.quantity,d.state,d.claimed_at,r.item_id,r.buyer_id,c.seller_id FROM frontier_trade_deliveries d JOIN frontier_trade_contracts c ON c.id=d.contract_id JOIN frontier_trade_requests r ON r.id=c.request_id WHERE c.seller_id=? OR r.buyer_id=? ORDER BY d.retry_at DESC LIMIT 60]],{company,company}),
 sales=Q([[SELECT s.id,s.quantity,s.state,s.claimed_at,o.item_id,s.buyer_id,o.seller_id FROM frontier_trade_sales s JOIN frontier_trade_offers o ON o.id=s.offer_id WHERE s.buyer_id=? OR o.seller_id=? ORDER BY s.retry_at DESC LIMIT 60]],{company,company})}
end)
-- Closing a company never interrupts a stock/payment transition. Settle those first.
exports('DrainBusiness',function(company,expired)
 if not allowedCaller() then return false end
 for _,v in ipairs(Q([[SELECT c.id FROM frontier_trade_contracts c JOIN frontier_trade_requests r ON r.id=c.request_id WHERE c.state='active' AND c.active_delivery IS NULL AND (c.seller_id=? OR r.buyer_id=?) LIMIT 100]],{company,company})) do contract('cancel',v.id,nil,company) end
 U("UPDATE frontier_trade_requests SET state='refund',retry_at=UTC_TIMESTAMP(),attempts=0 WHERE buyer_id=? AND state='open' AND active_contract IS NULL",{company})
 U("UPDATE frontier_trade_offers SET state='return',retry_at=UTC_TIMESTAMP() WHERE seller_id=? AND state='open' AND active_sale IS NULL",{company})
 if expired then
  -- At the deadline the Inventory adapter confiscates these company-owned escrow goods instead of moving them to a player.
  for _,v in ipairs(Q([[SELECT d.id FROM frontier_trade_deliveries d JOIN frontier_trade_contracts c ON c.id=d.contract_id JOIN frontier_trade_requests r ON r.id=c.request_id WHERE r.buyer_id=? AND d.state='complete' AND d.claimed_at IS NULL LIMIT 100]],{company})) do claim(0,company,v.id,'delivery',false) end
  for _,v in ipairs(Q("SELECT id FROM frontier_trade_sales WHERE buyer_id=? AND state='complete' AND claimed_at IS NULL LIMIT 100",{company})) do claim(0,company,v.id,'sale',false) end
 end
 local pending=MySQL.scalar.await([[SELECT
 (SELECT COUNT(*) FROM frontier_trade_requests WHERE buyer_id=? AND state IN ('funding','open','refund'))+
 (SELECT COUNT(*) FROM frontier_trade_offers WHERE seller_id=? AND state IN ('stock','open','return'))+
 (SELECT COUNT(*) FROM frontier_trade_contracts c JOIN frontier_trade_requests r ON r.id=c.request_id WHERE c.state='active' AND (c.seller_id=? OR r.buyer_id=?))+
 (SELECT COUNT(*) FROM frontier_trade_deliveries d JOIN frontier_trade_contracts c ON c.id=d.contract_id JOIN frontier_trade_requests r ON r.id=c.request_id WHERE r.buyer_id=? AND d.state='complete' AND d.claimed_at IS NULL)+
 (SELECT COUNT(*) FROM frontier_trade_sales s JOIN frontier_trade_offers o ON o.id=s.offer_id WHERE (s.buyer_id=? OR o.seller_id=?) AND s.state IN ('stock','payment','reverse'))+
 (SELECT COUNT(*) FROM frontier_trade_sales WHERE buyer_id=? AND state='complete' AND claimed_at IS NULL)]],{company,company,company,company,company,company,company,company})
 return tonumber(pending)==0
end)
exports('BusinessFixtureBusy',function(fid)
 if not allowedCaller() then return true end
 local n=MySQL.scalar.await([[SELECT
 (SELECT COUNT(*) FROM fb_trade_routes x JOIN frontier_trade_requests r ON r.id=x.reference_id WHERE x.fixture_id=? AND (r.state IN ('funding','open','refund') OR EXISTS(SELECT 1 FROM frontier_trade_deliveries d JOIN frontier_trade_contracts c ON c.id=d.contract_id WHERE c.request_id=r.id AND d.state='complete' AND d.claimed_at IS NULL)))+
 (SELECT COUNT(*) FROM fb_trade_routes x JOIN frontier_trade_offers o ON o.id=x.reference_id WHERE x.fixture_id=? AND o.state IN ('stock','open','return'))+
 (SELECT COUNT(*) FROM fb_trade_routes x JOIN frontier_trade_deliveries d ON d.id=x.reference_id WHERE x.fixture_id=? AND d.state IN ('stock','payment'))+
 (SELECT COUNT(*) FROM fb_trade_routes x JOIN frontier_trade_sales s ON s.id=x.reference_id WHERE x.fixture_id=? AND (s.state IN ('stock','payment','reverse') OR s.state='complete' AND s.claimed_at IS NULL))]],{fid,fid,fid,fid})
 return tonumber(n)~=0
end)

RegisterCommand('handelspferde',function(src)
 if src>0 and GetResourceState('frontier_farming')=='started' then exports.frontier_farming:OpenHorseMarket(src) end
end,false)
