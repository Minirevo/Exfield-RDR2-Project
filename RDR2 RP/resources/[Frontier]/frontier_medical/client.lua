local C,E=FrontierMedicalConfig,'frontier_medical:'
local state,received,ticket=nil,0,nil
local opened=false
local hospitalTicket,hospitalRequested=nil,nil
local function closeHospital()
 if hospitalTicket then TriggerServerEvent(E..'hospitalClose',hospitalTicket) end
 hospitalTicket=nil;hospitalRequested=nil;SetNuiFocus(false,false);SendNUIMessage({type='hospitalClose'})
end
local requestAt=0
local symptomVisible=false
local feedbackAt=-10000
local feedbackActive=false
local dispatchBlip,dispatchNumber=nil,nil
local patientDispatchVisible=false
local function truth(v) return v==true or v==1 end
local function native(name,...)
 local fn=_G[name];if type(fn)~='function' then return nil end
 local ok,a,b=pcall(fn,...);if ok then return a,b end
end
local function playing() return LocalPlayer.state.IsInSession==true end
local function clearDispatchMarker(number)
 if number and dispatchNumber~=number then return end
 if dispatchBlip and dispatchBlip~=0 then pcall(RemoveBlip,dispatchBlip) end
 dispatchBlip=nil;dispatchNumber=nil
end
RegisterNetEvent(E..'dispatchMarker',function(number,pos)
 if source~=65535 or not playing() or type(number)~='number' or type(pos)~='table' or type(pos.x)~='number' or type(pos.y)~='number' or type(pos.z)~='number' then return end
 clearDispatchMarker()
 local ok,blip=pcall(Citizen.InvokeNative,0x554D9D53F696D002,joaat('BLIP_STYLE_CHALLENGE_OBJECTIVE'),pos.x,pos.y,pos.z,Citizen.ResultAsInteger())
 if ok and blip and blip~=0 then
  dispatchBlip=blip;dispatchNumber=number
  pcall(SetBlipSprite,blip,joaat('blip_mp_travelling_saleswoman'),true)
  pcall(Citizen.InvokeNative,0x9CB1A1623062F402,blip,'Medical emergency #'..number)
 else
  TriggerEvent('chat:addMessage',{args={'Medical',('Map marker unavailable. Emergency coordinates: %.0f, %.0f'):format(pos.x,pos.y)}})
 end
end)
RegisterNetEvent(E..'dispatchClear',function(number)
 if source==65535 then clearDispatchMarker(number) end
end)
local function patientDispatch(active,message)
 if not active and not patientDispatchVisible then return end
 patientDispatchVisible=active==true
 SendNUIMessage({type='dispatchPatient',active=patientDispatchVisible,message=type(message)=='string' and message or ''})
end
RegisterNetEvent(E..'dispatchPatient',function(active,message)
 if source~=65535 or not playing() then return end
 if active==true and (not state or not state.down or state.dead) then return end
 patientDispatch(active==true,message)
end)
local function clearFeedback()
 if symptomVisible then SendNUIMessage({type='symptoms',symptoms={}});symptomVisible=false end
 if feedbackActive then SendNUIMessage({type='clearFeedback'});feedbackActive=false end
end
local function close()
 if ticket then TriggerServerEvent(E..'close',ticket) end
 ticket=nil;opened=false;SetNuiFocus(false,false);SendNUIMessage({type='close'})
