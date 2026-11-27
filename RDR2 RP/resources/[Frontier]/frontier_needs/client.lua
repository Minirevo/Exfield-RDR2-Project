local C=FrontierNeedsConfig
local value,last,seq,requested=nil,0,0,0
local animating=false
local function playing() return LocalPlayer.state.IsInSession==true end
local function truth(v) return v==true or v==1 end
local function alive(p) return p~=0 and not truth(IsEntityDead(p)) end
exports('GetState',function()
 if not playing() or not value or GetGameTimer()-last>10000 then return nil end
 return {hunger=value.hunger,thirst=value.thirst,energy=value.energy}
end)
RegisterNetEvent('frontier_needs:state',function(sequence,data)
 if source~=65535 or not playing() or sequence~=requested or type(data)~='table' then return end
 for _,k in ipairs({'hunger','thirst','energy'}) do if type(data[k])~='number' or data[k]<0 or data[k]>1000 then return end end
 value=data;last=GetGameTimer()
end)
RegisterNetEvent('vorp:SelectedCharacter',function() value=nil;requested=0 end)
CreateThread(function()
 while true do
  if playing() then
   seq=seq%2147483646+1;requested=seq
   TriggerServerEvent('frontier_needs:request',seq)
  else value=nil;requested=0 end
  Wait(2500)
 end
end)
RegisterNetEvent('frontier_needs:consequence',function(damage,energy,low)
 if source~=65535 or not playing() or not alive(PlayerPedId()) then return end
 local p=PlayerPedId()
 if type(damage)=='number' and damage>0 and damage<=C.damageAtZero*2 then
  local health=GetEntityHealth(p)
  if health>0 then SetEntityHealth(p,math.max(0,health-damage),0) end
 end
 if type(energy)=='number' and energy<=C.low then
  -- Cap the native stamina core while exhausted; do not replenish it.
  local ok,current=pcall(Citizen.InvokeNative,0x36731AC041289BB1,p,1)
  if ok and type(current)=='number' and current>25 then pcall(Citizen.InvokeNative,0xC6258F41D86676E0,p,1,25) end
 end
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
