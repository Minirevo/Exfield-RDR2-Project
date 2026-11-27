local E='frontier_inventory:'
local W=0xAC4BD4F1 -- INPUT_OPEN_WHEEL_MENU
local X,Y=0xA987235F,0xD2047988
local blocked={X,Y,0x07CE1E61,0xF84FA74F,0xD0842EDF,0xF78D7337,0x9CC7A1A4}
local enabled,opened,ready=false,false,false
local sequence,started=0,0
local token,slots,selected=nil,nil,0
local x,y=0,0
local waitRelease=false
local function notice(s) TriggerEvent('chat:addMessage',{args={'Frontier Wheel',s}}) end
local function allowed()
 local p=PlayerPedId()
 return ready and p~=0 and not IsEntityDead(p) and not IsPauseMenuActive()
  and not IsNuiFocused() and not IsPedOnMount(p) and not IsPedInAnyVehicle(p,false)
  and not (type(IsPedUsingAnyScenario)=='function' and IsPedUsingAnyScenario(p))
end
local function close(commit)
 if not opened then return end
 opened=false
 SendNUIMessage({type='close'})
 if commit and token then
  if selected==7 then TriggerServerEvent(E..'wheelSelect',token,0)
  elseif selected>=1 and selected<=6 and slots and slots[selected] and slots[selected].kind then
   TriggerServerEvent(E..'wheelSelect',token,selected)
  end
 end
 token,slots,selected=nil,nil,0
end
local function open()
 sequence=sequence%2147483646+1
 started=GetGameTimer()
 opened=true;token,slots,selected=nil,nil,0;x,y=0,0
 SendNUIMessage({type='open'})
 TriggerServerEvent(E..'wheelOpen',sequence)
end
RegisterNUICallback('ready',function(_,cb) ready=true;close(false);cb({ok=true}) end)
RegisterNetEvent(E..'wheelSnapshot',function(seq,t,data)
 if source~=65535 or not opened or seq~=sequence or type(t)~='string' or type(data)~='table' then return end
 token,slots=t,data
 SendNUIMessage({type='slots',slots=data})
end)
RegisterNetEvent(E..'wheelError',function(seq,msg)
 if source~=65535 or not opened or seq~=sequence then return end
 close(false);waitRelease=true;notice(msg)
end)
RegisterCommand('frontierwheeltest',function()
 enabled=not enabled;close(false);waitRelease=false
 notice(enabled and 'Test ON: hold TAB on foot, move mouse, release. /frontierwheeltest restores native wheel.'
  or 'Test OFF: native wheel restored.')
end,false)
RegisterCommand('frontierwheelcancel',function() close(false);waitRelease=true end,false)
CreateThread(function()
 while true do
  Wait(0)
  if enabled and allowed() then
   DisableControlAction(0,W,true)
   local held=IsDisabledControlPressed(0,W)
   if waitRelease then
    if not held then waitRelease=false end
   elseif not opened and IsDisabledControlJustPressed(0,W) then open() end
   if opened then
    for _,control in ipairs(blocked) do DisableControlAction(0,control,true) end
    -- No NUI focus: the game continues receiving TAB release. Suppress firing on this frame.
    if type(DisablePlayerFiring)=='function' then DisablePlayerFiring(PlayerId(),true) end
    if GetGameTimer()-started>14000 then close(false);waitRelease=true
    elseif not held then close(true)
    else
     local dx,dy=GetDisabledControlNormal(0,X),GetDisabledControlNormal(0,Y)
     x,y=FrontierWheelRules.limit(x+dx*0.65,y+dy*0.65)
     local nextSlot=FrontierWheelRules.segment(x,y,8)
     if nextSlot~=selected then
      selected=nextSlot
      SendNUIMessage({type='select',slot=selected})
     end
    end
   end
  else
   if opened then close(false);waitRelease=true end
   Wait(enabled and 0 or 100)
  end
 end
end)
AddEventHandler('onClientResourceStop',function(resource)
 if resource==GetCurrentResourceName() then close(false) end
end)
