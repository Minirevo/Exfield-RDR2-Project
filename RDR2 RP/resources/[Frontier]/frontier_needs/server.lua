local C,M=FrontierNeedsConfig,FrontierNeedsModel
local core=exports.frontier_core
local ready=false
local cooldown,requests,knownDead={}, {}, {}
local runtime={}
local activityNames={idle=true,walk=true,jog=true,sprint=true,swim=true,mounted=true,unknown=true}
local function db(method,sql,params)
 local ok,res=pcall(MySQL[method].await,sql,params)
 if not ok then print('[frontier_needs] Database error: '..method);return nil end
 return res
end
local function cid(src) return core:GetPlayerCharacterId(src) end
local function legacyRunning()
 local state=GetResourceState('vorp_metabolism')
 return state=='started' or state=='starting'
end
local function ensure(id)
 return db('update','INSERT IGNORE INTO frontier_needs_state(character_id) VALUES (?)',{id})~=nil
end
local function read(id)
 return db('single','SELECT hunger,thirst,energy,stamina FROM frontier_needs_state WHERE character_id=?',{id})
end
local function native(name,...)
 local fn=_G[name];if type(fn)~='function' then return nil end
 local ok,v=pcall(fn,...);if ok then return v end
end
local function truth(v) return v==true or v==1 end
local function dead(p,src)
 -- Known RedM issue: server-side entity health can report zero for alive peds.
 -- Keep the tested character-provider death state until Core owns lifecycle.
 local ok,v=pcall(function()
  local vorp=exports.vorp_core:GetCore()
  local user=vorp.getUser(src);if not user then return nil end
  local character=user.getUsedCharacter;if not character then return nil end
  return character.isdead
 end)
 if ok and v~=nil then return truth(v) or v=='1' or v=='true' end
 v=native('IsPedDeadOrDying',p,true)
 return v~=nil and truth(v) or false
end
local function currentPed(src)
 local p=GetPlayerPed(src)
 return p~=0 and DoesEntityExist(p) and p or nil
end
local function session(src,id)
 local r=runtime[src]
 if not r or r.id~=id then r={id=id,phase=0,activity='unknown',sampleAt=0};runtime[src]=r end
 return r
end
local function values(row)
 return {hunger=tonumber(row.hunger),thirst=tonumber(row.thirst),energy=tonumber(row.energy),stamina=tonumber(row.stamina)}
end
RegisterNetEvent('frontier_needs:request',function(sequence,activity)
 local src=source
 if type(sequence)~='number' or sequence%1~=0 or sequence<1 or sequence>2147483646 or not ready or legacyRunning() then return end
 local now=GetGameTimer();if requests[src] and now-requests[src]<750 then return end;requests[src]=now
 local id=cid(src);if not id then return end
 local r=session(src,id)
 -- Only an activity hint; clients cannot submit needs values or restore amounts.
 r.activity=type(activity)=='string' and activityNames[activity] and activity or 'unknown'
 r.sampleAt=now
 if r.value and cid(src)==id then TriggerClientEvent('frontier_needs:state',src,sequence,r.value) end
end)
exports('QueueConsumption',function(src,id,item,key,actor,fp)
 if GetInvokingResource()~='frontier_inventory' or not ready or legacyRunning() or cid(src)~=id or actor~='player:'..id then return false,'forbidden' end
 local e=C.effects[item]
 if not e or type(key)~='string' or #key>80 or type(fp)~='string' or #fp>8192 then return false,'invalid_request' end
 local p=currentPed(src)
 if not p or dead(p,src) then return false,'restricted' end
 local old=db('single','SELECT character_id,item,actor,fingerprint FROM frontier_needs_consumptions WHERE request_key=?',{key})
 if old then return old.character_id==id and old.item==item and old.actor==actor and old.fingerprint==fp,'request_conflict' end
 local now=GetGameTimer()
 if cooldown[id] and now-cooldown[id]<C.consumeCooldownMs then return false,'busy' end
 if not ensure(id) or cid(src)~=id then return false,'database_error' end
 local inserted=db('update',[[INSERT IGNORE INTO frontier_needs_consumptions
  (request_key,character_id,item,actor,fingerprint,hunger,thirst,energy)
  VALUES (?,?,?,?,?,?,?,?)]],{key,id,item,actor,fp,e.hunger,e.thirst,e.energy})
 if inserted~=1 then return false,'database_error' end
 cooldown[id]=now
 return true
end)
local function applyQueue()
 local rows=db('query',[[SELECT o.request_key,o.character_id,o.item
 FROM frontier_needs_consumptions o
 JOIN frontier_inventory_receipts r ON r.request_key=o.request_key AND r.completed=TRUE
 AND BINARY r.actor=BINARY o.actor AND BINARY r.fingerprint=BINARY o.fingerprint
 WHERE o.applied=FALSE ORDER BY o.created_at LIMIT 100]]) or {}
 for _,row in ipairs(rows) do
  -- Atomic state increment + applied marker. A repeat cannot restore twice.
  local changed=db('update',[[UPDATE frontier_needs_state n
   JOIN frontier_needs_consumptions o ON o.character_id=n.character_id
   JOIN frontier_inventory_receipts r ON r.request_key=o.request_key AND r.completed=TRUE
   AND BINARY r.actor=BINARY o.actor AND BINARY r.fingerprint=BINARY o.fingerprint
   SET n.hunger=LEAST(1000,n.hunger+o.hunger),n.thirst=LEAST(1000,n.thirst+o.thirst),
       n.energy=LEAST(1000,n.energy+o.energy),o.applied=TRUE
   WHERE o.request_key=? AND o.applied=FALSE]],{row.request_key})
  if changed and changed>0 then
   for _,p in pairs(core:GetPlayers()) do
    if p.frontierCharacterId==row.character_id and cid(p.source)==row.character_id then
     TriggerClientEvent('frontier_needs:consumed',p.source,row.item)
    end
   end
  end
 end
