local E='frontier_farming:'
local C,R=FarmConfig,FarmRules
local focused=false
local world,entities={},{}

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
RegisterNetEvent(E..'notice',function(s) if source~=65535 then return end;notice(s);SendNUIMessage({type='notice',message=s}) end)
RegisterNetEvent(E..'menu',function(d) if source~=65535 then return end;endWork();focused=true;SetNuiFocus(true,true);SendNUIMessage({type='menu',data=d}) end)
RegisterNetEvent(E..'workRound',function(d) if source==65535 then if d.round==1 then startWork(d.action) end;SendNUIMessage({type='workRound',data=d}) end end)
RegisterNetEvent(E..'workEnd',function() if source==65535 then endWork();SendNUIMessage({type='workEnd'}) end end)
RegisterNetEvent(E..'world',function(d) if source==65535 then world=d end end)
RegisterNUICallback('farmAction',function(d,cb) if focused then TriggerServerEvent(E..'action',d.action,d.data or {}) end;cb({ok=true}) end)
RegisterNUICallback('close',function(_,cb) endWork();focused=false;TriggerServerEvent(E..'action','cancelWork',{});SetNuiFocus(false,false);SendNUIMessage({type='close'});cb({ok=true}) end)
local function spawn(d)
 local h=GetHashKey(d.model);if not IsModelValid(h) then return end
 RequestModel(h);local untilTime=GetGameTimer()+1500
 while not HasModelLoaded(h) and GetGameTimer()<untilTime do Wait(20) end
 if not HasModelLoaded(h) then SetModelAsNoLongerNeeded(h);return end
 RequestCollisionAtCoord(d.x,d.y,d.z)
 local ok,z=GetGroundZFor_3dCoord(d.x,d.y,d.z+5,false)
 if not ok then SetModelAsNoLongerNeeded(h);return end
 local min=GetModelDimensions(h);z=z-min.z
 local ent
 if d.ped then ent=CreatePed(h,d.x,d.y,z,d.heading,false,false,false,false)
 else ent=CreateObject(h,d.x,d.y,z,false,false,false,false,false) end
 SetModelAsNoLongerNeeded(h)
 if not ent or ent==0 then return end
 SetEntityAsMissionEntity(ent,true,true);SetEntityCoordsNoOffset(ent,d.x,d.y,z,false,false,false);SetEntityHeading(ent,d.heading);SetEntityInvincible(ent,true)
 if d.ped then
  pcall(function() Citizen.InvokeNative(0x283978A15512B2FE,ent,true) end)
  SetBlockingOfNonTemporaryEvents(ent,true);TaskStandStill(ent,3000)
 else FreezeEntityPosition(ent,true) end
 return ent
