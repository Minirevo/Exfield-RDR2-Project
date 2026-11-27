-- Native health is a renewable sensor, never a gameplay health pool.
-- Guarded mode was validated in the dev lab on melee, firearm, knife, wolf, fall and drowning.
FrontierMedicalAdapter={}
local A,C,E=FrontierMedicalAdapter,FrontierMedicalConfig,'frontier_medical:'
local state,received,guard,failedPed=nil,0,nil,nil
local pending,queued,queuedRaw,water,seq=nil,{},0,false,0
local nextSend,fallAt,fatalAt=0,-10000,-10000
local function log(s) print('[frontier_medical] '..s) end
local function truth(v) return v==true or v==1 end
local function call(name,...)
 local fn=_G[name];if type(fn)~='function' then return false,'unavailable' end
 return pcall(fn,...)
end
local function get(name,...)
 local ok,a,b=call(name,...);if ok then return a,b end;return nil,nil
end
local function playing() return LocalPlayer.state.IsInSession==true end
local function alive(p) return p~=0 and not truth(get('IsEntityDead',p)) and not truth(get('IsPlayerDead',PlayerId())) end
local function health(p) return get('GetEntityHealth',p) end
local function maximum(p) return get('GetEntityMaxHealth',p,false) end
local function valid(n) return type(n)=='number' and n%1==0 and n>=1 and n<=1000000 end
local function setMax(p,n)
 local ok=call('SetEntityMaxHealth',p,n)
 if not ok then ok=pcall(Citizen.InvokeNative,0x166E7CF68597D8B5,p,n) end
 return ok,maximum(p)
end
local function setHealth(p,n)
 local ok=call('SetEntityHealth',p,n,0)
 if not ok then ok=pcall(Citizen.InvokeNative,0xAC2767ED8BDFAB15,p,n,0) end
 return ok
end
local function restore()
 local g=guard;guard=nil
 if not g or not DoesEntityExist(g.ped) then return true end
 local p=g.ped;local success=true
 for flag,prior in pairs(g.flags) do
  local ok=call('SetPedConfigFlag',p,flag,prior)
  local v=get('GetPedConfigFlag',p,flag,true)
  if not ok or v==nil or truth(v)~=prior then success=false end
 end
 if g.changedMax and maximum(p)~=g.original then
  local request=g.original
  if valid(g.request) and valid(g.readback) then request=math.max(1,g.request+g.original-g.readback) end
  for _=1,3 do
   local ok,actual=setMax(p,request)
   if actual==g.original then break end
   if not ok or not valid(actual) then break end
   local nextRequest=request+g.original-actual
   if not valid(nextRequest) or nextRequest==request then break end
   request=nextRequest
  end
  if maximum(p)~=g.original then success=false end
 end
 -- Do not resurrect or restore a historical HP value; clamp only an alive
 -- ped's current native buffer after restoring its cap.
 if alive(p) then
  local h,m=health(p),maximum(p)
  if valid(h) and valid(m) and h>m then setHealth(p,m) end
 end
 if not success then failedPed=p;log('WARNING: guarded settings restoration not verified; reconnect') end
 return success
end
local function setup(p)
 local m,h=maximum(p),health(p)
 if not valid(m) or not valid(h) then return false,'native health unavailable' end
 local g={ped=p,original=m,flags={},request=math.max(m,C.nativeBuffer)}
 guard=g
 for _,flag in ipairs(C.nativeFlags) do
  local prior=get('GetPedConfigFlag',p,flag,true)
  if prior==nil then return false,'cannot read flag '..flag end
  g.flags[flag]=truth(prior)
  if not call('SetPedConfigFlag',p,flag,true) or not truth(get('GetPedConfigFlag',p,flag,true)) then return false,'cannot set flag '..flag end
 end
 if m<g.request then
  g.changedMax=true
  local ok,actual=setMax(p,g.request);g.readback=actual
  if not ok or not valid(actual) or actual<g.request or actual>g.request*2 then return false,'native buffer rejected: '..tostring(actual) end
 else g.readback=m end
 g.target=g.readback
 if not setHealth(p,g.target) or health(p)~=g.target then return false,'initial refill failed' end
 g.last=g.target;g.checkAt=GetGameTimer()+1000
 log(('Guarded adapter active: original=%d effective=%d'):format(m,g.target))
 return true
