local C=JobsConfig
local E='frontier_jobs:'
local ticket,opened,requested
local peds,blips,boards={},{},{}
local attempts,spawnStatus={},{}
local function radius(mode) return mode=='employer' and C.employerReach or C.reach end
local routeTarget
local function close()
 if ticket then TriggerServerEvent(E..'close',ticket) end
 ticket=nil;opened=false;requested=nil;SetNuiFocus(false,false);SendNUIMessage({type='close'})
end
local function open(mode,place)
 requested=GetGameTimer();TriggerServerEvent(E..'open',mode,place)
end
RegisterNetEvent(E..'view',function(d)
 if source~=65535 or (not opened and (not requested or GetGameTimer()-requested>15000)) then return end
 ticket=d.ticket;opened=true;requested=nil;SetNuiFocus(true,true);SendNUIMessage({type='view',data=d})
end)
RegisterNetEvent(E..'notice',function(msg)
 if source~=65535 then return end
 if opened then SendNUIMessage({type='notice',message=msg}) else TriggerEvent('chat:addMessage',{args={'Employment',msg}}) end
end)
RegisterNetEvent(E..'close',function() if source==65535 then close() end end)
RegisterNUICallback('close',function(_,cb) close();cb({ok=true}) end)
RegisterNUICallback('action',function(d,cb)
 if opened and ticket then TriggerServerEvent(E..'action',ticket,d.op,d.data or {});cb({ok=true}) else cb({ok=false}) end
end)
local function clearRoute()
 if not routeTarget then return end
 Citizen.InvokeNative(0x4426D65E029A4DC0,false) -- SET_GPS_MULTI_ROUTE_RENDER
 Citizen.InvokeNative(0x9E0AB9AAEE87CE28) -- CLEAR_GPS_MULTI_ROUTE
 routeTarget=nil
end
RegisterNUICallback('waypoint',function(d,cb)
 local id=type(d)=='table' and d.id
 local p=id and (C.employers[id] or C.boards[id])
 if not opened or not p then cb({ok=false});return end
 local ok,err=pcall(function()
  -- RedM uses GPS routes; SetNewWaypoint is a GTA native.
  Citizen.InvokeNative(0x9E0AB9AAEE87CE28)
  Citizen.InvokeNative(0x3D3D15AF7BCAAF83,joaat('COLOR_RED'),true,true)
  Citizen.InvokeNative(0x64C59DD6834FA942,p.x+0.0,p.y+0.0,p.z+0.0,false)
  Citizen.InvokeNative(0x4426D65E029A4DC0,true)
  routeTarget=p
 end)
 if not ok then print('[frontier_jobs] GPS route failed: '..tostring(err)) end
 cb({ok=ok})
end)
RegisterNUICallback('clearRoute',function(_,cb)
 local ok=pcall(clearRoute);cb({ok=ok})
end)
RegisterCommand('clearjobroute',function() pcall(clearRoute) end,false)
CreateThread(function()
 while true do
  if routeTarget then
   local p=GetEntityCoords(PlayerPedId())
   if (p.x-routeTarget.x)^2+(p.y-routeTarget.y)^2+(p.z-routeTarget.z)^2<=C.reach^2 then pcall(clearRoute) end
  end
  Wait(1000)
 end
end)
AddEventHandler(E..'manage',function(id) if type(id)=='string' then open('manage',id) end end)
RegisterCommand('myjobs',function() open('personal') end,false)
local function nearest()
 local pos=GetEntityCoords(PlayerPedId());local best,dist,mode
 for m,group in pairs({board=C.boards,employer=C.employers}) do for id,p in pairs(group) do
  local n=(pos.x-p.x)^2+(pos.y-p.y)^2+(pos.z-p.z)^2
  if n<=radius(m)^2 and (not dist or n<dist) then best,dist,mode=id,n,m end
 end end
 return mode,best
end
RegisterCommand('jobs',function()
 -- Explicit interaction remains usable without an NPC or a HUD prompt.
 if opened then close() end
 local mode,id=nearest();if mode then open(mode,id) else open('personal') end
end,false)
RegisterCommand('jobdebug',function()
 local pos=GetEntityCoords(PlayerPedId())
 local best,dist,kind,place
 for mode,locations in pairs({board=C.boards,employer=C.employers}) do
  for id,p in pairs(locations) do
   local n=(pos.x-p.x)^2+(pos.y-p.y)^2+(pos.z-p.z)^2
   if not dist or n<dist then best,dist,kind,place=id,n,mode,p end
  end
 end
 if not best then return end
 local ped=peds[best]
 local msg=('Nearest %s %s: %.1fm (reach %.1fm); NPC exists=%s; menu=%s; player %.2f %.2f %.2f; point %.2f %.2f %.2f'):format(kind,best,math.sqrt(dist),radius(kind),tostring(ped~=nil and DoesEntityExist(ped)),tostring(opened==true),pos.x,pos.y,pos.z,place.x,place.y,place.z)
 if kind=='employer' then
  msg=msg..'; spawn='..tostring(spawnStatus[best] or 'not attempted')
  if ped and DoesEntityExist(ped) then local at=GetEntityCoords(ped);msg=msg..(' | ped %.2f %.2f %.2f'):format(at.x,at.y,at.z) end
 end
 print('[frontier_jobs] '..msg);TriggerEvent('chat:addMessage',{args={'Employment',msg}})
end,false)
local prompt,group
local function removeMarkers()
 for key,b in pairs(blips) do
  if DoesBlipExist(b) then RemoveBlip(b) end
  blips[key]=nil
 end
