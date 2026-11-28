local C,E=FrontierMedicalConfig,'frontier_medical:'
local state,received,ticket=nil,0,nil
local opened=false
local requestAt=0
local symptomVisible=false
local feedbackAt=-10000
local feedbackActive=false
local function truth(v) return v==true or v==1 end
local function native(name,...)
 local fn=_G[name];if type(fn)~='function' then return nil end
 local ok,a,b=pcall(fn,...);if ok then return a,b end
end
local function playing() return LocalPlayer.state.IsInSession==true end
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
 if not playing() or opened or (state and state.down) then return end
 local target=tonumber(args[1]) or GetPlayerServerId(PlayerId())
 requestAt=GetGameTimer()
 TriggerServerEvent(E..'open',target)
end,false)
RegisterNetEvent(E..'view',function(data)
 if source~=65535 or not playing() or type(data)~='table' or type(data.ticket)~='string' then return end
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
RegisterNetEvent('vorp:SelectedCharacter',function() state=nil;received=0;requestAt=0;feedbackAt=-10000;clearFeedback();FrontierMedicalAdapter.reset();if opened then close() end end)
AddEventHandler('onClientResourceStop',function(r) if r==GetCurrentResourceName() and opened then close() end end)