end
RegisterNetEvent(E..'notice',function(msg)
 if source~=65535 or type(msg)~='string' then return end
 TriggerEvent('chat:addMessage',{args={'Medical',msg}});print('[frontier_medical] '..msg)
 if opened then SendNUIMessage({type='notice',message=msg}) end
end)
RegisterNetEvent(E..'state',function(v)
 if source~=65535 or not playing() or type(v)~='table' then return end
 local previous=state
 state=v;received=GetGameTimer();FrontierMedicalAdapter.update(v)
 if v.down or v.dead then clearFeedback()
 else
  local symptoms=type(v.symptoms)=='table' and v.symptoms or {}
  if #symptoms>0 or symptomVisible then SendNUIMessage({type='symptoms',symptoms=symptoms}) end
  symptomVisible=#symptoms>0
  if symptomVisible then feedbackActive=true end
 end
 if previous and previous.life==v.life and previous.down~=v.down and not v.dead then
  local msg=v.down and 'You have lost consciousness.' or 'You have regained consciousness.'
  TriggerEvent('chat:addMessage',{args={'Medical',msg}})
 end
 if v.down and opened then close() end
 if v.down and hospitalTicket then closeHospital() end
 if not v.down or v.dead then patientDispatch(false)
 elseif not patientDispatchVisible then patientDispatch(true,'You are unconscious. Use /mediccall to request help.') end
end)
RegisterNetEvent(E..'injuryFeedback',function(token,message)
 if source~=65535 or not playing() or not state or state.token~=token or state.down or state.dead or type(message)~='string' then return end
 local now=GetGameTimer()
 if now-feedbackAt<1500 then return end
 feedbackAt=now;feedbackActive=true;SendNUIMessage({type='injuryFeedback',message=message})
end)
CreateThread(function()
 while true do
  Wait(1000)
  if not playing() or not state or GetGameTimer()-received>=C.stateTimeoutMs or truth(native('IsPlayerDead',PlayerId())) then
   if feedbackActive then clearFeedback() end
   clearDispatchMarker();patientDispatch(false)
   if hospitalTicket then closeHospital() end
  end
 end
end)
local sprint=joaat('INPUT_SPRINT')
local blocked={sprint,joaat('INPUT_MOVE_LR'),joaat('INPUT_MOVE_UD'),joaat('INPUT_ATTACK'),joaat('INPUT_AIM'),joaat('INPUT_JUMP'),joaat('INPUT_MELEE_ATTACK'),joaat('INPUT_ENTER'),joaat('INPUT_RELOAD')}
CreateThread(function()
 local ragPed,ragAt=nil,0
 while true do
  local p=PlayerPedId()
  if playing() and state and GetGameTimer()-received<C.stateTimeoutMs and p~=0 and not truth(IsEntityDead(p)) and not truth(native('IsPlayerDead',PlayerId())) then
   if state.down then
    for _,control in ipairs(blocked) do DisableControlAction(0,control,true) end
    DisablePlayerFiring(PlayerId(),true)
    if not state.dead and not truth(native('IsPedOnMount',p)) and not truth(native('IsPedInAnyVehicle',p,false)) and not truth(native('IsEntityAttachedToAnyPed',p)) then
     -- Keep the original collapse alive rather than periodically starting
     -- a fresh ragdoll task as the ped begins its get-up animation.
     local now=GetGameTimer()
     if not truth(native('IsPedRagdoll',p)) and (ragPed~=p or now-ragAt>=150) then
      native('SetPedToRagdoll',p,1000,1000,0,false,false,false)
      ragPed=p;ragAt=now
     end
     native('ResetPedRagdollTimer',p)
    else ragPed=nil end
    Wait(0)
   elseif state.legs or state.arms then
    ragPed=nil
    if state.legs then DisableControlAction(0,sprint,true) end
    if state.arms then DisablePlayerFiring(PlayerId(),true);DisableControlAction(0,joaat('INPUT_MELEE_ATTACK'),true) end
    Wait(0)
   else ragPed=nil;Wait(100) end
  else ragPed=nil;Wait(100) end
 end
end)
RegisterCommand('medical',function(_,args)
 if not playing() or opened or hospitalTicket or (state and state.down) then return end
 local target=tonumber(args[1]) or GetPlayerServerId(PlayerId())
 requestAt=GetGameTimer()
 TriggerServerEvent(E..'open',target)
end,false)
RegisterNetEvent(E..'view',function(data)
 if source~=65535 or not playing() or hospitalTicket or type(data)~='table' or type(data.ticket)~='string' then return end
 if opened and ticket~=data.ticket then return end
 if not opened and (requestAt==0 or GetGameTimer()-requestAt>10000) then return end
 requestAt=0
 local first=not opened
 ticket=data.ticket;opened=true;if first then SetNuiFocus(true,true) end;SendNUIMessage({type='view',data=data})
end)
RegisterNetEvent(E..'closeView',function(t)
 if source==65535 and ticket==t and opened then close() end
end)
RegisterNetEvent(E..'operationStage',function(t,d)
 if source==65535 and opened and ticket==t and type(d)=='table' then SendNUIMessage({type='operationStage',data=d}) end
end)
RegisterNetEvent(E..'operationEnd',function(key)
 if source==65535 and opened then SendNUIMessage({type='operationEnd',key=key}) end
end)
RegisterNUICallback('operationPress',function(d,cb)
 if opened and ticket and type(d)=='table' then TriggerServerEvent(E..'operationPress',d.key,d.stage) end
 cb({ok=true})
end)
RegisterNUICallback('close',function(_,cb) close();cb({ok=true}) end)
RegisterNUICallback('action',function(d,cb)
 if opened and ticket and type(d)=='table' then TriggerServerEvent(E..'action',ticket,d.action,d.region,d.item) end
 cb({ok=true})
end)
RegisterNetEvent('vorp:SelectedCharacter',function() if hospitalTicket then closeHospital() end; state=nil;received=0;requestAt=0;feedbackAt=-10000;clearFeedback();clearDispatchMarker();patientDispatch(false);FrontierMedicalAdapter.reset();if opened then close() end end)
AddEventHandler('onClientResourceStop',function(r) if r==GetCurrentResourceName() then clearDispatchMarker();if hospitalTicket then closeHospital() end;if opened then close() end end end)

-- Hospital screens share focus ownership with the existing examination chart.
local function hospitalOpen(mode,station)
 if not playing() or opened or hospitalTicket or not state or state.down or state.dead then return end
 hospitalRequested=GetGameTimer()
 TriggerServerEvent(E..'hospitalOpen',mode,station)
