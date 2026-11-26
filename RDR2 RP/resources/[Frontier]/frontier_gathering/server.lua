local C,R=GatherConfig,GatherRules
local E='frontier_gathering:'
local inv,skills,core=exports.frontier_inventory,exports.frontier_skills,exports.frontier_core
local ready=false
local sessions,locks,busy,last,worldLast,fishSessions,entityClaims={},{},{},{},{},{},{}
local modelKinds,herbItems,animals,fish={},{},{},{}
local function hash(s)return GetHashKey(s)&0xffffffff end
for _,s in ipairs(C.trees) do modelKinds[hash(s)]='logging' end
for _,s in ipairs(C.rocks) do modelKinds[hash(s)]='mining' end
for s,item in pairs(C.herbs) do local h=hash(s);modelKinds[h]='herbalism';herbItems[h]=item end
for s,item in pairs(C.animals) do animals[hash(s)]=item end
for _,s in ipairs(C.fish) do fish[hash(s)]=s end
local function notice(src,msg)TriggerClientEvent(E..'notice',src,tostring(msg)) end
local function uuid()local id=MySQL.scalar.await("SELECT LOWER(REPLACE(UUID(),'-',''))");assert(type(id)=='string' and #id==32 and id:match('^[a-f0-9]+
local function cid(src)return core:GetPlayerCharacterId(src) end
local function finite(n)return type(n)=='number' and n==n and math.abs(n)<20000 end
local function dist(a,b)return (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2 end
local function position(src)
 local ok,p=inv:GetGatheringPosition(src)
 if not ok then return nil,'inventory session: '..tostring(p) end
 if not C.worldBuckets[p.bucket] then return nil,'outdoor gathering unavailable in routing bucket '..tostring(p.bucket) end
 if not finite(p.x) or not finite(p.y) or not finite(p.z) then return nil,'invalid player coordinates' end
 return p
end
local function positionError(src,reason)
 if C.nativeDebug then
  local ped=GetPlayerPed(src)
  local health=ped and ped~=0 and DoesEntityExist(ped) and GetEntityHealth(ped) or 'unavailable'
  print(('[frontier_gathering] player=%s bucket=%s health=%s position rejected: %s'):format(src,tostring(GetPlayerRoutingBucket(src)),tostring(health),tostring(reason)))
 end
 return tostring(reason)
end
local function run(src,fn)
 if not ready then return notice(src,'Gathering is not ready; check the server console.') end
 if busy[src] then return notice(src,'Gathering is busy; try again.') end
 local now=GetGameTimer();if last[src] and now-last[src]<200 then return end
 last[src]=now;busy[src]=true
 local ok,err=pcall(fn);busy[src]=nil
 if not ok then print('[frontier_gathering] '..tostring(err));notice(src,'Gathering unavailable. Try again or /gatherrecover.') end
end
local function release(src)
 local w=sessions[src]
 if w and locks[w.node.id]==src then locks[w.node.id]=nil end
 sessions[src]=nil
end
local function reject(src,msg)release(src);TriggerClientEvent(E..'end',src);notice(src,msg) end
local function nodeFrom(src,d)
 if type(d)~='table' or not C.actions[d.action] or not finite(d.x) or not finite(d.y) or not finite(d.z) then return nil,'Invalid target' end
 local pos,why=position(src);if not pos then return nil,positionError(src,why) end
 if not R.inReach(d.action,pos,d) then
  local dx,dy,dz=pos.x-d.x,pos.y-d.y,pos.z-d.z
  return nil,('Move closer (horizontal %.1fm, vertical %.1fm)'):format(math.sqrt(dx*dx+dy*dy),math.abs(dz))
 end
 local a=d.action;local model=type(d.model)=='number' and math.tointeger(d.model) or 0
 model=model and model&0xffffffff or 0
 if a=='logging' or a=='mining' or a=='herbalism' then
  if modelKinds[model]~=a then return nil,'Unsupported natural model' end
  if R.protected(d.x,d.y) and a=='logging' then return nil,'Protected town trees' end
 else
  model=0
  if not R.region(pos.x,pos.y) then return nil,'Find an eligible river reach' end
 end
 local n={id=R.key(a,d.x,d.y,d.z),action=a,model=model,x=d.x,y=d.y,z=d.z,item=herbItems[model]}
 if C.strictSurvey then
  local row=MySQL.single.await('SELECT * FROM frontier_gather_survey WHERE id=?',{n.id})
  if not row or tonumber(row.model)~=model or dist(row,n)>2.25 then return nil,'This resource has not been surveyed' end
  n.x,n.y,n.z=row.x,row.y,row.z
 end
 return n
end
local function remaining(n)
 local row=MySQL.single.await('SELECT remaining,next_at FROM frontier_gather_nodes WHERE id=?',{n.id})
 local max=C.actions[n.action].charges
 if not row or tonumber(row.next_at)>0 and tonumber(row.next_at)<=os.time() then return max end
 return tonumber(row.remaining)
end
local function pending(id)
 return MySQL.single.await('SELECT * FROM frontier_gather_claims WHERE character_id=? AND phase<2 ORDER BY created LIMIT 1',{id})
end
local function commitHarvest(src,character,d,key,preview)
 return inv:GatheringCommit(src,character,{kind=d.kind,instance=d.instance,item=d.item,count=tonumber(d.count),wear=tonumber(d.wear),key=key,preview=preview==true,extra=d.extra,metadata=d.metadata})
end
local function recover(src,row)
 if not row then return true end
 local d=json.decode(row.payload)
 if cid(src)~=row.character_id then return false end
 if tonumber(row.phase)==0 then
  local ok,err
  if d.smith then ok,err=inv:GatheringSmith(src,row.character_id,d,'gather:'..row.id,false)
  else ok,err=commitHarvest(src,row.character_id,d,'gather:'..row.id,false) end
  if not ok then
   print(('[frontier_gathering] pending claim %s skill=%s reason=%s count=%s wear=%s tool=%s'):format(row.id,row.skill,tostring(err),tostring(d.count),tostring(d.wear),tostring(d.kind)))
   local hint=({weight='Free satchel weight',slots='Free satchel slots',tool_missing='Restore the original tool',conflict='Wait a moment and retry'})[err] or 'Saved reward retained; check server console'
   notice(src,'Pending harvest: '..tostring(err)..'. '..hint..', then /gatherrecover.');return false
  end
  MySQL.update.await('UPDATE frontier_gather_claims SET phase=1 WHERE id=? AND phase=0',{row.id})
 end
 local ok,err=skills:GrantXP(row.character_id,row.skill,d.xp,row.id)
 if not ok then notice(src,'Harvest secured; XP pending: '..tostring(err));return false end
 MySQL.update.await('UPDATE frontier_gather_claims SET phase=2 WHERE id=?',{row.id})
 notice(src,(d.smith and (d.instance and 'Tool repaired' or 'Crafted '..d.item) or (d.count>0 and ('Received '..d.count..' × '..(d.item or '')..(d.extra and (' + '..d.extra.count..' × '..d.extra.item) or '')) or 'Nothing valuable found'))..' · +'..d.xp..' XP')
 return true
end
local function makeClaim(src,id,skill,d,node,left)
 local key=uuid()
 local statements={}
 if node then
  statements[#statements+1]={query=[[INSERT INTO frontier_gather_nodes(id,action,model,x,y,z,remaining,next_at) VALUES(?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE action=VALUES(action),model=VALUES(model),x=VALUES(x),y=VALUES(y),z=VALUES(z),remaining=VALUES(remaining),next_at=VALUES(next_at)]],
   values={node.id,node.action,node.model,node.x,node.y,node.z,left,left==0 and os.time()+C.actions[node.action].regen or 0}}
 end
 statements[#statements+1]={query='INSERT INTO frontier_gather_claims(id,character_id,skill,payload,phase,created) VALUES(?,?,?,?,0,?)',values={key,id,skill,json.encode(d),os.time()}}
 if not MySQL.transaction.await(statements) then return nil end
 return {id=key,character_id=id,skill=skill,payload=json.encode(d),phase=0}
end
local function sample(src,node,score,skill,tool)
 local item,count=R.reward(node.action,node,score,skill,tool and tool.metadata,math.random())
 return {kind=C.actions[node.action].tool,instance=tool and tool.instance,item=item,count=count,wear=tool and skill.wear or 0,xp=math.floor(10+10*score)}
end
RegisterNetEvent(E..'begin',function(d)
 local src=source;run(src,function()
  if sessions[src] or fishSessions[src] then return notice(src,'Already working') end
  local id=cid(src);if not id then return notice(src,'No active Frontier character') end
  local p=pending(id);if p and not recover(src,p) then return end
  local n,err=nodeFrom(src,d);if not n then return notice(src,err) end
  if locks[n.id] then return notice(src,'Someone is already working here') end
  locks[n.id]=src
  local a=C.actions[n.action];local pos,why=position(src);if not pos then locks[n.id]=nil;return notice(src,positionError(src,why)) end
  local w={actor=id,node=n,bucket=pos.bucket,expires=GetGameTimer()+20000};sessions[src]=w
  if remaining(n)<=0 then return reject(src,'Resource depleted; return later') end
  local tool
  if a.tool then local ok,t=inv:GetGatheringTool(src,a.tool,false,true);if not ok then return reject(src,'Equip a working '..a.tool..' first') end;tool=t end
  local ok,skill=skills:GetSkill(src,n.action);if not ok then return reject(src,'Skill system unavailable') end
  -- Worst-case preview for every possible output; no animation when bag cannot fit even the minimum.
  local outputs=n.action=='mining' and {'iron_ore','coal','gather_stone','gather_copper_ore','gather_gold_ore'} or n.action=='prospecting' and {'gather_gold_dust','gather_gold_flakes','gather_gold_nugget'} or {n.action=='logging' and 'wood' or n.action=='herbalism' and n.item or 'gather_'..n.action}
  for _,item in ipairs(outputs) do
   local fits,e=commitHarvest(src,id,{kind=a.tool,instance=tool and tool.instance,item=item,count=1,wear=0},'preview:'..src,true)
   if not fits then return reject(src,'Inventory cannot receive '..item..': '..tostring(e)) end
  end
  local current,why=position(src);if not current then return reject(src,positionError(src,why)) end
  if cid(src)~=id or current.bucket~=w.bucket or not R.inReach(n.action,current,n) then return reject(src,'Character changed or moved away') end
  w.tool,w.skill=tool,skill
  w.token=uuid();w.duration=n.action=='herbalism' and C.herbMs or C.workMs
  w.target=math.random(27,73)/100;w.started=GetGameTimer();w.expires=w.started+w.duration+7000
  TriggerClientEvent(E..'work',src,{token=w.token,action=n.action,label=a.name,ms=w.duration,target=w.target,width=.11*skill.window,qte=n.action~='herbalism'})
 end)
end)
RegisterNetEvent(E..'strike',function(token)
 local src=source;local w=sessions[src];if not w or w.token~=token or w.hit or not w.started or cid(src)~=w.actor then return end
 local elapsed=GetGameTimer()-w.started
 if elapsed<0 or elapsed>w.duration+350 then return end
 -- Server timestamps; latency allowance is bounded, client never submits a score.
 local phase=(elapsed%1600)/1600;local distance=math.abs(phase-w.target)
 w.hit=R.clamp(1-distance/(.11*w.skill.window+.075),0,1)
end)
RegisterNetEvent(E..'finish',function(token)
 local src=source;run(src,function()
  local w=sessions[src];if not w or w.token~=token or w.finishing then return end
  w.finishing=true
  local elapsed=GetGameTimer()-w.started;local pos,why=position(src)
  if not pos then return reject(src,positionError(src,why)) end
  if elapsed<w.duration or GetGameTimer()>w.expires or cid(src)~=w.actor then return reject(src,'Work expired or character changed') end
  if pos.bucket~=w.bucket or not R.inReach(w.node.action,pos,w.node) then return reject(src,'You moved away from the resource') end
  if w.smith then
   local workshop=GetResourceState('frontier_property')=='started' and exports.frontier_property:GatheringWorkshop(src)
   if not workshop or workshop.id~=w.workshop.id then return reject(src,'Remain at the workshop') end
   local d=w.smith;local score=w.hit or 0
   if not d.instance then d.metadata=R.encodeQuality(d.material,math.floor(w.skill.level*.4+score*40+workshop.equipment*.2+.5),workshop.name) end
   local fits,err=inv:GatheringSmith(src,w.actor,d,'preview:'..src,true)
   if not fits then return reject(src,'Smithing failed: '..tostring(err)) end
   local row=makeClaim(src,w.actor,'blacksmithing',d)
   release(src);TriggerClientEvent(E..'end',src);if row then recover(src,row) else notice(src,'Could not reserve work') end;return
  end
  local n=w.node
  if w.tool then local ok,t=inv:GetGatheringTool(src,C.actions[n.action].tool,false,true);if not ok or t.instance~=w.tool.instance then return reject(src,'Keep the original tool equipped until work finishes') end end
  local left=remaining(n)
  if left<=0 then return reject(src,'Resource already depleted') end
  local score=n.action=='herbalism' and .65 or w.hit or 0
  local d=sample(src,n,score,w.skill,w.tool)
  local fits,issue=commitHarvest(src,w.actor,d,'preview:'..src,true)
  if not fits then return reject(src,'Cannot complete: '..tostring(issue)) end
  local current,why=position(src);if not current then return reject(src,positionError(src,why)) end
  if cid(src)~=w.actor or current.bucket~=w.bucket or not R.inReach(n.action,current,n) then return reject(src,'Character changed or moved away') end
  local row=makeClaim(src,w.actor,n.action,d,n,left-1)
  if not row then return reject(src,'Could not reserve resource') end
  if left==1 then TriggerClientEvent(E..'depleted',-1,{id=n.id,action=n.action,model=n.model,x=n.x,y=n.y,z=n.z,next_at=os.time()+C.actions[n.action].regen}) end
  release(src);TriggerClientEvent(E..'end',src);recover(src,row)
 end)
end)
RegisterNetEvent(E..'cancel',function()local src=source;if not busy[src] then release(src);TriggerClientEvent(E..'end',src) end end)
RegisterNetEvent(E..'recover',function()local src=source;run(src,function()local id=cid(src);if id then local p=pending(id);if p then recover(src,p) else notice(src,'No pending harvest') end end end)end)
RegisterNetEvent(E..'world',function()
 local src=source;if not ready then return end
 local now=GetGameTimer();if worldLast[src] and now-worldLast[src]<3000 then return end;worldLast[src]=now
 local p=position(src);if not p then return end
 local rows=MySQL.query.await('SELECT id,action,model,x,y,z,next_at FROM frontier_gather_nodes WHERE remaining=0 AND next_at>? AND x BETWEEN ? AND ? AND y BETWEEN ? AND ? LIMIT 500',{os.time(),p.x-C.stream,p.x+C.stream,p.y-C.stream,p.y+C.stream})
 TriggerClientEvent(E..'world',src,rows or {})
end)
RegisterNetEvent(E..'survey',function(d)
 local src=source;if not IsPlayerAceAllowed(src,C.adminAce) then return end
 run(src,function()
  if type(d)~='table' or not C.actions[d.action] or not finite(d.x) or not finite(d.y) or not finite(d.z) then return end
  local pos=position(src);if not pos or not R.inReach(d.action,pos,d) then return end
  local m=math.tointeger(d.model or 0);if not m then return end;m=m&0xffffffff
  if modelKinds[m]~=d.action and not (m==0 and R.region(d.x,d.y) and (d.action=='prospecting' or d.action=='clay' or d.action=='sand')) then return end
  local k=R.key(d.action,d.x,d.y,d.z)
  MySQL.update.await('INSERT INTO frontier_gather_survey(id,action,model,x,y,z) VALUES(?,?,?,?,?,?) ON DUPLICATE KEY UPDATE model=VALUES(model),x=VALUES(x),y=VALUES(y),z=VALUES(z)',{k,d.action,m,d.x,d.y,d.z})
  notice(src,'Surveyed '..k)
 end)
end)
-- Cfx/RedM builds differ in which death natives and health values replicate.
-- A confirmed dead animal may migrate owners while being skinned. Only the
-- weaker health-floor fallback requires ownership and the client's dead flag.
local function optionalNative(fn,...)
 if type(fn)~='function' then return nil end
 local ok,v=pcall(fn,...);if ok then return v end
end
local function nativeEntity(src,net,lookup,dead,reportedModel,reportedDead)
 if type(net)~='number' or net%1~=0 or net<=0 or net>65535 then return nil,'invalid network ID' end
 local ent=NetworkGetEntityFromNetworkId(net)
 if not ent or ent==0 or not DoesEntityExist(ent) then return nil,'animal not replicated' end
 local pos,why=position(src);if not pos then return nil,positionError(src,why) end
 if GetEntityType(ent)~=1 then return nil,'entity is not a ped' end
 local bucket=GetEntityRoutingBucket(ent)
 if bucket~=GetPlayerRoutingBucket(src) then return nil,'different routing bucket' end
 local p=GetEntityCoords(ent);if dist(pos,p)>64 then return nil,'animal too far away' end
 local model=GetEntityModel(ent)&0xffffffff
 if not lookup[model] then return nil,'unsupported animal model '..model end
 if reportedModel~=nil and reportedModel~=model then return nil,'animal model mismatch' end
 local owner=NetworkGetEntityOwner(ent)
 local used=entityClaims[net]
 if used and used.ent==ent then return nil,'animal already claimed' end
 if dead then
  local health=GetEntityHealth(ent)
  local isDead=optionalNative(IsEntityDead,ent)
  local isDying=optionalNative(IsPedDeadOrDying,ent,true)
  local confirmed=isDead==true or isDead==1 or isDying==true or isDying==1 or (type(health)=='number' and health<=0)
  if not confirmed then
   local maxHealth=optionalNative(GetEntityMaxHealth,ent) or optionalNative(GetPedMaxHealth,ent)
   local floor=C.allowHuntingHealthFloor and not C.strictSurvey and reportedDead==true and owner==src and health==100 and type(maxHealth)=='number' and maxHealth>100
   if not floor then return nil,('death state not confirmed (health=%s max=%s owner=%s)'):format(tostring(health),tostring(maxHealth),tostring(owner)) end
  end
 elseif owner~=src then return nil,'fish network ownership mismatch' end
 return ent,model
end
local function catchFailure(src,net,reason)
 if C.nativeDebug then print(('[frontier_gathering] native catch rejected: player=%s net=%s reason=%s'):format(src,tostring(net),tostring(reason))) end
 notice(src,'Native catch could not be verified: '..tostring(reason))
end
local function nativeClaim(src,net,skill,toolKind,lookup,dead,reportedModel,reportedDead)
 local id=cid(src);if not id then return false end
 local ent,model=nativeEntity(src,net,lookup,dead,reportedModel,reportedDead)
 -- Give OneSync a short window to replicate the corpse or its final death state.
 if not ent and dead and (model=='animal not replicated' or model:find('death state not confirmed',1,true)) then
  for i=1,5 do
   Wait(150);if cid(src)~=id then return false end
   ent,model=nativeEntity(src,net,lookup,dead,reportedModel,reportedDead);if ent then break end
   if model~='animal not replicated' and not model:find('death state not confirmed',1,true) then break end
  end
 end
 if not ent then catchFailure(src,net,model);return false end
 local p=pending(id);if p and not recover(src,p) then return false end
 local ok,tool=inv:GetGatheringTool(src,toolKind,false,true);if not ok then notice(src,'Equip a working '..toolKind..' first');return false end
 local found,stats=skills:GetSkill(src,skill);if not found then return false end
 local item=skill=='fishing' and 'gather_fish' or 'meat'
 local n=skill=='fishing' and 1 or math.max(1,math.floor(3*stats.yield*tool.metadata.yield+.5))
 local d={kind=toolKind,instance=tool.instance,item=item,count=n,wear=stats.wear,xp=20}
 if skill=='fishing' then d.metadata=json.encode({species=lookup[model]}) elseif item=='meat' then d.extra={item='gather_pelt',count=1} end
 local fits,err=commitHarvest(src,id,d,'preview:'..src,true)
 if not fits then notice(src,'Cannot carry catch: '..tostring(err));return false end
 if cid(src)~=id then return false end
 local checked,reason=nativeEntity(src,net,lookup,dead,reportedModel,reportedDead)
 if not checked or checked~=ent then catchFailure(src,net,checked and 'animal changed' or reason);return false end
 entityClaims[net]={ent=ent}
 local row=makeClaim(src,id,skill,d)
 if not row then entityClaims[net]=nil;return false end
 recover(src,row);return true
end
RegisterNetEvent(E..'skin',function(net,model,dead)
 local src=source;if not C.nativeHunting then return end
 if type(model)~='number' or not math.tointeger(model) or model<0 or model>0xffffffff or type(dead)~='boolean' then return end
 run(src,function()if not sessions[src] then nativeClaim(src,net,'hunting','knife',animals,true,model,dead) end end)
end)
RegisterNetEvent(E..'fishStart',function()
 local src=source;if not C.nativeFishing or GetResourceState('vorp_fishing')~='started' then return notice(src,'Native fishing resource is not running') end
 run(src,function()
  local id=cid(src);local pos,why=position(src);if not pos then return notice(src,positionError(src,why)) end
  if not id or not R.region(pos.x,pos.y) or fishSessions[src] or sessions[src] then return notice(src,'Stand at an eligible river reach and equip a native rod') end
  local p=pending(id);if p and not recover(src,p) then return end
  local ok,tool=inv:GetGatheringTool(src,'rod',false,true);if not ok then return notice(src,'Equip your Frontier fishing rod first') end
  local has,bait=inv:HasItem(src,'gather_bait',1);if not has or not bait then return notice(src,'Fishing bait required') end
  local key=uuid();local removed,err=inv:RemoveItem(src,'gather_bait',1,nil,'bait:'..key)
  if not removed then return notice(src,err) end
  if cid(src)~=id then return end
  fishSessions[src]={actor=id,started=GetGameTimer(),expires=GetGameTimer()+600000}
  TriggerClientEvent('vorp_fishing:UseBait',src,'p_baitWorm01x')
 end)
end)
exports('NativeFish',function(src,net,status)
 if GetInvokingResource()~='vorp_fishing' or not C.nativeFishing then return false end
 local w=fishSessions[src]
 if not w or w.actor~=cid(src) or GetGameTimer()-w.started<8000 or GetGameTimer()>w.expires or status~='keep' then return true end
 fishSessions[src]=nil
 run(src,function()nativeClaim(src,net,'fishing','rod',fish,false)end)
 return true
end)
exports('StopFishing',function(src)if GetInvokingResource()=='vorp_fishing' then fishSessions[src]=nil end end)
AddEventHandler('playerDropped',function()local src=source;release(src);fishSessions[src]=nil;busy[src]=nil;last[src]=nil;worldLast[src]=nil end)
AddEventHandler('entityRemoved',function(ent)for net,v in pairs(entityClaims) do if v.ent==ent then entityClaims[net]=nil end end end)
CreateThread(function()
 while true do Wait(1000);local now=GetGameTimer()
  for src,w in pairs(sessions) do if not busy[src] and (now>w.expires or cid(src)~=w.actor) then reject(src,'Work expired') end end
  for src,w in pairs(fishSessions) do if now>w.expires or cid(src)~=w.actor then fishSessions[src]=nil end end
 end
end)
CreateThread(function()
 for id,v in pairs(C.items) do
  while true do local ok,err=inv:RegisterItem(id,{name=v.name,description=v.name,category='Gathering',grams=v.grams,maxStack=40});if ok then break end;print('[frontier_gathering] '..id..': '..tostring(err));Wait(3000) end
 end
 for kind,t in pairs(C.tools) do for mat,m in pairs(C.materials) do
  local id='gather_'..kind..'_'..mat;local name=m.label..' '..t.name
  while true do
   local ok,err=inv:RegisterItem(id,{name=name,description='Repairable gathering tool',category='Tools',classification='tool',grams=t.grams,maxStack=1,condition=true,metadata=R.encodeQuality(mat,50,'General store')})
   if ok then break end;print('[frontier_gathering] '..id..': '..tostring(err));Wait(3000)
  end
 end end
 ready=true;print('[frontier_gathering] ready')
end)

RegisterNetEvent(E..'smithBegin',function(kind,material,repair)
 local src=source;run(src,function()
  if not C.tools[kind] or sessions[src] or fishSessions[src] then return notice(src,'Choose a tool or finish your current activity') end
  local id=cid(src);local pos,why=position(src);if not pos then return notice(src,positionError(src,why)) end;if not id then return notice(src,'No active Frontier character') end
  local p=pending(id);if p and not recover(src,p) then return end
  local workshop=GetResourceState('frontier_property')=='started' and exports.frontier_property:GatheringWorkshop(src)
  if not workshop then return notice(src,'Approach a completed workshop you may use') end
  local d={smith=true,kind=kind,xp=25}
  if repair==true then
   local ok,t=inv:GetGatheringTool(src,kind,true);if not ok then return notice(src,'No tool to repair') end
   if t.metadata.uses>=t.metadata.maxUses then return notice(src,'Tool is already fully repaired') end
   material=t.metadata.materialId;d.instance=t.instance;d.item=t.item
  else
   if not C.materials[material] then return notice(src,'Materials: crude, iron, steel, hardened') end
   d.item='gather_'..kind..'_'..material;d.metadata=R.encodeQuality(material,50,workshop.name)
  end
  if not C.materials[material] then return notice(src,'Unsupported tool material') end
  d.material=material;d.metal=(material=='steel' or material=='hardened') and 'gather_steel' or 'iron_ingot'
  d.cost=repair and 1 or material=='hardened' and 3 or 2;d.wood=1
  local fits,err=inv:GatheringSmith(src,id,d,'preview:'..src,true)
  if not fits then return notice(src,'Requires '..d.cost..' '..d.metal..' and 1 wood; '..tostring(err)) end
  local ok,skill=skills:GetSkill(src,'blacksmithing');if not ok then return notice(src,'Skills unavailable') end
  local node={id='smith:'..workshop.id,x=pos.x,y=pos.y,z=pos.z};if locks[node.id] then return notice(src,'Workshop is busy') end
  local token=uuid();local now=GetGameTimer()
  local w={actor=id,node=node,bucket=pos.bucket,smith=d,workshop=workshop,token=token,skill=skill,duration=C.workMs,target=math.random(27,73)/100,started=now,expires=now+C.workMs+7000}
  sessions[src]=w;locks[node.id]=src
  TriggerClientEvent(E..'work',src,{token=token,action='smith',label=repair and 'Repair tool' or 'Forge tool',ms=w.duration,target=w.target,width=.11*skill.window,qte=true})
 end)
end)

-- Diagnostic reads only server state; no client coordinates are trusted.
RegisterNetEvent(E..'debug',function()
 local src=source
 run(src,function()
  local pos,why=position(src)
  if not pos then return notice(src,positionError(src,why)) end
  local ped=GetPlayerPed(src)
  local msg=('Server position %.2f %.2f %.2f | bucket=%s health=%s | gathering session OK'):format(pos.x,pos.y,pos.z,tostring(pos.bucket),tostring(GetEntityHealth(ped)))
  print('[frontier_gathering] '..msg);notice(src,msg)
 end)
end)
),'Invalid database UUID');return id end
local function cid(src)return core:GetPlayerCharacterId(src) end
local function finite(n)return type(n)=='number' and n==n and math.abs(n)<20000 end
local function dist(a,b)return (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2 end
local function position(src)
 local ok,p=inv:GetGatheringPosition(src)
 if not ok then return nil,'inventory session: '..tostring(p) end
 if not C.worldBuckets[p.bucket] then return nil,'outdoor gathering unavailable in routing bucket '..tostring(p.bucket) end
 if not finite(p.x) or not finite(p.y) or not finite(p.z) then return nil,'invalid player coordinates' end
 return p
end
local function positionError(src,reason)
 if C.nativeDebug then
  local ped=GetPlayerPed(src)
  local health=ped and ped~=0 and DoesEntityExist(ped) and GetEntityHealth(ped) or 'unavailable'
  print(('[frontier_gathering] player=%s bucket=%s health=%s position rejected: %s'):format(src,tostring(GetPlayerRoutingBucket(src)),tostring(health),tostring(reason)))
 end
 return tostring(reason)
end
local function run(src,fn)
 if not ready then return notice(src,'Gathering is not ready; check the server console.') end
 if busy[src] then return notice(src,'Gathering is busy; try again.') end
 local now=GetGameTimer();if last[src] and now-last[src]<200 then return end
 last[src]=now;busy[src]=true
 local ok,err=pcall(fn);busy[src]=nil
 if not ok then print('[frontier_gathering] '..tostring(err));notice(src,'Gathering unavailable. Try again or /gatherrecover.') end
end
local function release(src)
 local w=sessions[src]
 if w and locks[w.node.id]==src then locks[w.node.id]=nil end
 sessions[src]=nil
end
local function reject(src,msg)release(src);TriggerClientEvent(E..'end',src);notice(src,msg) end
local function nodeFrom(src,d)
 if type(d)~='table' or not C.actions[d.action] or not finite(d.x) or not finite(d.y) or not finite(d.z) then return nil,'Invalid target' end
 local pos,why=position(src);if not pos then return nil,positionError(src,why) end
 if not R.inReach(d.action,pos,d) then
  local dx,dy,dz=pos.x-d.x,pos.y-d.y,pos.z-d.z
  return nil,('Move closer (horizontal %.1fm, vertical %.1fm)'):format(math.sqrt(dx*dx+dy*dy),math.abs(dz))
 end
 local a=d.action;local model=type(d.model)=='number' and math.tointeger(d.model) or 0
 model=model and model&0xffffffff or 0
 if a=='logging' or a=='mining' or a=='herbalism' then
  if modelKinds[model]~=a then return nil,'Unsupported natural model' end
  if R.protected(d.x,d.y) and a=='logging' then return nil,'Protected town trees' end
 else
  model=0
  if not R.region(pos.x,pos.y) then return nil,'Find an eligible river reach' end
 end
 local n={id=R.key(a,d.x,d.y,d.z),action=a,model=model,x=d.x,y=d.y,z=d.z,item=herbItems[model]}
 if C.strictSurvey then
  local row=MySQL.single.await('SELECT * FROM frontier_gather_survey WHERE id=?',{n.id})
  if not row or tonumber(row.model)~=model or dist(row,n)>2.25 then return nil,'This resource has not been surveyed' end
  n.x,n.y,n.z=row.x,row.y,row.z
 end
 return n
end
local function remaining(n)
 local row=MySQL.single.await('SELECT remaining,next_at FROM frontier_gather_nodes WHERE id=?',{n.id})
 local max=C.actions[n.action].charges
 if not row or tonumber(row.next_at)>0 and tonumber(row.next_at)<=os.time() then return max end
 return tonumber(row.remaining)
end
local function pending(id)
 return MySQL.single.await('SELECT * FROM frontier_gather_claims WHERE character_id=? AND phase<2 ORDER BY created LIMIT 1',{id})
end
local function recover(src,row)
 if not row then return true end
 local d=json.decode(row.payload)
 if cid(src)~=row.character_id then return false end
 if tonumber(row.phase)==0 then
  local ok,err
  if d.smith then ok,err=inv:GatheringSmith(src,row.character_id,d,'gather:'..row.id,false)
  else ok,err=inv:GatheringCommit(src,row.character_id,d.kind,d.instance,d.item,d.count,d.wear,'gather:'..row.id,false,d.extra,d.metadata) end
  if not ok then notice(src,'Pending harvest: '..tostring(err)..'. Free satchel space or restore your tool, then /gatherrecover.');return false end
  MySQL.update.await('UPDATE frontier_gather_claims SET phase=1 WHERE id=? AND phase=0',{row.id})
 end
 local ok,err=skills:GrantXP(row.character_id,row.skill,d.xp,row.id)
 if not ok then notice(src,'Harvest secured; XP pending: '..tostring(err));return false end
 MySQL.update.await('UPDATE frontier_gather_claims SET phase=2 WHERE id=?',{row.id})
 notice(src,(d.smith and (d.instance and 'Tool repaired' or 'Crafted '..d.item) or (d.count>0 and ('Received '..d.count..' × '..(d.item or '')) or 'Nothing valuable found'))..' · +'..d.xp..' XP')
 return true
end
local function makeClaim(src,id,skill,d,node,left)
 local key=uuid()
 local statements={}
 if node then
  statements[#statements+1]={query=[[INSERT INTO frontier_gather_nodes(id,action,model,x,y,z,remaining,next_at) VALUES(?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE action=VALUES(action),model=VALUES(model),x=VALUES(x),y=VALUES(y),z=VALUES(z),remaining=VALUES(remaining),next_at=VALUES(next_at)]],
   values={node.id,node.action,node.model,node.x,node.y,node.z,left,left==0 and os.time()+C.actions[node.action].regen or 0}}
 end
 statements[#statements+1]={query='INSERT INTO frontier_gather_claims(id,character_id,skill,payload,phase,created) VALUES(?,?,?,?,0,?)',values={key,id,skill,json.encode(d),os.time()}}
 if not MySQL.transaction.await(statements) then return nil end
 return {id=key,character_id=id,skill=skill,payload=json.encode(d),phase=0}
end
local function sample(src,node,score,skill,tool)
 local item,count=R.reward(node.action,node,score,skill,tool and tool.metadata,math.random())
 return {kind=C.actions[node.action].tool,instance=tool and tool.instance,item=item,count=count,wear=tool and skill.wear or 0,xp=math.floor(10+10*score)}
end
RegisterNetEvent(E..'begin',function(d)
 local src=source;run(src,function()
  if sessions[src] or fishSessions[src] then return notice(src,'Already working') end
  local id=cid(src);if not id then return notice(src,'No active Frontier character') end
  local p=pending(id);if p and not recover(src,p) then return end
  local n,err=nodeFrom(src,d);if not n then return notice(src,err) end
  if locks[n.id] then return notice(src,'Someone is already working here') end
  locks[n.id]=src
  local a=C.actions[n.action];local pos,why=position(src);if not pos then locks[n.id]=nil;return notice(src,positionError(src,why)) end
  local w={actor=id,node=n,bucket=pos.bucket,expires=GetGameTimer()+20000};sessions[src]=w
  if remaining(n)<=0 then return reject(src,'Resource depleted; return later') end
  local tool
  if a.tool then local ok,t=inv:GetGatheringTool(src,a.tool);if not ok then return reject(src,'A working '..a.tool..' is required in your satchel or toolbelt') end;tool=t end
  local ok,skill=skills:GetSkill(src,n.action);if not ok then return reject(src,'Skill system unavailable') end
  -- Worst-case preview for every possible output; no animation when bag cannot fit even the minimum.
  local outputs=n.action=='mining' and {'iron_ore','coal','gather_stone','gather_copper_ore','gather_gold_ore'} or n.action=='prospecting' and {'gather_gold_dust','gather_gold_flakes','gather_gold_nugget'} or {n.action=='logging' and 'wood' or n.action=='herbalism' and n.item or 'gather_'..n.action}
  for _,item in ipairs(outputs) do
   local fits,e=inv:GatheringCommit(src,id,a.tool,tool and tool.instance,item,1,0,'preview:'..src,true)
   if not fits then return reject(src,'Inventory cannot receive '..item..': '..tostring(e)) end
  end
  local current,why=position(src);if not current then return reject(src,positionError(src,why)) end
  if cid(src)~=id or current.bucket~=w.bucket or not R.inReach(n.action,current,n) then return reject(src,'Character changed or moved away') end
  w.tool,w.skill=tool,skill
  w.token=uuid();w.duration=n.action=='herbalism' and C.herbMs or C.workMs
  w.target=math.random(27,73)/100;w.started=GetGameTimer();w.expires=w.started+w.duration+7000
  TriggerClientEvent(E..'work',src,{token=w.token,action=n.action,label=a.name,ms=w.duration,target=w.target,width=.11*skill.window,qte=n.action~='herbalism'})
 end)
end)
RegisterNetEvent(E..'strike',function(token)
 local src=source;local w=sessions[src];if not w or w.token~=token or w.hit or not w.started or cid(src)~=w.actor then return end
 local elapsed=GetGameTimer()-w.started
 if elapsed<0 or elapsed>w.duration+350 then return end
 -- Server timestamps; latency allowance is bounded, client never submits a score.
 local phase=(elapsed%1600)/1600;local distance=math.abs(phase-w.target)
 w.hit=R.clamp(1-distance/(.11*w.skill.window+.075),0,1)
end)
RegisterNetEvent(E..'finish',function(token)
 local src=source;run(src,function()
  local w=sessions[src];if not w or w.token~=token or w.finishing then return end
  w.finishing=true
  local elapsed=GetGameTimer()-w.started;local pos,why=position(src)
  if not pos then return reject(src,positionError(src,why)) end
  if elapsed<w.duration or GetGameTimer()>w.expires or cid(src)~=w.actor then return reject(src,'Work expired or character changed') end
  if pos.bucket~=w.bucket or not R.inReach(w.node.action,pos,w.node) then return reject(src,'You moved away from the resource') end
  if w.smith then
   local workshop=GetResourceState('frontier_property')=='started' and exports.frontier_property:GatheringWorkshop(src)
   if not workshop or workshop.id~=w.workshop.id then return reject(src,'Remain at the workshop') end
   local d=w.smith;local score=w.hit or 0
   if not d.instance then d.metadata=R.encodeQuality(d.material,math.floor(w.skill.level*.4+score*40+workshop.equipment*.2+.5),workshop.name) end
   local fits,err=inv:GatheringSmith(src,w.actor,d,'preview:'..src,true)
   if not fits then return reject(src,'Smithing failed: '..tostring(err)) end
   local row=makeClaim(src,w.actor,'blacksmithing',d)
   release(src);TriggerClientEvent(E..'end',src);if row then recover(src,row) else notice(src,'Could not reserve work') end;return
  end
  local n=w.node;local left=remaining(n)
  if left<=0 then return reject(src,'Resource already depleted') end
  local score=n.action=='herbalism' and .65 or w.hit or 0
  local d=sample(src,n,score,w.skill,w.tool)
  local fits,issue=inv:GatheringCommit(src,w.actor,d.kind,d.instance,d.item,d.count,d.wear,'preview:'..src,true)
  if not fits then return reject(src,'Cannot complete: '..tostring(issue)) end
  local current,why=position(src);if not current then return reject(src,positionError(src,why)) end
  if cid(src)~=w.actor or current.bucket~=w.bucket or not R.inReach(n.action,current,n) then return reject(src,'Character changed or moved away') end
  local row=makeClaim(src,w.actor,n.action,d,n,left-1)
  if not row then return reject(src,'Could not reserve resource') end
  if left==1 then TriggerClientEvent(E..'depleted',-1,{id=n.id,action=n.action,model=n.model,x=n.x,y=n.y,z=n.z,next_at=os.time()+C.actions[n.action].regen}) end
  release(src);TriggerClientEvent(E..'end',src);recover(src,row)
 end)
end)
RegisterNetEvent(E..'cancel',function()local src=source;if not busy[src] then release(src);TriggerClientEvent(E..'end',src) end end)
RegisterNetEvent(E..'recover',function()local src=source;run(src,function()local id=cid(src);if id then local p=pending(id);if p then recover(src,p) else notice(src,'No pending harvest') end end end)end)
RegisterNetEvent(E..'world',function()
 local src=source;if not ready then return end
 local now=GetGameTimer();if worldLast[src] and now-worldLast[src]<3000 then return end;worldLast[src]=now
 local p=position(src);if not p then return end
 local rows=MySQL.query.await('SELECT id,action,model,x,y,z,next_at FROM frontier_gather_nodes WHERE remaining=0 AND next_at>? AND x BETWEEN ? AND ? AND y BETWEEN ? AND ? LIMIT 500',{os.time(),p.x-C.stream,p.x+C.stream,p.y-C.stream,p.y+C.stream})
 TriggerClientEvent(E..'world',src,rows or {})
end)
RegisterNetEvent(E..'survey',function(d)
 local src=source;if not IsPlayerAceAllowed(src,C.adminAce) then return end
 run(src,function()
  if type(d)~='table' or not C.actions[d.action] or not finite(d.x) or not finite(d.y) or not finite(d.z) then return end
  local pos=position(src);if not pos or not R.inReach(d.action,pos,d) then return end
  local m=math.tointeger(d.model or 0);if not m then return end;m=m&0xffffffff
  if modelKinds[m]~=d.action and not (m==0 and R.region(d.x,d.y) and (d.action=='prospecting' or d.action=='clay' or d.action=='sand')) then return end
  local k=R.key(d.action,d.x,d.y,d.z)
  MySQL.update.await('INSERT INTO frontier_gather_survey(id,action,model,x,y,z) VALUES(?,?,?,?,?,?) ON DUPLICATE KEY UPDATE model=VALUES(model),x=VALUES(x),y=VALUES(y),z=VALUES(z)',{k,d.action,m,d.x,d.y,d.z})
  notice(src,'Surveyed '..k)
 end)
end)
-- Cfx/RedM builds differ in which death natives and health values replicate.
-- A confirmed dead animal may migrate owners while being skinned. Only the
-- weaker health-floor fallback requires ownership and the client's dead flag.
local function optionalNative(fn,...)
 if type(fn)~='function' then return nil end
 local ok,v=pcall(fn,...);if ok then return v end
end
local function nativeEntity(src,net,lookup,dead,reportedModel,reportedDead)
 if type(net)~='number' or net%1~=0 or net<=0 or net>65535 then return nil,'invalid network ID' end
 local ent=NetworkGetEntityFromNetworkId(net)
 if not ent or ent==0 or not DoesEntityExist(ent) then return nil,'animal not replicated' end
 local pos,why=position(src);if not pos then return nil,positionError(src,why) end
 if GetEntityType(ent)~=1 then return nil,'entity is not a ped' end
 local bucket=GetEntityRoutingBucket(ent)
 if bucket~=GetPlayerRoutingBucket(src) then return nil,'different routing bucket' end
 local p=GetEntityCoords(ent);if dist(pos,p)>64 then return nil,'animal too far away' end
 local model=GetEntityModel(ent)&0xffffffff
 if not lookup[model] then return nil,'unsupported animal model '..model end
 if reportedModel~=nil and reportedModel~=model then return nil,'animal model mismatch' end
 local owner=NetworkGetEntityOwner(ent)
 local used=entityClaims[net]
 if used and used.ent==ent then return nil,'animal already claimed' end
 if dead then
  local health=GetEntityHealth(ent)
  local isDead=optionalNative(IsEntityDead,ent)
  local isDying=optionalNative(IsPedDeadOrDying,ent,true)
  local confirmed=isDead==true or isDead==1 or isDying==true or isDying==1 or (type(health)=='number' and health<=0)
  if not confirmed then
   local maxHealth=optionalNative(GetEntityMaxHealth,ent) or optionalNative(GetPedMaxHealth,ent)
   local floor=C.allowHuntingHealthFloor and not C.strictSurvey and reportedDead==true and owner==src and health==100 and type(maxHealth)=='number' and maxHealth>100
   if not floor then return nil,('death state not confirmed (health=%s max=%s owner=%s)'):format(tostring(health),tostring(maxHealth),tostring(owner)) end
  end
 elseif owner~=src then return nil,'fish network ownership mismatch' end
 return ent,model
end
local function catchFailure(src,net,reason)
 if C.nativeDebug then print(('[frontier_gathering] native catch rejected: player=%s net=%s reason=%s'):format(src,tostring(net),tostring(reason))) end
 notice(src,'Native catch could not be verified: '..tostring(reason))
end
local function nativeClaim(src,net,skill,toolKind,lookup,dead,reportedModel,reportedDead)
 local id=cid(src);if not id then return false end
 local ent,model=nativeEntity(src,net,lookup,dead,reportedModel,reportedDead)
 -- Give OneSync a short window to replicate the corpse or its final death state.
 if not ent and dead and (model=='animal not replicated' or model:find('death state not confirmed',1,true)) then
  for i=1,5 do
   Wait(150);if cid(src)~=id then return false end
   ent,model=nativeEntity(src,net,lookup,dead,reportedModel,reportedDead);if ent then break end
   if model~='animal not replicated' and not model:find('death state not confirmed',1,true) then break end
  end
 end
 if not ent then catchFailure(src,net,model);return false end
 local p=pending(id);if p and not recover(src,p) then return false end
 local ok,tool=inv:GetGatheringTool(src,toolKind);if not ok then notice(src,'A working '..toolKind..' is required');return false end
 local found,stats=skills:GetSkill(src,skill);if not found then return false end
 local item=skill=='fishing' and 'gather_fish' or lookup[model]
 local n=skill=='fishing' and 1 or math.max(1,math.floor(3*stats.yield*tool.metadata.yield+.5))
 local d={kind=toolKind,instance=tool.instance,item=item,count=n,wear=stats.wear,xp=20}
 if skill=='fishing' then d.metadata=json.encode({species=lookup[model]}) elseif item=='meat' then d.extra={item='gather_hide',count=1} end
 local fits,err=inv:GatheringCommit(src,id,d.kind,d.instance,item,n,d.wear,'preview:'..src,true,d.extra,d.metadata)
 if not fits then notice(src,'Cannot carry catch: '..tostring(err));return false end
 if cid(src)~=id then return false end
 local checked,reason=nativeEntity(src,net,lookup,dead,reportedModel,reportedDead)
 if not checked or checked~=ent then catchFailure(src,net,checked and 'animal changed' or reason);return false end
 entityClaims[net]={ent=ent}
 local row=makeClaim(src,id,skill,d)
 if not row then entityClaims[net]=nil;return false end
 recover(src,row);return true
end
RegisterNetEvent(E..'skin',function(net,model,dead)
 local src=source;if not C.nativeHunting then return end
 if type(model)~='number' or not math.tointeger(model) or model<0 or model>0xffffffff or type(dead)~='boolean' then return end
 run(src,function()if not sessions[src] then nativeClaim(src,net,'hunting','knife',animals,true,model,dead) end end)
end)
RegisterNetEvent(E..'fishStart',function()
 local src=source;if not C.nativeFishing or GetResourceState('vorp_fishing')~='started' then return notice(src,'Native fishing resource is not running') end
 run(src,function()
  local id=cid(src);local pos,why=position(src);if not pos then return notice(src,positionError(src,why)) end
  if not id or not R.region(pos.x,pos.y) or fishSessions[src] or sessions[src] then return notice(src,'Stand at an eligible river reach and equip a native rod') end
  local p=pending(id);if p and not recover(src,p) then return end
  local ok,tool=inv:GetGatheringTool(src,'rod');if not ok then return notice(src,'A working fishing rod item is required') end
  local has,bait=inv:HasItem(src,'gather_bait',1);if not has or not bait then return notice(src,'Fishing bait required') end
  local key=uuid();local removed,err=inv:RemoveItem(src,'gather_bait',1,nil,'bait:'..key)
  if not removed then return notice(src,err) end
  if cid(src)~=id then return end
  fishSessions[src]={actor=id,started=GetGameTimer(),expires=GetGameTimer()+600000}
  TriggerClientEvent('vorp_fishing:UseBait',src,'p_baitWorm01x')
 end)
end)
exports('NativeFish',function(src,net,status)
 if GetInvokingResource()~='vorp_fishing' or not C.nativeFishing then return false end
 local w=fishSessions[src]
 if not w or w.actor~=cid(src) or GetGameTimer()-w.started<8000 or GetGameTimer()>w.expires or status~='keep' then return true end
 fishSessions[src]=nil
 run(src,function()nativeClaim(src,net,'fishing','rod',fish,false)end)
 return true
end)
exports('StopFishing',function(src)if GetInvokingResource()=='vorp_fishing' then fishSessions[src]=nil end end)
AddEventHandler('playerDropped',function()local src=source;release(src);fishSessions[src]=nil;busy[src]=nil;last[src]=nil;worldLast[src]=nil end)
AddEventHandler('entityRemoved',function(ent)for net,v in pairs(entityClaims) do if v.ent==ent then entityClaims[net]=nil end end end)
CreateThread(function()
 while true do Wait(1000);local now=GetGameTimer()
  for src,w in pairs(sessions) do if not busy[src] and (now>w.expires or cid(src)~=w.actor) then reject(src,'Work expired') end end
  for src,w in pairs(fishSessions) do if now>w.expires or cid(src)~=w.actor then fishSessions[src]=nil end end
 end
end)
CreateThread(function()
 for id,v in pairs(C.items) do
  while true do local ok,err=inv:RegisterItem(id,{name=v.name,description=v.name,category='Gathering',grams=v.grams,maxStack=40});if ok then break end;print('[frontier_gathering] '..id..': '..tostring(err));Wait(3000) end
 end
 for kind,t in pairs(C.tools) do for mat,m in pairs(C.materials) do
  local id='gather_'..kind..'_'..mat;local name=m.label..' '..t.name
  while true do
   local ok,err=inv:RegisterItem(id,{name=name,description='Repairable gathering tool',category='Tools',classification='tool',grams=t.grams,maxStack=1,condition=true,metadata=R.encodeQuality(mat,50,'General store')})
   if ok then break end;print('[frontier_gathering] '..id..': '..tostring(err));Wait(3000)
  end
 end end
 ready=true;print('[frontier_gathering] ready')
end)

RegisterNetEvent(E..'smithBegin',function(kind,material,repair)
 local src=source;run(src,function()
  if not C.tools[kind] or sessions[src] or fishSessions[src] then return notice(src,'Choose a tool or finish your current activity') end
  local id=cid(src);local pos,why=position(src);if not pos then return notice(src,positionError(src,why)) end;if not id then return notice(src,'No active Frontier character') end
  local p=pending(id);if p and not recover(src,p) then return end
  local workshop=GetResourceState('frontier_property')=='started' and exports.frontier_property:GatheringWorkshop(src)
  if not workshop then return notice(src,'Approach a completed workshop you may use') end
  local d={smith=true,kind=kind,xp=25}
  if repair==true then
   local ok,t=inv:GetGatheringTool(src,kind,true);if not ok then return notice(src,'No tool to repair') end
   if t.metadata.uses>=t.metadata.maxUses then return notice(src,'Tool is already fully repaired') end
   material=t.metadata.materialId;d.instance=t.instance;d.item=t.item
  else
   if not C.materials[material] then return notice(src,'Materials: crude, iron, steel, hardened') end
   d.item='gather_'..kind..'_'..material;d.metadata=R.encodeQuality(material,50,workshop.name)
  end
  if not C.materials[material] then return notice(src,'Unsupported tool material') end
  d.material=material;d.metal=(material=='steel' or material=='hardened') and 'gather_steel' or 'iron_ingot'
  d.cost=repair and 1 or material=='hardened' and 3 or 2;d.wood=1
  local fits,err=inv:GatheringSmith(src,id,d,'preview:'..src,true)
  if not fits then return notice(src,'Requires '..d.cost..' '..d.metal..' and 1 wood; '..tostring(err)) end
  local ok,skill=skills:GetSkill(src,'blacksmithing');if not ok then return notice(src,'Skills unavailable') end
  local node={id='smith:'..workshop.id,x=pos.x,y=pos.y,z=pos.z};if locks[node.id] then return notice(src,'Workshop is busy') end
  local token=uuid();local now=GetGameTimer()
  local w={actor=id,node=node,bucket=pos.bucket,smith=d,workshop=workshop,token=token,skill=skill,duration=C.workMs,target=math.random(27,73)/100,started=now,expires=now+C.workMs+7000}
  sessions[src]=w;locks[node.id]=src
  TriggerClientEvent(E..'work',src,{token=token,action='smith',label=repair and 'Repair tool' or 'Forge tool',ms=w.duration,target=w.target,width=.11*skill.window,qte=true})
 end)
end)

-- Diagnostic reads only server state; no client coordinates are trusted.
RegisterNetEvent(E..'debug',function()
 local src=source
 run(src,function()
  local pos,why=position(src)
  if not pos then return notice(src,positionError(src,why)) end
  local ped=GetPlayerPed(src)
  local msg=('Server position %.2f %.2f %.2f | bucket=%s health=%s | gathering session OK'):format(pos.x,pos.y,pos.z,tostring(pos.bucket),tostring(GetEntityHealth(ped)))
  print('[frontier_gathering] '..msg);notice(src,msg)
 end)
end)
