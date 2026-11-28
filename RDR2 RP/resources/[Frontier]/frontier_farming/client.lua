local E='frontier_farming:'
local C,R=FarmConfig,FarmRules
local focused=false
local world,entities={},{}
local slaughterToken,pendingSlaughter

local working=false
local previousProps={}
local workPropModels={}
for _,name in ipairs({'p_hoe01x','p_pitchfork01x','p_bucket01x','p_wateringcan01x','p_rake01x','p_sickle01x','p_hoe02x'}) do workPropModels[GetHashKey(name)]=true end
local function attachedProps(ped)
 local out={}
 for _,obj in ipairs(GetGamePool('CObject')) do
  if DoesEntityExist(obj) and IsEntityAttachedToEntity(obj,ped) then out[obj]=true end
 end
 return out
end
local function endWork()
 if not working then return end
 working=false
 local ped=PlayerPedId();local props=attachedProps(ped)
 ClearPedTasksImmediately(ped)
 -- Only clean locally owned farm scenario props that were not attached before work.
 for obj in pairs(props) do
  if not previousProps[obj] and DoesEntityExist(obj) and workPropModels[GetEntityModel(obj)] and not NetworkGetEntityIsNetworked(obj) then
   DetachEntity(obj,true,true);SetEntityAsMissionEntity(obj,true,true);DeleteEntity(obj)
  end
 end
 previousProps={}
end
local function startWork(action)
 endWork()
 local scenario=C.scenarios[action];if not scenario then return end
 local ped=PlayerPedId();previousProps=attachedProps(ped);working=true
 pcall(function() TaskStartScenarioInPlace(ped,GetHashKey(scenario),-1,true,false,false,false) end)
end

local function notice(s) TriggerEvent('chat:addMessage',{args={'Farming',s}}) end
RegisterCommand('farm',function() TriggerServerEvent(E..'action','open',{}) end,false)
AddEventHandler('frontier_farming:manageSign',function(id)
 if not focused and not pendingSlaughter and not IsNuiFocused() then TriggerServerEvent(E..'action','openFacility',{id=id}) end
end)
RegisterNetEvent(E..'notice',function(s) if source~=65535 then return end;notice(s);SendNUIMessage({type='notice',message=s}) end)
RegisterNetEvent(E..'menu',function(d) if source~=65535 then return end;endWork();focused=true;SetNuiFocus(true,true);SendNUIMessage({type='menu',data=d}) end)
RegisterNetEvent(E..'workRound',function(d) if source==65535 then if d.round==1 then startWork(d.action) end;SendNUIMessage({type='workRound',data=d}) end end)
RegisterNetEvent(E..'workEnd',function() if source==65535 then endWork();SendNUIMessage({type='workEnd'}) end end)
RegisterNetEvent(E..'world',function(d) if source==65535 then world=d end end)
RegisterNUICallback('farmAction',function(d,cb) if focused then TriggerServerEvent(E..'action',d.action,d.data or {}) end;cb({ok=true}) end)
RegisterNUICallback('close',function(_,cb) endWork();focused=false;TriggerServerEvent(E..'action','cancelWork',{});SetNuiFocus(false,false);SendNUIMessage({type='close'});cb({ok=true}) end)
local V=C.fieldVisuals
local fieldDims,fieldLayouts,vegModifiers={}, {}, {}
local function terrain(x,y,z)
 RequestCollisionAtCoord(x,y,z)
 local ok,g=GetGroundZFor_3dCoord(x,y,z+8.0,false)
 if ok and math.abs(g-z)<=5 then return g end
