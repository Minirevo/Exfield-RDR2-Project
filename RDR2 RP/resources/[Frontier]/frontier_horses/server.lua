local C,R=HorseConfig,HorseRules
local E='frontier_horses:'
local core,eco,inv,biz=exports.frontier_core,exports.frontier_economy,exports.frontier_inventory,exports.frontier_business
local Q,S,U,V=MySQL.query.await,MySQL.single.await,MySQL.update.await,MySQL.scalar.await
local ready,busy=false,false
local active,leases,views,rate={}, {}, {}, {}
local function check(ok,msg) if not ok then error(msg or 'Denied',0) end;return ok end
local function cid(src) return core:GetPlayerCharacterId(src) end
local function tell(src,msg) if src then TriggerClientEvent(E..'notice',src,tostring(msg)) else print('[frontier_horses] '..tostring(msg)) end end
local function uuid() return V('SELECT LOWER(UUID())') end
local function pos(src)
 local p=GetPlayerPed(src);if p==0 or GetPlayerRoutingBucket(src)~=0 or not cid(src) then return end
 if GetResourceState('frontier_medical')=='started' and not exports.frontier_medical:CanAct(src) then return end
 local v=GetEntityCoords(p);return {x=v.x,y=v.y,z=v.z}
end
local function nearest(p,r)
 local best,dist=nil,r or math.huge
 for id,s in pairs(C.sites) do local d=R.distance(p,s);if d<dist then best,dist=id,d end end
 return best
end
local function horse(id) return R.id(id) and S('SELECT * FROM frontier_horses WHERE id=?',{id}) end
local function rec(h) local d=json.decode(h.record);d.gear=d.gear or {};d.name=h.name;return d end
local function allowed(src,h)
 local who=cid(src);return who and h and ((h.owner_type=='character' and h.owner_id==who) or (h.owner_type=='company' and biz:HasCompanyPermission(h.owner_id,who,'trade')))
end
local function assigned(id) return V('SELECT wagon_id FROM fl_harnesses WHERE horse_id=?',{id}) end
local function pending(id)
 return V("SELECT id FROM frontier_horse_orders WHERE state IN ('payment','apply','refund') AND JSON_UNQUOTE(JSON_EXTRACT(payload,'$.horse'))=? LIMIT 1",{id})
end
local function save(h,d) U('UPDATE frontier_horses SET record=?,updated=? WHERE id=?',{json.encode(d),os.time(),h.id}) end
local function run(src,fn)
 if not ready or busy then tell(src,'Stables busy or unavailable.');return end
 busy=true;local ok,e=pcall(fn);busy=false;if not ok then tell(src,e) end
