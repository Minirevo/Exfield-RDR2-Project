local L=LogisticsRuntime
local C=L.C
local function modelHash(name)return GetHashKey(name)&0xffffffff end
local function setWagonState(w,state,p,h)
 L.U('UPDATE fl_wagons SET state=?,x=?,y=?,z=?,heading=?,updated_at=? WHERE id=?',{state,p.x,p.y,p.z,h or 0,L.now(),w.id})
end
local function delete(entity)if entity and entity~=0 and DoesEntityExist(entity) then pcall(DeleteEntity,entity) end end
local function cleanup(id)
 local e=L.entities[id];L.entities[id]=nil
 if e then
  for _,h in ipairs(e.horses or {}) do delete(h) end
  delete(e.vehicle)
 end
end
function L.assignmentState()
 for _,p in pairs(L.Core:GetPlayers()) do
  local rows=L.Q('SELECT horse_id FROM fl_harnesses WHERE character_id=?',{p.frontierCharacterId})
  local assigned={};for _,h in ipairs(rows) do assigned[tostring(h.horse_id)]=true end
  Player(p.source).state:set('frontierHarnesses',assigned,true)
 end
end
function L.assign(src,w,ids)
 L.check(w and L.right(src,w,'trade') and w.state=='stored' and L.dealer(src) and not L.wagonBusy(w.id),'Store wagon at freight yard first')
 L.check(type(ids)=='table' and (#ids==0 or #ids==C.Wagons[w.model].horses),'Select exactly '..C.Wagons[w.model].horses..' horses, or clear assignment')
 local horses=L.horses(src);local owned={};for _,h in ipairs(horses) do owned[tostring(h.id)]=h end
 local p=L.Core:GetPlayer(src);local seen={}
 local tx={{query='DELETE FROM fl_harnesses WHERE wagon_id=?',values={w.id}}}
 for slot,id in ipairs(ids) do
  local h=owned[tostring(id)]
  L.check(h and not seen[id] and (not h.wagon_id or h.wagon_id==w.id),'Horse unavailable or already assigned')
  L.check((tonumber(h.injured) or 0)==0,'Use healthy horses')
  L.check(type(h.modelname)=='string' and h.modelname:lower():match('^a_c_horse_'),'Invalid horse model')
  -- Initial live release limits harness models to the tested Shire variant.
  L.check(h.modelname:lower()==C.HorseModel,'Use the tested Dark Bay Shire horses for this release')
  seen[id]=true
  tx[#tx+1]={query='INSERT INTO fl_harnesses(horse_id,wagon_id,slot_no,character_id,provider_id,model) VALUES(?,?,?,?,?,?)',values={h.id,w.id,slot-1,p.frontierCharacterId,p.providerCharacterId,h.modelname}}
 end
 L.check(MySQL.transaction.await(tx),'Assignment failed')
 L.assignmentState()
 -- Prevent an existing, called VORP horse remaining as a duplicate.
 TriggerClientEvent(L.E..'dismissAssigned',src)
end
local function spawnStatus(id,message,src)
 L.spawnStatus=L.spawnStatus or {};local old=L.spawnStatus[id];L.spawnStatus[id]=message
 if old~=message then print(('[frontier_logistics/spawn] %s: %s'):format(id,message));if src then L.tell(src,message) end end
end
function L.spawnLease(w,src)
 if L.entities[w.id] or L.leases[w.id] or not C.EnabledModels[w.model] or w.state~='world' then return end
 local a=L.assignments(w.id)
 if #a~=C.Wagons[w.model].horses then spawnStatus(w.id,'Missing assigned horses',src);return end
 for _,h in ipairs(a) do
  local actual=L.S("SELECT id,modelname FROM stables WHERE id=? AND charidentifier=? AND type='horse'",{h.horse_id,h.provider_id})
  if not actual or tostring(actual.modelname):lower()~=tostring(h.model):lower() then spawnStatus(w.id,'Assigned horse ownership/model no longer matches',src);return end
 end
 local ticket=L.uuid()
 local lease={id=w.id,token=ticket,src=src,untilTime=L.now()+C.SpawnLeaseSeconds,model=w.model,x=w.x,y=w.y,z=w.z,heading=w.heading,horses=a}
 L.leases[w.id]=lease
 spawnStatus(w.id,'Spawning wagon and assigned horses...',src)
 TriggerClientEvent(L.E..'spawn',src,lease)
end
-- Receive acknowledgements immediately, even while the database worker is busy.
-- Only the valid lease holder may submit; one immutable network team per lease.
RegisterNetEvent(L.E..'spawnAck',function(id,token,net,horseNets,models)
 local src=tonumber(source);if not L.id(id) or not src then return end
 local lease=L.leases[id];local registered=L.entities[id]
 if registered and registered.token==token and registered.spawnSource==src and registered.net==net and DoesEntityExist(registered.vehicle) then
  TriggerClientEvent(L.E..'spawnAccepted',src,token);return
 end
 if not lease or tonumber(lease.src)~=src or lease.token~=token or lease.untilTime<L.now() then return end
 if type(net)~='number' or net%1~=0 or net<=0 or net>65535 or type(horseNets)~='table' or #horseNets~=#lease.horses or type(models)~='table' or #models~=#lease.horses+1 then
  spawnStatus(id,'Invalid spawn acknowledgement payload',src);return
 end
 local seen={[net]=true}
 for _,n in ipairs(horseNets) do
  if type(n)~='number' or n%1~=0 or n<=0 or n>65535 or seen[n] then spawnStatus(id,'Invalid or duplicate draft network ID',src);return end
  seen[n]=true
 end
 for _,m in ipairs(models) do if type(m)~='number' or m%1~=0 or m==0 or m< -2147483648 or m>4294967295 then spawnStatus(id,'Invalid client model hash',src);return end end
 if lease.ack then return end
 lease.ack={src=src,net=net,horseNets=horseNets,models=models}
 spawnStatus(id,'Server received wagon team; checking network entities',src)
end)
local function validateTeamEntity(net,src,lease,expected,clientModel,kind,label,radius)
 local entity=NetworkGetEntityFromNetworkId(net)
 L.check(entity and entity~=0 and DoesEntityExist(entity),label..' net='..net..' not yet visible to server')
 local actualType=GetEntityType(entity)
 L.check(actualType==kind,label..' entity type='..tostring(actualType)..' expected='..kind)
 local actualOwner=tonumber(NetworkGetEntityOwner(entity))
 L.check(actualOwner==src,label..' network owner='..tostring(actualOwner)..' expected='..src)
 if type(GetEntityRoutingBucket)=='function' then
  L.check(GetEntityRoutingBucket(entity)==0,label..' outside world routing bucket')
 end
 local p=GetEntityCoords(entity);local distance=L.dist(p,lease)
 L.check(distance<=radius,label..' distance from lease='..('%.1f'):format(distance))
 local serverModel=GetEntityModel(entity)
 local ok,fallback=L.R.networkModel(serverModel,expected,clientModel,kind==1)
 L.check(ok,label..' server model='..tostring(serverModel)..' expected='..tostring(expected)..' client='..tostring(clientModel))
 return entity,fallback
end
local function registerTeam(id,lease)
 local ack=lease.ack;local src=ack.src
 L.check(L.leases[id]==lease and not L.entities[id] and lease.untilTime>=L.now(),'Spawn lease expired')
 L.check(L.near(src,lease,C.StreamDistance),'Spawn player left saved location or world')
 local v=validateTeamEntity(ack.net,src,lease,modelHash(lease.model),ack.models[1],2,'Wagon',15)
 local horses,unverified={},{};local seen={[v]=true}
 for i,n in ipairs(ack.horseNets) do
  local h,fb=validateTeamEntity(n,src,lease,modelHash(lease.horses[i].model),ack.models[i+1],1,'Horse slot '..lease.horses[i].slot_no,25)
  L.check(not seen[h],'Duplicate resolved entity');seen[h]=true;horses[i]=h
  if fb then unverified[#unverified+1]=lease.horses[i].slot_no end
 end
 -- Reject any entity already registered to a different wagon team.
 for otherId,other in pairs(L.entities) do
  L.check(not seen[other.vehicle],'Vehicle already assigned to another wagon')
  for _,h in ipairs(other.horses or {}) do L.check(not seen[h],'Horse already assigned to another wagon') end
 end
 if type(SetEntityOrphanMode)=='function' then
  pcall(SetEntityOrphanMode,v,2);for _,h in ipairs(horses) do pcall(SetEntityOrphanMode,h,2) end
 end
 -- Initial cargo interaction state publication is separate from registration.
 for i,h in ipairs(horses) do Entity(h).state:set('frontierDraftHorse',{wagon=id,horse=lease.horses[i].horse_id},true) end
 Entity(v).state:set('frontierWagonId',id,true)
 L.entities[id]={vehicle=v,horses=horses,net=ack.net,seen=L.now(),lastSave=0,token=lease.token,spawnSource=src,publishPending=true}
 L.leases[id]=nil
 TriggerClientEvent(L.E..'spawnAccepted',src,lease.token)
 local suffix=#unverified>0 and (' (RedM horse model unavailable on server, slots '..table.concat(unverified,',')..'; client model verified)') or ''
 spawnStatus(id,'Wagon registered and ready'..suffix,src)
end
-- Process queued acknowledgements independently of contract and inventory polling.
-- No SQL awaits inside registerTeam; identity changes remain serialized.
CreateThread(function()
 while true do
  Wait(200)
  if L.ready and not L.busy then
   L.run(nil,function()
    for id,lease in pairs(L.leases) do
     if lease.ack and lease.untilTime>=L.now() then
      local ok,why=pcall(registerTeam,id,lease)
      if not ok then spawnStatus(id,'Registration pending: '..tostring(why),lease.ack.src) end
     end
    end
   end)
  end
 end
end)
RegisterNetEvent(L.E..'spawnFailed',function(id,token,why)
 local src=source;local a=L.leases[id]
 if a and a.src==src and a.token==token then
  a.ack=nil;a.untilTime=L.now()+8
  local previous=(L.spawnStatus or {})[id] or ''
  spawnStatus(id,'Spawn failed: '..tostring(why):sub(1,140)..' | last server check: '..previous:sub(1,180),src)
 end
end)
function L.deploy(src,w)
 L.check(w and L.right(src,w,'trade') and w.state=='stored' and not L.wagonBusy(w.id),'Wagon not deployable')
 local p=L.dealer(src);L.check(p,'Approach freight yard')
 L.check(tonumber(w.condition_value)>0,'Repair wagon first')
 L.check(#L.assignments(w.id)==C.Wagons[w.model].horses,'Assign draft horses first')
 -- Deployment location is fixed by yard; never client-supplied.
 for _,other in ipairs(L.Q("SELECT * FROM fl_wagons WHERE state='world'")) do
  L.check(L.dist(other,p)>8,'Freight yard spawn occupied')
 end
 setWagonState(w,'world',p,p.heading);L.spawnLease(L.wagon(w.id),src)
end
function L.retrySpawn(src,w)
 L.check(w and w.state=='world' and L.right(src,w,'trade'),'Wagon not deployed or unauthorized')
 L.check(L.near(src,w,C.StreamDistance),'Go to the last saved wagon location first')
 L.check(not L.entities[w.id],'Wagon already registered; look at its saved location')
 local lease=L.leases[w.id]
 if lease and lease.untilTime>=L.now() then return 'Spawn already pending: '..tostring((L.spawnStatus or {})[w.id] or 'please wait') end
 L.leases[w.id]=nil;L.spawnLease(w,src);return 'Spawn retry requested'
end
function L.store(src,w)
 L.check(w and L.right(src,w,'trade') and L.stationary(w) and L.near(src,L.point(w),C.InteractionDistance) and L.dealer(src) and not L.wagonBusy(w.id),'Approach stationary wagon at yard')
 L.check(tonumber(w.stolen)==0,'Resolve stolen wagon report first')
 local p=L.point(w);L.check(L.dist(p,L.dealer(src))<=C.DepotDistance,'Wagon outside yard')
 local ok,box=L.I:LogisticsRead(L.route(w.id));L.check(ok and #box.slots==0 and #L.freight(w.id)==0,'Unload all cargo first')
 setWagonState(w,'stored',p,GetEntityHeading(L.entities[w.id].vehicle));cleanup(w.id)
end
function L.wreck(w,p)
 if w.state~='world' then return end
 local id=L.uuid()
 local statements={
  {query="UPDATE fl_wagons SET state='wreck_pending',x=?,y=?,z=?,updated_at=? WHERE id=? AND state='world'",values={p.x,p.y,p.z,L.now(),w.id}},
  {query="INSERT INTO fl_crates(id,wagon_id,x,y,z,state,created_at) VALUES(?,?,?,?,?,'pending',?)",values={id,w.id,p.x,p.y,p.z,L.now()}},
  {query="UPDATE fl_contracts SET state='wreck',issue='Wagon destroyed' WHERE wagon_id=? AND state='in_transit'",values={w.id}},
  {query="UPDATE fl_contracts SET state='return',issue='Wagon destroyed before pickup' WHERE wagon_id=? AND state='pickup'",values={w.id}},
  {query="INSERT INTO fl_jobs(id,kind,actor,wagon_id,state,payload,created_at) VALUES(?,'wreck',?,?,'wreck',?,?)",values={id,w.owner_id,w.id,json.encode({crate=id}),L.now()}}
 }
 L.check(MySQL.transaction.await(statements),'Could not journal destruction')
 cleanup(w.id)
end
function L.worldTick()
 local players=L.Core:GetPlayers()
 for _,w in ipairs(L.Q("SELECT * FROM fl_wagons WHERE state='world'")) do
  local e=L.entities[w.id]
  if e and DoesEntityExist(e.vehicle) then
   if e.publishPending then
    local ok,why=pcall(L.broadcastWagon,w)
    if ok then e.publishPending=nil else spawnStatus(w.id,'Registered; cargo state pending: '..tostring(why)) end
   end
   local p=L.point(w);local health=GetEntityHealth(e.vehicle)
   -- A missing entity is not destruction. Only a live server-observed dead vehicle qualifies.
   if L.now()-e.seen>=10 and type(health)=='number' and health<=0 then L.wreck(w,p)
   else
    if L.now()-e.lastSave>=5 then
     L.U("UPDATE fl_wagons SET x=?,y=?,z=?,heading=?,updated_at=? WHERE id=? AND state='world'",{p.x,p.y,p.z,GetEntityHeading(e.vehicle),L.now(),w.id})
     local travelled=L.dist(w,p)
     if travelled>=5 then
      local wear=travelled/5000*(1.25-(tonumber(w.quality) or 50)/200)
      e.wear=(e.wear or 0)+wear
      if e.wear>=1 then L.U('UPDATE fl_wagons SET condition_value=GREATEST(1,condition_value-?) WHERE id=?',{math.floor(e.wear),w.id});e.wear=e.wear%1 end
     end
     e.lastSave=L.now()
    end
   end
  elseif e then
   -- Lost network entity: preserve cargo/location, remove surviving owned draft entities.
   cleanup(w.id)
   L.leases[w.id]={untilTime=L.now()+10}
  else
   local lease=L.leases[w.id]
   if lease and lease.untilTime<L.now() then L.leases[w.id]=nil;lease=nil end
   if not lease then
    for _,p in pairs(players) do
     if L.near(p.source,w,C.StreamDistance) then L.spawnLease(w,p.source);break end
    end
   end
  end
 end
 -- Crates are persistent records, rendered locally by nearby clients.
 for _,p in pairs(players) do
  local pos=L.pos(p.source);local visible={}
  if pos then
   for _,c in ipairs(L.Q("SELECT id,x,y,z FROM fl_crates WHERE state='available' AND x BETWEEN ? AND ? AND y BETWEEN ? AND ?",{pos.x-C.StreamDistance,pos.x+C.StreamDistance,pos.y-C.StreamDistance,pos.y+C.StreamDistance})) do
    if L.dist(c,pos)<=C.StreamDistance then visible[#visible+1]=c end
   end
  end
  TriggerClientEvent(L.E..'crates',p.source,visible)
 end
end
function L.stopWorld()
 for id in pairs(L.entities) do cleanup(id) end
end
exports('HorseAssigned',function(horse)
 if GetInvokingResource()~='vorp_stables' then return true end
 if not L.ready then return true end
 return L.V('SELECT horse_id FROM fl_harnesses WHERE horse_id=?',{tonumber(horse) or -1})~=nil
end)