end
local function resetQueue()
 pending=nil;queued={};queuedRaw=0;water=false;seq=0;nextSend=0
end
function A.reset()
 restore();state=nil;received=0;resetQueue()
end
function A.update(v)
 if type(v.token)~='string' or type(v.seq)~='number' or type(v.life)~='number' then return end
 if not state or state.token~=v.token then
  restore();resetQueue();seq=v.seq
 elseif pending and v.seq>=pending.seq then pending=nil;seq=math.max(seq,v.seq)
 else seq=math.max(seq,v.seq) end
 state=v;received=GetGameTimer()
end
RegisterNetEvent(E..'damageAck',function(token,n)
 if source~=65535 or not state or state.token~=token or not pending or pending.seq~=n then return end
 pending=nil
end)
local firearm={}
for _,name in ipairs({
 'WEAPON_REVOLVER_CATTLEMAN','WEAPON_REVOLVER_DOUBLEACTION','WEAPON_REVOLVER_SCHOFIELD','WEAPON_REVOLVER_LEMAT','WEAPON_REVOLVER_NAVY',
 'WEAPON_PISTOL_VOLCANIC','WEAPON_PISTOL_MAUSER','WEAPON_PISTOL_SEMIAUTO','WEAPON_PISTOL_M1899',
 'WEAPON_RIFLE_BOLTACTION','WEAPON_RIFLE_SPRINGFIELD','WEAPON_RIFLE_VARMINT','WEAPON_SNIPERRIFLE_ROLLINGBLOCK','WEAPON_SNIPERRIFLE_CARCANO',
 'WEAPON_REPEATER_WINCHESTER','WEAPON_REPEATER_CARBINE','WEAPON_REPEATER_HENRY','WEAPON_REPEATER_EVANS',
 'WEAPON_SHOTGUN_DOUBLEBARREL','WEAPON_SHOTGUN_PUMP','WEAPON_SHOTGUN_REPEATING','WEAPON_SHOTGUN_SEMIAUTO','WEAPON_SHOTGUN_SAWEDOFF','WEAPON_BOW'
}) do firearm[joaat(name)]=true end
local blades={}
for _,name in ipairs({'WEAPON_MELEE_KNIFE','WEAPON_MELEE_KNIFE_JAWBONE','WEAPON_MELEE_KNIFE_MINER','WEAPON_MELEE_KNIFE_CIVIL_WAR','WEAPON_MELEE_HATCHET','WEAPON_THROWN_THROWING_KNIVES','WEAPON_THROWN_TOMAHAWK','WEAPON_MELEE_MACHETE'}) do blades[joaat(name)]=true end
local drownHashes={[joaat('WEAPON_DROWNING')]=true,[joaat('WEAPON_DROWNING_IN_VEHICLE')]=true}
local function region(p)
 local ok,bone=get('GetPedLastDamageBone',p)
 if truth(ok) and type(bone)=='number' then return C.bones[bone] or 'chest' end
 if type(ok)=='number' and ok>1 and bone==nil then return C.bones[ok] or 'chest' end
 return 'chest'
end
local function damageKind(p,raw)
 local inWater=truth(get('IsEntityInWater',p)) or truth(get('IsPedSwimming',p)) or truth(get('IsPedSwimmingUnderWater',p))
 local cause=get('GetPedCauseOfDeath',p)
 -- The lab observed very large repeated losses while drowning, without
 -- network events. Do not interpret thousands of those frames as wounds.
 if inWater and (raw>=C.drowningRawThreshold or drownHashes[cause]) then return 'drowning' end
 if truth(get('IsEntityOnFire',p)) then return 'burn' end
 for hash in pairs(firearm) do if truth(get('HasEntityBeenDamagedByWeapon',p,hash,0)) then return 'penetrating' end end
 for hash in pairs(blades) do if truth(get('HasEntityBeenDamagedByWeapon',p,hash,0)) then return 'cut' end end
 local src=get('GetPedSourceOfDamage',p)
 if type(src)=='number' and src~=0 and src~=p and DoesEntityExist(src) and truth(get('IsEntityAPed',src)) then
  local human=get('IsPedHuman',src)
  if human==false or human==0 then return 'bite' end
 end
 if firearm[cause] then return 'penetrating' end
 if blades[cause] then return 'cut' end
 return GetGameTimer()-fallAt<1500 and 'fall' or 'blunt'
