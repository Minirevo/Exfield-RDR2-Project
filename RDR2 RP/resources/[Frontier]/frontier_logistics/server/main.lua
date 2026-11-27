local L=LogisticsRuntime
local C,R=L.C,L.R
local function selectOwner(src,company)
 local who=L.cid(src)
 if type(company)=='string' and company~='' then
  L.check(L.id(company) and L.licensed('company',company) and L.B:HasCompanyPermission(company,who,'trade'),'Company transport license and trade permission required')
  return 'company',company
 end
 return 'character',who
end
local function needs(dict)
 local out={};for id,count in pairs(dict) do out[#out+1]={id=id,count=count} end
 table.sort(out,function(a,b)return a.id<b.id end);return out
end
local function newWagon(j,d)
 local def=C.Wagons[d.model];L.check(def,'Unknown wagon model')
 L.check(L.I:LogisticsEnsure(L.route(j.wagon_id),def.slots,def.grams),'Cargo container unavailable')
 L.U("INSERT IGNORE INTO fl_wagons(id,owner_type,owner_id,name,model,state,quality,condition_value,updated_at) VALUES(?,?,?,?,?,'stored',?,100,?)",{j.wagon_id,d.ownerType,d.ownerId,d.name,d.model,d.quality or 50,L.now()})
 L.jobState(j,'complete')
end
local function jobStep(j)
 local d=json.decode(j.payload)
 if j.kind=='buy' then
  local paid,why=L.ECO:DebitAccount(d.bank,d.price,{key='lg:'..j.id..':buy',reason='Purchase freight wagon',reference=j.wagon_id})
  if paid then newWagon(j,d) elseif why=='insufficient_funds' then L.jobState(j,'failed',why) else L.check(false,why) end
 elseif j.kind=='assemble' or j.kind=='repair' then
  -- Receipt check happens before expected revision validation in inventory.
  local consumed,why=L.I:LogisticsConsume('lg:'..j.id..':parts',d.route,d.needs,false,d.revision)
  if not consumed then
   if why=='database_error' then L.check(false,why) else L.jobState(j,'failed',why) end
  elseif j.kind=='assemble' then newWagon(j,d)
  else
   L.U('UPDATE fl_wagons SET condition_value=? WHERE id=?',{d.condition,j.wagon_id});L.jobState(j,'complete')
  end
 elseif j.kind=='wreck' then L.wreckStep(j)
 elseif j.kind=='cargo' and j.state=='commit' then
  local ok,why=L.I:LogisticsPlan('lg:'..j.id,d.plan,false)
  if ok then
   L.jobState(j,'complete')
   local w=L.wagon(j.wagon_id);if w then L.broadcastWagon(w) end
   if d.crate then local found,b=L.I:LogisticsRead(L.crateRoute(d.crate));if found and #b.slots==0 then L.U("UPDATE fl_crates SET state='empty' WHERE id=?",{d.crate}) end end
  elseif why~='database_error' then L.jobState(j,'cancelled',why) else L.check(false,why) end
 end
end
local function benchStocks(src,p)
 local out={};local bag=L.bag(src);if bag then out[#out+1]={id=bag,name='Personal inventory'} end
 for _,s in ipairs(L.P:LogisticsNearbyStorage(src)) do if L.dist(s,p)<=C.LoadDistance then out[#out+1]={id='s_'..s.id,name=s.name} end end
 for _,s in ipairs(L.B:LogisticsStock(src,false)) do if s.retrieve and L.dist(s,p)<=C.LoadDistance then out[#out+1]={id='s_'..s.id,name=s.name} end end
 return out
end
local function workshop(src,v,d,repair)
 local p=L.P:LogisticsBench(src,v.sid,v.fid);L.check(p,'Approach construction bench')
 local model=d.model or 'supplywagon'
 L.check(C.EnabledModels[model],'Model not enabled')
 local route;for _,s in ipairs(benchStocks(src,p)) do if s.id==d.route then route=s.id end end
 L.check(route,'Select accessible component storage')
 local items=needs(repair and C.Repair or C.Assembly)
 local key=L.uuid();local ok,preview=L.I:LogisticsConsume('lg:'..key..':parts',route,items,true)
 L.check(ok,preview)
 local wagon,typ,owner
 if repair then
  local w=L.wagon(d.wagon)
  L.check(w and L.right(src,w,'trade') and w.state=='world' and L.stationary(w) and L.dist(L.point(w),p)<=C.LoadDistance and not L.wagonBusy(w.id),'Bring your wagon to the construction bench')
  L.check(tonumber(w.condition_value)<100,'Wagon already in full condition')
  wagon=w.id;typ=w.owner_type;owner=w.owner_id
 else
  typ,owner=selectOwner(src,d.company);wagon=L.uuid()
 end
 local data={ownerType=typ,ownerId=owner,model=model,name=C.Wagons[model].name,quality=preview.quality,route=route,needs=items,revision=preview.revision,condition=100}
 L.U('INSERT INTO fl_jobs(id,kind,actor,wagon_id,state,payload,created_at) VALUES(?,?,?,?,?,?,?)',{key,repair and 'repair' or 'assemble',L.cid(src),wagon,repair and 'repair' or 'assemble',json.encode(data),L.now()})
end
local function inventoryView(src,v)
 local w=v.wagon and L.wagon(v.wagon)
 if v.mode=='cargo' then
  if v.crate then
   local c=L.S('SELECT * FROM fl_crates WHERE id=?',{v.crate})
   L.check(c and c.state=='available' and L.near(src,c,C.InteractionDistance),'Recovery crate unavailable')
   return L.cargoSnapshot(src,nil,c)
  end
  L.check(w and L.access(src,w,'trade'),'Cargo locked or wagon unavailable')
  local snap=L.cargoSnapshot(src,w);snap.contracts=L.contractView(src,w);return snap
 elseif v.mode=='locked' then
  L.check(w and L.near(src,L.point(w),C.InteractionDistance),'Approach wagon')
  return {mode='locked',wagon=w,manage=L.right(src,w,'trade')}
 elseif v.mode=='bench' then
  local p=L.P:LogisticsBench(src,v.sid,v.fid);L.check(p,'Approach construction bench')
  return {mode='bench',wagons=L.ownerWagons(src),companies=L.B:LogisticsCompanies(L.cid(src)),assembly=C.Assembly,repair=C.Repair,stocks=benchStocks(src,p)}
 else
  local stock=L.B:LogisticsStock(src,true);local origins={}
  for _,s in ipairs(stock) do
   if s.retrieve and L.near(src,s,C.InteractionDistance) then
    local ok,box=L.I:LogisticsRead('s_'..s.id);if ok then s.box=box;origins[#origins+1]=s end
   end
  end
  L.check(L.dealer(src) or #origins>0,'Approach freight yard or authorized warehouse')
  return {mode='registry',dealer=L.dealer(src)~=nil,wagons=L.ownerWagons(src),horses=L.horses(src),companies=L.B:LogisticsCompanies(L.cid(src)),models=C.EnabledModels,prices=C.PriceMinor,definitions=C.Wagons,contracts=L.contractView(src),stock=stock,origins=origins}
 end
end
local function open(src,v)
 local snap=inventoryView(src,v);v.ticket=L.uuid();v.actor=L.cid(src);v.seq=0;L.views[src]=v
 TriggerClientEvent(L.E..'view',src,v.ticket,snap)
end
RegisterNetEvent(L.E..'open',function(mode,id,sid)
 local src=source
 L.run(src,function()
  L.check(L.pos(src),'Character unavailable')
  L.check(not L.loads[src] and not L.lockTests[src],'Finish current work')
  if mode=='wagon' then
   local w=L.wagon(id)
   L.check(w and w.state=='world' and L.near(src,L.point(w),C.InteractionDistance) and L.stationary(w),'Approach a stationary registered wagon')
   open(src,{mode=L.access(src,w,'trade') and 'cargo' or 'locked',wagon=id})
  elseif mode=='crate' then L.check(L.id(id),'Invalid crate');open(src,{mode='cargo',crate=id})
  elseif mode=='bench' then L.check(L.id(id) and L.id(sid),'Invalid bench');open(src,{mode='bench',fid=id,sid=sid})
  else open(src,{mode='registry'}) end
 end)
end)
RegisterNetEvent(L.E..'request',function(ticket,seq,a,d)
 local src=source;local v=L.views[src]
 if not v or v.ticket~=ticket or v.actor~=L.cid(src) or type(seq)~='number' or seq%1~=0 or seq<=0 or seq>2147483647 or type(a)~='string' or type(d)~='table' then return end
 if seq==v.seq and v.response then return TriggerClientEvent(L.E..'result',src,ticket,seq,v.response) end
 if seq<=v.seq then return end
 if L.busy then return TriggerClientEvent(L.E..'result',src,ticket,seq,{ok=false,message='Logistics busy; retry'}) end
 L.run(src,function()
  local ok,msg=pcall(function()
   local snapshot=inventoryView(src,v)
   local w=v.wagon and L.wagon(v.wagon) or L.wagon(d.wagon)
   if a=='refresh' then return 'Updated'
   elseif a=='buy' and v.mode=='registry' and L.dealer(src) then
    local model=d.model;L.check(C.EnabledModels[model],'Model not enabled')
    local typ,id=selectOwner(src,d.company);local bank=L.account(src,typ,id,'finance');L.check(bank,'Bank account unavailable')
    local wagon=L.uuid()
    L.newJob('buy',L.cid(src),wagon,{ownerType=typ,ownerId=id,model=model,name=C.Wagons[model].name,bank=bank,price=C.PriceMinor[model],quality=50},'purchase')
    return 'Purchase queued'
   elseif a=='assign' and v.mode=='registry' then L.assign(src,w,d.horses);return 'Harnesses updated'
   elseif a=='deploy' and v.mode=='registry' then L.deploy(src,w);return 'Deployment requested'
   elseif a=='store' and v.mode=='cargo' then L.store(src,w);L.views[src]=nil;TriggerClientEvent(L.E..'close',src);return 'Wagon stored'
   elseif a=='lock' and (v.mode=='cargo' or v.mode=='locked') then
    L.check(w and L.right(src,w,'trade') and L.stationary(w) and not L.wagonBusy(w.id),'Management permission required')
    L.U('UPDATE fl_wagons SET locked=? WHERE id=?',{tonumber(w.locked)==1 and 0 or 1,w.id});L.broadcastWagon(L.wagon(w.id));return 'Lock updated'
   elseif a=='pick' and v.mode=='locked' then L.lockStart(src,w);return 'Lockpick started'
   elseif a=='load' and v.mode=='cargo' then
    local crate=v.crate and L.S('SELECT * FROM fl_crates WHERE id=?',{v.crate}) or nil
    L.startLoad(src,w,crate,d);return 'Loading started'
   elseif a=='report' and v.mode=='registry' then
    L.check(w and L.right(src,w,'trade'),'Not your wagon')
    L.U('UPDATE fl_wagons SET stolen=? WHERE id=?',{tonumber(w.stolen)==1 and 0 or 1,w.id});L.broadcastWagon(L.wagon(w.id));return 'Registration report updated'
   elseif a=='assemble' and v.mode=='bench' then workshop(src,v,d,false);return 'Assembly queued'
   elseif a=='repair' and v.mode=='bench' then workshop(src,v,d,true);return 'Repair queued'
   elseif a=='createContract' and v.mode=='registry' then L.createContract(src,d);return 'Freight request queued'
   elseif a=='acceptContract' and v.mode=='cargo' then L.acceptContract(src,w,d.contract);return 'Contract accepted'
   elseif (a=='pickup' or a=='deliver' or a=='returnFreight' or a=='abandonContract' or a=='stealFreight') and v.mode=='cargo' or a=='cancelContract' and v.mode=='registry' then L.contractAction(src,w,d.contract,a);return 'Contract updated'
   end
   error('Action unavailable',0)
  end)
  if L.views[src]~=v then return end
  local snapshot;local fresh,s=pcall(inventoryView,src,v);if fresh then snapshot=s end
  v.seq=seq;v.response={ok=ok,message=tostring(msg),snapshot=snapshot}
  TriggerClientEvent(L.E..'result',src,ticket,seq,v.response)
 end)
end)
RegisterNetEvent(L.E..'close',function(ticket)local src=source;if L.views[src] and L.views[src].ticket==ticket then L.views[src]=nil end end)
RegisterNetEvent(L.E..'cancelLoad',function(id)local src=source;L.run(src,function()L.cancelLoad(src,id)end)end)
RegisterNetEvent(L.E..'lockStrike',function(id)local src=source;L.run(src,function()L.lockStrike(src,id)end)end)
AddEventHandler('frontier:playerUnloaded',function(p)L.views[p.source]=nil;L.loads[p.source]=nil;L.lockTests[p.source]=nil end)
AddEventHandler('playerDropped',function()local src=source;L.views[src]=nil;L.loads[src]=nil;L.lockTests[src]=nil end)
RegisterCommand('wagoninspect',function(src,args)
 L.run(src,function()
  local w=L.wagon(args[1]);L.check(w and L.near(src,L.point(w),C.InteractionDistance),'Approach wagon')
  L.tell(src,('Registration %s | %s | %s'):format(w.id,w.name,tonumber(w.stolen)==1 and 'REPORTED STOLEN' or 'No active stolen report'))
  if L.Core:HasPermission(src,'frontier.logistics.police') then L.tell(src,'Legal owner: '..w.owner_type..' '..w.owner_id) end
 end)
end,false)
RegisterCommand('logisticsdiagnostics',function(src)
 if src~=0 and not L.Core:HasPermission(src,'frontier.logistics.admin') then return end
 L.run(src==0 and nil or src,function()
  for _,j in ipairs(L.Q("SELECT id,kind,state,issue FROM fl_jobs WHERE state NOT IN ('complete','cancelled','failed') LIMIT 100")) do L.tell(src==0 and nil or src,j.id..' '..j.kind..' '..j.state..' '..j.issue) end
  for _,c in ipairs(L.Q("SELECT id,state,issue FROM fl_contracts WHERE state NOT IN ('complete','cancelled','failed') LIMIT 100")) do L.tell(src==0 and nil or src,c.id..' freight '..c.state..' '..c.issue) end
 end)
end,false)
MySQL.ready(function()
 while not L.ready do
  local ok,err=pcall(function()
   L.Q('SELECT id FROM fl_wagons LIMIT 1');L.Q('SELECT id FROM fl_jobs LIMIT 1');L.Q('SELECT id FROM fl_contracts LIMIT 1')
   L.check(L.V("SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA=DATABASE() AND ROUTINE_NAME='frontier_inventory_logistics_commit_v1'" )==1 or tonumber(L.V("SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA=DATABASE() AND ROUTINE_NAME='frontier_inventory_logistics_commit_v1'"))==1,'Apply 002_inventory_atomic.sql')
   L.U("UPDATE fl_jobs SET state='cancelled',issue='Loading interrupted by restart' WHERE state='loading'")
   L.assignmentState()
  end)
  if ok then L.ready=true;print('[frontier_logistics] ready') else L.tell(nil,err);Wait(5000) end
 end
 local lastWorld,lastAssignments=0,0
 while true do
  Wait(1000)
  L.run(nil,function()
   L.loadTick();L.cleanupLockTests()
   -- Disconnects leave pre-commit cargo unchanged.
   for _,j in ipairs(L.Q("SELECT * FROM fl_jobs WHERE state='loading'")) do
    local found=false;for _,a in pairs(L.loads) do if a.id==j.id then found=true;break end end
    if not found then L.jobState(j,'cancelled','Player disconnected') end
   end
   for _,j in ipairs(L.Q("SELECT * FROM fl_jobs WHERE state IN ('purchase','assemble','repair','wreck','commit') ORDER BY created_at,id LIMIT 30")) do
    local ok,err=pcall(jobStep,j);if not ok then L.U('UPDATE fl_jobs SET issue=? WHERE id=?',{tostring(err):sub(1,255),j.id}) end
   end
   L.contractTick()
   if L.now()-lastWorld>=3 then L.worldTick();lastWorld=L.now() end
   if L.now()-lastAssignments>=15 then L.assignmentState();lastAssignments=L.now() end
  end)
 end
end)
AddEventHandler('onResourceStop',function(name)if name==GetCurrentResourceName() then L.stopWorld() end end)
