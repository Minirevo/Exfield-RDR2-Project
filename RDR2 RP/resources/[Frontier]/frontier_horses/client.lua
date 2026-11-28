local C=HorseConfig
local E='frontier_horses:'
local opened,ticket=false,nil
local mount,provisional=0,0
local npcs,blips={},{}
local function notice(msg) TriggerEvent('chat:addMessage',{args={'Stable',tostring(msg)}}) end
local function close()opened=false;ticket=nil;SetNuiFocus(false,false);SendNUIMessage({type='close'})end
local function near()
 local p=GetEntityCoords(PlayerPedId())
 for id,s in pairs(C.sites) do if #(p-vector3(s.x,s.y,s.z))<=C.reach then return id end end
end
RegisterCommand('stable',function()TriggerServerEvent(E..'open')end,false)
RegisterCommand('horsecall',function()TriggerServerEvent(E..'call')end,false)
RegisterCommand('horsebags',function()TriggerServerEvent(E..'bags')end,false)
RegisterNetEvent(E..'notice',function(m)if source~=65535 then return end;if opened then SendNUIMessage({type='notice',message=m})else notice(m)end end)
RegisterNetEvent(E..'view',function(d)if source~=65535 then return end;opened=true;ticket=d.ticket;SetNuiFocus(true,true);SendNUIMessage({type='view',data=d})end)
RegisterNetEvent(E..'close',function()if source==65535 then close()end end)
RegisterNUICallback('close',function(_,cb)close();cb({ok=true})end)
RegisterNUICallback('action',function(d,cb)if opened and ticket then TriggerServerEvent(E..'action',ticket,d.op,d.data or {});cb({ok=true})else cb({ok=false})end end)
RegisterNetEvent(E..'spawn',function(d)
 if source~=65535 then return end
 close()
 CreateThread(function()
  local h=joaat(d.model);RequestModel(h,false);local deadline=GetGameTimer()+7000
  while not HasModelLoaded(h) and GetGameTimer()<deadline do Wait(50)end
  if not HasModelLoaded(h) then TriggerServerEvent(E..'spawnFail',d.token);return end
  local p=d.point;RequestCollisionAtCoord(p.x,p.y,p.z)
  local ped=CreatePed(h,p.x,p.y,p.z,GetEntityHeading(PlayerPedId()),true,true,false,false)
  if not ped or ped==0 then TriggerServerEvent(E..'spawnFail',d.token);return end
  provisional=ped;deadline=GetGameTimer()+5000
  while not DoesEntityExist(ped) and GetGameTimer()<deadline do Wait(50)end
  if not DoesEntityExist(ped) then provisional=0;TriggerServerEvent(E..'spawnFail',d.token);return end
  pcall(Citizen.InvokeNative,0x283978A15512B2FE,ped,true)
  pcall(PlaceEntityOnGroundProperly,ped,true)
  for _,id in pairs(d.horse.gear or {}) do local g=C.equipment[id];if g and g.component then pcall(Citizen.InvokeNative,0xD3A7B003ED343FD9,ped,g.component,true,true,true)end end
  pcall(Citizen.InvokeNative,0xCC8CA3E88256E58F,ped,0,1,1,1,0)
  pcall(Citizen.InvokeNative,0xD2CB0FB0FDCB473D,PlayerId(),ped)
  for k,v in pairs({[0]=d.horse.genes.health,[1]=d.horse.genes.stamina,[4]=d.horse.genes.speed,[5]=d.horse.genes.speed}) do pcall(Citizen.InvokeNative,0x5DA12E025D47D4E5,ped,k,math.floor(v*10+(d.horse.training or 0)*3))end
  pcall(Citizen.InvokeNative,0xC6258F41D86676E0,ped,0,math.floor(d.horse.health))
  pcall(Citizen.InvokeNative,0xC6258F41D86676E0,ped,1,math.floor(d.horse.care))
  if not NetworkGetEntityIsNetworked(ped) then NetworkRegisterEntityAsNetworked(ped)end
  local net=NetworkGetNetworkIdFromEntity(ped);SetModelAsNoLongerNeeded(h)
  if not net or net==0 then DeleteEntity(ped);provisional=0;TriggerServerEvent(E..'spawnFail',d.token);return end
  TriggerServerEvent(E..'spawnAck',d.token,net)
  Wait(22000);if provisional==ped then if DoesEntityExist(ped) then DeleteEntity(ped)end;provisional=0 end
 end)
end)
RegisterNetEvent(E..'accepted',function(net)if source~=65535 then return end;mount=NetToPed(net);provisional=0;notice('Horse ready. /horsecall or /horsebags. Bring it to a stable to board.')end)
RegisterNetEvent(E..'stored',function()if source~=65535 then return end;if provisional~=0 and DoesEntityExist(provisional) then DeleteEntity(provisional)end;provisional=0;mount=0 end)
RegisterNetEvent(E..'follow',function(net)if source~=65535 then return end;local p=NetToPed(net);if p~=0 then pcall(Citizen.InvokeNative,0x6A071245EB0D1882,p,PlayerPedId(),-1,4.0,100.0,0,0)end end)
CreateThread(function()
 local group=GetRandomIntInRange(0,0xffffff);local prompt=UiPromptRegisterBegin();UiPromptSetControlAction(prompt,0x760A9C6F);UiPromptSetText(prompt,VarString(10,'LITERAL_STRING','Manage horses'));UiPromptSetEnabled(prompt,true);UiPromptSetVisible(prompt,true);UiPromptSetStandardMode(prompt,true);UiPromptSetGroup(prompt,group,0);UiPromptRegisterEnd(prompt)
 while true do
  local id=near()
  if id and not opened and not IsNuiFocused() and LocalPlayer.state.IsInSession then UiPromptSetActiveGroupThisFrame(group,VarString(10,'LITERAL_STRING',C.sites[id].name),0,0,0,0);if UiPromptHasStandardModeCompleted(prompt,0) then TriggerServerEvent(E..'open');Wait(1000)end;Wait(0)else Wait(300)end
 end
end)
CreateThread(function()
 while true do Wait(1500);local p=GetEntityCoords(PlayerPedId())
  if NetworkIsPlayerActive(PlayerId()) then
   for id,s in pairs(C.sites) do
    if not blips[id] then pcall(function()local b=BlipAddForCoords(1664425300,s.x,s.y,s.z);SetBlipSprite(b,joaat('blip_shop_horse'),false);SetBlipName(b,s.name);blips[id]=b end)end
    if #(p-vector3(s.x,s.y,s.z))<45 and (not npcs[id] or not DoesEntityExist(npcs[id])) then
     local h=joaat('A_M_M_VALTOWNFOLK_01');RequestModel(h,false);local t=GetGameTimer()+3000;while not HasModelLoaded(h) and GetGameTimer()<t do Wait(50)end
     if HasModelLoaded(h) then local n=s.npc;local ped=CreatePed(h,n[1],n[2],n[3],n[4],false,false,false,false);Wait(100);if DoesEntityExist(ped) then npcs[id]=ped;pcall(Citizen.InvokeNative,0x283978A15512B2FE,ped,true);pcall(PlaceEntityOnGroundProperly,ped,true);SetEntityInvincible(ped,true);SetBlockingOfNonTemporaryEvents(ped,true);FreezeEntityPosition(ped,true)end;SetModelAsNoLongerNeeded(h)end
    elseif npcs[id] and #(p-vector3(s.x,s.y,s.z))>60 then DeleteEntity(npcs[id]);npcs[id]=nil end
   end
  end
 end
end)
AddEventHandler('onClientResourceStop',function(n)if n==GetCurrentResourceName() then close();for _,p in pairs(npcs)do if DoesEntityExist(p)then DeleteEntity(p)end end;for _,b in pairs(blips)do RemoveBlip(b)end end end)
