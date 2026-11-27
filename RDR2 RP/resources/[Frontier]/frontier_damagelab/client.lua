local L=FrontierDamageLab
local E='frontier_damagelab:'
local trial=nil
local function truth(v) return v==true or v==1 end
local function log(msg)
 print(('[frontier_damagelab] %s'):format(msg))
end
local function call(name,...)
 local fn=_G[name]
 if type(fn)~='function' then return false,'unavailable' end
 return pcall(fn,...)
end
local function get(name,...)
 return L.readNative(_G[name],...)
end
local function health(p) return get('GetEntityHealth',p) end
local function maximum(p)
 return get('GetEntityMaxHealth',p,false)
end
local function dead(p)
 return truth(get('IsEntityDead',p)) or truth(get('IsPlayerDead',PlayerId()))
end
local function setMax(p,n)
 local ok=call('SetEntityMaxHealth',p,n)
 if not ok then ok=pcall(Citizen.InvokeNative,0x166E7CF68597D8B5,p,n) end
 return ok and maximum(p)==n
end
local function setHealth(p,n)
 local ok=call('SetEntityHealth',p,n,0)
 if not ok then ok=pcall(Citizen.InvokeNative,0xAC2767ED8BDFAB15,p,n,0) end
 return ok
end
local function localIsolation()
 for _,r in ipairs({'frontier_medical','frontier_needs','vorp_medic','vorp_metabolism'}) do
  local st=GetResourceState(r);if st=='started' or st=='starting' then return false end
 end
 return true
end
local function finish(reason)
 local t=trial
 if not t then return end
 trial=nil
 local p=t.ped
 -- Undo only settings this trial changed. Never resurrect an engine-dead ped.
 if DoesEntityExist(p) then
  for flag,prior in pairs(t.flags) do
   if not call('SetPedConfigFlag',p,flag,prior) then log('WARNING: could not restore flag '..flag) end
  end
  if t.changedMax then
   if not setMax(p,t.originalMax) then log('WARNING: max health restoration not verified') end
  end
  if t.modifiedHealth and not truth(get('IsEntityDead',p)) and not t.stats.dead then
   if not setHealth(p,math.min(t.originalHealth,t.originalMax)) then log('WARNING: could not restore health') end
  end
 end
 if t.changedInvincible then
  if not call('SetPlayerInvincible',PlayerId(),t.originalInvincible) then log('WARNING: invincibility restoration failed') end
 end
 local summary=L.summary(t.stats)
 log(('END trial=%s mode=%s mark=%s reason=%s %s'):format(t.id,t.mode,t.mark,reason,summary))
 TriggerServerEvent(E..'result',t.id,summary,reason,t.lastError)
end
local function errors(t,msg)
 t.stats.errors=t.stats.errors+1
 t.lastError=tostring(msg):gsub('[%c]',' '):sub(1,200)
 if t.stats.errors<=5 then log(('ERROR: trial=%s mode=%s %s'):format(t.id,t.mode,t.lastError)) end
end
local function bone(p)
 local ok,b=get('GetPedLastDamageBone',p)
 if truth(ok) and type(b)=='number' then return tostring(b) end
 if type(ok)=='number' and ok>1 and b==nil then return tostring(ok) end
 return '?'
end
local function context(p)
 return ('bone=%s source=%s cause=%s falling=%s ragdoll=%s fire=%s swimming=%s'):format(
 bone(p),tostring(get('GetPedSourceOfDamage',p)),tostring(get('GetPedCauseOfDeath',p)),tostring(get('IsPedFalling',p)),tostring(get('IsPedRagdoll',p)),tostring(get('IsEntityOnFire',p)),tostring(get('IsPedSwimming',p)))
