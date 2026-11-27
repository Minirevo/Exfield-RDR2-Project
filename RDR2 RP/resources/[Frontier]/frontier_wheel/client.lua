local E='frontier_inventory:'
local arms=FrontierWeapons
local inventoryGuns=nil
local page='main'
local toolSlots=nil
local consumables=nil
local layout=FrontierWheelLayout
local entries={}
local hoveredAt=0
local documents=false
local docsPending=false
local docSequence=0
local W,H=0xAC4BD4F1,0xB238FE0B -- hold wheel, tap holster
local X,Y=0xA987235F,0xD2047988
local blocked={X,Y,0x07CE1E61,0xF84FA74F,0xD0842EDF,0xF78D7337,0x9CC7A1A4}
local enabled,opened,ready=GetConvarInt('frontier_wheel_default',1)==1,false,false
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
 if GetResourceState('vorp_inventory')=='started' or GetResourceState('vorp_inventory')=='starting' then return 'Legacy inventory still running' end
 if not LocalPlayer.state.IsInSession then return 'character not loaded' end
 if arms.busy() then return 'weapon transition' end
 if documents or docsPending then return 'documents open' end
 local p=PlayerPedId()
 if p==0 or callBool('IsEntityDead',p) then return 'dead/no ped' end
 if callBool('IsPauseMenuActive') then return 'pause menu' end
 if callBool('IsNuiFocused') then return 'other NUI focused' end
 if callBool('IsPedOnMount',p) then return 'mounted' end
 if callBool('IsPedInAnyVehicle',p,false) then return 'vehicle' end
 if callBool('IsPedUsingAnyScenario',p) then return 'scenario' end
end
local function notifyUnavailable() notice('This feature is not available yet.') end
local function requestDocuments(mode)
 if docsPending or documents then return end
 docSequence=docSequence%2147483646+1
 local seq=docSequence
 docsPending=true
 TriggerServerEvent('frontier_wheel:documentsOpen',seq,mode)
 SetTimeout(5000,function()
  if docsPending and docSequence==seq then docsPending=false;notice('Documents did not respond.') end
 end)
end
local function close(commit)
 if not opened then return end
 local item=entries[selected]
 opened=false;manual=false;arms.wheelOpen=false
 SendNUIMessage({type='close'})
 if commit and item then
  if item.kind=='weapon' then
   if token then arms.select(token,item.target) end
  elseif item.kind=='holster' then
   arms.holster();TriggerServerEvent(E..'holsterTool')
   if not arms.active() then SetCurrentPedWeapon(PlayerPedId(),joaat('WEAPON_UNARMED'),false,0,false,false) end
  elseif item.kind=='consume' and token then
   TriggerServerEvent(E..'wheelConsume',token,item.target)
  elseif item.kind=='tool' and token then
   local t,slot=token,item.target
   arms.holster(function(ok) if ok then TriggerServerEvent(E..'wheelSelect',t,slot) end end)
  elseif item.kind=='toolHolster' and token then TriggerServerEvent(E..'wheelSelect',token,0)
  elseif item.kind=='menu' then
   if GetResourceState(item.resource)=='started' then
    local command=item.target
    SetTimeout(100,function() if not blocker() then ExecuteCommand(command) end end)
   else notifyUnavailable() end
  elseif item.kind=='documents' or item.kind=='profile' then requestDocuments(item.kind)
  elseif item.kind=='disabled' then notifyUnavailable() end
 end
 token,slots,selected=nil,nil,0;toolSlots=nil;consumables=nil;inventoryGuns=nil;entries={}
end
local function renderPage()
 if page=='main' then
  local guns=arms.decorate(inventoryGuns)
  entries=layout.main(guns)
 elseif page=='character' then
  entries=layout.character()
  for _,item in ipairs(entries) do if item.resource and GetResourceState(item.resource)~='started' then item.kind='disabled' end end
 elseif page=='food' or page=='drink' then entries=layout.consumables(consumables and consumables[page])
 else entries=layout.tools(toolSlots) end
 SendNUIMessage({type='page',page=page,slots=entries,loading=page=='tools' and not toolSlots,selected=selected})
