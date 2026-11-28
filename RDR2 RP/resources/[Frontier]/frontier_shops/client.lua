local C=ShopConfig
local E='frontier_shops:'
local opened,ticket,requested=false,nil,nil
local peds,attempts,markers={},{},{}
local function close()
 if ticket then TriggerServerEvent(E..'close',ticket) end
 opened=false;ticket=nil;requested=nil;SetNuiFocus(false,false);SendNUIMessage({type='close'})
end
local function near()
 local p=GetEntityCoords(PlayerPedId());local id,best
 for k,s in pairs(C.sites) do local n=(p.x-s.x)^2+(p.y-s.y)^2+(p.z-s.z)^2;if n<=C.reach^2 and (not best or n<best) then id,best=k,n end end
 return id
end
local function open()
 if opened then return end
 local id=near();if not id then TriggerEvent('chat:addMessage',{args={'Shop','Visit a shop counter.'}});return end
 requested=GetGameTimer();TriggerServerEvent(E..'open',id)
end
RegisterCommand('shop',open,false)
RegisterNetEvent(E..'view',function(d)
 if source~=65535 or (not opened and (not requested or GetGameTimer()-requested>15000)) then return end
 opened=true;requested=nil;ticket=d.ticket;SetNuiFocus(true,true);SendNUIMessage({type='view',data=d})
end)
RegisterNetEvent(E..'notice',function(m)
 if source~=65535 then return end
 if opened then SendNUIMessage({type='notice',message=m}) else TriggerEvent('chat:addMessage',{args={'Shop',m}}) end
end)
RegisterNetEvent(E..'close',function() if source==65535 then close() end end)
RegisterNUICallback('close',function(_,cb)close();cb({ok=true})end)
RegisterNUICallback('refresh',function(_,cb)if opened then TriggerServerEvent(E..'refresh',ticket) end;cb({ok=opened})end)
RegisterNUICallback('checkout',function(d,cb)
 if opened and ticket and type(d)=='table' then TriggerServerEvent(E..'checkout',ticket,d.mode,d.lines);cb({ok=true}) else cb({ok=false}) end
end)
local prompt,group
CreateThread(function()
 group=GetRandomIntInRange(0,0xffffff);prompt=UiPromptRegisterBegin()
 UiPromptSetControlAction(prompt,0x760A9C6F);UiPromptSetText(prompt,VarString(10,'LITERAL_STRING','Browse shop'))
 UiPromptSetEnabled(prompt,true);UiPromptSetVisible(prompt,true);UiPromptSetStandardMode(prompt,true);UiPromptSetGroup(prompt,group,0);UiPromptRegisterEnd(prompt)
 while true do
  local sleep=500
  if not opened and LocalPlayer.state.IsInSession and not IsNuiFocused() then
   local id=near()
   if id then sleep=0;UiPromptSetActiveGroupThisFrame(group,VarString(10,'LITERAL_STRING',C.sites[id].name),0,0,0,0)
    if UiPromptHasStandardModeCompleted(prompt,0) and (not requested or GetGameTimer()-requested>1500) then open() end
   end
  end
  Wait(sleep)
 end
end)
local function remove(id) local p=peds[id];if p and DoesEntityExist(p) then DeleteEntity(p) end;peds[id]=nil end
local function spawn(id,s)
 if peds[id] and DoesEntityExist(peds[id]) then return end
 if attempts[id] and GetGameTimer()-attempts[id]<12000 then return end
 attempts[id]=GetGameTimer()
 local n=s.npc
 for _,model in ipairs({n.model,'S_M_M_UNIBUTCHERS_01'}) do
  local hash=joaat(model);RequestModel(hash,false);local deadline=GetGameTimer()+5000
  while not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(50) end
  if HasModelLoaded(hash) then
   RequestCollisionAtCoord(n.x+0.0,n.y+0.0,n.z+0.0)
   local p=CreatePed(hash,n.x+0.0,n.y+0.0,n.z+0.0,n.h+0.0,false,false,false,false)
   local untilAt=GetGameTimer()+3000
   while p and p~=0 and not DoesEntityExist(p) and GetGameTimer()<untilAt do Wait(50) end
   if p and p~=0 and DoesEntityExist(p) then
    peds[id]=p
    pcall(SetEntityAsMissionEntity,p,true,true)
    pcall(Citizen.InvokeNative,0x283978A15512B2FE,p,true)
    -- Use VORP counter height; do not ground-snap through multi-floor interiors.
    pcall(SetEntityCanBeDamaged,p,false);pcall(SetEntityInvincible,p,true);pcall(SetBlockingOfNonTemporaryEvents,p,true)
    pcall(TaskStandStill,p,-1);pcall(FreezeEntityPosition,p,true)
    SetModelAsNoLongerNeeded(hash);return
   end
  end
  SetModelAsNoLongerNeeded(hash)
 end
 print('[frontier_shops] NPC spawn failed: '..id)
end
CreateThread(function()
 while true do
  if LocalPlayer.state.IsInSession then
   local p=GetEntityCoords(PlayerPedId())
   for id,s in pairs(C.sites) do
    if (p.x-s.x)^2+(p.y-s.y)^2+(p.z-s.z)^2<=C.stream^2 then local ok,err=pcall(spawn,id,s);if not ok then print('[frontier_shops] '..id..': '..tostring(err)) end
    else remove(id);attempts[id]=nil end
   end
  else for id in pairs(peds) do remove(id) end end
  Wait(1500)
 end
end)
CreateThread(function()
 while true do
  if NetworkIsPlayerActive(PlayerId()) then
   for id,s in pairs(C.sites) do
    if not markers[id] or not DoesBlipExist(markers[id]) then
     local ok,err=pcall(function()
      local b=BlipAddForCoords(1664425300,s.x+0.0,s.y+0.0,s.z+0.0)
      if not b or b==0 then return end
      markers[id]=b;SetBlipSprite(b,s.sprite,false);BlipAddModifier(b,joaat('BLIP_MODIFIER_MP_COLOR_32'));SetBlipName(b,s.name)
     end)
     if not ok then print('[frontier_shops] Marker '..id..': '..tostring(err)) end
    end
   end
  end
  Wait(10000)
 end
end)
AddEventHandler('onClientResourceStop',function(r)
 if r~=GetCurrentResourceName() then return end
 close();if prompt then UiPromptDelete(prompt) end
 for id in pairs(peds) do remove(id) end
 for _,b in pairs(markers) do if DoesBlipExist(b) then RemoveBlip(b) end end
end)