end
local function slope(d,h,z)
 local min,max=GetModelDimensions(h)
 local hx,hy=math.max(.15,(max.x-min.x)/2),math.max(.15,(max.y-min.y)/2)
 local a=math.rad(d.heading);local c,s=math.cos(a),math.sin(a)
 local l=terrain(d.x-hx*c,d.y-hx*s,d.z);local r=terrain(d.x+hx*c,d.y+hx*s,d.z)
 local b=terrain(d.x+hy*s,d.y-hy*c,d.z);local f=terrain(d.x-hy*s,d.y+hy*c,d.z)
 local function clamp(n) return math.max(-V.maxSlope,math.min(V.maxSlope,n)) end
 local roll=l and r and clamp(-math.deg(math.atan(r-l,2*hx))) or 0
 local pitch=b and f and clamp(math.deg(math.atan(f-b,2*hy))) or 0
 if l and r and b and f then z=(l+r+b+f)/4 end
 return z-min.z+(d.offset or 0),pitch,roll
end
local function spawn(d)
 local h=GetHashKey(d.model);if not IsModelValid(h) then return end
 RequestModel(h);local untilTime=GetGameTimer()+1500
 while not HasModelLoaded(h) and GetGameTimer()<untilTime do Wait(20) end
 if not HasModelLoaded(h) then SetModelAsNoLongerNeeded(h);return end
 RequestCollisionAtCoord(d.x,d.y,d.z)
 local ok,z=GetGroundZFor_3dCoord(d.x,d.y,d.z+5,false)
 if not ok then SetModelAsNoLongerNeeded(h);return end
 local min=GetModelDimensions(h);local pitch,roll=0,0
 if d.field then z,pitch,roll=slope(d,h,z) else z=z-min.z end
 local ent
 if d.ped then ent=CreatePed(h,d.x,d.y,z,d.heading,false,false,false,false)
 else ent=CreateObject(h,d.x,d.y,z,false,false,false,false,false) end
 SetModelAsNoLongerNeeded(h)
 if not ent or ent==0 then return end
 SetEntityAsMissionEntity(ent,true,true);SetEntityCoordsNoOffset(ent,d.x,d.y,z,false,false,false);SetEntityHeading(ent,d.heading);SetEntityInvincible(ent,true)
 if d.ped then
  pcall(function() Citizen.InvokeNative(0x283978A15512B2FE,ent,true) end)
  SetBlockingOfNonTemporaryEvents(ent,true);TaskStandStill(ent,3000)
 else
  if d.field then SetEntityRotation(ent,pitch,roll,d.heading,2,true);SetEntityCollision(ent,false,false) end
  FreezeEntityPosition(ent,true)
 end
 return ent
end

-- Model extents are cached after loading; group meshes can contain several plants.
local function fieldSize(name)
 local cached=fieldDims[name]
 if cached and cached.x then return cached end
 if cached and GetGameTimer()<cached.retry then return end
 local h=GetHashKey(name)
 if not IsModelValid(h) then fieldDims[name]={retry=GetGameTimer()+30000};return end
 RequestModel(h);local deadline=GetGameTimer()+1500
 while not HasModelLoaded(h) and GetGameTimer()<deadline do Wait(20) end
 if not HasModelLoaded(h) then SetModelAsNoLongerNeeded(h);fieldDims[name]={retry=GetGameTimer()+10000};return end
 local min,max=GetModelDimensions(h);SetModelAsNoLongerNeeded(h)
 local d={x=math.max(.25,max.x-min.x),y=math.max(.25,max.y-min.y)}
 fieldDims[name]=d;return d
end

local function clearVeg(id)
 local old=vegModifiers[id]
 if not old then return end
 for _,m in ipairs(old.handles) do
  Citizen.InvokeNative(0x9CF1836C03FB67A2,Citizen.PointerValueIntInitialized(m),0)
 end
 vegModifiers[id]=nil
end