end
local function switchPage(target)
 if not opened or not ({main=true,tools=true,character=true,food=true,drink=true})[target] then return end
 page=target;selected=0;x,y=0,0;hoveredAt=GetGameTimer()
 renderPage()
 trace('page '..page)
end
local function open()
 if opened then return end
 sequence=sequence%2147483646+1
 started=GetGameTimer()
 opened=true;arms.wheelOpen=true;arms.cancelReload();token,slots,selected=nil,nil,0;toolSlots=nil;consumables=nil;inventoryGuns=nil;x,y=0,0
 page='main';hoveredAt=started
 SendNUIMessage({type='open'});renderPage()
 TriggerServerEvent(E..'wheelOpen',sequence)
 trace('opened sequence '..sequence)
end
RegisterNUICallback('ready',function(_,cb)
 ready=true;close(false);trace('NUI ready');cb({ok=true})
end)
RegisterNetEvent(E..'wheelSnapshot',function(seq,t,data,food,guns)
 if source~=65535 or not opened or seq~=sequence or type(t)~='string' or type(data)~='table' then return end
 token,toolSlots=t,data;consumables=food;inventoryGuns=guns
 if page=='main' or page=='tools' or page=='food' or page=='drink' then renderPage() end
 trace('toolbelt snapshot received')
end)
RegisterNetEvent(E..'wheelError',function(seq,msg)
 if source~=65535 or not opened or seq~=sequence then return end
 if page=='tools' then notice(msg) else trace('toolbelt unavailable: '..tostring(msg)) end
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
 if not enabled then
  arms.holster()
 end
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
     local nextSlot=FrontierWheelRules.segment(x,y,#entries)
     if nextSlot~=selected then
      selected=nextSlot;hoveredAt=GetGameTimer()
      SendNUIMessage({type='select',slot=selected})
     end
     local item=entries[selected]
     if item and item.kind=='page' and GetGameTimer()-hoveredAt>=350 then switchPage(item.target) end
    end
   end
  else
   if opened then close(false);waitRelease=true end
   Wait(enabled and 0 or 100)
  end
 end
end)
AddEventHandler('onClientResourceStop',function(resource)
 if resource==GetCurrentResourceName() then close(false);if documents then SetNuiFocus(false,false) end end
end)

local function closeDocuments()
 if documents then SetNuiFocus(false,false) end
 documents=false;docsPending=false
 SendNUIMessage({type='docsClose'})
 TriggerServerEvent('frontier_wheel:documentsClose')
end
RegisterNetEvent('frontier_wheel:documentsView',function(seq,data)
 if source~=65535 or not docsPending or seq~=docSequence then return end
 docsPending=false
 if not data or type(data)~='table' then notice('Documents unavailable.');return end
 if blocker() then TriggerServerEvent('frontier_wheel:documentsClose');return end
 documents=true;SetNuiFocus(true,true);SetNuiFocusKeepInput(false)
 SendNUIMessage({type='docs',data=data})
end)
RegisterNetEvent('frontier_wheel:documentsNotice',function(msg)
 if source==65535 then notice(msg);SendNUIMessage({type='docsNotice',message=msg}) end
end)
RegisterNUICallback('docsClose',function(_,cb) closeDocuments();cb({ok=true}) end)
RegisterNUICallback('docsPresent',function(d,cb)
 if documents and type(d)=='table' then TriggerServerEvent('frontier_wheel:documentsPresent',d.index,d.target) end
 cb({ok=true})
end)
CreateThread(function()
 while true do
  Wait(250)
  if documents and (not LocalPlayer.state.IsInSession or callBool('IsEntityDead',PlayerPedId()) or IsPauseMenuActive()) then closeDocuments() end
 end
end)
