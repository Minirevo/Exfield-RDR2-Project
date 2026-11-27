local C,M=FrontierMedicalConfig,FrontierMedicalModel
local core,inv=exports.frontier_core,exports.frontier_inventory
local E='frontier_medical:'
local ready=false
local cache,views,working,lastHit,lastOpen,lastAction={},{},{},{},{},{}
local function db(method,sql,args)
 local ok,v=pcall(MySQL[method].await,sql,args)
 if not ok then print('[frontier_medical] Database error: '..method);return nil end
 return v
end
local function cid(src) return core:GetPlayerCharacterId(src) end
local function legacy()
 local x=GetResourceState('vorp_medic');return x=='started' or x=='starting'
end
local function death(src)
 local ok,v=pcall(function()
  local u=exports.vorp_core:GetCore().getUser(src)
  local c=u and u.getUsedCharacter
  if c then return c.isdead end
 end)
 return ok and (v==true or v==1 or v=='1' or v=='true')
end
local function read(id)
 local row=db('single','SELECT state,revision FROM frontier_medical_state WHERE character_id=?',{id})
 if not row then
  if db('update','INSERT IGNORE INTO frontier_medical_state(character_id,state) VALUES (?,?)',{id,json.encode(M.new())})==nil then return end
  row=db('single','SELECT state,revision FROM frontier_medical_state WHERE character_id=?',{id})
 end
 if not row then return end
 local ok,s=pcall(json.decode,row.state)
 if not ok or type(s)~='table' or type(s.wounds)~='table' then return end
 return s,tonumber(row.revision)
end
local function write(id,s,rev)
 local n=db('update','UPDATE frontier_medical_state SET state=?,revision=revision+1 WHERE character_id=? AND revision=?',{json.encode(s),id,rev})
 return n==1
end
local function notify(src,msg) TriggerClientEvent(E..'notice',src,tostring(msg)) end
local function publish(src,id,s)
 if cid(src)~=id then return end
 local r=M.restrictions(s);cache[src]={id=id,state=s}
 TriggerClientEvent(E..'state',src,r)
 if s.blood<=0 and not s.dead then TriggerClientEvent(E..'fatal',src) end
end
local function nearby(a,b)
 if not cid(a) or not cid(b) or GetPlayerRoutingBucket(a)~=GetPlayerRoutingBucket(b) then return false end
 local p,q=GetPlayerPed(a),GetPlayerPed(b)
 if p==0 or q==0 or not DoesEntityExist(p) or not DoesEntityExist(q) then return false end
 local x,y=GetEntityCoords(p),GetEntityCoords(q)
 return x and y and (x.x-y.x)^2+(x.y-y.y)^2+(x.z-y.z)^2<=C.reach^2
end
local function capable(src)
 if not ready or legacy() or death(src) then return false,'Medical unavailable or character dead' end
 local v=cache[src]
 if not v or v.id~=cid(src) then return false,'Medical state loading' end
 local r=M.restrictions(v.state)
 if r.down then return false,'Unconscious' end
 return true,r
end
exports('CanWork',function(src)
 local ok,r=capable(src);if not ok then return false,r end
 if r.arms or r.legs then return false,'Stabilise your fracture before physical work' end
 return true
end)
exports('CanAct',function(src)
 local ok,r=capable(src);return ok,ok and nil or r
end)
RegisterNetEvent(E..'hit',function(region,kind,damage)
 local src=source
 if not ready or legacy() or death(src) or type(damage)~='number' or damage%1~=0 or damage<1 or damage>C.maxDamageReport then return end
 if type(region)~='string' or #region>24 or type(kind)~='string' or #kind>16 then return end
 local now=GetGameTimer();if lastHit[src] and now-lastHit[src]<C.reportInterval then return end
 lastHit[src]=now
 local id=cid(src);if not id or GetPlayerPed(src)==0 then return end
 -- Only the reporting player's own character can be injured; report is bounded.
 for i=1,4 do
  local s,rev=read(id);if not s or cid(src)~=id then return end
  if not M.injure(s,region,kind,damage,os.time()) then return end
  if write(id,s,rev) then publish(src,id,s);return end
 end
end)
local function queue(id,s,item,region,key,actor,fp)
 if not M.eligible(s,item,region,os.time()) then return false,'No eligible injury' end
 local n=db('update',[[INSERT IGNORE INTO frontier_medical_treatments(request_key,patient,life,item,region,actor,fingerprint)
 VALUES (?,?,?,?,?,?,?)]],{key,id,s.life,item,region,actor,fp})
 if n==1 then return true end
 local old=db('single','SELECT patient,life,item,region,actor,fingerprint FROM frontier_medical_treatments WHERE request_key=?',{key})
 return old and old.patient==id and tonumber(old.life)==s.life and old.item==item and old.region==region and old.actor==actor and old.fingerprint==fp,'Treatment receipt conflict'
