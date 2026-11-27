local L=LogisticsRuntime
local C=L.C
function L.cargoSnapshot(src,w,crate)
 local route=crate and L.crateRoute(crate.id) or L.route(w.id)
 local ok,box=L.I:LogisticsRead(route);L.check(ok,'Cargo unavailable')
 local inventories={{id=route,name=crate and 'Recovery crate' or w.name,box=box,deposit=not crate,retrieve=true}}
 local bag,data=L.bag(src);if bag then inventories[#inventories+1]={id=bag,name='Personal inventory',box=data,deposit=true,retrieve=true} end
 if not crate then
  local point=L.point(w)
  for _,s in ipairs(L.P:LogisticsNearbyStorage(src)) do
   if L.dist(s,point)<=C.LoadDistance then
    local found,b=L.I:LogisticsRead('s_'..s.id);if found then inventories[#inventories+1]={id='s_'..s.id,name=s.name,box=b,deposit=true,retrieve=true} end
   end
  end
  for _,s in ipairs(L.B:LogisticsStock(src,false)) do
   if L.dist(s,point)<=C.LoadDistance then
    local found,b=L.I:LogisticsRead('s_'..s.id);if found then inventories[#inventories+1]={id='s_'..s.id,name=s.name,box=b,deposit=s.deposit,retrieve=s.retrieve} end
   end
  end
 end
 local grams,slots=0,0;if not crate then grams,slots=L.freightCapacity(w.id) end
 return {mode='cargo',wagon=w,crate=crate,route=route,inventories=inventories,freightWeight=grams,freightSlots=slots,
  manage=w and L.right(src,w,'trade') or false,locked=w and tonumber(w.locked)==1 or false}
end
function L.cargoAllowed(src,w,crate,plan)
 if crate then
  if crate.state~='available' or not L.near(src,crate,C.InteractionDistance) then return false end
 else
  if not L.access(src,w,'trade') then return false end
 end
 local who=L.cid(src);if not who then return false end
 local bag='p_'..who
 local route=crate and L.crateRoute(crate.id) or L.route(w.id)
 for _,line in ipairs(plan.lines) do
  if line.from~=route and line.to~=route then return false end
  if crate then
   if line.from~=route or line.to~=bag then return false end
  else
   if line.from==route and not L.access(src,w,'retrieve') or line.to==route and not L.access(src,w,'deposit') then return false end
   if line.from~=route and line.from~=bag then
    if type(line.from)~='string' or not line.from:match('^s_') or not L.validateStorage(src,line.from:sub(3),'from',w) then return false end
   end
   if line.to~=route and line.to~=bag then
    if type(line.to)~='string' or not line.to:match('^s_') or not L.validateStorage(src,line.to:sub(3),'to',w) then return false end
   end
  end
 end
 return true
end
function L.startLoad(src,w,crate,d)
 L.check(not L.loads[src] and (crate or not L.wagonBusy(w.id)),'Finish current handling first')
 L.check(type(d.lines)=='table' and #d.lines>=1 and #d.lines<=C.MaxCargoPlanLines and type(d.revisions)=='table','Invalid cargo plan')
 local plan={lines={},revisions={}}
 -- Resolve metadata from a fresh server snapshot; never accept arbitrary metadata from browser.
 local snap=L.cargoSnapshot(src,w,crate);local byId={}
 for _,entry in ipairs(snap.inventories) do byId[entry.id]=entry end
 for _,line in ipairs(d.lines) do
  L.check(type(line)=='table' and byId[line.from] and byId[line.to] and L.R.integer(line.slot,1,200) and L.R.integer(line.quantity,1,10000),'Invalid transfer line')
  local a,b=byId[line.from],byId[line.to];L.check(a.retrieve and b.deposit,'Storage permission denied')
  L.check(d.revisions[a.id]==a.box.revision and d.revisions[b.id]==b.box.revision,'Cargo changed; refresh and plan again')
  local original
  for _,s in ipairs(a.box.slots) do if s.slot==line.slot then original=s;break end end
  L.check(original,'Source slot changed')
  plan.lines[#plan.lines+1]={from=a.id,to=b.id,slot=line.slot,item=original.item,instance=original.instance,metadata=original.metadata,quantity=line.quantity}
  plan.revisions[a.id]=a.box.revision;plan.revisions[b.id]=b.box.revision
 end
 L.check(L.cargoAllowed(src,w,crate,plan),'Move closer or check storage access')
 if w then plan.wagon=L.route(w.id);plan.freightWeight,plan.freightSlots=L.freightCapacity(w.id) end
 local key=L.uuid()
 plan.fingerprint='cargo:'..key -- ID identifies frozen persisted payload; no client controls key
 local ok,metrics=L.I:LogisticsPlan('lg:'..key,plan,true);L.check(ok,metrics)
 local skilled,skill=L.K:GetSkill(src,'transportation')
 local seconds=L.R.loadingSeconds(metrics.grams,metrics.units,skilled and skill.level or 1)
 local payload={plan=plan,crate=crate and crate.id or nil,seconds=seconds}
 L.U("INSERT INTO fl_jobs(id,kind,actor,wagon_id,state,payload,created_at) VALUES(?,'cargo',?,?,'loading',?,?)",{key,L.cid(src),w and w.id or '',json.encode(payload),L.now()})
 local point=w and L.point(w) or crate
 L.loads[src]={id=key,actor=L.cid(src),untilTime=L.now()+seconds,point=point}
 L.views[src]=nil
 TriggerClientEvent(L.E..'loading',src,{id=key,seconds=seconds,label='Handling cargo'})
end
function L.cancelLoad(src,id)
 local a=L.loads[src];if not a or a.id~=id then return end
 local j=L.job(id);if j and j.state=='loading' then L.jobState(j,'cancelled','Cancelled before commit') end
 L.loads[src]=nil
 TriggerClientEvent(L.E..'loadingEnd',src,'Cancelled; inventories unchanged')
end
function L.loadTick()
 for src,a in pairs(L.loads) do
  local j=L.job(a.id)
  if not j or j.state~='loading' or L.cid(src)~=a.actor then L.loads[src]=nil
  else
   local d=json.decode(j.payload)
   local w=j.wagon_id~='' and L.wagon(j.wagon_id) or nil
   local crate=d.crate and L.S('SELECT * FROM fl_crates WHERE id=?',{d.crate}) or nil
   if not (w or crate) or not L.cargoAllowed(src,w,crate,d.plan) or L.dist(a.point,w and L.point(w) or crate)>2 then
    L.cancelLoad(src,a.id)
   elseif L.now()>=a.untilTime then
    -- Move the entire frozen plan in one transaction; if another player changed a slot, abort.
    L.jobState(j,'commit')
    L.loads[src]=nil
    local ok,err=L.I:LogisticsPlan('lg:'..j.id,d.plan,false)
    if ok then
     L.jobState(L.job(j.id),'complete')
     if w then L.broadcastWagon(w) end
     if crate then
      local found,b=L.I:LogisticsRead(L.crateRoute(crate.id));if found and #b.slots==0 then L.U("UPDATE fl_crates SET state='empty' WHERE id=?",{crate.id}) end
     end
     TriggerClientEvent(L.E..'loadingEnd',src,'Cargo handling complete')
    elseif err=='database_error' then
     TriggerClientEvent(L.E..'loadingEnd',src,'Database confirmation pending; cargo will reconcile')
    else
     L.jobState(L.job(j.id),'cancelled',err)
     TriggerClientEvent(L.E..'loadingEnd',src,'Cargo not moved: '..tostring(err))
    end
   end
  end
 end
end
function L.wreckStep(j)
 local w=L.wagon(j.wagon_id);local d=json.decode(j.payload)
 L.check(w and w.state=='wreck_pending','Wreck unavailable')
 if L.V("SELECT id FROM fl_jobs WHERE wagon_id=? AND state='commit' LIMIT 1",{w.id}) or L.V("SELECT id FROM fl_contracts WHERE wagon_id=? AND state='steal' LIMIT 1",{w.id}) then return end
 L.check(L.I:LogisticsEnsure(L.crateRoute(d.crate),200,100000000),'Recovery container unavailable')
 local from={L.route(w.id)}
 local contracts=L.Q("SELECT id FROM fl_contracts WHERE wagon_id=? AND state='wreck' ORDER BY id",{w.id})
 for _,c in ipairs(contracts) do from[#from+1]=L.freightRoute(c.id) end
 local ok,err=L.I:LogisticsRecover('lg:'..j.id..':wreck',from,L.crateRoute(d.crate))
 L.check(ok,err)
 local found,box=L.I:LogisticsRead(L.crateRoute(d.crate));L.check(found,'Recovery stock unavailable')
 L.check(MySQL.transaction.await({
  {query="UPDATE fl_crates SET state=? WHERE id=?",values={#box.slots>0 and 'available' or 'empty',d.crate}},
  {query="UPDATE fl_wagons SET state='destroyed',condition_value=0 WHERE id=?",values={w.id}},
  {query="DELETE FROM fl_harnesses WHERE wagon_id=?",values={w.id}},
  {query="UPDATE fl_contracts SET state='refund',issue='Freight destroyed; surviving goods in wreck crate' WHERE wagon_id=? AND state='wreck'",values={w.id}},
  {query="UPDATE fl_jobs SET state='complete' WHERE id=?",values={j.id}}
 }),'Wreck finalization failed')
 L.assignmentState()
end
function L.lockStart(src,w)
 L.check(w and w.state=='world' and tonumber(w.locked)==1 and L.near(src,L.point(w),C.InteractionDistance) and L.stationary(w) and not L.wagonBusy(w.id),'Approach locked stationary wagon')
 local ok,has=L.I:HasItem(src,C.LockpickItem,1);L.check(ok and has,'Lockpick required')
 L.check(not L.lockTests[src],'Already picking a lock')
 local key=L.uuid();local route=L.bag(src);L.check(route,'Inventory unavailable')
 -- Consumable lockpick, consumed exactly once per attempt.
 local used,why=L.I:LogisticsConsume('lg:'..key..':pick',route,{{id=C.LockpickItem,count=1}},false)
 L.check(used,why)
 local test={id=key,wagon=w.id,actor=L.cid(src),start=GetGameTimer(),target=math.random(30,70)/100}
 L.lockTests[src]=test
 L.views[src]=nil
 TriggerClientEvent(L.E..'lockpick',src,{id=key,ms=C.LockpickMs,target=test.target})
end
function L.lockStrike(src,id)
 local t=L.lockTests[src];if not t or t.id~=id then return end
 L.lockTests[src]=nil
 local w=L.wagon(t.wagon)
 local ms=GetGameTimer()-t.start
 local success=t.actor==L.cid(src) and w and tonumber(w.locked)==1 and L.near(src,L.point(w),C.InteractionDistance) and L.stationary(w) and ms>=0 and ms<=C.LockpickMs and math.abs((ms%2000)/2000-t.target)<=.10
 if success then
  L.U('UPDATE fl_wagons SET locked=0 WHERE id=?',{w.id});L.broadcastWagon(L.wagon(w.id))
 end
 TriggerClientEvent(L.E..'loadingEnd',src,success and 'Cargo lock opened' or 'Lockpick failed')
end
function L.cleanupLockTests()
 for src,t in pairs(L.lockTests) do if L.cid(src)~=t.actor or GetGameTimer()-t.start>C.LockpickMs+1000 then L.lockTests[src]=nil;TriggerClientEvent(L.E..'loadingEnd',src,'Lockpick attempt ended') end end
end
