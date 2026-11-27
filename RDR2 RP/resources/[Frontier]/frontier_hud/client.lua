local ready,enabled=false,true
local balances=nil
local seq,requested=0,0
local showVorp=true
local function truth(v) return v==true or v==1 end
local function playing() return LocalPlayer.state.IsInSession==true end
local function active() return ready and enabled and playing() end
exports('IsReplacingHud',active)
local function native(name,...)
 local fn=_G[name]
 if type(fn)~='function' then return nil end
 local ok,v=pcall(fn,...)
 if ok and type(v)=='number' then return v end
end
local function pct(v,max)
 if type(v)~='number' or v~=v or not max or max<=0 then return nil end
 return math.max(0,math.min(100,math.floor(v/max*100+.5)))
end
local function core(p,index)
 local ok,v=pcall(Citizen.InvokeNative,0x36731AC041289BB1,p,index)
 return ok and pct(v,100) or nil
end
local function needs()
 if GetResourceState('frontier_needs')~='started' then return {} end
 local ok,data=pcall(function() return exports.frontier_needs:GetState() end)
 return ok and type(data)=='table' and data or {}
end
RegisterNUICallback('ready',function(_,cb) ready=true;cb({ok=true}) end)
RegisterNetEvent('frontier_hud:balance',function(sequence,value)
 if source==65535 and sequence==requested and playing() and type(value)=='table' then balances=value end
end)
RegisterNetEvent('vorp:SelectedCharacter',function() balances=nil;requested=0 end)
RegisterCommand('frontierhud',function()
 enabled=not enabled
 if not enabled then SendNUIMessage({type='hide'}) end
end,false)
AddEventHandler('vorp:showUi',function(v) showVorp=v~=false end)
CreateThread(function()
 local nextBalance=0
 while true do
  Wait(250)
  if not playing() then balances=nil;requested=0;nextBalance=0 end
  if active() then
   local now=GetGameTimer()
   if now>=nextBalance then seq=seq%2147483646+1;requested=seq;TriggerServerEvent('frontier_hud:balance',seq);nextBalance=now+5000 end
   local p=PlayerPedId()
   if p~=0 and not truth(IsPauseMenuActive()) and not truth(IsHudHidden()) and not truth(IsRadarHidden()) and not truth(NetworkIsInSpectatorMode()) and showVorp then
    local n=needs()
    SendNUIMessage({type='status',cash=balances and balances.cash,bank=balances and balances.bank,
     medical=GetResourceState('frontier_medical')=='started',health=GetResourceState('frontier_medical')~='started' and pct(native('GetEntityHealth',p),native('GetEntityMaxHealth',p)) or nil,
     endurance=pct(n.stamina,1000),deadeye=core(p,2),hunger=pct(n.hunger,1000),thirst=pct(n.thirst,1000),energy=pct(n.energy,1000),
     dead=truth(IsEntityDead(p))})
   else SendNUIMessage({type='hide'}) end
  else SendNUIMessage({type='hide'}) end
 end
end)
AddEventHandler('onClientResourceStop',function(r)
 if r==GetCurrentResourceName() then TriggerEvent('vorp:showUi',true) end
end)
