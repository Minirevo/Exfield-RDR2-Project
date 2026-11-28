local C,R=ShopConfig,ShopRules
local E='frontier_shops:'
local inv,eco,core=exports.frontier_inventory,exports.frontier_economy,exports.frontier_core
local Q,S,U,V=MySQL.query.await,MySQL.single.await,MySQL.update.await,MySQL.scalar.await
local ready,busy=false,false
local sessions,last={},{}
local function cid(src) return core:GetPlayerCharacterId(src) end
local function need(ok,msg) if not ok then error(msg,0) end return ok end
local function msg(src,m) TriggerClientEvent(E..'notice',src,tostring(m)) end
local function uuid() return V('SELECT LOWER(UUID())') end
local function position(src) local ok,p=inv:ShopPosition(src);if ok then return p end end
local function valid(src,v)
 return v and cid(src)==v.character and R.near(position(src),C.sites[v.site],C.reach)
end
local function available(site)
 local out={}
 for id,d in pairs(C.catalogs[C.sites[site].kind]) do
  local ok,def=inv:ShopDefinition(id)
  if ok then
   out[id]={id=id,name=d.name,description=def.description,grams=def.grams,maxStack=def.maxStack,category=d.category,buy=d.buy,sell=d.sell,icon=d.icon}
  end
 end
 return out