end
local function createMarkers()
 local count=0
 for kind,locations in pairs({board=C.boards,employer=C.employers}) do
  for id,p in pairs(locations) do
   local key=kind..':'..id
   if not blips[key] or not DoesBlipExist(blips[key]) then
    local ok,err=pcall(function()
     local b=BlipAddForCoords(1664425300,p.x+0.0,p.y+0.0,p.z+0.0)
     if not b or b==0 or not DoesBlipExist(b) then error('blip creation failed') end
     blips[key]=b
     SetBlipSprite(b,joaat(kind=='board' and C.boardSprite or C.employerSprite),false)
     BlipAddModifier(b,joaat('BLIP_MODIFIER_MP_COLOR_32'))
     SetBlipName(b,p.name)
    end)
    if not ok then
     if blips[key] and DoesBlipExist(blips[key]) then RemoveBlip(blips[key]) end
     blips[key]=nil;print('[frontier_jobs] Marker '..key..': '..tostring(err))
    end
   end
   if blips[key] then count=count+1 end
  end
 end
 return count
end
-- Character selection may reset map state. Recreate only missing blips after spawn.
CreateThread(function()
 while true do
  if NetworkIsPlayerActive(PlayerId()) then createMarkers() end
  Wait(10000)
 end
end)
RegisterCommand('jobmarkers',function()
 removeMarkers()
 local count=createMarkers()
 TriggerEvent('chat:addMessage',{args={'Employment',('Created %d employment map markers.'):format(count)}})
end,false)
CreateThread(function()
 group=GetRandomIntInRange(0,0xffffff);prompt=UiPromptRegisterBegin()
 UiPromptSetControlAction(prompt,joaat('INPUT_CONTEXT_X'));UiPromptSetText(prompt,VarString(10,'LITERAL_STRING','Employment'))
 UiPromptSetEnabled(prompt,true);UiPromptSetVisible(prompt,true);UiPromptSetStandardMode(prompt,true);UiPromptSetGroup(prompt,group,0);UiPromptRegisterEnd(prompt)
 while true do
  local sleep=500
  if not opened then
   local mode,id=nearest()
   if mode then
    sleep=0;local p=(mode=='board' and C.boards or C.employers)[id]
    UiPromptSetEnabled(prompt,true);UiPromptSetVisible(prompt,true)
    UiPromptSetActiveGroupThisFrame(group,VarString(10,'LITERAL_STRING',p.name),0,0,0,0)
    if UiPromptHasStandardModeCompleted(prompt,0) and (not requested or GetGameTimer()-requested>1500) then open(mode,id) end
   end
  end
  Wait(sleep)
 end
end)
CreateThread(function()
 while true do
  local pos=GetEntityCoords(PlayerPedId())
  if C.boardProp then
   for id,p in pairs(C.boards) do
    local distance=(pos.x-p.x)^2+(pos.y-p.y)^2+(pos.z-p.z)^2
    if distance<=C.stream^2 and boards[id]==nil then
     local h=joaat(C.boardProp);RequestModel(h);local deadline=GetGameTimer()+1000
     while not HasModelLoaded(h) and GetGameTimer()<deadline do Wait(25) end
     if HasModelLoaded(h) then
      local obj=CreateObject(h,p.x,p.y,p.z-0.9,false,false,false,false,false)
      if obj and obj~=0 and DoesEntityExist(obj) then
       boards[id]=obj;SetEntityAsMissionEntity(obj,true,true);SetEntityHeading(obj,p.heading or 0.0);FreezeEntityPosition(obj,true)
      end
     else boards[id]=false end
     SetModelAsNoLongerNeeded(h)
    elseif distance>C.stream^2 and boards[id]~=nil then if boards[id] then DeleteEntity(boards[id]) end;boards[id]=nil end
   end
  end
  Wait(1500)
 end
end)
-- Keep the scenery NPC worker separate from board props and prompts.
local function removeEmployer(id)
 local ped=peds[id]
 if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
 peds[id]=nil
