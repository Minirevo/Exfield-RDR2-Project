local C=FrontierNeedsConfig
local value,last,seq,requested=nil,0,0,0
local sprintControl=joaat('INPUT_SPRINT')
local animating=false
local function playing() return LocalPlayer.state.IsInSession==true end
local function truth(v) return v==true or v==1 end
local function alive(p) return p~=0 and not truth(IsEntityDead(p)) end
exports('GetState',function()
 if not playing() or not value or GetGameTimer()-last>10000 then return nil end
 return {hunger=value.hunger,thirst=value.thirst,energy=value.energy,stamina=value.stamina,capacity=value.capacity,locked=value.locked}
end)
RegisterNetEvent('frontier_needs:state',function(sequence,data)
 if source~=65535 or not playing() or sequence~=requested or type(data)~='table' then return end
 for _,k in ipairs({'hunger','thirst','energy','stamina','capacity'}) do if type(data[k])~='number' or data[k]<0 or data[k]>1000 then return end end
 if type(data.locked)~='boolean' then return end
 value=data;last=GetGameTimer()
end)
RegisterNetEvent('vorp:SelectedCharacter',function() value=nil;requested=0 end)
local function native(name,...)
 local fn=_G[name];if type(fn)~='function' then return nil end
 local ok,v=pcall(fn,...);if ok then return v end
end
local function mounted(p)
 return truth(native('IsPedOnMount',p)) or truth(native('IsPedInAnyVehicle',p,false))
end
local function activity()
 local p=PlayerPedId()
 if not alive(p) then return 'unknown' end
 if mounted(p) then return 'mounted' end
 if truth(native('IsPedSwimming',p)) or truth(native('IsPedSwimmingUnderWater',p)) then return 'swim' end
 local speed=tonumber(native('GetEntitySpeed',p)) or 0
 if speed<C.walkSpeed then return 'idle' end
 if truth(native('IsPedSprinting',p)) or speed>=C.sprintSpeed then return 'sprint' end
 if truth(native('IsPedRunning',p)) or speed>=C.jogSpeed then return 'jog' end
 if speed>=C.walkSpeed then return 'walk' end
 return 'idle'
end
CreateThread(function()
 while true do
  if playing() then
   seq=seq%2147483646+1;requested=seq
   TriggerServerEvent('frontier_needs:request',seq,activity())
  else value=nil;requested=0 end
  Wait(1000)
 end
end)
CreateThread(function()
 while true do
  local p=PlayerPedId()
  if playing() and value and GetGameTimer()-last<=10000 and value.locked and alive(p) and not mounted(p) then
   DisableControlAction(0,sprintControl,true)
   Wait(0)
  else Wait(100) end
 end
end)
RegisterNetEvent('frontier_needs:consequence',function(percent)
 if source~=65535 or not playing() or not alive(PlayerPedId()) then return end
 if type(percent)~='number' or percent<=0 or percent>C.starvePct+C.dehydratePct then return end
 local p=PlayerPedId()
 local health,maximum=GetEntityHealth(p),GetEntityMaxHealth(p)
 if type(health)=='number' and type(maximum)=='number' and health>0 and maximum>0 then
  local damage=math.max(1,math.ceil(maximum*percent/100))
  TriggerEvent('frontier_medical:ignoreDamage',damage)
  SetEntityHealth(p,math.max(0,health-damage),0)
 end
end)
RegisterNetEvent('frontier_needs:diagnostic',function(msg)
 if source~=65535 or type(msg)~='string' then return end
 print('[frontier_needs] '..msg)
 TriggerEvent('chat:addMessage',{args={'Frontier Needs',msg}})
end)
RegisterNetEvent('frontier_needs:consumed',function(item)
 if source~=65535 or not playing() or animating or not C.effects[item] then return end
 local p=PlayerPedId()
 if not alive(p) or truth(IsPedOnMount(p)) or truth(IsPedInAnyVehicle(p,false)) then return end
 if GetPedCurrentHeldWeapon(p)~=joaat('WEAPON_UNARMED') then return end
 -- Best-effort cosmetic animation AFTER the durable effect. Never consume twice
 -- or refund on animation interruption. No network props or unbounded loads.
 local drink=C.effects[item].kind=='drink'
 local dict=drink and 'amb_rest_drunk@world_human_drinking@male_a@idle_a' or 'mech_inventory@clothing@bandana'
 local anim=drink and 'idle_a' or 'NECK_2_FACE_RH'
 if drink and not truth(IsPedMale(p)) then dict='amb_rest_drunk@world_human_drinking@female_a@idle_b';anim='idle_b' end
 animating=true
 CreateThread(function()
  RequestAnimDict(dict)
  local start=GetGameTimer()
  while not HasAnimDictLoaded(dict) and GetGameTimer()-start<1500 do Wait(50) end
  if HasAnimDictLoaded(dict) and PlayerPedId()==p and alive(p) and GetPedCurrentHeldWeapon(p)==joaat('WEAPON_UNARMED') then
   TaskPlayAnim(p,dict,anim,1.0,8.0,2500,31,0.0,false,false,false)
   Wait(2500)
  end
  RemoveAnimDict(dict);animating=false
 end)
end)
