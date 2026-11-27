local C=FrontierNeedsConfig
local core=exports.frontier_core
local ready=false
local cooldown,requests,knownDead={}, {}, {}
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
 return db('single','SELECT hunger,thirst,energy FROM frontier_needs_state WHERE character_id=?',{id})
end
local function native(name,...)
 local fn=_G[name];if type(fn)~='function' then return nil end
 local ok,v=pcall(fn,...);if ok then return v end
end
local function truth(v) return v==true or v==1 end
local function dead(p)
 local v=native('IsPedDeadOrDying',p,true)
 if v~=nil then return truth(v) end
 local h=native('GetEntityHealth',p)
 return type(h)=='number' and h<=0
end
local function currentPed(src)
 local p=GetPlayerPed(src)
 return p~=0 and DoesEntityExist(p) and p or nil
end
local function state(src,id,sequence)
 if not ready or legacyRunning() or cid(src)~=id or not ensure(id) then return end
 local row=read(id)
 if row and cid(src)==id then
  TriggerClientEvent('frontier_needs:state',src,sequence,{hunger=tonumber(row.hunger),thirst=tonumber(row.thirst),energy=tonumber(row.energy)})
 end
end
RegisterNetEvent('frontier_needs:request',function(sequence)
 local src=source
 if type(sequence)~='number' or sequence%1~=0 or sequence<1 or sequence>2147483646 or not ready then return end
 local now=GetGameTimer();if requests[src] and now-requests[src]<1500 then return end;requests[src]=now
 local id=cid(src);if id then state(src,id,sequence) end
end)
exports('QueueConsumption',function(src,id,item,key,actor,fp)
 if GetInvokingResource()~='frontier_inventory' or not ready or legacyRunning() or cid(src)~=id or actor~='player:'..id then return false,'forbidden' end
 local e=C.effects[item]
 if not e or type(key)~='string' or #key>80 or type(fp)~='string' or #fp>8192 then return false,'invalid_request' end
 local p=currentPed(src)
 if not p or dead(p) then return false,'restricted' end
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
local function tick(p)
 local src,id=p.source,p.frontierCharacterId
 if cid(src)~=id then return end
 local ped=currentPed(src);if not ped or not ensure(id) then return end
 if dead(ped) then knownDead[src]=id;return end
 if knownDead[src]==id then
  if db('update','UPDATE frontier_needs_state SET hunger=1000,thirst=1000,energy=1000 WHERE character_id=?',{id})~=nil then knownDead[src]=nil end
  return
 end
 local speed=tonumber(native('GetEntitySpeed',ped)) or 0
 local running=speed>=C.runSpeed and not truth(native('IsPedOnMount',ped)) and not truth(native('IsPedInAnyVehicle',ped,false))
 local h=C.hungerDecay+(running and C.runningHunger or 0)
 local t=C.thirstDecay+(running and C.runningThirst or 0)
 local energy=running and -C.energyDrain or C.energyRecovery
 if cid(src)~=id then return end
 local changed=db('update',[[UPDATE frontier_needs_state SET
  hunger=GREATEST(0,CAST(hunger AS SIGNED)-?),thirst=GREATEST(0,CAST(thirst AS SIGNED)-?),
  energy=GREATEST(0,LEAST(1000,CAST(energy AS SIGNED)+?)) WHERE character_id=?]],{h,t,energy,id})
 if changed==nil then return end
 local row=read(id)
 if row and cid(src)==id and currentPed(src)==ped and not dead(ped) then
  local damage=(tonumber(row.hunger)==0 and C.damageAtZero or 0)+(tonumber(row.thirst)==0 and C.damageAtZero or 0)
  local low=math.min(tonumber(row.hunger),tonumber(row.thirst),tonumber(row.energy))<=C.low
  if damage>0 or low then TriggerClientEvent('frontier_needs:consequence',src,damage,tonumber(row.energy),low) end
 end
end
AddEventHandler('playerDropped',function() requests[source]=nil;knownDead[source]=nil end)
AddEventHandler('frontier:playerUnloaded',function(p) requests[p.source]=nil;knownDead[p.source]=nil;cooldown[p.frontierCharacterId]=nil end)
MySQL.ready(function()
 while not ready do
  local a=db('query','SELECT character_id FROM frontier_needs_state LIMIT 0')
  local b=db('query','SELECT request_key FROM frontier_needs_consumptions LIMIT 0')
  ready=a~=nil and b~=nil
  if not ready then print('[frontier_needs] Apply sql/migrations/001_needs.sql');Wait(5000) end
 end
 CreateThread(function() while true do if not legacyRunning() then applyQueue() end;Wait(1000) end end)
 while true do
  Wait(C.tickMs)
  if legacyRunning() then print('[frontier_needs] Stop vorp_metabolism; Frontier decay is paused.')
  else for _,p in pairs(core:GetPlayers()) do tick(p) end end
 end
end)