end
exports('QueueConsumption',function(src,id,item,key,actor,fp)
 if GetInvokingResource()~='frontier_inventory' or not C.items[item] or cid(src)~=id or actor~='player:'..id then return false,'forbidden' end
 if type(key)~='string' or #key>80 or type(fp)~='string' or #fp>8192 then return false,'invalid_request' end
 if not capable(src) or working[src] then return false,'restricted' end
 local s=read(id);if not s then return false,'not_ready' end
 local region=M.choose(s,item,os.time())
 if not region then return false,'no_injury' end
 local ok=queue(id,s,item,region,key,actor,fp)
 return ok==true,ok and nil or 'use_failed'
end)
local function applyTreatments()
 local rows=db('query',[[SELECT t.* FROM frontier_medical_treatments t JOIN frontier_inventory_receipts r
 ON r.request_key=t.request_key AND r.completed=TRUE AND BINARY r.actor=BINARY t.actor AND BINARY r.fingerprint=BINARY t.fingerprint
 WHERE t.applied=FALSE ORDER BY t.created_at LIMIT 100]]) or {}
 for _,t in ipairs(rows) do
  local s,rev=read(t.patient)
  if s then
   local changed=tonumber(t.life)==s.life and M.treat(s,t.item,t.region,os.time())
   -- Update patient and mark receipt applied in one statement; a new life cannot receive old treatment.
   local n=db('update',[[UPDATE frontier_medical_state m JOIN frontier_medical_treatments t ON t.patient=m.character_id
   JOIN frontier_inventory_receipts r ON r.request_key=t.request_key AND r.completed=TRUE AND BINARY r.actor=BINARY t.actor AND BINARY r.fingerprint=BINARY t.fingerprint
   SET m.state=?,m.revision=m.revision+1,t.applied=TRUE WHERE t.request_key=? AND t.applied=FALSE AND m.revision=?]],{json.encode(s),t.request_key,rev})
   if n and n>0 and changed then
    for _,p in pairs(core:GetPlayers()) do if p.frontierCharacterId==t.patient then publish(p.source,t.patient,s);notify(p.source,C.items[t.item]..' applied') end end
   end
  end
 end
end
local function validRegion(region)
 for _,r in ipairs(C.regions) do if r==region then return true end end
 return false
end
local function validView(src,v)
 return v and views[src]==v and v.expires>GetGameTimer() and cid(src)==v.actor and cid(v.target)==v.patient and nearby(src,v.target) and capable(src)
end
local function snapshot(src,v)
 if not validView(src,v) then return end
 local s=read(v.patient);if not s then return end
 local wounds={};for r in pairs(v.examined) do wounds[r]=M.exam(s,r,os.time()) end
 TriggerClientEvent(E..'view',src,{ticket=v.ticket,target=v.target,self=src==v.target,status=M.status(s,os.time()),wounds=wounds,pulse=v.pulse and M.pulse(s,os.time()) or 'Not checked',busy=working[src]~=nil})