end
local function desired()
 local want={};local pos=GetEntityCoords(PlayerPedId())
 for _,v in ipairs(world) do local b=v.b
  if #(pos-vector3(b.x,b.y,b.z))<C.stream then
   if v.crop and not v.dead then
    local c=C.crops[v.crop];local stage=math.min(#c.models,math.max(1,math.floor(v.growth*(#c.models-1)+1.000001)))
    local spacing=C.cropRows[v.crop] or {x=c.spacing,y=c.spacing}
    local cols=math.max(1,math.floor(b.width/spacing.x))
    local rows=math.max(1,math.floor(b.length/spacing.y))
    local total=cols*rows
    local density=#c.models>1 and 1 or math.max(.22,v.growth)
    local visible=math.max(1,math.floor(total*density+.5))
    for i=0,total-1 do
     -- Deterministic, distributed early growth, then fill the rows as the crop matures.
     local rank=((i%cols)*rows+math.floor(i/cols))
     if math.floor((rank+1)*visible/total)>math.floor(rank*visible/total) then
      local col=i%cols;local line=math.floor(i/cols)
      local x,y=R.world(b,(col+.5)*b.width/cols-b.width/2,(line+.5)*b.length/rows-b.length/2)
      local models=c.models
      local model=models[stage]
      if v.crop=='corn' and stage==#models then model=C.cornMatureModels[(i%#C.cornMatureModels)+1] end
      want[b.id..':crop:'..i]={model=model,x=x,y=y,z=b.z,heading=b.heading}
     end
    end
   end
   if v.species then
    local c=C.species[v.species];local count=math.min(8,v.female+v.male+v.young)
    for i=1,count do
     local a=i*2.39996;local x,y=R.world(b,math.cos(a)*b.width*.23,math.sin(a)*b.length*.23)
     want[b.id..':animal:'..i]={model=(v.species=='horse' and v.horses and v.horses[i] and C.horseBreeds[v.horses[i].breed].model) or ((i==1 and v.male>0) and c.male or c.female),x=x,y=y,z=b.z,heading=(i*83)%360,ped=true}
    end
   end
  end
 end
 return want
end
CreateThread(function()
 while true do
  Wait(1000);local wanted=desired()
  for key,e in pairs(entities) do if not wanted[key] or wanted[key].model~=e.model or not DoesEntityExist(e.handle) then DeleteEntity(e.handle);entities[key]=nil end end
  for _,e in pairs(entities) do if e.ped and DoesEntityExist(e.handle) then local p=GetEntityCoords(e.handle);local d=e.spawn;if #(p-vector3(d.x,d.y,d.z))>1.8 then TaskGoStraightToCoord(e.handle,d.x,d.y,d.z,1.0,4000,d.heading,0.2) elseif math.random()<.2 then TaskGoStraightToCoord(e.handle,d.x+(math.random()-.5)*1.5,d.y+(math.random()-.5)*1.5,p.z,0.5,3000,d.heading,0.2) end end end
  local added=0
  for key,d in pairs(wanted) do if not entities[key] and added<12 then
   local h=spawn(d);if h then local pos=GetEntityCoords(h);d.z=pos.z;entities[key]={handle=h,model=d.model,spawn=d,ped=d.ped};added=added+1 end
  end end
 end
end)
AddEventHandler('onClientResourceStop',function(r) if r==GetCurrentResourceName() then endWork();for _,e in pairs(entities) do DeleteEntity(e.handle) end;if focused then SetNuiFocus(false,false) end end end)

RegisterCommand('farmshop',function() TriggerServerEvent(E..'action','shop',{}) end,false)
RegisterNetEvent(E..'shop',function(d) if source~=65535 then return end;focused=true;SetNuiFocus(true,true);SendNUIMessage({type='shop',data=d}) end)

local slaughterToken
RegisterNetEvent(E..'slaughter',function(d)
 if source~=65535 then return end
 slaughterToken=d.token;endWork();focused=false;SetNuiFocus(false,false);SendNUIMessage({type='slaughter',data=d})
 notice('Slaughter the '..d.count..' marked animals, then /farmfinish. /farmcancel cancels without rewards.')
 CreateThread(function()
  for _,id in ipairs(d.ids) do
   local deadline=GetGameTimer()+5000
   while not NetworkDoesEntityExistWithNetworkId(id) and GetGameTimer()<deadline do Wait(50) end
   if NetworkDoesEntityExistWithNetworkId(id) then local p=NetToPed(id);pcall(function() Citizen.InvokeNative(0x283978A15512B2FE,p,true) end) end
  end
 end)
end)
RegisterCommand('farmfinish',function() if slaughterToken then TriggerServerEvent(E..'action','slaughterFinish',{token=slaughterToken}) end end,false)
RegisterCommand('farmcancel',function() endWork();slaughterToken=nil;TriggerServerEvent(E..'action','cancelWork',{}) end,false)

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
   if dist<60 and not suppliers[i] then
    local h=spawn({model=C.supplierModel,x=q.x,y=q.y,z=q.z,heading=0,ped=true})
    if h then suppliers[i]=h;TaskStandStill(h,-1);FreezeEntityPosition(h,true) end
   elseif dist>75 and suppliers[i] then DeleteEntity(suppliers[i]);suppliers[i]=nil end
  end
 end
end)
CreateThread(function()
 while true do
  local p=GetEntityCoords(PlayerPedId());local shop=false
  for _,q in ipairs(C.suppliers) do if #(p-vector3(q.x,q.y,q.z))<4 then shop=true;break end end
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