end
RegisterCommand('medicalbills',function() hospitalOpen('patient') end,false)
RegisterCommand('medicalreports',function() hospitalOpen('police') end,false)
RegisterNetEvent(E..'hospitalView',function(d)
 if source~=65535 or not playing() or opened or not state or state.down or state.dead or type(d)~='table' or type(d.ticket)~='string' then return end
 if hospitalTicket and hospitalTicket~=d.ticket then return end
 if not hospitalTicket and (not hospitalRequested or GetGameTimer()-hospitalRequested>15000) then return end
 local first=not hospitalTicket;hospitalTicket=d.ticket;hospitalRequested=nil
 if first then SetNuiFocus(true,true) end
 SendNUIMessage({type='hospitalView',data=d})
end)
RegisterNetEvent(E..'hospitalDetail',function(t,d)
 if source==65535 and t==hospitalTicket then SendNUIMessage({type='hospitalDetail',data=d}) end
end)
RegisterNetEvent(E..'billingView',function(t,d)
 if source==65535 and opened and t==ticket then SendNUIMessage({type='billingView',data=d}) end
end)
RegisterNetEvent(E..'hospitalCloseView',function(t)
 if source==65535 and t==hospitalTicket then closeHospital() end
end)
RegisterNUICallback('hospitalClose',function(_,cb) if hospitalTicket then closeHospital() end;cb({ok=true}) end)
RegisterNUICallback('hospitalAction',function(d,cb)
 if hospitalTicket and type(d)=='table' then TriggerServerEvent(E..'hospitalAction',hospitalTicket,d.action,d.id,d.count,d.search,d.before) end
 cb({ok=true})
end)
RegisterNUICallback('hospitalDispatch',function(d,cb)
 if hospitalTicket and type(d)=='table' then
  if d.action=='release' then ExecuteCommand('medicrelease')
  elseif d.action=='accept' and type(d.number)=='number' and d.number%1==0 and d.number>0 then ExecuteCommand('medicaccept '..d.number) end
  TriggerServerEvent(E..'hospitalAction',hospitalTicket,'refresh')
 end
 cb({ok=true})
end)
-- Station coordinates come from the retired VORP medical resource.
-- Local scenery peds; no client coordinates are trusted by the server.
local HC=FrontierHospitalConfig
local peds,attempts={},{}
local prompt,group
local function deleteClerk(id)
 local ped=peds[id];if ped and DoesEntityExist(ped) then DeleteEntity(ped) end;peds[id]=nil
end
local function spawnClerk(id,st)
 if peds[id] or (attempts[id] and GetGameTimer()-attempts[id]<15000) then return end
 attempts[id]=GetGameTimer()
 local hash=joaat(st.model)
 RequestModel(hash)
 local deadline=GetGameTimer()+3000
 while not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(25) end
 if not HasModelLoaded(hash) then SetModelAsNoLongerNeeded(hash);return end
 if playing() then
  local ped=CreatePed(hash,st.x,st.y,st.z,st.heading,false,false,false,false)
  if ped and ped~=0 and DoesEntityExist(ped) then
   peds[id]=ped;SetEntityAsMissionEntity(ped,true,true)
   pcall(Citizen.InvokeNative,0x283978A15512B2FE,ped,true)
   FreezeEntityPosition(ped,true);SetEntityInvincible(ped,true);SetBlockingOfNonTemporaryEvents(ped,true)
  end
 end
 SetModelAsNoLongerNeeded(hash)
end
CreateThread(function()
 group=GetRandomIntInRange(0,0xffffff)
 prompt=UiPromptRegisterBegin()
 UiPromptSetControlAction(prompt,joaat('INPUT_CONTEXT_X'))
 UiPromptSetText(prompt,VarString(10,'LITERAL_STRING','Hospital service'))
 UiPromptSetEnabled(prompt,true);UiPromptSetVisible(prompt,true);UiPromptSetStandardMode(prompt,true)
 UiPromptSetGroup(prompt,group,0);UiPromptRegisterEnd(prompt)
 while true do
  local sleep=500
  if playing() then
   local pos=GetEntityCoords(PlayerPedId())
   for id,st in pairs(HC.stations) do
    local distance=(pos.x-st.x)^2+(pos.y-st.y)^2+(pos.z-st.z)^2
    if distance<=HC.spawnDistance^2 then
     if not peds[id] then spawnClerk(id,st) end
     if distance<=HC.reach^2 and not opened and not hospitalTicket and state and not state.down and not state.dead then
      sleep=0;UiPromptSetActiveGroupThisFrame(group,VarString(10,'LITERAL_STRING',st.name),0,0,0,0)
      if UiPromptHasStandardModeCompleted(prompt,0) then hospitalOpen('station',id) end
     end
    else deleteClerk(id) end
   end
  else for id in pairs(peds) do deleteClerk(id) end end
  Wait(sleep)
 end
end)
AddEventHandler('onClientResourceStop',function(r)
 if r==GetCurrentResourceName() then
  for id in pairs(peds) do deleteClerk(id) end
  if prompt then UiPromptDelete(prompt) end
 end
end)
