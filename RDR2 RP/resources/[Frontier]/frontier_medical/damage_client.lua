-- Native health is a renewable sensor, never a gameplay health pool.
-- Guarded mode was validated in the dev lab on melee, firearm, knife, wolf, fall and drowning.
FrontierMedicalAdapter={}
local A,C,E=FrontierMedicalAdapter,FrontierMedicalConfig,'frontier_medical:'
local D=FrontierMedicalDamageRules
local state,received,guard,failedPed=nil,0,nil,nil
local retryAt,lastError,fallbackLast=0,'none',nil
local pending,queued,queuedRaw,water,seq=nil,{},0,false,0
local nextSend,fallAt,fatalAt=0,-10000,-10000
local totalRaw,acknowledged,drowningReports,lastKind=0,0,0,'none'
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
local valid=D.valid
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
 local g=guard;guard=nil;fallbackLast=nil
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
  if valid(h) and valid(m) then
   local limit=g.active and m or math.min(m,g.originalHealth)
   if h>limit then setHealth(p,limit) end
  end
 end
 if not success then failedPed=p;lastError='guard cleanup failed; reconnect';log('WARNING: '..lastError) end
 return success
end
local function setup(p)
 local m,h=maximum(p),health(p)
 if not valid(m) or not valid(h) then return false,'native health unavailable' end
 local g={ped=p,original=m,originalHealth=h,flags={},request=math.max(m,C.nativeBuffer)}
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
  if not ok or not D.acceptCap(g.request,actual) then return false,('native buffer rejected: requested=%s actual=%s setter=%s'):format(tostring(g.request),tostring(actual),tostring(ok)) end
 else g.readback=m end
 g.cap=g.readback
 local filled=setHealth(p,g.cap)
 local actual=health(p)
 if not filled or not D.acceptFill(g.request,g.cap,actual) then
  return false,('initial refill failed: requested=%s actual=%s cap=%s'):format(tostring(g.cap),tostring(actual),tostring(g.cap))
 end
 g.target=actual;g.last=actual;g.checkAt=GetGameTimer()+1000;g.active=true
 fallbackLast=nil;lastError='none'
 log(('Guarded adapter active: original=%d effective=%d refill=%d'):format(m,g.cap,g.target))
 return true
end
local function resetQueue()
 pending=nil;queued={};queuedRaw=0;water=false;seq=0;nextSend=0
 totalRaw=0;acknowledged=0;drowningReports=0;lastKind='none'
end
local function acknowledge()
 if not pending then return end
 acknowledged=acknowledged+1
 if pending.drowning then drowningReports=drowningReports+1 end
 pending=nil
end
function A.reset()
 restore();state=nil;received=0;resetQueue();retryAt=0;fallbackLast=nil
end
function A.update(v)
 if type(v.token)~='string' or type(v.seq)~='number' or type(v.life)~='number' then return end
 if not state or state.token~=v.token then
  restore();resetQueue();seq=v.seq;retryAt=GetGameTimer()+C.guardStartupMs;fallbackLast=nil
 elseif pending and v.seq>=pending.seq then acknowledge();seq=math.max(seq,v.seq)
 else seq=math.max(seq,v.seq) end
 state=v;received=GetGameTimer()
