local C,E=FrontierMedicalConfig,'frontier_medical:'
local state,received,ticket=nil,0,nil
local opened=false
local requestAt=0
local ignore,ignoreUntil=0,0
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
 state=v;received=GetGameTimer()
 if v.down and opened then close() end
end)
RegisterNetEvent(E..'fatal',function()
 if source~=65535 or not playing() then return end
 local p=PlayerPedId()
 if p~=0 and not truth(IsEntityDead(p)) then SetEntityHealth(p,0,0) end
end)
AddEventHandler('frontier_medical:ignoreDamage',function(amount)
 if type(amount)=='number' and amount>0 then ignore=amount;ignoreUntil=GetGameTimer()+1000 end
end)
local function region(p)
 local ok,bone=native('GetPedLastDamageBone',p)
 if truth(ok) and type(bone)=='number' then return C.bones[bone] or 'chest' end
 return 'chest'
end
local known={}
for _,name in ipairs({'WEAPON_REVOLVER_CATTLEMAN','WEAPON_REPEATER_WINCHESTER','WEAPON_REVOLVER_DOUBLEACTION','WEAPON_REVOLVER_SCHOFIELD','WEAPON_PISTOL_VOLCANIC','WEAPON_RIFLE_BOLTACTION','WEAPON_RIFLE_SPRINGFIELD','WEAPON_REPEATER_CARBINE','WEAPON_REPEATER_HENRY','WEAPON_SHOTGUN_DOUBLEBARREL','WEAPON_BOW'}) do known[joaat(name)]=true end
local function kind(p,fall)
 -- A cause-of-death hash can be stale on live peds. Prefer a recent weapon damage flag when exposed.
 for hash in pairs(known) do
  if truth(native('HasEntityBeenDamagedByWeapon',p,hash,0)) then return 'penetrating' end
 end
 if truth(native('HasEntityBeenDamagedByWeapon',p,joaat('WEAPON_MELEE_KNIFE'),0)) then return 'cut' end
 local hash=native('GetPedCauseOfDeath',p)
 if known[hash] then return 'penetrating' end
 if hash==joaat('WEAPON_MELEE_KNIFE') then return 'cut' end
 return fall and 'fall' or 'blunt'
end
CreateThread(function()
 local lastPed,lastHealth,fallAt=0,nil,-10000
 while true do
  Wait(400)
  local p=PlayerPedId()
  if not playing() or p==0 or truth(IsEntityDead(p)) then lastPed=0;lastHealth=nil;ignore=0
  else
   if truth(native('IsPedFalling',p)) or truth(native('IsPedRagdoll',p)) then fallAt=GetGameTimer() end
   local h=GetEntityHealth(p);local max=GetEntityMaxHealth(p)
   if lastPed==p and lastHealth and h<lastHealth and max>0 then
    local lost=lastHealth-h
    if ignoreUntil>=GetGameTimer() then local amount=math.min(ignore,lost);lost=lost-amount;ignore=ignore-amount else ignore=0 end
    if lost>0 then
     local dmg=math.max(1,math.min(C.maxDamageReport,math.floor(lost/max*100+.5)))
     TriggerServerEvent(E..'hit',region(p),kind(p,GetGameTimer()-fallAt<1500),dmg)
     native('ClearEntityLastWeaponDamage',p)
     native('ClearPedLastDamageBone',p)
    end
   end
   lastPed=p;lastHealth=h
  end
 end
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
RegisterNetEvent('vorp:SelectedCharacter',function() state=nil;received=0;requestAt=0;if opened then close() end end)
AddEventHandler('onClientResourceStop',function(r) if r==GetCurrentResourceName() and opened then close() end end)