end
RegisterNetEvent(E..'open',function(target)
 local src=source
 if type(target)~='number' or target%1~=0 or target<1 then return end
 local now=GetGameTimer();if lastOpen[src] and now-lastOpen[src]<1000 then return end;lastOpen[src]=now
 if not capable(src) or not nearby(src,target) or working[src] then return notify(src,'Patient unavailable or too far away') end
 local actor,patient=cid(src),cid(target)
 local ticket=db('scalar','SELECT UUID()');if not ticket or cid(src)~=actor or cid(target)~=patient then return end
 local v={ticket=ticket,actor=actor,patient=patient,target=target,expires=now+C.viewMs,examined={},pulse=false}
 views[src]=v;snapshot(src,v)
end)
RegisterNetEvent(E..'close',function(ticket)
 local src=source;local v=views[src]
 if v and v.ticket==ticket then views[src]=nil;working[src]=nil end
end)
RegisterNetEvent(E..'action',function(ticket,action,region,item)
 local src=source;local v=views[src]
 if not v or v.ticket~=ticket or not validView(src,v) or working[src] then return end
 local now=GetGameTimer();if lastAction[src] and now-lastAction[src]<600 then return end;lastAction[src]=now
 if action=='examine' then
  if type(region)~='string' or not validRegion(region) then return end
  v.examined[region]=true;return snapshot(src,v)
 elseif action=='pulse' then v.pulse=true;return snapshot(src,v)
 elseif action~='treat' or type(region)~='string' or not C.items[item] or not v.examined[region] then return end
 local s=read(v.patient);if not s or not M.eligible(s,item,region,os.time()) then return notify(src,'No eligible injury for that treatment') end
 local ok,has=inv:HasItem(src,item,1);if not ok or not has then return notify(src,'Missing '..C.items[item]) end
 local key=db('scalar','SELECT UUID()');if not key or not validView(src,v) or working[src] then return end
 key='med:'..key:gsub('-','')
 local w={view=v,key=key};working[src]=w;snapshot(src,v)
 SetTimeout(C.treatmentMs,function()
  if working[src]~=w then return end
  if not validView(src,v) then working[src]=nil;return notify(src,'Treatment interrupted') end
  local current=read(v.patient)
  if not current or not M.eligible(current,item,region,os.time()) or not validView(src,v) then working[src]=nil;snapshot(src,v);return end
  -- Matches the inventory RemoveItem resource receipt exactly.
  local fp=json.encode({'change',false,v.actor,false,item,1,false})
  local queued=queue(v.patient,current,item,region,key,'resource:frontier_medical',fp)
  if queued and validView(src,v) then
   local paid,why=inv:RemoveItem(src,item,1,nil,key)
   if not paid then notify(src,'Treatment not completed: '..tostring(why)) else notify(src,'Treatment submitted') end
  else notify(src,'Treatment interrupted') end
  if working[src]==w then working[src]=nil end
  snapshot(src,v)
  SetTimeout(1500,function() if validView(src,v) then snapshot(src,v) end end)
 end)
end)
local function tick(p)
 local src,id=p.source,p.frontierCharacterId
 if cid(src)~=id then return end
 local s,rev=read(id);if not s then return end
 local before=json.encode(s)
 if death(src) then s.dead=true;s.down=true
 elseif s.dead then s=M.new(s.life+1)
 else
  local n=db('single','SELECT hunger,thirst FROM frontier_needs_state WHERE character_id=?',{id})
  M.tick(s,os.time(),n and tonumber(n.hunger)>100 and tonumber(n.thirst)>100)
 end
 if cid(src)~=id then return end
 if before~=json.encode(s) and not write(id,s,rev) then return end
 publish(src,id,s)
end
local function clear(src) cache[src]=nil;views[src]=nil;working[src]=nil;lastHit[src]=nil;lastOpen[src]=nil;lastAction[src]=nil end
AddEventHandler('playerDropped',function() clear(tonumber(source) or source) end)
AddEventHandler('frontier:playerUnloaded',function(p) clear(p.source) end)
MySQL.ready(function()
 while not ready do
  ready=db('query','SELECT character_id FROM frontier_medical_state LIMIT 0')~=nil and db('query','SELECT request_key FROM frontier_medical_treatments LIMIT 0')~=nil
  if not ready then print('[frontier_medical] Apply sql/migrations/001_medical.sql');Wait(5000) end
 end
 CreateThread(function() while true do if not legacy() then applyTreatments() end;Wait(1000) end end)
 while true do
  if not legacy() then
   for _,p in pairs(core:GetPlayers()) do local ok,err=pcall(tick,p);if not ok then print('[frontier_medical] '..tostring(err)) end end
  else cache={} end
  for src,v in pairs(views) do
   if not validView(src,v) then views[src]=nil;working[src]=nil;TriggerClientEvent(E..'closeView',src,v.ticket) end
  end
  Wait(C.tickMs)
 end
end)