end
local function noteSpawn(id,msg)
 spawnStatus[id]=msg;print('[frontier_jobs] Employer '..id..': '..msg)
end
local function spawnEmployer(id,p)
 if peds[id] and DoesEntityExist(peds[id]) then return end
 peds[id]=nil
 if attempts[id] and GetGameTimer()-attempts[id]<C.spawnRetryMs then return end
 attempts[id]=GetGameTimer()
 for _,model in ipairs({p.model,C.fallbackPed}) do
  local hash=joaat(model)
  RequestModel(hash,false)
  local deadline=GetGameTimer()+5000
  while not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(50) end
  if HasModelLoaded(hash) then
   local pos=GetEntityCoords(PlayerPedId())
   if (pos.x-p.x)^2+(pos.y-p.y)^2+(pos.z-p.z)^2>C.stream^2 then SetModelAsNoLongerNeeded(hash);return end
   RequestCollisionAtCoord(p.x+0.0,p.y+0.0,p.z+0.0)
   local z=p.z+0.0
   -- Use streamed terrain when available. The configured interaction point remains authoritative.
   local groundDeadline=GetGameTimer()+1500
   repeat
    local ok,ground=GetGroundZFor_3dCoord(p.x+0.0,p.y+0.0,p.z+30.0,false)
    if ok and type(ground)=='number' and math.abs(ground-p.z)<30 then z=ground;break end
    Wait(100)
   until GetGameTimer()>=groundDeadline
   local ped=CreatePed(hash,p.x+0.0,p.y+0.0,z,p.heading+0.0,false,false,false,false)
   local entityDeadline=GetGameTimer()+3000
   -- RedM may return a handle before the entity is ready (same as VORP stores).
   while ped and ped~=0 and not DoesEntityExist(ped) and GetGameTimer()<entityDeadline do Wait(50) end
   if ped and ped~=0 and DoesEntityExist(ped) then
    peds[id]=ped
    -- Do not delete an otherwise valid ped because one optional setup native failed.
    local function setup(label,fn,...)
     local ok,err=pcall(fn,...)
     if not ok then print('[frontier_jobs] '..id..' '..label..': '..tostring(err)) end
    end
    setup('mission',SetEntityAsMissionEntity,ped,true,true)
    setup('outfit',Citizen.InvokeNative,0x283978A15512B2FE,ped,true)
    setup('ground',PlaceEntityOnGroundProperly,ped,true)
    setup('damage',SetEntityCanBeDamaged,ped,false)
    setup('invincible',SetEntityInvincible,ped,true)
    setup('blocking',SetBlockingOfNonTemporaryEvents,ped,true)
    Wait(250)
    if DoesEntityExist(ped) then
     setup('stand',TaskStandStill,ped,-1)
     setup('freeze',FreezeEntityPosition,ped,true)
     local at=GetEntityCoords(ped)
     noteSpawn(id,('spawned %s handle=%s at %.2f %.2f %.2f (configured z %.2f)'):format(model,tostring(ped),at.x,at.y,at.z,p.z))
     SetModelAsNoLongerNeeded(hash)
     return
    end
    peds[id]=nil
   end
   noteSpawn(id,'CreatePed did not produce a live entity for '..model)
  else noteSpawn(id,'model not loaded: '..model) end
  SetModelAsNoLongerNeeded(hash)
 end
end
RegisterCommand('jobnpc',function()
 local pos=GetEntityCoords(PlayerPedId())
 for id,p in pairs(C.employers) do
  if (pos.x-p.x)^2+(pos.y-p.y)^2+(pos.z-p.z)^2<=C.stream^2 then
   removeEmployer(id);attempts[id]=nil
  end
 end
 TriggerEvent('chat:addMessage',{args={'Employment','Nearby NPCs will be recreated. Check F8 or /jobdebug for the spawn result.'}})
end,false)
CreateThread(function()
 while true do
  local pos=GetEntityCoords(PlayerPedId())
  for id,p in pairs(C.employers) do
   local distance=(pos.x-p.x)^2+(pos.y-p.y)^2+(pos.z-p.z)^2
   if distance<=C.stream^2 then
    local ok,err=pcall(spawnEmployer,id,p)
    if not ok then noteSpawn(id,'spawn error: '..tostring(err)) end
   else removeEmployer(id);attempts[id]=nil end
  end
  Wait(1500)
 end
end)
AddEventHandler('onClientResourceStop',function(r)
 if r~=GetCurrentResourceName() then return end
 close();if prompt then UiPromptDelete(prompt) end
 for _,ped in pairs(peds) do DeleteEntity(ped) end
 for _,obj in pairs(boards) do if obj then DeleteEntity(obj) end end
 removeMarkers();pcall(clearRoute)
end)