end
local function view(src,v)
 if sessions[src]~=v or not valid(src,v) then sessions[src]=nil;TriggerClientEvent(E..'close',src);return end
 local ok,accounts=eco:GetCharacterAccounts(src);need(ok and accounts.characterId==v.character,'Cash account unavailable.')
 local ok2,bag=inv:GetInventory(src);need(ok2,'Inventory unavailable.')
 local counts={};for _,e in pairs(bag.slots or {}) do counts[e.item]=(counts[e.item] or 0)+e.quantity end
 local catalog=available(v.site)
 local list={};for id,d in pairs(catalog) do d.owned=counts[id] or 0;list[#list+1]=d end
 table.sort(list,function(a,b)return a.category==b.category and a.name<b.name or a.category<b.category end)
 local orders=Q("SELECT id,mode,state,total,lines,issue,receipt,created FROM frontier_shops_orders WHERE character_id=? ORDER BY created DESC,id DESC LIMIT 40",{v.character})
 for _,o in ipairs(orders) do o.lines=json.decode(o.lines) end
 v.ticket=uuid()
 if sessions[src]==v and valid(src,v) then TriggerClientEvent(E..'view',src,{ticket=v.ticket,shop=C.sites[v.site].name,kind=C.types[C.sites[v.site].kind],cash=accounts.cash.balance_minor,weight=bag.weight,weightLimit=bag.weightLimit,catalog=list,orders=orders,maxQuantity=C.maxQuantity}) end
end
local function state(id,old,new,issue)
 return U('UPDATE frontier_shops_orders SET state=?,issue=? WHERE id=? AND state=?',{new,issue or '',id,old})==1
end
local function options(o,op) return {key='shops:'..o.id..':'..op,reason='Frontier shop '..op,reference=o.id} end
local function definite(e) return ({slots=true,weight=true,capacity=true,quantity=true,insufficient_stock=true,invalid_item=true,invalid_request=true,forbidden=true,invalid_metadata=true})[e]==true end
local function progress(o)
 local amount,account=tonumber(o.total),tonumber(o.account)
 if o.state=='debit' then
  local ok,r=eco:DebitAccount(account,amount,options(o,'purchase'))
  if ok then state(o.id,'debit','grant')
  elseif r=='insufficient_funds' or definite(r) or r=='invalid_account' or r=='invalid_amount' then state(o.id,'debit','failed',r)
  else return false,r end
 elseif o.state=='grant' then
  local ok,r=inv:ShopBasket(o.character_id,o.id,'grant',o.lines)
  if ok then state(o.id,'grant','done')
  elseif definite(r) then state(o.id,'grant','refund',r)
  else return false,r end
 elseif o.state=='refund' then
  local ok,r=eco:CreditAccount(account,amount,options(o,'refund'))
  if not ok then return false,r end
  U("UPDATE frontier_shops_orders SET state='failed',receipt=? WHERE id=? AND state='refund'",{r.operationId,o.id})
 elseif o.state=='take' then
  local ok,r=inv:ShopBasket(o.character_id,o.id,'take',o.lines)
  if ok then state(o.id,'take','credit')
  elseif definite(r) then state(o.id,'take','failed',r)
  else return false,r end
 elseif o.state=='credit' then
  local ok,r=eco:CreditAccount(account,amount,options(o,'sale'))
  if not ok then return false,r end
  U("UPDATE frontier_shops_orders SET state='done',receipt=? WHERE id=? AND state='credit'",{r.operationId,o.id})
 end
 return true
end
local function advance(id)
 for i=1,4 do
  local o=S('SELECT * FROM frontier_shops_orders WHERE id=?',{id})
  if not o or o.state=='done' or o.state=='failed' then return o end
  local ok,why=progress(o);if not ok then print('[frontier_shops] Pending '..id..': '..tostring(why));return o end
 end
 return S('SELECT * FROM frontier_shops_orders WHERE id=?',{id})
end
local function run(src,fn)
 if not ready then return msg(src,'Shop is not ready. Check server startup.') end
 if busy then return msg(src,'Shop is busy. Try again shortly.') end
 local t=GetGameTimer();if last[src] and t-last[src]<250 then return end;last[src]=t
 busy=true;local ok,err=pcall(fn);busy=false
 if not ok then print('[frontier_shops] '..tostring(err));msg(src,tostring(err)) end
end
RegisterNetEvent(E..'open',function(site)
 local src=source;run(src,function()
  need(type(site)=='string' and C.sites[site],'Unknown shop.')
  local character=need(cid(src),'Load a character first.')
  local v={site=site,character=character};need(valid(src,v),'Move closer to the shop counter.')
  sessions[src]=v;view(src,v)
 end)
end)
RegisterNetEvent(E..'close',function(ticket)
 local v=sessions[source];if v and v.ticket==ticket then sessions[source]=nil end
end)
RegisterNetEvent(E..'refresh',function(ticket)
 local src=source;run(src,function()local v=sessions[src];need(v and v.ticket==ticket and valid(src,v),'Shop session expired.');view(src,v) end)
end)
RegisterNetEvent(E..'checkout',function(ticket,mode,lines)
 local src=source;run(src,function()
  local v=sessions[src];need(v and v.ticket==ticket and valid(src,v),'Shop session expired.')
  local normalized,total=R.basket(available(v.site),mode,lines,C);need(normalized,total)
  local ok,a=eco:GetCharacterAccounts(src);need(ok and a.characterId==v.character,'Cash unavailable.')
  if mode=='buy' then need(a.cash.balance_minor>=total,'Not enough cash.') end
  local payload=json.encode(normalized)
  local checked,why=inv:ShopBasket(v.character,ticket,mode=='buy' and 'previewGrant' or 'previewTake',payload);need(checked,why=='weight' and 'Satchel too heavy.' or why=='slots' and 'Not enough satchel slots.' or why=='insufficient_stock' and 'Not enough goods in your satchel.' or tostring(why))
  need(valid(src,v),'Move closer to the shop.')
  U([[INSERT INTO frontier_shops_orders(id,character_id,shop,mode,state,account,total,lines,created)
   VALUES(?,?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE id=id]],{ticket,v.character,v.site,mode,mode=='buy' and 'debit' or 'take',a.cash.id,total,payload,os.time()})
  local o=advance(ticket)
  if o and o.state=='done' then msg(src,mode=='buy' and 'Purchase complete. Goods are in your satchel.' or 'Sale complete. You received cash.')
  elseif o and o.state=='failed' then msg(src,'Transaction failed or refunded: '..tostring(o.issue))
  else msg(src,'Transaction saved. It will finish automatically; check receipts.') end
  view(src,v)
 end)
end)
AddEventHandler('playerDropped',function()sessions[source]=nil;last[source]=nil end)
MySQL.ready(function()
 local ok,err=pcall(function() S('SELECT id FROM frontier_shops_orders LIMIT 1') end)
 if not ok then print('[frontier_shops] Apply sql/001_shops.sql: '..tostring(err));return end
 ready=true;print('[frontier_shops] Ready')
 CreateThread(function()
  while true do
   Wait(5000)
   if not busy then
    busy=true
    local good,e=pcall(function()
     for _,o in ipairs(Q("SELECT id FROM frontier_shops_orders WHERE state IN ('debit','grant','refund','take','credit') ORDER BY created LIMIT 30")) do advance(o.id) end
    end)
    busy=false;if not good then print('[frontier_shops] Recovery: '..tostring(e)) end
   end
  end
 end)
end)
