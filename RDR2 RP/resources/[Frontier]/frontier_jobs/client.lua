local C=JobsConfig
local E='frontier_jobs:'
local ticket,opened,requested
local peds,blips,boards={},{},{}
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
RegisterNUICallback('waypoint',function(d,cb)
 local p=C.employers[d.id] or C.boards[d.id]
 if not p then cb({ok=false});return end
 local ok=pcall(function()
  if type(SetNewWaypoint)=='function' then SetNewWaypoint(p.x,p.y)
  else Citizen.InvokeNative(0x3D3D15AF7BCAAF83,p.x,p.y) end
 end)
 cb({ok=ok})
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
CreateThread(function()
 for id,p in pairs(C.boards) do
  local ok,b=pcall(Citizen.InvokeNative,0x554D9D53F696D002,1664425300,p.x,p.y,p.z)
  if ok and b and b~=0 then
   blips[id]=b
   pcall(SetBlipSprite,b,joaat('blip_ambient_job'),true)
   pcall(Citizen.InvokeNative,0x9CB1A1623062F402,b,p.name)
  end
 end
end)
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
 for _,blip in pairs(blips) do RemoveBlip(blip) end
end)
