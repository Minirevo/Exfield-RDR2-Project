local C=JobsConfig
local E='frontier_jobs:'
local ticket,opened,requested
local peds,blips,boards={},{},{}
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
  if n<=C.reach^2 and (not dist or n<dist) then best,dist,mode=id,n,m end
 end end
 return mode,best
end
RegisterCommand('jobs',function()
 local mode,id=nearest();if mode then open(mode,id) else open('personal') end
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
    UiPromptSetActiveGroupThisFrame(group,VarString(10,'LITERAL_STRING',p.name),0,0,0,0)
    if UiPromptHasStandardModeCompleted(prompt,0) then open(mode,id) end
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
  for id,p in pairs(C.employers) do
   local distance=(pos.x-p.x)^2+(pos.y-p.y)^2+(pos.z-p.z)^2
   if distance<=C.stream^2 and not peds[id] then
    local h=joaat(p.model);RequestModel(h);local deadline=GetGameTimer()+2000
    while not HasModelLoaded(h) and GetGameTimer()<deadline do Wait(25) end
    if HasModelLoaded(h) then
     local ped=CreatePed(h,p.x,p.y,p.z,p.heading,false,false,false,false)
     if ped and ped~=0 and DoesEntityExist(ped) then
      peds[id]=ped;SetEntityAsMissionEntity(ped,true,true);FreezeEntityPosition(ped,true);SetEntityInvincible(ped,true);SetBlockingOfNonTemporaryEvents(ped,true)
     end
    end
    SetModelAsNoLongerNeeded(h)
   elseif distance>C.stream^2 and peds[id] then DeleteEntity(peds[id]);peds[id]=nil end
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
