local E='frontier_farming:'
local C,R=FarmConfig,FarmRules
local focused=false
local world,entities={},{}
local function notice(s) TriggerEvent('chat:addMessage',{args={'Farming',s}}) end
RegisterCommand('farm',function() TriggerServerEvent(E..'action','open',{}) end,false)
RegisterNetEvent(E..'notice',function(s) if source~=65535 then return end;notice(s);SendNUIMessage({type='notice',message=s}) end)
RegisterNetEvent(E..'menu',function(d) if source~=65535 then return end;focused=true;SetNuiFocus(true,true);SendNUIMessage({type='menu',data=d}) end)
RegisterNetEvent(E..'world',function(d) if source==65535 then world=d end end)
RegisterNUICallback('farmAction',function(d,cb) if focused then TriggerServerEvent(E..'action',d.action,d.data or {}) end;cb({ok=true}) end)
RegisterNUICallback('close',function(_,cb) focused=false;SetNuiFocus(false,false);SendNUIMessage({type='close'});cb({ok=true}) end)
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
  SetBlockingOfNonTemporaryEvents(ent,true);TaskStandStill(ent,-1)
 else FreezeEntityPosition(ent,true) end
 return ent
end
local function desired()
 local want={};local pos=GetEntityCoords(PlayerPedId())
 for _,v in ipairs(world) do local b=v.b
  if #(pos-vector3(b.x,b.y,b.z))<C.stream then
   if v.crop and not v.dead and v.growth>0 then
    local c=C.crops[v.crop];local stage=math.min(#c.models,math.max(1,math.ceil(v.growth*#c.models)))
    local n=math.max(1,math.floor(b.width/c.spacing));local total=n*n;local visible=math.max(1,math.floor(total*(#c.models>1 and 1 or math.max(.15,v.growth))))
    for i=0,visible-1 do
     local col=i%n;local line=math.floor(i/n);local x,y=R.world(b,(col+.5)*b.width/n-b.width/2,(line+.5)*b.length/n-b.length/2)
     want[b.id..':crop:'..i]={model=c.models[stage],x=x,y=y,z=b.z,heading=b.heading}
    end
   end
   if v.species then
    local c=C.species[v.species];local count=math.min(8,v.female+v.male+v.young)
    for i=1,count do
     local a=i*2.39996;local x,y=R.world(b,math.cos(a)*b.width*.23,math.sin(a)*b.length*.23)
     want[b.id..':animal:'..i]={model=(i==1 and v.male>0) and c.male or c.female,x=x,y=y,z=b.z,heading=(i*83)%360,ped=true}
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
  local added=0
  for key,d in pairs(wanted) do if not entities[key] and added<12 then
   local h=spawn(d);if h then entities[key]={handle=h,model=d.model};added=added+1 end
  end end
 end
end)
AddEventHandler('onClientResourceStop',function(r) if r==GetCurrentResourceName() then for _,e in pairs(entities) do DeleteEntity(e.handle) end;if focused then SetNuiFocus(false,false) end end end)