end
local function queueLoss(p,raw)
 local kind=damageKind(p,raw)
 if kind=='drowning' then water=true
 else
  local r=region(p)
  local key=r..':'..kind
  local hit=queued[key] or {region=r,kind=kind,raw=0}
  local n=math.max(0,math.min(math.floor(raw),C.maxRawGroup-hit.raw,C.maxRawBatch-queuedRaw))
  if n>0 then hit.raw=hit.raw+n;queued[key]=hit;queuedRaw=queuedRaw+n end
 end
 get('ClearEntityLastWeaponDamage',p);get('ClearPedLastDamageBone',p)
end
local function send(now)
 if pending then
  if now-pending.sent>=C.reportRetryMs then
   pending.sent=now
   TriggerServerEvent(E..'damageBatch',state.token,pending.seq,pending.hits,pending.drowning)
  end
  return
 end
 if now<nextSend or (queuedRaw==0 and not water) then return end
 local hits={}
 for _,hit in pairs(queued) do hits[#hits+1]=hit end
 seq=seq+1;pending={seq=seq,hits=hits,drowning=water,sent=now}
 queued={};queuedRaw=0;water=false;nextSend=now+C.reportInterval
 TriggerServerEvent(E..'damageBatch',state.token,pending.seq,pending.hits,pending.drowning)
end
local function fail(p,reason)
 log('Guarded adapter unavailable: '..tostring(reason)..'; native death fallback remains active')
 restore();failedPed=p
end
CreateThread(function()
 while true do
  if not playing() or not state or GetGameTimer()-received>C.stateTimeoutMs then
   if guard then restore() end
   if not playing() then state=nil;resetQueue() end
   Wait(100)
  else
   local p=PlayerPedId();local now=GetGameTimer()
   if guard and guard.ped~=p then restore() end
   if failedPed and failedPed~=p then failedPed=nil end
   if state.dead then
    if guard then restore() end
    -- Only a server-persisted medical death authorises native fatal damage.
    -- When provider already observed death, wait for its respawn confirmation.
    if state.fatal and alive(p) and now-fatalAt>=500 then
     fatalAt=now;setHealth(p,0)
    end
    Wait(50)
   elseif not alive(p) then
    if guard then restore() end
    Wait(100)
   elseif failedPed==p then
    -- Fail open to the native engine rather than silently granting immunity.
    Wait(250)
   else
    local ok,err=pcall(function()
     if not guard then
      local started,why=setup(p)
      if not started then fail(p,why);return end
     end
     local g=guard
     if truth(get('IsPedFalling',p)) then fallAt=now end
     local h=health(p)
     if not valid(h) then fail(p,'health read failed');return end
     if now>=g.checkAt then
      g.checkAt=now+1000
      local m=maximum(p)
      if m~=g.target then fail(p,'native maximum changed unexpectedly');return end
     end
     if h<g.last then queueLoss(p,g.last-h) end
     if h<g.target then
      if not setHealth(p,g.target) or health(p)~=g.target then fail(p,'refill not verified');return end
      h=g.target
     end
     g.last=h
     send(now)
    end)
    if not ok then fail(p,err) end
    Wait(0)
   end
  end
 end
end)
RegisterCommand('frontiermedicalstatus',function()
 local g=guard
 local msg=('adapter=%s native=%s/%s state=%s queuedRaw=%d pending=%s'):format(
  g and 'guarded' or 'inactive',tostring(health(PlayerPedId())),tostring(maximum(PlayerPedId())),
  state and (state.dead and 'dead' or state.down and 'unconscious' or 'conscious') or 'loading',queuedRaw,tostring(pending~=nil))
 log(msg);TriggerEvent('chat:addMessage',{args={'Medical',msg}})
end,false)
AddEventHandler('onClientResourceStop',function(r) if r==GetCurrentResourceName() then restore() end end)
