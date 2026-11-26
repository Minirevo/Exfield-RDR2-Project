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
local function uuid()return MySQL.scalar.await('SELECT REPLACE(UUID(),"-","")') end
local function cid(src)return core:GetPlayerCharacterId(src) end
local function finite(n)return type(n)=='number' and n==n and math.abs(n)<20000 end
local function dist(a,b)return (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2 end
local function position(src)
 local ped=GetPlayerPed(src)
 if ped==0 or not DoesEntityExist(ped) or GetPlayerRoutingBucket(src)~=0 or GetEntityHealth(ped)<=0 then return end
 local v=GetEntityCoords(ped);return {x=v.x,y=v.y,z=v.z}
end
local function run(src,fn)
 if not ready or busy[src] then return end
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
 local pos=position(src);if not pos or dist(pos,d)>C.reach^2 then return nil,'Move closer' end
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
  local ok,err=inv:GatheringCommit(src,row.character_id,d.kind,d.instance,d.item,d.count,d.wear,'gather:'..row.id,false)
  if not ok then notice(src,'Pending harvest: '..tostring(err)..'. Free satchel space or restore your tool, then /gatherrecover.');return false end
  MySQL.update.await('UPDATE frontier_gather_claims SET phase=1 WHERE id=? AND phase=0',{row.id})
 end
 local ok,err=skills:GrantXP(row.character_id,row.skill,d.xp,row.id)
 if not ok then notice(src,'Harvest secured; XP pending: '..tostring(err));return false end
 MySQL.update.await('UPDATE frontier_gather_claims SET phase=2 WHERE id=?',{row.id})
 notice(src,(d.count>0 and ('Received '..d.count..' × '..(d.item or '')) or 'Nothing valuable found')..' · +'..d.xp..' XP')
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
  local id=cid(src);if not id then return end
  local p=pending(id);if p and not recover(src,p) then return end
  local n,err=nodeFrom(src,d);if not n then return notice(src,err) end
  if locks[n.id] then return notice(src,'Someone is already working here') end
  locks[n.id]=src
  local a=C.actions[n.action];local w={actor=id,node=n,expires=GetGameTimer()+20000};sessions[src]=w
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
  if cid(src)~=id or not position(src) then return reject(src,'Character changed') end
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
  local elapsed=GetGameTimer()-w.started;local pos=position(src)
  if elapsed<w.duration or GetGameTimer()>w.expires or cid(src)~=w.actor or not pos or dist(pos,w.node)>C.reach^2 then return reject(src,'Work expired or you moved away') end
  local n=w.node;local left=remaining(n)
  if left<=0 then return reject(src,'Resource already depleted') end
  local score=n.action=='herbalism' and .65 or w.hit or 0
  local d=sample(src,n,score,w.skill,w.tool)
  local fits,issue=inv:GatheringCommit(src,w.actor,d.kind,d.instance,d.item,d.count,d.wear,'preview:'..src,true)
  if not fits then return reject(src,'Cannot complete: '..tostring(issue)) end
  if cid(src)~=w.actor or not position(src) then return reject(src,'Character changed') end
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
  local pos=position(src);if not pos or dist(pos,d)>C.reach^2 then return end
  local m=math.tointeger(d.model or 0);if not m then return end;m=m&0xffffffff
  if modelKinds[m]~=d.action and not (m==0 and R.region(d.x,d.y) and (d.action=='prospecting' or d.action=='clay' or d.action=='sand')) then return end
  local k=R.key(d.action,d.x,d.y,d.z)
  MySQL.update.await('INSERT INTO frontier_gather_survey(id,action,model,x,y,z) VALUES(?,?,?,?,?,?) ON DUPLICATE KEY UPDATE model=VALUES(model),x=VALUES(x),y=VALUES(y),z=VALUES(z)',{k,d.action,m,d.x,d.y,d.z})
  notice(src,'Surveyed '..k)
 end)
end)
local function nativeEntity(src,net,lookup,dead)
 if type(net)~='number' or net%1~=0 or net<=0 or net>65535 then return end
 local ent=NetworkGetEntityFromNetworkId(net);local pos=position(src)
 if ent==0 or not pos or not DoesEntityExist(ent) or GetEntityType(ent)~=1 or NetworkGetEntityOwner(ent)~=src then return end
 local p=GetEntityCoords(ent);if dist(pos,p)>64 then return end
 if dead and GetEntityHealth(ent)>0 then
  local ok,d=pcall(IsEntityDead,ent);if not ok or not d then return end
 end
 local model=GetEntityModel(ent)&0xffffffff
 if not lookup[model] then return end
 local used=entityClaims[net]
 if used and used.ent==ent then return end
 return ent,model
end
local function nativeClaim(src,net,skill,toolKind,lookup,dead)
 local id=cid(src);if not id then return false end
 local ent,model=nativeEntity(src,net,lookup,dead);if not ent then notice(src,'Native catch could not be verified');return false end
 local p=pending(id);if p and not recover(src,p) then return false end
 local ok,tool=inv:GetGatheringTool(src,toolKind);if not ok then notice(src,'A working '..toolKind..' is required');return false end
 local found,stats=skills:GetSkill(src,skill);if not found then return false end
 local item=skill=='fishing' and 'gather_fish' or lookup[model]
 local n=skill=='fishing' and 1 or math.max(1,math.floor(3*stats.yield*tool.metadata.yield+.5))
 local d={kind=toolKind,instance=tool.instance,item=item,count=n,wear=stats.wear,xp=20}
 local fits,err=inv:GatheringCommit(src,id,d.kind,d.instance,item,n,d.wear,'preview:'..src,true)
 if not fits then notice(src,'Cannot carry catch: '..tostring(err));return false end
 if cid(src)~=id or not nativeEntity(src,net,lookup,dead) then return false end
 entityClaims[net]={ent=ent}
 local row=makeClaim(src,id,skill,d)
 if not row then entityClaims[net]=nil;return false end
 recover(src,row);return true
end
RegisterNetEvent(E..'skin',function(net)
 local src=source;if not C.nativeHunting then return end
 run(src,function()if not sessions[src] then nativeClaim(src,net,'hunting','knife',animals,true) end end)
end)
RegisterNetEvent(E..'fishStart',function()
 local src=source;if not C.nativeFishing or GetResourceState('vorp_fishing')~='started' then return notice(src,'Native fishing resource is not running') end
 run(src,function()
  local id=cid(src);local pos=position(src);if not id or not pos or not R.region(pos.x,pos.y) or fishSessions[src] or sessions[src] then return notice(src,'Stand at an eligible river reach and equip a native rod') end
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
   local ok,err=inv:RegisterItem(id,{name=name,description='Repairable gathering tool',category='Tools',classification='tool',grams=t.grams,maxStack=1,condition=true,metadata=json.encode(R.quality(mat,50,'General store'))})
   if ok then break end;print('[frontier_gathering] '..id..': '..tostring(err));Wait(3000)
  end
 end end
 ready=true;print('[frontier_gathering] ready')
end)
