local L=LogisticsRuntime
local C=L.C
local terminal={complete=true,cancelled=true,failed=true}
local function contract(id)
 if type(id)=='string' and #id==36 and id:match('^[a-f0-9-]+$') then return L.S('SELECT * FROM fl_contracts WHERE id=?',{id}) end
end
local function update(c,state,issue)
 L.U('UPDATE fl_contracts SET state=?,issue=? WHERE id=? AND state=?',{state,tostring(issue or ''):sub(1,255),c.id,c.state})
end
local function authority(src,typ,id,perm)
 return typ=='character' and L.cid(src)==id or typ=='company' and L.B:HasCompanyPermission(id,L.cid(src),perm)==true
end
local function stock(src,id,perm,all)
 for _,s in ipairs(L.B:LogisticsStock(src,all)) do if s.id==id and s[perm] then return s end end
end
local function nearStock(src,w,id)
 local p=L.B:LogisticsStockPoint(id)
 return p and w and w.state=='world' and L.near(src,p,C.InteractionDistance) and L.near(src,L.point(w),C.InteractionDistance) and L.dist(p,L.point(w))<=C.LoadDistance and L.stationary(w)
end
local function reservePlan(src,origin,route,lines,key,revision)
 local ok,box=L.I:LogisticsRead('s_'..origin);L.check(ok,'Origin stock unavailable')
 L.check(revision~=nil and revision==box.revision,'Origin stock changed; refresh and select cargo again')
 local found,freight=L.I:LogisticsRead(route);L.check(found,'Freight hold unavailable')
 L.check(type(lines)=='table' and #lines>=1 and #lines<=60,'Select cargo stacks')
 local bySlot={};for _,s in ipairs(box.slots) do bySlot[s.slot]=s end
 local plan={lines={},revisions={['s_'..origin]=box.revision,[route]=freight.revision},fingerprint='freight:'..key}
 for _,v in ipairs(lines) do
  L.check(type(v)=='table' and L.R.integer(v.slot,1,200) and L.R.integer(v.quantity,1,10000),'Invalid freight quantity')
  local s=bySlot[v.slot];L.check(s,'Source stack missing')
  plan.lines[#plan.lines+1]={from='s_'..origin,to=route,slot=s.slot,item=s.item,instance=s.instance,metadata=s.metadata,quantity=v.quantity}
 end
 local valid,metrics=L.I:LogisticsPlan('lg:'..key..':reserve',plan,true);L.check(valid,metrics)
 return plan,metrics
end
function L.createContract(src,d)
 local origin=stock(src,d.origin,'retrieve',false);local dest=stock(src,d.destination,'deposit',true)
 L.check(origin and dest and origin.id~=dest.id,'Select an accessible origin and destination warehouse')
 L.check(origin.ownerType==dest.ownerType and origin.ownerId==dest.ownerId,'Both warehouses must belong to the customer')
 L.check(authority(src,origin.ownerType,origin.ownerId,'trade'),'Trade permission required')
 local reward=tonumber(d.reward);local hours=tonumber(d.hours)
 L.check(L.R.integer(reward,1,1000000) and L.R.integer(hours,1,168),'Invalid reward or deadline')
 local bank=L.account(src,origin.ownerType,origin.ownerId,'finance');L.check(bank,'Finance permission required')
 local id=L.uuid(true);local route=L.freightRoute(id)
 L.check(L.I:LogisticsEnsure(route,60,1200000),'Freight hold unavailable')
 local plan,metrics=reservePlan(src,origin.id,route,d.lines,id,d.revision)
 L.U("INSERT INTO fl_contracts(id,customer_type,customer_id,customer_bank,origin_id,destination_id,reward,payload,state,deadline,created_at) VALUES(?,?,?,?,?,?,?,?,'fund',?,?)",{id,origin.ownerType,origin.ownerId,bank,origin.id,dest.id,reward,json.encode({plan=plan,grams=metrics.grams,units=metrics.units}),L.now()+hours*3600,L.now()})
 return id
end
function L.acceptContract(src,w,id)
 local c=contract(id);L.check(c and c.state=='open' and tonumber(c.deadline)>L.now(),'Contract unavailable')
 L.check(w and w.state=='world' and L.right(src,w,'trade') and L.licensed(w.owner_type,w.owner_id),'Licensed carrier wagon required')
 L.check(L.near(src,L.point(w),C.InteractionDistance) and L.stationary(w) and not L.wagonBusy(w.id),'Approach your stationary wagon')
 L.check(c.customer_type~=w.owner_type or c.customer_id~=w.owner_id,'Cannot carry your own paid contract')
 L.check(#L.freight(w.id)==0,'Only one freight contract per wagon')
 local ok,b=L.I:LogisticsRead(L.route(w.id));local got,f=L.I:LogisticsRead(L.freightRoute(c.id))
 L.check(ok and got and b.weight+f.weight<=b.weightLimit and #b.slots+#f.slots<=b.capacity,'Not enough free wagon capacity')
 local bank=L.account(src,w.owner_type,w.owner_id,'trade');L.check(bank,'Carrier account unavailable')
 L.U("UPDATE fl_contracts SET state='pickup',carrier_type=?,carrier_id=?,carrier_bank=?,carrier_actor=?,wagon_id=? WHERE id=? AND state='open'",{w.owner_type,w.owner_id,bank,L.cid(src),w.id,c.id})
 L.broadcastWagon(w)
end
function L.contractAction(src,w,id,a)
 local c=contract(id);L.check(c,'Contract unavailable')
 if a=='stealFreight' then
  L.check(w and c.wagon_id==w.id and c.state=='in_transit' and not L.right(src,w,'trade') and tonumber(w.locked)==0 and L.access(src,w,'retrieve') and not L.wagonBusy(w.id),'Unlocked loaded wagon required')
  update(c,'steal','Freight stolen from wagon');return
 end
 if a=='cancelContract' then
  L.check(authority(src,c.customer_type,c.customer_id,'trade') and c.state=='open','Only unaccepted contracts may be cancelled')
  update(c,'return');return
 end
 L.check(w and w.state=='world' and c.wagon_id==w.id and authority(src,c.carrier_type,c.carrier_id,'trade') and L.right(src,w,'trade') and L.near(src,L.point(w),C.InteractionDistance) and L.stationary(w) and not L.wagonBusy(w.id),'Approach your stationary carrier wagon')
 if a=='pickup' then
  L.check(c.state=='pickup' and tonumber(c.deadline)>L.now() and nearStock(src,w,c.origin_id),'Approach origin with the assigned wagon before deadline')
  -- Cargo was frozen at order creation. Pickup associates the reserved hold with the physical wagon.
  update(c,'in_transit');L.broadcastWagon(w)
 elseif a=='deliver' then
  L.check(c.state=='in_transit' and nearStock(src,w,c.destination_id),'Approach destination with the assigned wagon')
  update(c,'deliver')
 elseif a=='abandonContract' then
  L.check(c.state=='pickup','Loaded freight must be delivered or returned to origin')
  update(c,'return')
 elseif a=='returnFreight' then
  L.check(c.state=='in_transit' and nearStock(src,w,c.origin_id),'Return freight at its original warehouse')
  update(c,'return')
 else L.check(false,'Unknown contract action') end
end
function L.contractView(src,w)
 local who=L.cid(src);local out={}
 for _,c in ipairs(L.Q("SELECT * FROM fl_contracts WHERE state NOT IN ('complete','cancelled','failed') ORDER BY created_at DESC LIMIT 100")) do
  local customer=authority(src,c.customer_type,c.customer_id,'trade')
  local carrier=c.carrier_id and authority(src,c.carrier_type,c.carrier_id,'trade')
  local theft=w and c.wagon_id==w.id and c.state=='in_transit' and not L.right(src,w,'trade') and tonumber(w.locked)==0
  if c.state=='open' or customer or carrier or theft then
   local d=json.decode(c.payload);local origin=L.B:LogisticsStockPoint(c.origin_id);local dest=L.B:LogisticsStockPoint(c.destination_id)
   out[#out+1]={id=c.id,state=c.state,origin=origin and origin.name or c.origin_id,destination=dest and dest.name or c.destination_id,
    originPoint=origin,destinationPoint=dest,reward=c.reward,deadline=c.deadline,grams=d.grams,units=d.units,customer=customer,carrier=carrier==true,wagon=c.wagon_id,issue=c.issue,
    canSteal=theft==true,canAccept=w and c.state=='open' and tonumber(c.deadline)>L.now() and (c.customer_type~=w.owner_type or c.customer_id~=w.owner_id) and L.right(src,w,'trade') and L.licensed(w.owner_type,w.owner_id) or false}
  end
 end
 return out
end
function L.contractTick()
 for _,c in ipairs(L.Q("SELECT * FROM fl_contracts WHERE state NOT IN ('complete','cancelled','failed','wreck') ORDER BY created_at,id LIMIT 100")) do
  local ok,err=pcall(function()
   local d=json.decode(c.payload)
   if c.state=='fund' then
    local paid,why=L.ECO:FundTradeHold(c.id,c.customer_id,tonumber(c.customer_bank),tonumber(c.reward))
    if paid then update(c,'reserve') elseif why=='insufficient_funds' then update(c,'failed',why) else L.check(false,why) end
   elseif c.state=='reserve' then
    local moved,why=L.I:LogisticsPlan('lg:'..c.id..':reserve',d.plan,false)
    if moved then update(c,'open')
    elseif why=='conflict' or why=='forbidden' or why=='weight' or why=='slots' or why=='capacity' or why=='insufficient_stock' then update(c,'refund','Stock changed: '..tostring(why))
    else L.check(false,why) end
   elseif (c.state=='open' or c.state=='pickup') and tonumber(c.deadline)<=L.now() then
    update(c,'return','Pickup deadline expired')
   elseif c.state=='return' then
    local p=L.B:LogisticsStockPoint(c.origin_id);L.check(p and p.ownerType==c.customer_type and p.ownerId==c.customer_id,'Original warehouse unavailable; restore it for freight recovery')
    local moved,why=L.I:LogisticsMoveAll('lg:'..c.id..':return',L.freightRoute(c.id),'s_'..c.origin_id)
    L.check(moved,why);update(c,'refund')
    local w=c.wagon_id and L.wagon(c.wagon_id);if w then L.broadcastWagon(w) end
   elseif c.state=='steal' then
    local w=L.wagon(c.wagon_id);L.check(w and (w.state=='world' or w.state=='wreck_pending'),'Wagon unavailable')
    local moved,why=L.I:LogisticsMoveAll('lg:'..c.id..':steal',L.freightRoute(c.id),L.route(w.id));L.check(moved,why)
    update(c,'refund','Freight stolen; carrier not paid');L.broadcastWagon(w)
   elseif c.state=='deliver' then
    local p=L.B:LogisticsStockPoint(c.destination_id);L.check(p and p.ownerType==c.customer_type and p.ownerId==c.customer_id,'Destination unavailable; restore warehouse')
    local moved,why=L.I:LogisticsMoveAll('lg:'..c.id..':deliver',L.freightRoute(c.id),'s_'..c.destination_id)
    L.check(moved,why);update(c,'pay')
    local w=c.wagon_id and L.wagon(c.wagon_id);if w then L.broadcastWagon(w) end
   elseif c.state=='pay' then
    local paid,why=L.ECO:PayTradeDelivery(c.id,c.id,c.carrier_id,tonumber(c.carrier_bank),tonumber(c.reward));L.check(paid,why)
    update(c,'xp')
   elseif c.state=='xp' then
    local granted,why=L.K:GrantXP(c.carrier_actor,'transportation',math.min(1000,math.max(10,math.floor(d.grams/10000))),c.id)
    L.check(granted,why);update(c,'complete')
   elseif c.state=='refund' then
    local paid,why=L.ECO:ReleaseTradeHold(c.id,c.customer_id,tonumber(c.customer_bank),tonumber(c.reward));L.check(paid,why)
    update(c,'cancelled',c.issue)
   end
  end)
  if not ok then L.U('UPDATE fl_contracts SET issue=? WHERE id=?',{tostring(err):sub(1,255),c.id}) end
 end
end
exports('StockBound',function(id)
 if GetInvokingResource()~='frontier_business' or not L.ready then return true end
 return L.V("SELECT id FROM fl_contracts WHERE (origin_id=? OR destination_id=?) AND state NOT IN ('complete','cancelled','failed') LIMIT 1",{id,id})~=nil
end)
