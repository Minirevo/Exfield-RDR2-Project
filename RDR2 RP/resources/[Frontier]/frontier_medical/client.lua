local C,E=FrontierMedicalConfig,'frontier_medical:'
local state,received,ticket=nil,0,nil
local opened=false
local requestAt=0
local function truth(v) return v==true or v==1 end
local function native(name,...)
 local fn=_G[name];if type(fn)~='function' then return nil end
 local ok,a,b=pcall(fn,...);if ok then return a,b end
end
local function playing() return LocalPlayer.state.IsInSession==true end
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
 state=v;received=GetGameTimer();FrontierMedicalAdapter.update(v)
 if v.down and opened then close() end
end)
local sprint=joaat('INPUT_SPRINT')
local blocked={sprint,joaat('INPUT_MOVE_LR'),joaat('INPUT_MOVE_UD'),joaat('INPUT_ATTACK'),joaat('INPUT_AIM'),joaat('INPUT_JUMP'),joaat('INPUT_MELEE_ATTACK'),joaat('INPUT_ENTER'),joaat('INPUT_RELOAD')}
CreateThread(function()
 local ragAt=0
 while true do
  local p=PlayerPedId()
  if playing() and state and GetGameTimer()-received<15000 and p~=0 and not truth(IsEntityDead(p)) then
   if state.down then
    for _,control in ipairs(blocked) do DisableControlAction(0,control,true) end
    DisablePlayerFiring(PlayerId(),true)
    if GetGameTimer()-ragAt>2000 and not truth(native('IsPedOnMount',p)) and not truth(native('IsPedInAnyVehicle',p,false)) then
     native('SetPedToRagdoll',p,2500,2500,0,false,false,false);ragAt=GetGameTimer()
    end
    Wait(0)
   elseif state.legs or state.arms then
    if state.legs then DisableControlAction(0,sprint,true) end
    if state.arms then DisablePlayerFiring(PlayerId(),true);DisableControlAction(0,joaat('INPUT_MELEE_ATTACK'),true) end
    Wait(0)
   else Wait(100) end
  else Wait(100) end
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
 ticket=data.ticket;opened=true;SetNuiFocus(true,true);SendNUIMessage({type='view',data=data})
end)
RegisterNetEvent(E..'closeView',function(t)
 if source==65535 and ticket==t and opened then close() end
end)
RegisterNUICallback('close',function(_,cb) close();cb({ok=true}) end)
RegisterNUICallback('action',function(d,cb)
 if opened and ticket and type(d)=='table' then TriggerServerEvent(E..'action',ticket,d.action,d.region,d.item) end
 cb({ok=true})
end)
RegisterNetEvent('vorp:SelectedCharacter',function() state=nil;received=0;requestAt=0;FrontierMedicalAdapter.reset();if opened then close() end end)
AddEventHandler('onClientResourceStop',function(r) if r==GetCurrentResourceName() and opened then close() end end)