end
local function view(src,site)
 local p=pos(src);if not site or nearest(p,C.reach)~=site then views[src]=nil;return end
 local who=cid(src);local ok,a=eco:GetCharacterAccounts(src);check(ok and a.characterId==who,'Cash unavailable')
 local list={}
 for _,h in ipairs(Q("SELECT * FROM frontier_horses WHERE status<>'dead' ORDER BY name,id")) do
  if allowed(src,h) then local d=rec(h);d.id=h.id;d.name=h.name;d.model=h.model;d.ownerType=h.owner_type;d.ownerId=h.owner_id;d.stable=h.stable;d.status=h.status;d.assigned=assigned(h.id);d.pending=not not pending(h.id);list[#list+1]=d end
 end
 local gear={};for id,d in pairs(C.equipment) do local ok,n=inv:GetItemCount(src,id);gear[id]={name=d.name,price=d.price,slot=d.slot,owned=ok and n or 0} end
 local v={site=site,who=who,ticket=uuid()};views[src]=v
 TriggerClientEvent(E..'view',src,{ticket=v.ticket,site=site,sites=C.sites,horses=list,breeds=C.breeds,gear=gear,cash=a.cash.balance_minor,carePrice=C.carePrice,healPrice=C.healPrice,transferPrice=C.transferPrice})
end
local function finishOrder(o)
 local p=json.decode(o.payload);local amount,account=tonumber(o.amount),tonumber(o.account)
 if o.state=='payment' then
  if amount>0 then
   local ok,e=eco:DebitAccount(account,amount,{key='horse:'..o.id..':pay',reason='Stable purchase',reference=o.id})
   if not ok then if e=='insufficient_funds' or e=='insufficient_balance' then U("UPDATE frontier_horse_orders SET state='failed' WHERE id=?",{o.id}) end;return false,e end
  end
  U("UPDATE frontier_horse_orders SET state='apply' WHERE id=? AND state='payment'",{o.id});o.state='apply'
 end
 if o.state=='refund' then
  local ok,e=eco:CreditAccount(account,amount,{key='horse:'..o.id..':refund',reason='Stable refund',reference=o.id})
  if not ok then return false,e end
  U("UPDATE frontier_horse_orders SET state='failed' WHERE id=?",{o.id});return false,'Refunded'
 end
 if o.state~='apply' then return o.state=='done',o.state end
 if o.kind=='gear' or o.kind=='equip' then
  local mode=o.kind=='gear' and 'grant' or 'take'
  local ok,e=inv:ShopBasket(o.actor,o.id,mode,p.basket)
  if not ok then
   if ({weight=true,slots=true,capacity=true,insufficient_stock=true,invalid_item=true,invalid_request=true,stack_conflict=true})[e] then
    U("UPDATE frontier_horse_orders SET state=? WHERE id=?",{amount>0 and 'refund' or 'failed',o.id})
   end
   return false,e
  end
 end
 local statements={}
 if o.kind=='buy' then
  statements[#statements+1]={query='INSERT IGNORE INTO frontier_horses(id,owner_type,owner_id,stable,status,model,name,record,updated) VALUES(?,?,?,?,?,?,?,?,?)',values={p.horse,'character',o.actor,p.stable,'stored',p.model,p.name,json.encode(p.record),os.time()}}
 elseif o.kind=='equip' or o.kind=='care' or o.kind=='transfer' then
  statements[#statements+1]={query='UPDATE frontier_horses SET record=?,stable=?,updated=? WHERE id=?',values={json.encode(p.record),p.stable,os.time(),p.horse}}
 end
 statements[#statements+1]={query="UPDATE frontier_horse_orders SET state='done' WHERE id=?",values={o.id}}
 check(MySQL.transaction.await(statements),'Stable transaction pending')
 return true,'Completed'
end
local function order(src,id,kind,amount,payload)
 local who=cid(src);local ok,a=eco:GetCharacterAccounts(src);check(ok and a.characterId==who,'Cash unavailable')
 if amount>0 then check(a.cash.balance_minor>=amount,'Not enough cash') end
 local existing=S('SELECT * FROM frontier_horse_orders WHERE id=?',{id})
 if not existing then
  U("INSERT INTO frontier_horse_orders(id,actor,kind,state,account,amount,payload,created) VALUES(?,?,?,'payment',?,?,?,?)",{id,who,kind,a.cash.id,amount,json.encode(payload),os.time()})
  existing=S('SELECT * FROM frontier_horse_orders WHERE id=?',{id})
 end
 check(existing.actor==who,'Invalid order')
 return finishOrder(existing)
end
local function equip(src,h,item)
 local gear=C.equipment[item];check(gear,'Unknown equipment')
 local d=rec(h);check(not d.gear[gear.slot],'Equipment slot already occupied')
 local basket=json.encode({{id=item,quantity=1}});local id=uuid()
 local ok,e=inv:ShopBasket(cid(src),id,'previewTake',basket);check(ok,'You need '..gear.name..' in your satchel')
 d.gear[gear.slot]=item
 return order(src,id,'equip',0,{horse=h.id,record=d,stable=h.stable,basket=basket})
end
local function delete(ped) if ped and ped~=0 and DoesEntityExist(ped) then DeleteEntity(ped) end end
local function store(src,site,dead)
 local m=active[src];if not m then return end
 local h=horse(m.id)
 if h then
  local d=rec(h)
  if dead then d.health=0
  elseif m.ped and DoesEntityExist(m.ped) then
   local hp=GetEntityHealth(m.ped);if hp<=0 then dead=true;d.health=0 end
  end
  U('UPDATE frontier_horses SET status=?,stable=?,record=?,updated=? WHERE id=?',{dead and 'dead' or 'stored',site or h.stable,json.encode(d),os.time(),h.id})
 end
 delete(m.ped);active[src]=nil;leases[src]=nil
 TriggerClientEvent(E..'stored',src)
end
local function spawn(src,h)
 check(not active[src] and not leases[src],'Board your current horse first')
 check(h and h.status=='stored' and allowed(src,h) and not assigned(h.id) and not pending(h.id),'Horse unavailable')
 local d=rec(h);check(R.ride(d),'An adult, healthy horse with a saddle is required')
 local p=check(pos(src),'Cannot retrieve here')
 check(U("UPDATE frontier_horses SET status='out' WHERE id=? AND status='stored'",{h.id})==1,'Horse already in use')
 local token=uuid();local old={};for _,ped in ipairs(GetAllPeds()) do old[ped]=true end
 leases[src]={id=h.id,token=token,point={x=p.x+2,y=p.y,z=p.z+.2},model=h.model,untilTime=os.time()+C.spawnSeconds,old=old}
 active[src]={id=h.id,ped=0,actor=cid(src),last=os.time()}
 TriggerClientEvent(E..'spawn',src,{token=token,model=h.model,point=leases[src].point,horse=d})
end
RegisterNetEvent(E..'spawnAck',function(token,net)
 local src=source;run(src,function()
  local l=leases[src];check(l and l.token==token and os.time()<=l.untilTime and type(net)=='number','Invalid horse lease')
  local ped=NetworkGetEntityFromNetworkId(net);local deadline=GetGameTimer()+3000
  while (not ped or ped==0 or not DoesEntityExist(ped)) and GetGameTimer()<deadline do Wait(50);ped=NetworkGetEntityFromNetworkId(net) end
  check(ped and ped~=0 and DoesEntityExist(ped) and not l.old[ped] and GetEntityType(ped)==1 and NetworkGetEntityOwner(ped)==src,'Horse did not replicate')
  check(GetEntityModel(ped)==joaat(l.model) and GetEntityRoutingBucket(ped)==0 and R.distance(GetEntityCoords(ped),l.point)<12,'Horse validation failed')
  active[src].ped=ped;leases[src]=nil
  pcall(SetEntityOrphanMode,ped,2);Entity(ped).state:set('frontierHorse',l.id,true)
  TriggerClientEvent(E..'accepted',src,net)
 end)
end)
RegisterNetEvent(E..'spawnFail',function(token) local src=source;run(src,function() if leases[src] and leases[src].token==token then store(src);tell(src,'Horse returned to its stable record; retry.') end end) end)
RegisterNetEvent(E..'open',function()local src=source;run(src,function() view(src,check(nearest(pos(src),C.reach),'Approach a stable.')) end)end)
RegisterNetEvent(E..'action',function(ticket,op,d)
 local src=source;run(src,function()
  local v=views[src];check(v and v.ticket==ticket and v.who==cid(src) and nearest(pos(src),C.reach)==v.site,'Stable session expired')
  check(type(d)=='table','Invalid request')
  if op=='refresh' then return view(src,v.site) end
  if op=='buy' then
   local b=check(C.breeds[d.breed],'Unknown breed')
   local id=ticket:gsub('-','');local name=b.name;local genes={};for k,n in pairs(b.genes) do genes[k]=n+math.random(-5,5) end
   local record={id=id,breed=d.breed,sex=d.sex=='male' and 'male' or 'female',age=C.adultAge,genes=genes,health=100,care=100,training=0,trainedAt=0,neglectSeconds=0,gear={}}
   local ok,e=order(src,ticket,'buy',b.price,{horse=id,stable=v.site,model=b.model,name=name,record=record});tell(src,ok and 'Horse purchased and boarded.' or e)
  elseif op=='gear' then
   local g=check(C.equipment[d.item],'Unknown equipment');local basket=json.encode({{id=d.item,quantity=1}})
   local ok,e=inv:ShopBasket(cid(src),ticket,'previewGrant',basket);check(ok,e)
   local done,why=order(src,ticket,'gear',g.price,{basket=basket});tell(src,done and 'Equipment in satchel.' or why)
  elseif op=='board' then
   local m=check(active[src],'No active horse');check(m.ped~=0 and DoesEntityExist(m.ped) and R.distance(GetEntityCoords(m.ped),C.sites[v.site])<=C.storeReach,'Bring your horse to the stable.')
   store(src,v.site);tell(src,'Horse boarded.')
  else
   local h=check(horse(d.id),'Unknown horse');check(allowed(src,h) and not pending(h.id),'Horse unavailable')
   local r=rec(h)
   if op=='transfer' then
    check(h.status=='stored' and not assigned(h.id) and C.sites[d.site] and d.site==v.site and h.stable~=v.site,'Select a boarded horse at another stable.')
    local ok,e=order(src,ticket,'transfer',C.transferPrice,{horse=h.id,stable=v.site,record=r});tell(src,ok and 'Horse transferred.' or e)
   else
    check(h.status=='stored' and h.stable==v.site and not assigned(h.id),'Horse must be boarded here and unassigned.')
    if op=='retrieve' then spawn(src,h);views[src]=nil;return
    elseif op=='rename' then check(R.name(d.name),'Invalid name');U('UPDATE frontier_horses SET name=? WHERE id=?',{d.name,h.id})
    elseif op=='equip' then local ok,e=equip(src,h,d.item);tell(src,ok and 'Equipment fitted.' or e)
    elseif op=='care' or op=='heal' then
     if op=='care' then r.care=100 else r.health=100 end
     local ok,e=order(src,ticket,'care',op=='care' and C.carePrice or C.healPrice,{horse=h.id,stable=h.stable,record=r});tell(src,ok and 'Service complete.' or e)
    else error('Unknown stable action',0) end
   end
  end
  view(src,v.site)
 end)
end)
RegisterNetEvent(E..'call',function()
 local src=source;run(src,function()
  local m=check(active[src],'Retrieve a horse at a stable first')
  check(m.ped~=0 and DoesEntityExist(m.ped) and R.distance(pos(src),GetEntityCoords(m.ped))<=100,'Your horse is too far away.')
  TriggerClientEvent(E..'follow',src,NetworkGetNetworkIdFromEntity(m.ped))
 end)
end)
RegisterNetEvent(E..'bags',function()
 local src=source;run(src,function()
  local m=check(active[src],'No active horse');local h=check(horse(m.id),'Horse unavailable');check(allowed(src,h) and rec(h).gear.bags,'Fit saddlebags first')
  check(m.ped~=0 and DoesEntityExist(m.ped) and R.distance(pos(src),GetEntityCoords(m.ped))<=4,'Approach your horse')
  TriggerClientEvent(E..'close',src);local ok,e=inv:HorseStorage(src,'horse_'..h.id);check(ok,e)
 end)
end)
exports('CanAccessSaddlebags',function(src,id)
 if GetInvokingResource()~='frontier_inventory' or not ready then return false end
 local m=active[src];if not m or id~='horse_'..m.id or m.ped==0 or not DoesEntityExist(m.ped) or not (R.distance(pos(src),GetEntityCoords(m.ped))<=4) then return false end
 local h=horse(m.id);return allowed(src,h) and rec(h).gear.bags~=nil
end)
-- Called only by Farming after its atomic transfer removes the certificate from its enclosure.
exports('RanchRelease',function(src,id)
 if GetInvokingResource()~='frontier_farming' or not ready or busy then return false,'Stables unavailable' end
 busy=true;local ok,e=pcall(function()
  local h=check(horse(id),'Horse transfer not found');check(allowed(src,h),'No ownership')
  if not rec(h).gear.saddle then local done,why=equip(src,h,'horse_saddle');check(done,why);h=horse(id) end
  spawn(src,h)
 end);busy=false;return ok,ok and 'Horse released.' or tostring(e)
end)
exports('RanchDestination',function(src)
 if GetInvokingResource()~='frontier_farming' or not ready or busy or active[src] or leases[src] then return false,'Board your current horse or retry later.' end
 return true,nearest(pos(src))
end)
-- Draft assignments share the horse resource lock with retrieval/equipment/boarding.
exports('AssignDraftTeam',function(src,wagon,ids)
 if GetInvokingResource()~='frontier_logistics' or not ready or busy then return false,'Horse registry busy' end
 busy=true;local ok,e=pcall(function()
  local w=check(S("SELECT * FROM fl_wagons WHERE id=? AND state='stored'",{wagon}),'Store wagon first')
  check(allowed(src,w),'No wagon ownership')
  local tx={{query='DELETE FROM fl_harnesses WHERE wagon_id=?',values={wagon}}};local seen={}
  for i,id in ipairs(ids) do
   id=tostring(id);local h=check(horse(id),'Unknown horse')
   check(not seen[id] and allowed(src,h) and h.owner_type==w.owner_type and h.owner_id==w.owner_id and h.status=='stored' and not pending(id) and (not assigned(id) or assigned(id)==wagon) and R.draft(rec(h),h.model),'Use healthy boarded Shires owned by the wagon owner')
   seen[id]=true
   tx[#tx+1]={query='INSERT INTO fl_harnesses(horse_id,wagon_id,slot_no,character_id,provider_id,model) VALUES(?,?,?,?,?,?)',values={id,wagon,i-1,cid(src),'frontier',h.model}}
  end
  check(MySQL.transaction.await(tx),'Assignment failed')
 end);busy=false;return ok,ok and 'Assigned' or tostring(e)
end)
exports('DraftCandidates',function(src)
 if GetInvokingResource()~='frontier_logistics' or not ready then return {} end
 local out={}
 for _,h in ipairs(Q("SELECT h.*,a.wagon_id,a.slot_no FROM frontier_horses h LEFT JOIN fl_harnesses a ON a.horse_id=h.id WHERE h.status='stored'")) do
  if allowed(src,h) and not pending(h.id) and R.draft(rec(h),h.model) then out[#out+1]={id=h.id,name=h.name,modelname=h.model,injured=0,wagon_id=h.wagon_id,slot_no=h.slot_no,owner_type=h.owner_type,owner_id=h.owner_id} end
 end
 return out
end)
exports('ValidateDraft',function(id,wagon,model)
 if GetInvokingResource()~='frontier_logistics' or not ready then return false end
 local h=horse(tostring(id));return h and h.status=='stored' and h.model:lower()==model:lower() and assigned(h.id)==wagon and not pending(h.id) and R.draft(rec(h),h.model) or false
end)
AddEventHandler('playerDropped',function()local src=source;views[src]=nil;CreateThread(function() while busy do Wait(100) end;run(nil,function()store(src)end)end)end)
AddEventHandler('frontier:playerUnloaded',function(p)local src=p.source;views[src]=nil;CreateThread(function()while busy do Wait(100) end;run(nil,function()store(src)end)end)end)
AddEventHandler('onResourceStop',function(n)if n==GetCurrentResourceName() then for _,m in pairs(active) do delete(m.ped) end end end)
MySQL.ready(function()
 local ok,e=pcall(function()
  Q('SELECT id,record FROM frontier_horses LIMIT 1');Q('SELECT id FROM frontier_horse_orders LIMIT 1')
  local kind=V("SELECT DATA_TYPE FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='fl_harnesses' AND COLUMN_NAME='horse_id'");check(kind=='varchar','Apply horse migration 001 including harness ID change')
  for id,d in pairs(C.equipment) do
   local valid,why=inv:RegisterItem(id,{name=d.name,description=d.name,grams=d.grams,maxStack=10,category='Horse equipment'})
   check(valid,'Register '..id..': '..tostring(why))
  end
  U("UPDATE frontier_horses SET status='stored' WHERE status='out'")
 end)
 if not ok then print('[frontier_horses] Startup failed: '..tostring(e));return end
 ready=true;print('[frontier_horses] Ready')
 CreateThread(function()
  while true do Wait(5000);if not busy then run(nil,function()
   for _,o in ipairs(Q("SELECT * FROM frontier_horse_orders WHERE state IN ('payment','apply','refund') ORDER BY created LIMIT 30")) do finishOrder(o) end
   for src,m in pairs(active) do
    local l=leases[src]
    if (l and l.untilTime<os.time()) or cid(src)~=m.actor or (m.ped~=0 and not DoesEntityExist(m.ped)) then store(src)
    elseif m.ped~=0 and GetEntityHealth(m.ped)<=0 then store(src,nil,true)
    elseif m.ped~=0 and os.time()-m.last>=60 then
     local h=horse(m.id);if h then local d=rec(h)
      if R.distance(pos(src),GetEntityCoords(m.ped))<4 and GetEntitySpeed(m.ped)>2 then d.training=math.min(100,(d.training or 0)+1);d.care=math.max(0,d.care-.2);save(h,d) end
     end;m.last=os.time()
    end
   end
  end) end end
 end)
end)
