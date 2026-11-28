local C=HorseConfig
local E='frontier_horses:'
local opened,ticket=false,nil
local mount,provisional=0,0
local npcs,blips={},{}
local previewSite,previewModels=nil,{}
local previewPed,previewCam,previewGeneration,previewHeading=0,nil,0,0
local previewKey=nil
local function notice(msg) TriggerEvent('chat:addMessage',{args={'Stable',tostring(msg)}}) end
local function clearPreview()
 previewGeneration=previewGeneration+1;previewKey=nil
 if previewPed~=0 and DoesEntityExist(previewPed) then DeletePed(previewPed) end
 previewPed=0
 if previewCam then RenderScriptCams(false,false,0,true,true,0);DestroyCam(previewCam,false);previewCam=nil end
end
local function close()
 clearPreview();previewSite=nil;previewModels={}
 opened=false;ticket=nil;SetNuiFocus(false,false);SendNUIMessage({type='close'})
end
local function near()
 local p=GetEntityCoords(PlayerPedId())
 for id,s in pairs(C.sites) do if #(p-vector3(s.x,s.y,s.z))<=C.reach then return id end end
end
RegisterCommand('stable',function()TriggerServerEvent(E..'open')end,false)
RegisterCommand('horsecall',function()TriggerServerEvent(E..'call')end,false)
RegisterCommand('horsebags',function()TriggerServerEvent(E..'bags')end,false)
RegisterCommand('horsecare',function()TriggerServerEvent(E..'care')end,false)
RegisterNetEvent(E..'notice',function(m)if source~=65535 then return end;if opened then SendNUIMessage({type='notice',message=m})else notice(m)end end)
RegisterNetEvent(E..'view',function(d)
 if source~=65535 then return end
 if previewSite and previewSite~=d.site then clearPreview() end
 previewSite=d.site;previewModels={}
 for id,h in pairs(d.breeds or {}) do previewModels['npc:'..id]={model=h.model,gear={}} end
 for _,h in ipairs(d.listings or {}) do
  if type(h.model)=='string' then previewModels['ranch:'..h.id]={model=h.model,gear=h.gear or {}} end
 end
 opened=true;ticket=d.ticket;SetNuiFocus(true,true);SendNUIMessage({type='view',data=d})
end)
RegisterNUICallback('previewStop',function(_,cb)clearPreview();cb({ok=true})end)
RegisterNUICallback('previewRotate',function(d,cb)
 if opened and previewPed~=0 and DoesEntityExist(previewPed) then
  local step=d.direction=='left' and -30 or d.direction=='right' and 30 or 0
  previewHeading=(previewHeading+step)%360;SetEntityHeading(previewPed,previewHeading)
 end
 cb({ok=true})
end)
RegisterNUICallback('previewHorse',function(d,cb)
 local key=type(d)=='table' and d.key
 local h=type(key)=='string' and previewModels[key]
 local site=previewSite and C.sites[previewSite]
 if not opened or not h or not site or type(h.model)~='string' or not h.model:lower():match('^a_c_horse_') or not site.preview or not site.camera then cb({ok=false});return end
 if previewKey==key and previewPed~=0 and DoesEntityExist(previewPed) then cb({ok=true});return end
 previewGeneration=previewGeneration+1;local generation=previewGeneration;previewKey=key
 if previewPed~=0 and DoesEntityExist(previewPed) then DeletePed(previewPed) end
 previewPed=0
 cb({ok=true})
 CreateThread(function()
  local hash=joaat(h.model);local p=site.preview;local c=site.camera
  local ok,err=pcall(function()
   RequestCollisionAtCoord(p[1]+0.0,p[2]+0.0,p[3]+0.0)
   RequestModel(hash,false);local deadline=GetGameTimer()+6000
   while opened and generation==previewGeneration and not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(50) end
   if not opened or generation~=previewGeneration then return end
   if not HasModelLoaded(hash) then error('Model could not be streamed') end
   local ped=CreatePed(hash,p[1]+0.0,p[2]+0.0,p[3]+0.0,p[4]+0.0,false,false,false,false)
   if not ped or ped==0 then error('Preview horse could not spawn') end
   deadline=GetGameTimer()+3000
   while not DoesEntityExist(ped) and GetGameTimer()<deadline and opened and generation==previewGeneration do Wait(50) end
   if not opened or generation~=previewGeneration then if DoesEntityExist(ped) then DeletePed(ped) end;return end
   if not DoesEntityExist(ped) then error('Preview horse did not initialize') end
   previewPed=ped;previewHeading=p[4]
   SetEntityAsMissionEntity(ped,true,true)
   Citizen.InvokeNative(0x283978A15512B2FE,ped,true)
   Citizen.InvokeNative(0xC8A9481A01E63C28,ped,1)
   for _,id in pairs(h.gear or {}) do local g=C.equipment[id];if g and g.component then pcall(Citizen.InvokeNative,0xD3A7B003ED343FD9,ped,g.component,true,true,true) end end
   pcall(Citizen.InvokeNative,0xCC8CA3E88256E58F,ped,0,1,1,1,0)
   SetEntityInvincible(ped,true);SetEntityCanBeDamaged(ped,false);SetBlockingOfNonTemporaryEvents(ped,true)
   pcall(SetEntityCollision,ped,false,false)
   FreezeEntityPosition(ped,true)
   if not previewCam then
    previewCam=Citizen.InvokeNative(0x40C23491CE83708E,'DEFAULT_SCRIPTED_CAMERA',c[1]+0.0,c[2]+0.0,c[3]+0.0,c[4]+0.0,c[5]+0.0,c[6]+0.0,70.0,false,0)
    if not previewCam or previewCam==0 then previewCam=nil;error('Camera could not be created') end
    SetCamActive(previewCam,true);RenderScriptCams(true,false,0,true,true,0)
   end
   SendNUIMessage({type='previewStatus',key=key,ok=true})
  end)
  -- A newer request may be streaming the same hash. Avoid releasing its model early.
  if generation==previewGeneration then
   SetModelAsNoLongerNeeded(hash)
   if not ok then
    print('[frontier_horses] Preview '..tostring(key)..': '..tostring(err))
    clearPreview();SendNUIMessage({type='previewStatus',key=key,ok=false,message='3D preview unavailable. You can still browse and buy.'})
   end
  elseif not opened or not previewKey or not previewModels[previewKey] or joaat(previewModels[previewKey].model)~=hash then SetModelAsNoLongerNeeded(hash) end
 end)
end)
CreateThread(function()
 while true do
  if opened then
   if not LocalPlayer.state.IsInSession or IsEntityDead(PlayerPedId()) or near()~=previewSite then close() end
   Wait(500)
  else Wait(1000) end
 end
end)
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
