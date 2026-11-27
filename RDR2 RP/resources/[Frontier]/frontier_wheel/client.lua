local E='frontier_inventory:'
local W,H=0xAC4BD4F1,0xB238FE0B -- hold wheel, tap holster
local X,Y=0xA987235F,0xD2047988
local blocked={X,Y,0x07CE1E61,0xF84FA74F,0xD0842EDF,0xF78D7337,0x9CC7A1A4}
local enabled,opened,ready=false,false,false
local sequence,started=0,0
local token,slots,selected=nil,nil,0
local x,y=0,0
local waitRelease,rawHeld,manual=false,false,false
local rawAvailable=false
local presses,releases=0,0
local function trace(s) print('[frontier_wheel] '..s) end
local function notice(s) TriggerEvent('chat:addMessage',{args={'Frontier Wheel',s}});trace(s) end
local function callBool(name,...)
 local fn=_G[name]
 if type(fn)~='function' then return false end
 local ok,result=pcall(fn,...)
 return ok and (result==true or result==1)
end
local function blocker()
 if not ready then return 'NUI not ready' end
 local p=PlayerPedId()
 if p==0 or callBool('IsEntityDead',p) then return 'dead/no ped' end
 if callBool('IsPauseMenuActive') then return 'pause menu' end
 if callBool('IsNuiFocused') then return 'other NUI focused' end
 if callBool('IsPedOnMount',p) then return 'mounted' end
 if callBool('IsPedInAnyVehicle',p,false) then return 'vehicle' end
 if callBool('IsPedUsingAnyScenario',p) then return 'scenario' end
end
local function close(commit)
 if not opened then return end
 opened=false;manual=false
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
 if opened then return end
 sequence=sequence%2147483646+1
 started=GetGameTimer()
 opened=true;token,slots,selected=nil,nil,0;x,y=0,0
 SendNUIMessage({type='open'})
 TriggerServerEvent(E..'wheelOpen',sequence)
 trace('opened sequence '..sequence)
end
RegisterNUICallback('ready',function(_,cb)
 ready=true;close(false);trace('NUI ready');cb({ok=true})
end)
RegisterNetEvent(E..'wheelSnapshot',function(seq,t,data)
 if source~=65535 or not opened or seq~=sequence or type(t)~='string' or type(data)~='table' then return end
 token,slots=t,data
 SendNUIMessage({type='slots',slots=data})
 trace('toolbelt snapshot received')
end)
RegisterNetEvent(E..'wheelError',function(seq,msg)
 if source~=65535 or not opened or seq~=sequence then return end
 close(false);waitRelease=true;notice(msg)
end)
local function down()
 if rawHeld then return end
 rawHeld=true;presses=presses+1
 if enabled then
  local why=blocker()
  trace('TAB down; '..(why or 'eligible'))
  if not why and not waitRelease then open() end
 end
end
local function up()
 rawHeld=false;releases=releases+1
 if enabled then trace('TAB up') end
 if opened and not manual then close(not blocker()) end
 waitRelease=false
end
if type(RegisterRawKeymap)=='function' then
 rawAvailable=pcall(RegisterRawKeymap,'frontier_wheel_tab',down,up,0x09,true)
end
trace('raw TAB registered: '..tostring(rawAvailable))
RegisterCommand('frontierwheeltest',function()
 enabled=not enabled;close(false);waitRelease=false;rawHeld=false
 notice(enabled and ('Test ON: hold TAB. NUI ready='..tostring(ready)..', raw TAB='..tostring(rawAvailable))
  or 'Test OFF: native wheel restored.')
end,false)
RegisterCommand('frontierwheelcancel',function() close(false);waitRelease=true end,false)
RegisterCommand('frontierwheeldebug',function()
 notice(('enabled=%s ready=%s raw=%s pressed=%d released=%d open=%s blocked=%s'):format(
  tostring(enabled),tostring(ready),tostring(rawAvailable),presses,releases,tostring(opened),blocker() or 'none'))
end,false)
-- Bypass TAB to diagnose the NUI and snapshot separately. Enter twice to select/close.
RegisterCommand('frontierwheelopen',function()
 SetTimeout(200,function()
  if opened then close(true);return end
  local why=blocker()
  if why then notice('Cannot open: '..why);return end
  enabled=true;manual=true;open()
 end)
end,false)
local function pressed(control)
 return IsControlPressed(0,control) or IsDisabledControlPressed(0,control)
end
CreateThread(function()
 while true do
  Wait(0)
  if enabled and not blocker() then
   -- Read both native states before suppression; raw key callbacks are the primary input.
   local held=pressed(W) or pressed(H) or rawHeld
   DisableControlAction(0,W,true)
   DisableControlAction(0,H,true)
   DisableControlAction(0,0x938D4071,true)
   held=held or pressed(W) or pressed(H)
   if waitRelease then
    if not held then waitRelease=false end
   elseif not opened and held then open() end
   if opened then
    for _,control in ipairs(blocked) do DisableControlAction(0,control,true) end
    if type(DisablePlayerFiring)=='function' then DisablePlayerFiring(PlayerId(),true) end
    if GetGameTimer()-started>14000 then close(false);waitRelease=true
    elseif not manual and not held then close(true)
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