end
RegisterNetEvent(E..'damageAck',function(token,n)
 if source~=65535 or not state or state.token~=token or not pending or pending.seq~=n then return end
 acknowledge()
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
 lastKind=kind
 if kind=='drowning' then water=true
 else
  local r=region(p)
  local key=r..':'..kind
  local hit=queued[key] or {region=r,kind=kind,raw=0}
  local n=math.max(0,math.min(math.floor(raw),C.maxRawGroup-hit.raw,C.maxRawBatch-queuedRaw))
  if n>0 then hit.raw=hit.raw+n;queued[key]=hit;queuedRaw=queuedRaw+n;totalRaw=totalRaw+n end
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
 lastError=tostring(reason)
 log('Guarded adapter unavailable: '..lastError..'; recording native damage until retry')
 restore()
 retryAt=GetGameTimer()+C.guardRetryMs
end
local function sampleFallback(p,now)
 local h,m=health(p),maximum(p)
 if truth(get('IsPedFalling',p)) then fallAt=now end
 if valid(h) and valid(m) then
  local current={ped=p,cap=m,hp=h}
  local lost=D.loss(fallbackLast,current)
  if lost>0 then queueLoss(p,lost) end
  fallbackLast=current
 else fallbackLast=nil end
 send(now)
end
-- VORP may finish setting health and cores several seconds after selection.
-- Do not permanently disable the adapter just because it ran too early.
AddEventHandler('vorp_core:Client:OnPlayerSpawned',function()
 if not guard and not failedPed then retryAt=GetGameTimer()+250 end
end)
CreateThread(function()
 while true do
  if not playing() or not state or GetGameTimer()-received>C.stateTimeoutMs then
   if guard then restore() end
   fallbackLast=nil
   if not playing() then state=nil;resetQueue();retryAt=0 end
   Wait(100)
  else
   local p=PlayerPedId();local now=GetGameTimer()
   if guard and guard.ped~=p then restore() end
   if failedPed and failedPed~=p then failedPed=nil;lastError='none';retryAt=now+C.guardStartupMs;fallbackLast=nil end
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
    fallbackLast=nil
    Wait(100)
   elseif not guard and (failedPed==p or now<retryAt) then
    -- No protection here: preserve measurable injuries even if guard setup
    -- temporarily fails. Never repeatedly modify a ped after cleanup failure.
    local ok,err=pcall(sampleFallback,p,now)
    if not ok then lastError='fallback sample: '..tostring(err);fallbackLast=nil end
    Wait(0)
   else
    local ok,err=pcall(function()
     if not guard then
      sampleFallback(p,now)
      local started,why=setup(p)
      if not started then
       fail(p,why)
       local h,m=health(p),maximum(p)
       if valid(h) and valid(m) then fallbackLast={ped=p,cap=m,hp=h} end
       return
      end
     end
     local g=guard
     if truth(get('IsPedFalling',p)) then fallAt=now end
     local h=health(p)
     if not valid(h) then fail(p,'health read failed');return end
     -- Do not count a native cap change as an injury. Re-establish the
     -- tested guard if the game reapplies character health modifiers.
     if now>=g.checkAt or h<g.last then
      local m=maximum(p)
      if not valid(m) then fail(p,'maximum health unavailable');return end
      if m~=g.cap then
       local previous=g.cap
       if m<g.request then
        g.changedMax=true
        local applied,actual=setMax(p,g.request)
        if not applied or not D.acceptCap(g.request,actual) then fail(p,('could not re-establish native buffer: actual=%s'):format(tostring(actual)));return end
        m=actual
       end
       if not D.acceptCap(g.request,m) then fail(p,'native maximum outside tested range: '..tostring(m));return end
       g.readback=m;g.cap=m
       local filled=setHealth(p,m);local actual=health(p)
       if not filled or not D.acceptFill(g.request,m,actual) then fail(p,'buffer refresh failed: '..tostring(actual));return end
       g.target=actual;g.last=actual;h=actual
       log(('Native buffer refreshed: %d -> %d (refill %d)'):format(previous,m,actual))
      end
      if now>=g.checkAt then
       g.checkAt=now+1000
       for _,flag in ipairs(C.nativeFlags) do
        if not truth(get('GetPedConfigFlag',p,flag,true)) then
         if not call('SetPedConfigFlag',p,flag,true) or not truth(get('GetPedConfigFlag',p,flag,true)) then fail(p,'guard flag lost: '..flag);return end
        end
       end
      end
     end
     if h<g.last then queueLoss(p,g.last-h) end
     if h<g.target then
      local filled=setHealth(p,g.target);local actual=health(p)
      if not filled or not D.acceptFill(g.request,g.cap,actual) then fail(p,('refill not verified: wanted=%s actual=%s'):format(tostring(g.target),tostring(actual)));return end
      g.target=actual;h=actual
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
 local g=guard;local now=GetGameTimer();local p=PlayerPedId()
 local mode=g and 'guarded' or state and playing() and alive(p) and not state.dead and now-received<=C.stateTimeoutMs and 'fallback' or 'inactive'
 local msg=('adapter=%s native=%s/%s state=%s rawTrauma=%d acknowledged=%d drowningReports=%d lastKind=%s queuedRaw=%d pending=%s stateAgeMs=%s retryInMs=%d lastError=%s'):format(
  mode,tostring(health(p)),tostring(maximum(p)),
  state and (state.dead and 'dead' or state.down and 'unconscious' or 'conscious') or 'loading',totalRaw,acknowledged,drowningReports,lastKind,queuedRaw,tostring(pending~=nil),
  state and tostring(now-received) or 'none',math.max(0,retryAt-now),lastError)
 log(msg);TriggerEvent('chat:addMessage',{args={'Medical',msg}})
end,false)
AddEventHandler('onClientResourceStop',function(r) if r==GetCurrentResourceName() then restore() end end)