end
RegisterNetEvent(E..'notice',function(msg)
 if source~=65535 or type(msg)~='string' then return end
 log(msg);TriggerEvent('chat:addMessage',{args={'Damage Lab',msg}})
end)
RegisterNetEvent(E..'start',function(id,mode,duration)
 if source~=65535 or type(id)~='string' or not L.validMode(mode) or duration~=L.durationMs then return end
 finish('new trial')
 local p=PlayerPedId();local h,m=health(p),maximum(p)
 if not localIsolation() or not LocalPlayer.state.IsInSession or p==0 or dead(p) or type(h)~='number' or type(m)~='number' or h<=0 or m<=0 then
  log('Trial refused: need isolated loaded living character')
  TriggerServerEvent(E..'result',id,'start refused','isolated loaded living character required');return
 end
 local t={id=id,mode=mode,ped=p,expires=GetGameTimer()+duration,mark='unlabelled',originalHealth=h,originalMax=m,flags={},stats=L.newStats(),target=L.target(m,mode)}
 trial=t
 local cfg=L.modes[mode]
 if cfg.flags then
  for _,flag in ipairs(L.flags) do
   local prior=get('GetPedConfigFlag',p,flag,true)
   if prior==nil then errors(t,'GetPedConfigFlag '..flag);return finish('flag unavailable') end
   t.flags[flag]=truth(prior)
   local set,why=call('SetPedConfigFlag',p,flag,true)
   local actual=get('GetPedConfigFlag',p,flag,true)
   if not set or not truth(actual) then errors(t,('flag %d set=%s result=%s actual=%s'):format(flag,tostring(set),tostring(why),tostring(actual)));return finish('flag failed') end
  end
 end
 if cfg.invincible then
  local prior=get('GetPlayerInvincible',PlayerId())
  if prior==nil then errors(t,'GetPlayerInvincible unavailable');return finish('invincibility unavailable') end
  t.originalInvincible=truth(prior);t.changedInvincible=true
  if not call('SetPlayerInvincible',PlayerId(),true) or not truth(get('GetPlayerInvincible',PlayerId())) then errors(t,'SetPlayerInvincible not verified');return finish('invincibility failed') end
 end
 if cfg.refill then
  if cfg.buffer and t.target~=m then
   t.changedMax=true
   if not setMax(p,t.target) then errors(t,('native max health buffer rejected: wanted=%s actual=%s'):format(tostring(t.target),tostring(maximum(p))));return finish('max health failed') end
  end
  t.modifiedHealth=true
  if not setHealth(p,t.target) then errors(t,'initial fill failed');return finish('fill failed') end
 end
 t.lastHealth=health(p)
 if type(t.lastHealth)~='number' or (cfg.refill and t.lastHealth<t.target) then
  errors(t,('initial health not verified: wanted=%s actual=%s'):format(tostring(t.target),tostring(t.lastHealth)))
  return finish('initial fill not verified')
 end
 log(('START trial=%s mode=%s original=%s/%s actual=%s/%s invincible=%s'):format(id,mode,tostring(h),tostring(m),tostring(t.lastHealth),tostring(maximum(p)),tostring(get('GetPlayerInvincible',PlayerId()))))
 TriggerServerEvent(E..'started',id,t.lastHealth,maximum(p))
 log('Use /damagelabmark npc-punch (or any test label), /damagelabstatus and /damagelab off.')
end)
RegisterNetEvent(E..'stop',function(id,reason)
 if source==65535 and trial and trial.id==id then finish(tostring(reason)) end
end)
-- These are independent candidate signals. Never add their values together as damage.
local function eventHash(name) return joaat(name)&0xffffffff end
local queues={
 [0]={[eventHash('EVENT_ENTITY_DAMAGED')]={label='AI_DAMAGE',slots=9,stat='aiEvents'},[eventHash('EVENT_ENTITY_DESTROYED')]={label='AI_DESTROYED',slots=9,stat='incapEvents'}},
 [1]={[eventHash('EVENT_NETWORK_DAMAGE_ENTITY')]={label='NET_DAMAGE',slots=32,stat='networkEvents'},[eventHash('EVENT_NETWORK_INCAPACITATED_ENTITY')]={label='NET_INCAP',slots=4,stat='incapEvents'}}
}
local function readQueues(t)
 for group,defs in pairs(queues) do
  local n=get('GetNumberOfEvents',group)
  if type(n)=='number' then
   for i=0,math.min(n,128)-1 do
    local hash=get('GetEventAtIndex',group,i)
    local def=type(hash)=='number' and defs[hash&0xffffffff]
    if def then
     local ok,err=pcall(function()
      local d=DataView.ArrayBuffer(def.slots*8)
      local found=Citizen.InvokeNative(0x57EC5FA4D4D6AFCA,group,i,d:Buffer(),def.slots,Citizen.ReturnResultAnyway())
      if not truth(found) or d:GetInt32(0)~=t.ped then return end
      local raw={}
      for k=0,def.slots-1 do raw[#raw+1]=tostring(d:GetInt32(k*8)) end
      t.stats[def.stat]=t.stats[def.stat]+1
      local offset=group==0 and 32 or def.slots==32 and 16 or 24
      local value=d:GetFloat32(offset)
      log(('%s trial=%s mark=%s t=%d amountFloat=%s raw=[%s] %s'):format(def.label,t.id,t.mark,GetGameTimer(),tostring(value),table.concat(raw,','),context(t.ped)))
     end)
     if not ok then errors(t,'queue decode '..tostring(err)) end
    end
   end
  end
 end
end
AddEventHandler('gameEventTriggered',function(name,args)
 local t=trial
 if not t or type(name)~='string' or type(args)~='table' then return end
 local lower=name:lower()
 if not (lower:find('damage',1,true) or lower:find('dead',1,true) or lower:find('incapac',1,true) or lower:find('destroy',1,true)) then return end
 if args[1]~=t.ped then return end
 local raw={}
 for i=1,math.min(#args,32) do raw[#raw+1]=tostring(args[i]) end
 t.stats.gameEvents=t.stats.gameEvents+1
 log(('GAME_EVENT trial=%s mark=%s t=%d name=%s raw=[%s]'):format(t.id,t.mark,GetGameTimer(),name,table.concat(raw,',')))
end)
RegisterCommand('damagelabmark',function(_,args)
 local t=trial;if not t then return log('No active trial') end
 local mark=table.concat(args,' '):sub(1,60):gsub('[%c]','')
 t.mark=mark~='' and mark or 'unlabelled'
 log(('MARK trial=%s mode=%s mark=%s t=%d %s'):format(t.id,t.mode,t.mark,GetGameTimer(),L.summary(t.stats)))
end,false)
RegisterCommand('damagelabstatus',function()
 local t=trial;if not t then return log('No active trial') end
 log(('STATUS trial=%s mode=%s mark=%s health=%s/%s remaining=%ds %s'):format(t.id,t.mode,t.mark,tostring(health(t.ped)),tostring(maximum(t.ped)),math.max(0,math.ceil((t.expires-GetGameTimer())/1000)),L.summary(t.stats)))
end,false)
CreateThread(function()
 while true do
  local t=trial
  if not t then Wait(150)
  else
   Wait(0)
   if trial==t then
    local ok,err=pcall(function()
     if GetGameTimer()>=t.expires or PlayerPedId()~=t.ped or not LocalPlayer.state.IsInSession or not localIsolation() then return finish('timeout, session or resource changed') end
     local p=t.ped
     readQueues(t)
     local h=health(p)
     if type(h)~='number' then errors(t,'health unavailable');return finish('health unavailable') end
     local loss=L.loss(t.lastHealth,h)
     if loss>0 then
      t.stats.lossSamples=t.stats.lossSamples+1;t.stats.rawLoss=t.stats.rawLoss+loss
      log(('HEALTH_LOSS trial=%s mark=%s t=%d before=%s after=%s rawLoss=%s max=%s %s'):format(t.id,t.mark,GetGameTimer(),tostring(t.lastHealth),tostring(h),tostring(loss),tostring(maximum(p)),context(p)))
     end
     if dead(p) or h<=0 then
      t.stats.dead=true;log('NATIVE_DEATH '..context(p));return finish('native death')
     end
     if L.modes[t.mode].refill and h<t.target then
      if not setHealth(p,t.target) then errors(t,'refill failed');return finish('refill failed') end
      t.stats.refills=t.stats.refills+1
      h=health(p)
      if type(h)~='number' or h<t.target then errors(t,'refill not verified');return finish('refill not verified') end
     end
     t.lastHealth=h
    end)
    if not ok then errors(t,tostring(err));finish('runtime error') end
   end
  end
 end
end)
AddEventHandler('onClientResourceStop',function(name)
 if name==GetCurrentResourceName() then finish('resource stopped') end
end)