end
local function activityFor(ped,r)
 local recent=GetGameTimer()-r.sampleAt<3500 and r.sampleAt>0
 local activity=recent and r.activity or 'unknown'
 -- Prefer reliable client movement classification for RDR3-only natives.
 -- Corroborate clearly fast on-foot movement when server speed exists.
 if activity=='mounted' or truth(native('IsPedOnMount',ped)) or truth(native('IsPedInAnyVehicle',ped,false)) then return 'mounted' end
 if activity=='swim' or truth(native('IsPedSwimming',ped)) then return 'swim' end
 local speed=tonumber(native('GetEntitySpeed',ped))
 if speed and speed>=C.sprintSpeed then return 'sprint' end
 if speed and speed>=C.jogSpeed and (activity=='idle' or activity=='walk' or activity=='unknown') then return 'jog' end
 if activity=='unknown' and speed and speed>=C.walkSpeed then return 'walk' end
 return activity
end
local function tick(p)
 local src,id=p.source,p.frontierCharacterId
 if cid(src)~=id then return end
 local ped=currentPed(src);if not ped then return end
 local r=session(src,id)
 if dead(ped,src) then knownDead[src]=id;return end
 if knownDead[src]==id then
  if db('update','UPDATE frontier_needs_state SET hunger=1000,thirst=1000,energy=1000,stamina=1000 WHERE character_id=?',{id})~=nil then
   knownDead[src]=nil;r.value=nil;r.phase=0;r.locked=false;r.damageAt=nil
  end
  return
 end
 local row=read(id)
 if not row then
  if not ensure(id) then return end
  row=read(id);if not row then return end
 end
 local old=values(row)
 for _,v in pairs(old) do if type(v)~='number' then return end end
 if old.stamina==nil or old.hunger==nil or old.thirst==nil or old.energy==nil then return end
 local phase=(r.phase+1)%C.basalEvery
 local activity=activityFor(ped,r)
 local locked=r.locked
 if locked==nil then locked=old.stamina<C.resumeSprint end
 local next=M.step(old,activity,phase==0,locked)
 if cid(src)~=id or runtime[src]~=r then return end
 if old.hunger~=next.hunger or old.thirst~=next.thirst or old.energy~=next.energy or old.stamina~=next.stamina then
  -- Compare-and-swap: a concurrently applied consumption must not be overwritten.
  local changed=db('update',[[UPDATE frontier_needs_state SET hunger=?,thirst=?,energy=?,stamina=?
   WHERE character_id=? AND hunger=? AND thirst=? AND energy=? AND stamina=?]],
   {next.hunger,next.thirst,next.energy,next.stamina,id,old.hunger,old.thirst,old.energy,old.stamina})
  if changed~=1 then return end
 end
 if cid(src)~=id or runtime[src]~=r or currentPed(src)~=ped then return end
 r.value=next;r.phase=phase;r.locked=next.locked;r.lastActivity=activity
 local pct=M.damage(next.hunger,next.thirst)
 local now=GetGameTimer()
 if pct==0 then r.damageAt=nil
 elseif not r.damageAt then r.damageAt=now
 elseif now-r.damageAt>=C.damageIntervalMs then
  r.damageAt=now
  if not dead(ped,src) then TriggerClientEvent('frontier_needs:consequence',src,pct) end
 end
end
local function clear(src)
 requests[src]=nil;knownDead[src]=nil;runtime[src]=nil
end
AddEventHandler('playerDropped',function() clear(tonumber(source) or source) end)
AddEventHandler('frontier:playerUnloaded',function(p) clear(p.source);cooldown[p.frontierCharacterId]=nil end)
RegisterCommand('frontierneedsstatus',function(src)
 if src==0 then print('[frontier_needs] Run /frontierneedsstatus in-game.');return end
 local id=cid(src);local r=runtime[src]
 local v=r and r.id==id and r.value
 local msg=v and ('Activity=%s | Stamina=%d/%d | Energy=%d | Food=%d | Water=%d | Sprint locked=%s'):format(r.lastActivity or 'unknown',v.stamina,v.capacity,v.energy,v.hunger,v.thirst,tostring(v.locked))
  or ('No state yet | ready=%s | legacy=%s | character=%s'):format(tostring(ready),tostring(legacyRunning()),tostring(id~=nil))
 TriggerClientEvent('frontier_needs:diagnostic',src,msg)
end,false)
MySQL.ready(function()
 while not ready do
  local a=db('query','SELECT character_id,stamina FROM frontier_needs_state LIMIT 0')
  local b=db('query','SELECT request_key FROM frontier_needs_consumptions LIMIT 0')
  ready=a~=nil and b~=nil
  if not ready then print('[frontier_needs] Apply sql/migrations/001_needs.sql and 002_stamina.sql');Wait(5000) end
 end
 CreateThread(function() while true do if not legacyRunning() then applyQueue() end;Wait(1000) end end)
 while true do
  Wait(C.tickMs)
  if legacyRunning() then
   -- Do not let clients continue using stale state while legacy needs is active.
   runtime={}
  else
   for _,p in pairs(core:GetPlayers()) do
    local ok,err=pcall(tick,p)
    if not ok then print('[frontier_needs] Tick failed: '..tostring(err)) end
   end
  end
 end
end)