local function ensureVeg(b)
 if not V.vegetation then return end
 local key=table.concat({b.x,b.y,b.z,b.heading,b.width,b.length},':')
 if vegModifiers[b.id] and vegModifiers[b.id].key==key then return end
 clearVeg(b.id)
 local handles={}
 local nx,ny=math.ceil(b.width/2.5),math.ceil(b.length/2.5)
 local sx,sy=b.width/nx,b.length/ny
 local radius=math.sqrt(sx*sx+sy*sy)/2
 for col=1,nx do for row=1,ny do
  local x,y=R.world(b,-b.width/2+(col-.5)*sx,-b.length/2+(row-.5)*sy)
  local z=terrain(x,y,b.z)
  if z then
   local m=Citizen.InvokeNative(0xFA50F79257745E74,x,y,z,radius,1,1+2+4+8+16+256,0,Citizen.ResultAsInteger())
   if m and m~=0 then handles[#handles+1]=m end
  end
 end end
 if #handles>0 then vegModifiers[b.id]={key=key,handles=handles} end
end

local function fieldLayout(v)
 local b=v.b
 -- Empty plots retain planting beds, using the default corn footprint.
 local name=v.crop and C.crops[v.crop] and v.crop or 'corn'
 local crop=C.crops[name];local rotation=V.rotations[name] or 0
 local cd=fieldSize(crop.models[#crop.models])
 local sd=fieldSize(V.soilModel)
 if not cd or not sd then return end
 local cw,cl=cd.x,cd.y
 if rotation%180==90 then cw,cl=cl,cw end
 local bw,bl=math.max(sd.x,cw),math.max(sd.y,cl)
 local aw,al=math.max(.5,b.width-2*V.margin),math.max(.5,b.length-2*V.margin)
 local cols,rows=math.max(1,math.floor(aw/((bw+V.rowGap)*V.spacing))),math.max(1,math.floor(al/((bl+.2)*V.spacing)))
 local nx=math.max(1,math.ceil(bw/(sd.x*V.soilOverlap)))
 local ny=math.max(1,math.ceil(bl/(sd.y*V.soilOverlap)))
 local spanX,spanY=math.max(0,bw-sd.x),math.max(0,bl-sd.y)
 if spanX==0 then nx=1 end;if spanY==0 then ny=1 end
 -- Bound the total while distributing beds evenly across the plot.
 while cols*rows*(nx*ny+1)>V.maxProps and (cols>1 or rows>1) do
  if cols>=rows and cols>1 then cols=cols-1 else rows=rows-1 end
 end
 while nx*ny+1>V.maxProps do if nx>=ny and nx>1 then nx=nx-1 else ny=ny-1 end end
 local key=table.concat({name,b.x,b.y,b.z,b.heading,b.width,b.length},':')
 local cache=fieldLayouts[b.id]
 if cache and cache.key==key then return cache end
 local soil,beds={},{}
 for col=1,cols do for row=1,rows do
  local x,y=-aw/2+(col-.5)*aw/cols,-al/2+(row-.5)*al/rows
  beds[#beds+1]={x=x,y=y}
  for i=1,nx do for j=1,ny do
   local dx=nx>1 and (-spanX/2+(i-1)*spanX/(nx-1)) or 0
   local dy=ny>1 and (-spanY/2+(j-1)*spanY/(ny-1)) or 0
   soil[#soil+1]={x=x+dx,y=y+dy}
  end end
 end end
 cache={key=key,soil=soil,beds=beds,rotation=rotation};fieldLayouts[b.id]=cache
 return cache
end

local function addField(want,v,layout)
 local b=v.b
 local function put(key,model,p,rotation,offset)
  local x,y=R.world(b,p.x,p.y)
  want[b.id..':'..key]={model=model,x=x,y=y,z=b.z,heading=(b.heading+rotation)%360,offset=offset,field=true}
 end
 for i,p in ipairs(layout.soil) do put('soil:'..i,V.soilModel,p,0,V.soilOffset) end
 if not v.crop or v.dead then return end
 local c=C.crops[v.crop];if not c then return end
 local growth=math.max(0,math.min(1,v.growth or 0))
 local stage=math.min(#c.models,math.max(1,math.floor(growth*(#c.models-1)+1.000001)))
 local count=#layout.beds;local visible=math.max(1,math.floor(count*(#c.models>1 and 1 or math.max(.22,growth))+.5))
 for i,p in ipairs(layout.beds) do
  if math.floor(i*visible/count)>math.floor((i-1)*visible/count) then
   local model=c.models[stage]
   put('crop:'..i,model,p,layout.rotation,V.cropOffset)
  end
 end
end

local function desired()
 local want,fields={},{};local pos=GetEntityCoords(PlayerPedId())
 for _,v in ipairs(world) do local b=v.b
  if #(pos-vector3(b.x,b.y,b.z))<C.stream then
   if b.kind=='field' and #(pos-vector3(b.x,b.y,b.z))<V.distance then
    fields[#fields+1]={v=v,distance=#(pos-vector3(b.x,b.y,b.z))}
   end
   if v.species and not (pendingSlaughter and pendingSlaughter.facility==b.id) then
    local c=C.species[v.species];local limit=v.species=='chicken' and ({small=3,medium=5,large=8})[b.size] or 8
    local count=math.min(limit or 3,v.female+v.male+v.young)
    for i=1,count do
     local a=i*2.39996;local x,y=R.world(b,math.cos(a)*b.width*.23,math.sin(a)*b.length*.23)
     want[b.id..':animal:'..i]={model=(v.species=='horse' and v.horses and v.horses[i] and C.horseBreeds[v.horses[i].breed].model) or ((i==1 and v.male>0) and c.male or c.female),x=x,y=y,z=b.z,heading=(i*83)%360,ped=true}
    end
   end
  end
 end
 table.sort(fields,function(a,b) return a.distance<b.distance end)
 local active,used={},0
 for _,entry in ipairs(fields) do
  local v=entry.v;local layout=fieldLayout(v)
  if layout and used+#layout.soil+#layout.beds<=V.maxTotal then
   active[v.b.id]=true;used=used+#layout.soil+#layout.beds
   ensureVeg(v.b);addField(want,v,layout)
  end
 end
 for id in pairs(vegModifiers) do if not active[id] then clearVeg(id) end end
 for id in pairs(fieldLayouts) do if not active[id] then fieldLayouts[id]=nil end end
 return want
end
CreateThread(function()
 while true do
  Wait(1000);local wanted=desired()
  for key,e in pairs(entities) do if not wanted[key] or wanted[key].model~=e.model or (wanted[key].field and (wanted[key].x~=e.spawn.x or wanted[key].y~=e.spawn.y or wanted[key].heading~=e.spawn.heading or wanted[key].z~=e.spawn.anchorZ)) or not DoesEntityExist(e.handle) then DeleteEntity(e.handle);entities[key]=nil end end
  for _,e in pairs(entities) do if e.ped and DoesEntityExist(e.handle) then local p=GetEntityCoords(e.handle);local d=e.spawn;if #(p-vector3(d.x,d.y,d.z))>1.8 then TaskGoStraightToCoord(e.handle,d.x,d.y,d.z,1.0,4000,d.heading,0.2) elseif math.random()<.2 then TaskGoStraightToCoord(e.handle,d.x+(math.random()-.5)*1.5,d.y+(math.random()-.5)*1.5,p.z,0.5,3000,d.heading,0.2) end end end
  local added=0
  for key,d in pairs(wanted) do if not entities[key] and added<12 then
   local h=spawn(d);if h then local pos=GetEntityCoords(h);d.anchorZ=d.z;d.z=pos.z;entities[key]={handle=h,model=d.model,spawn=d,ped=d.ped};added=added+1 end
  end end
 end
end)
AddEventHandler('onClientResourceStop',function(r) if r==GetCurrentResourceName() then endWork();for id in pairs(vegModifiers) do clearVeg(id) end;for _,e in pairs(entities) do DeleteEntity(e.handle) end;if focused then SetNuiFocus(false,false) end end end)

RegisterCommand('farmshop',function() if GetResourceState('frontier_shops')=='started' then ExecuteCommand('shop') else TriggerServerEvent(E..'action','shop',{}) end end,false)
RegisterNetEvent(E..'shop',function(d) if source~=65535 then return end;focused=true;SetNuiFocus(true,true);SendNUIMessage({type='shop',data=d}) end)

local function clearSlaughterSpawn(token)
 local job=pendingSlaughter
 if not job or token and job.token~=token then return end
 pendingSlaughter=nil
 SendNUIMessage({type='slaughterHudEnd'})
 for _,ped in ipairs(job.peds) do
  if DoesEntityExist(ped) then
   if NetworkHasControlOfEntity(ped) then SetEntityAsMissionEntity(ped,true,true);DeleteEntity(ped) end
  end
 end
end
RegisterNetEvent(E..'slaughterCleanup',function(token)
 if source~=65535 then return end
 clearSlaughterSpawn(token)
 if slaughterToken==token then slaughterToken=nil end
end)
RegisterNetEvent(E..'slaughterSpawn',function(d)
 if source~=65535 then return end
 endWork();clearSlaughterSpawn()
 local job={token=d.token,peds={},facility=d.facility};pendingSlaughter=job
 for key,e in pairs(entities) do
  if e.ped and key:sub(1,#d.facility+8)==d.facility..':animal:' then DeleteEntity(e.handle);entities[key]=nil end
 end
 SendNUIMessage({type='notice',message='Preparing networked animals...'})
 CreateThread(function()
  local h=GetHashKey(d.model)
  local function fail(reason)
   if pendingSlaughter~=job then return end
   print('[frontier_farming] slaughter spawn: '..reason)
   clearSlaughterSpawn(job.token);SetModelAsNoLongerNeeded(h)
   TriggerServerEvent(E..'action','slaughterSpawnFailed',{token=job.token})
  end
  if not IsModelValid(h) then return fail('Invalid animal model '..d.model) end
  RequestModel(h);local deadline=GetGameTimer()+6000
  while not HasModelLoaded(h) and GetGameTimer()<deadline and pendingSlaughter==job do Wait(50) end
  if pendingSlaughter~=job then SetModelAsNoLongerNeeded(h);return end
  if not HasModelLoaded(h) then return fail('Model loading timed out') end
  local ids={}
  for i,p in ipairs(d.points) do
   if pendingSlaughter~=job then SetModelAsNoLongerNeeded(h);return end
   RequestCollisionAtCoord(p.x,p.y,p.z)
   local ok,z=GetGroundZFor_3dCoord(p.x,p.y,p.z+5.0,false)
   if not ok then return fail('Ground unavailable at animal '..i) end
   local min=GetModelDimensions(h);z=z-min.z
   local ped=CreatePed(h,p.x+0.0,p.y+0.0,z+0.0,p.heading+0.0,true,true,false,false)
   if not ped or ped==0 or not DoesEntityExist(ped) then return fail('CreatePed failed for animal '..i) end
   job.peds[#job.peds+1]=ped
   SetEntityAsMissionEntity(ped,true,true)
pcall(function() Citizen.InvokeNative(0x283978A15512B2FE,ped,true) end)

Wait(100)

local maxHealth = GetEntityMaxHealth(ped)

if maxHealth > 0 then
    SetEntityHealth(ped, maxHealth, 0)
end

print(("[frontier_farming] Animal health: %s/%s"):format(
    GetEntityHealth(ped), maxHealth
))
   SetEntityCoordsNoOffset(ped,p.x,p.y,z,false,false,false)
   FreezeEntityPosition(ped,true);SetEntityInvincible(ped,true)
   SetBlockingOfNonTemporaryEvents(ped,true)
   if not NetworkGetEntityIsNetworked(ped) then NetworkRegisterEntityAsNetworked(ped) end
   local id=NetworkGetNetworkIdFromEntity(ped);local untilTime=GetGameTimer()+1500
   while (not id or id==0) and GetGameTimer()<untilTime and pendingSlaughter==job do Wait(50);id=NetworkGetNetworkIdFromEntity(ped) end
   if pendingSlaughter~=job then SetModelAsNoLongerNeeded(h);return end
   if not id or id==0 then return fail('No network ID for animal '..i) end
   ids[i]=id
  end
  SetModelAsNoLongerNeeded(h)
  if pendingSlaughter==job then TriggerServerEvent(E..'action','slaughterSpawned',{token=job.token,ids=ids}) end
 end)
end)
AddEventHandler('onClientResourceStop',function(r) if r==GetCurrentResourceName() then clearSlaughterSpawn() end end)
RegisterNetEvent(E..'slaughter',function(d)
 if source~=65535 then return end
 local job=pendingSlaughter
 if not job or job.token~=d.token then return end
 for _,ped in ipairs(job.peds) do if DoesEntityExist(ped) then SetEntityInvincible(ped,false);FreezeEntityPosition(ped,true);TaskStandStill(ped,300000) end end
 slaughterToken=d.token;endWork();focused=false;SetNuiFocus(false,false);SendNUIMessage({type='slaughter',data=d})
 notice('Butcher the marked animals. Completion is automatic.')
 job.ids=d.ids
 CreateThread(function()
  local lastSend=-2500
  local lastHud=0
  while pendingSlaughter==job and slaughterToken==job.token do
   local deadIds,markers={},{}
   for i,ped in ipairs(job.peds) do
    if DoesEntityExist(ped) then
     if IsEntityDead(ped) or GetEntityHealth(ped)<=0 then
      local id=NetworkGetNetworkIdFromEntity(ped)
      if id and id>0 then deadIds[#deadIds+1]=id end
     else
      local pos=GetEntityCoords(ped)
      local _,max=GetModelDimensions(GetEntityModel(ped))
      local ok,visible,x,y=pcall(GetScreenCoordFromWorldCoord,pos.x,pos.y,pos.z+max.z+0.25)
      if ok and visible then markers[#markers+1]={x=x,y=y} end
     end
    end
   end
   local now=GetGameTimer()
   if now-lastHud>=50 then
    lastHud=now
    SendNUIMessage({type='slaughterProgress',dead=#deadIds,total=#job.peds,markers=markers,finishing=#deadIds==#job.peds})
   end
   if #deadIds==#job.peds and now-lastSend>=2500 then
    lastSend=now
    TriggerServerEvent(E..'action','slaughterFinish',{token=job.token,deadIds=deadIds})
   end
   if IsControlJustPressed(0,0x156F7119) then
    ExecuteCommand('farmcancel');break
   end
   Wait(0)
  end
 end)
end)
RegisterCommand('farmcancel',function() endWork();clearSlaughterSpawn();slaughterToken=nil;TriggerServerEvent(E..'action','cancelWork',{}) end,false)

RegisterNetEvent(E..'horseMarket',function(d) if source~=65535 then return end;focused=true;SetNuiFocus(true,true);SendNUIMessage({type='horseMarket',data=d}) end)
RegisterCommand('farmhorses',function() TriggerServerEvent(E..'action','horseMarket',{}) end,false)

RegisterCommand('farmwater',function()
 local p=PlayerPedId();local v=GetEntityCoords(p)
 local ok,zone=pcall(function() return GetWaterMapZoneAtCoords(v.x,v.y,v.z) end)
 if not IsEntityInWater(p) and (not ok or not zone or zone==0) then notice('Stand at the water edge.');return end
 TriggerServerEvent(E..'action','riverStart',{})
end,false)
RegisterNetEvent(E..'waterWork',function(d)
 if source~=65535 then return end
 local p=PlayerPedId()
 -- Gathering duration is enforced by the server; animation is cosmetic.
 pcall(function() TaskStartScenarioInPlace(p,GetHashKey('WORLD_HUMAN_CROUCH_INSPECT'),d.ms,true,false,false,false) end)
 CreateThread(function() Wait(d.ms+150);ClearPedTasks(p);TriggerServerEvent(E..'action','riverFinish',{token=d.token}) end)
end)
RegisterCommand('farmreturn',function() TriggerServerEvent(E..'action','returnMount',{}) end,false)
RegisterNetEvent(E..'horseReleased',function() if source==65535 then focused=false;SetNuiFocus(false,false);SendNUIMessage({type='close'}) end end)
RegisterNetEvent(E..'mount',function(d)
 if source~=65535 then return end
 focused=false;SetNuiFocus(false,false);SendNUIMessage({type='close'})
 CreateThread(function()
  local deadline=GetGameTimer()+8000
  while not NetworkDoesEntityExistWithNetworkId(d.id) and GetGameTimer()<deadline do Wait(50) end
  if not NetworkDoesEntityExistWithNetworkId(d.id) then notice('Mount not streamed. /farmreturn to recover.');return end
  local horse=NetToPed(d.id);local h=d.horse
  NetworkRequestControlOfEntity(horse)
  pcall(function()
   Citizen.InvokeNative(0x283978A15512B2FE,horse,true)
   Citizen.InvokeNative(0xD2CB0FB0FDCB473D,PlayerId(),horse)
   Citizen.InvokeNative(0x5DA12E025D47D4E5,horse,0,math.floor(h.genes.health*10+h.training*3))
   Citizen.InvokeNative(0x5DA12E025D47D4E5,horse,1,math.floor(h.genes.stamina*10+h.training*3))
   Citizen.InvokeNative(0x5DA12E025D47D4E5,horse,4,math.floor(h.genes.speed*10+h.training*3))
   Citizen.InvokeNative(0x5DA12E025D47D4E5,horse,5,math.floor(h.genes.speed*10+h.training*3))
   Citizen.InvokeNative(0xC6258F41D86676E0,horse,0,math.floor(h.health))
   Citizen.InvokeNative(0xC6258F41D86676E0,horse,1,math.floor(h.care))
   SetPedConfigFlag(horse,297,true);SetPedConfigFlag(horse,312,true)
  end)
  notice('Your horse is ready. Mount normally. /farmreturn returns it to its enclosure.')
 end)
end)
RegisterNetEvent(E..'mountReturned',function() if source==65535 then notice('Mount returned to stable record.') end end)

local suppliers={}
CreateThread(function()
 while true do Wait(1500);local p=GetEntityCoords(PlayerPedId())
  for i,q in ipairs(C.suppliers) do
   local dist=#(p-vector3(q.x,q.y,q.z))
   if GetResourceState('frontier_shops')=='started' then
    if suppliers[i] then DeleteEntity(suppliers[i]);suppliers[i]=nil end
   elseif dist<60 and not suppliers[i] then
    local h=spawn({model=C.supplierModel,x=q.x,y=q.y,z=q.z,heading=0,ped=true})
    if h then suppliers[i]=h;TaskStandStill(h,-1);FreezeEntityPosition(h,true) end
   elseif dist>75 and suppliers[i] then DeleteEntity(suppliers[i]);suppliers[i]=nil end
  end
 end
end)
CreateThread(function()
 while true do
  local p=GetEntityCoords(PlayerPedId());local shop=false
  if GetResourceState('frontier_shops')~='started' then
   for _,q in ipairs(C.suppliers) do if #(p-vector3(q.x,q.y,q.z))<4 then shop=true;break end end
  end
  local farm=false
  if not shop then for _,v in ipairs(world) do local b=v.b;if #(p-vector3(b.x,b.y,b.z))<math.max(b.width,b.length)/2+C.reach then farm=true;break end end end
  if not focused and (shop or farm) and not (type(IsNuiFocused)=='function' and IsNuiFocused()) then
   Wait(0);local msg=shop and 'Agricultural supplies: /farmshop or G' or 'Farm management: /farm or G'
   SetTextScale(.30,.30);SetTextColor(255,255,255,255);SetTextCentre(true);DisplayText(CreateVarString(10,'LITERAL_STRING',msg),.5,.91)
   if IsControlJustPressed(0,0x760A9C6F) then TriggerServerEvent(E..'action',shop and 'shop' or 'open',{}) end
  else Wait(300) end
 end
end)
AddEventHandler('onClientResourceStop',function(r) if r==GetCurrentResourceName() then for _,h in pairs(suppliers) do DeleteEntity(h) end end end)
