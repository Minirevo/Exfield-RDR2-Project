local C,M,Q=FrontierMedicalConfig,FrontierMedicalModel,FrontierMedicalQTE
local core,inv=exports.frontier_core,exports.frontier_inventory
local E='frontier_medical:'
local ready=false
local cache,views,working,reports,lastOpen,lastAction={},{},{},{},{},{}
local reportCounter=0
local D=FrontierMedicalDispatch
local board=D.new()
local H=FrontierHospital
local dispatchPublish,dispatchClear,dispatchTick
local testMedics,operations,patientLocks,testAt={},{},{},{}
local finishOperation,beginOperation,sendStage
local function ace(src,permission)
 if src<=0 then return false end
 local value=IsPlayerAceAllowed(src,permission)
 return value==true or value==1
end
local function admin(src) return ace(src,C.adminAce) end
local function testing(src)
 local grant=testMedics[src]
 local id=core:GetPlayerCharacterId(src)
 return grant~=nil and id~=nil and grant.id==id and (grant.console==true or admin(src))
end
local function medic(src)
 return core:GetPlayerCharacterId(src)~=nil and (ace(src,C.medicAce) or testing(src))
end
local function selfTest(src,v) return src==v.target and testing(src) end
local function db(method,sql,args)
 local ok,v=pcall(MySQL[method].await,sql,args)
 if not ok then print('[frontier_medical] Database error: '..method);return nil end
 return v
end
local function cid(src) return core:GetPlayerCharacterId(src) end
local function legacy()
 local x=GetResourceState('vorp_medic')
 return (x=='started' or x=='starting') and GetResourceMetadata('vorp_medic','frontier_retired',0)~='medical-v1'
end
local function death(src)
 local ok,v=pcall(function()
  local u=exports.vorp_core:GetCore().getUser(src)
  local c=u and u.getUsedCharacter
  if c then return c.isdead end
 end)
 if not ok or v==nil then return nil end
 return v==true or v==1 or v=='1' or v=='true'
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
 return M.normalize(s),tonumber(row.revision)
end
local function write(id,s,rev)
 local n=db('update','UPDATE frontier_medical_state SET state=?,revision=revision+1 WHERE character_id=? AND revision=?',{json.encode(s),id,rev})
 return n==1
end
local function notify(src,msg) TriggerClientEvent(E..'notice',src,tostring(msg)) end
local function reportSession(src,id,life)
 local q=reports[src]
 if not q or q.id~=id or q.life~=life then
  reportCounter=reportCounter+1
  q={id=id,life=life,token=('%d:%d:%d:%d'):format(src,os.time(),GetGameTimer(),reportCounter)}
  reports[src]=q
 end
 return q
end
local function publish(src,id,s,rev)
 if cid(src)~=id then return end
 local previous=cache[src]
 if previous and previous.id==id and previous.revision>rev then return end
 local q=reportSession(src,id,s.life)
 local r=M.restrictions(s)
 r.life=s.life;r.token=q.token;r.seq=s.reportToken==q.token and (s.reportSeq or 0) or 0
 r.dead=s.dead==true;r.fatal=r.dead and not s.nativeSeen
 r.symptoms=M.symptoms(s,os.time())
 cache[src]={id=id,state=s,revision=rev,publishedAt=GetGameTimer()}
 TriggerClientEvent(E..'state',src,r)
 if dispatchPublish then
  local ok,err=pcall(dispatchPublish,src,id,s)
  if not ok then print('[frontier_medical] Dispatch publication failed: '..tostring(err)) end
 end
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
-- One bounded, sequenced batch per 500ms; only the victim's own character.
-- Apply the batch and its receipt in the same revision CAS, including retries.
RegisterNetEvent(E..'damageBatch',function(token,seq,hits,drowning)
 local src=source;local q=reports[src]
 if not ready or legacy() or death(src) or not q or q.token~=token or q.id~=cid(src) or q.busy then return end
 if type(seq)~='number' or seq%1~=0 or seq<1 or seq>2147483646 or not M.validReport(hits,drowning) then return end
 local now=GetGameTimer()
 if q.lastAt and now-q.lastAt<C.reportMinMs then return end
 q.lastAt=now;q.busy=true
 local ok,err=pcall(function()
  for i=1,5 do
   local s,rev=read(q.id)
   if not s or reports[src]~=q or cid(src)~=q.id or s.life~=q.life then return end
   local last=s.reportToken==q.token and (s.reportSeq or 0) or 0
   if seq<=last then TriggerClientEvent(E..'damageAck',src,token,seq);return end
   if seq~=last+1 or s.dead or death(src) then return end
   local timestamp=os.time()
   for _,hit in ipairs(hits) do if not s.dead then M.applyRaw(s,hit.region,hit.kind,hit.raw,timestamp) end end
   if drowning and not s.dead then M.drown(s,timestamp) end
   s.reportToken=q.token;s.reportSeq=seq
   if write(q.id,s,rev) then
    if reports[src]==q and cid(src)==q.id then
     publish(src,q.id,s,rev+1);TriggerClientEvent(E..'damageAck',src,token,seq)
     if not s.dead and not s.down then
      local message=M.hitDescription(hits,drowning)
      if message then TriggerClientEvent(E..'injuryFeedback',src,q.token,message) end
     end
    end
    return
   end
  end
 end)
 q.busy=false
 if not ok then print('[frontier_medical] Damage batch failed: '..tostring(err)) end
end)
-- Trusted Needs server calls this on its existing starvation/dehydration cadence.
exports('ApplyDeprivation',function(src,id,pct)
 if GetInvokingResource()~='frontier_needs' or not ready or legacy() or cid(src)~=id or death(src) then return false end
 if type(pct)~='number' or pct%1~=0 or pct<1 or pct>5 then return false end
 for i=1,5 do
  local s,rev=read(id);if not s or cid(src)~=id or s.dead then return false end
  if not M.deprive(s,pct,os.time()) then return false end
  if write(id,s,rev) then publish(src,id,s,rev+1);return true end
 end
 return false
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
   LEFT JOIN frontier_medical_charges c ON c.request_key=t.request_key
   SET m.state=?,m.revision=m.revision+1,t.applied=TRUE,c.eligible=IF(?=1,TRUE,FALSE) WHERE t.request_key=? AND t.applied=FALSE AND m.revision=?]],{json.encode(s),changed and 1 or 0,t.request_key,rev})
   if n and n>0 and changed then
    for _,p in pairs(core:GetPlayers()) do if p.frontierCharacterId==t.patient then publish(p.source,t.patient,s,rev+1);notify(p.source,C.items[t.item]..' applied') end end
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
 v.snapshotSeq=(v.snapshotSeq or 0)+1
 local seq=v.snapshotSeq
 local s=read(v.patient);if not s or v.snapshotSeq~=seq or not validView(src,v) then return end
 if v.life and v.life~=s.life then
  if operations[src] then finishOperation(src,operations[src],'failed') end
  views[src]=nil;working[src]=nil;TriggerClientEvent(E..'closeView',src,v.ticket);return
 end
 v.life=s.life
 local now=os.time()
 local visible,wounds,actions,findings,procedures={},{},{},{},{}
 local licensed=medic(src)
 local billing=licensed and H.canBill(src,v) or false
 for _,r in ipairs(C.regions) do
  visible[r]=M.visible(s,r)
  local examined=v.examined[r]==true
  if examined then wounds[r]=M.exam(s,r,now) end
  actions[r]={}
  for item in pairs(C.items) do actions[r][item]=M.observedTreatment(s,item,r,now,examined,src==v.target) end
  if licensed and v.profExam[r] then
   findings[r]=M.professionalFindings(s,r);procedures[r]={}
   for id in pairs(C.procedures) do procedures[r][id]=(src~=v.target or selfTest(src,v)) and M.procedureEligible(s,r,id,now) end
  end
 end
 local status=s.dead and 'Dead' or s.down and 'Unconscious' or 'Conscious'
 local vitals
 if licensed and (v.vitals or v.temperature) then
  local all=M.vitals(s,now);vitals={}
  if v.vitals then vitals.pulse=all.pulse;vitals.respiration=all.respiration;vitals.circulation=all.circulation end
  if v.temperature then vitals.temperature=all.temperature end
 end
 TriggerClientEvent(E..'view',src,{ticket=v.ticket,target=v.target,self=src==v.target,status=status,visible=visible,wounds=wounds,actions=actions,pulse=v.pulse and M.pulse(s,now) or 'Not checked',breathing=v.breathing and M.breathing(s) or 'Not checked',busy=working[src]~=nil,medic=licensed==true,billing=billing==true,findings=licensed and findings or nil,procedures=licensed and procedures or nil,vitals=vitals,selfTest=selfTest(src,v)==true})
end
RegisterNetEvent(E..'open',function(target)
 local src=source
 if type(target)~='number' or target%1~=0 or target<1 then return end
 local now=GetGameTimer();if lastOpen[src] and now-lastOpen[src]<1000 then return end;lastOpen[src]=now
 if not capable(src) or not nearby(src,target) or working[src] then return notify(src,'Patient unavailable or too far away') end
 local actor,patient=cid(src),cid(target)
 local ticket=db('scalar','SELECT UUID()');if not ticket or cid(src)~=actor or cid(target)~=patient then return end
 local v={ticket=ticket,actor=actor,patient=patient,target=target,expires=now+C.viewMs,examined={},profExam={},pulse=false}
 views[src]=v;snapshot(src,v)
end)
RegisterNetEvent(E..'close',function(ticket)
 local src=source;local v=views[src]
 if v and v.ticket==ticket then
  if operations[src] then finishOperation(src,operations[src],'failed') end
  views[src]=nil;working[src]=nil
 end
end)
RegisterNetEvent(E..'action',function(ticket,action,region,item)
 local src=source;local v=views[src]
 if not v or v.ticket~=ticket or not validView(src,v) or working[src] then return end
 local now=GetGameTimer();if lastAction[src] and now-lastAction[src]<600 then return end;lastAction[src]=now
 if action=='examine' then
  if type(region)~='string' or not validRegion(region) then return end
  v.examined[region]=true;return snapshot(src,v)
 elseif action=='pulse' then v.pulse=true;return snapshot(src,v)
 elseif action=='breathing' then v.breathing=true;return snapshot(src,v)
 elseif action=='professional' then
  if not medic(src) or not validRegion(region) then return end
  v.profExam[region]=true;v.examined[region]=true;return snapshot(src,v)
 elseif action=='vitals' or action=='temperature' then
  if not medic(src) then return end
  local item=action=='vitals' and 'stethoscope' or 'thermometer'
  local ok,has=inv:HasItem(src,item,1)
  if not ok or not has then return notify(src,'Missing '..C.equipment[item]) end
  if not validView(src,v) or not medic(src) then return end
  v[action]=true;return snapshot(src,v)
 elseif action=='billing' or action=='issueBill' or action=='waiveCharges' then
  return H.chart(src,v,action)
 elseif action=='procedure' then return beginOperation(src,v,region,item)
 elseif action~='treat' or type(region)~='string' or not validRegion(region) or not C.items[item] then return end
 local s=read(v.patient)
 if not s or s.life~=v.life or not M.observedTreatment(s,item,region,os.time(),v.examined[region],src==v.target) then return notify(src,'No eligible observed injury for that treatment') end
 local ok,has=inv:HasItem(src,item,1);if not ok or not has then return notify(src,'Missing '..C.items[item]) end
 local key=db('scalar','SELECT UUID()');if not key or not validView(src,v) or working[src] then return end
 key='med:'..key:gsub('-','')
 local w={view=v,key=key};working[src]=w;snapshot(src,v)
 SetTimeout(C.treatmentMs,function()
  if working[src]~=w then return end
  if not validView(src,v) then working[src]=nil;return notify(src,'Treatment interrupted') end
  local current=read(v.patient)
  if not current or current.life~=v.life or not M.observedTreatment(current,item,region,os.time(),v.examined[region],src==v.target) or not validView(src,v) then working[src]=nil;snapshot(src,v);return end
  -- Matches the inventory RemoveItem resource receipt exactly.
  local fp=json.encode({'change',false,v.actor,false,item,1,false})
  local queued=queue(v.patient,current,item,region,key,'resource:frontier_medical',fp)
  if queued and validView(src,v) then
   H.capture(src,v,key,item,region,current.life)
   if not validView(src,v) or working[src]~=w then return end
   local paid,why=inv:RemoveItem(src,item,1,nil,key)
   if not paid then notify(src,'Treatment not completed: '..tostring(why)) else notify(src,'Treatment submitted') end
  else notify(src,'Treatment interrupted') end
  if working[src]==w then working[src]=nil end
  snapshot(src,v)
  SetTimeout(1500,function() if validView(src,v) then snapshot(src,v) end end)
 end)
end)
-- Durable operations are paid before the challenge begins. The outbox uses the
-- exact inventory receipt and a patient-life CAS; an unpaid attempt has no effect.
local function releaseOperation(src,o)
 if operations[src]==o then operations[src]=nil end
 if patientLocks[o.patient]==o then patientLocks[o.patient]=nil end
 if working[src]==o then working[src]=nil end
end
local function operationValid(src,o)
 return operations[src]==o and working[src]==o and medic(src) and validView(src,o.view)
  and (src~=o.view.target or selfTest(src,o.view)) and os.time()<o.expires
end
finishOperation=function(src,o,outcome)
 if operations[src]~=o or o.finishing then return end
 o.finishing=true
 if not o.key then releaseOperation(src,o);return end
 if Q.isSuccessful(outcome) and not operationValid(src,o) then outcome='failed' end
 -- On DB uncertainty the row remains pending and expires as a paid failure.
 local n=db('update',[[UPDATE frontier_medical_operations SET outcome=? WHERE request_key=? AND outcome='pending' AND applied=FALSE]],{outcome,o.key})
 releaseOperation(src,o)
 if cid(src)==o.doctor then
  TriggerClientEvent(E..'operationEnd',src,o.key)
  notify(src,n==1 and (outcome=='success' and 'Perfect procedure; awaiting medical record.' or outcome=='acceptable' and 'Acceptable procedure; treatment completed safely.' or outcome=='complication' and 'Procedure complication. Reassess the patient.' or 'Procedure failed or interrupted.') or 'Procedure outcome pending.')
  if validView(src,o.view) then snapshot(src,o.view) end
 end
end
sendStage=function(src,o)
 if not operationValid(src,o) then return finishOperation(src,o,'failed') end
 o.stage=o.stage+1
 -- Vary the sweep slightly each stage. Keep both orange edges within the track.
 o.duration=math.max(1250,o.def.duration+math.random(-100,100)-(o.stage-1)*60)
 local margin=math.max(o.acceptable+90,math.floor(o.duration*.24))
 o.center=math.random(margin,o.duration-margin)
 o.ping=math.max(0,math.min(C.stagePingCapMs,tonumber(GetPlayerPing(src)) or 0))
 o.started=GetGameTimer()
 TriggerClientEvent(E..'operationStage',src,o.view.ticket,{key=o.key,stage=o.stage,total=o.def.stages,label=o.def.label,
  center=o.center,perfect=o.perfect,acceptable=o.acceptable,duration=o.duration,lead=C.stageLeadMs,previous=o.previous})
 local stage=o.stage
 SetTimeout(C.stageLeadMs+o.duration+o.ping+250,function()
  if operations[src]==o and o.stage==stage then finishOperation(src,o,'failed') end
 end)
end
beginOperation=function(src,v,r,id)
 local def=type(id)=='string' and C.procedures[id]
 if not def or not validRegion(r) or not medic(src) or not v.profExam[r] or (src==v.target and not selfTest(src,v)) then return notify(src,'Professional procedure unavailable.') end
 if working[src] or patientLocks[v.patient] then return notify(src,'A procedure is already in progress.') end
 -- Reserve the patient and actor before any yielding calls. Close/disconnect
 -- during setup cannot allow an unpaid challenge or a second operation.
 local o={view=v,patient=v.patient,doctor=v.actor,region=r,id=id,def=def,stage=0,expires=os.time()+C.operationSeconds}
 operations[src]=o;working[src]=o;patientLocks[v.patient]=o
 local function refuse(msg) releaseOperation(src,o);if cid(src)==v.actor then notify(src,msg) end end
 local current=read(v.patient)
 if not current or current.life~=v.life or not M.procedureEligible(current,r,id,os.time()) or not operationValid(src,o) then return refuse('Patient no longer eligible.') end
 local pending=db('scalar',[[SELECT COUNT(*) FROM frontier_medical_operations o
 LEFT JOIN frontier_inventory_receipts r ON r.request_key=o.request_key AND r.completed=TRUE AND BINARY r.actor=BINARY 'resource:frontier_medical' AND BINARY r.fingerprint=BINARY o.fingerprint
 WHERE o.patient=? AND o.applied=FALSE AND (o.expires_at>=? OR r.request_key IS NOT NULL)]],{v.patient,os.time()})
 if pending==nil or tonumber(pending)>0 then return refuse('A previous operation is still being resolved.') end
 local ok,has=inv:HasItem(src,def.supply,1)
 if not ok or not has then return refuse('Missing supply: '..def.supply) end
 if def.instrument then
  ok,has=inv:HasItem(src,def.instrument,1)
  if not ok or not has then return refuse('Missing instrument: '..def.instrument) end
 end
 local skillOk,skill=exports.frontier_skills:GetSkill(src,'doctoring')
 local level=skillOk and skill.level or 1
 o.perfect,o.acceptable=Q.windows(def,level)
 o.quality='success'
 local uuid=db('scalar','SELECT UUID()')
 if not uuid or not operationValid(src,o) then return refuse('Procedure interrupted.') end
 o.key='op:'..uuid:gsub('-','')
 o.life=current.life
 local fp=json.encode({'change',false,v.actor,false,def.supply,1,false})
 local inserted=db('update',[[INSERT INTO frontier_medical_operations(request_key,patient,life,doctor,region,procedure_id,fingerprint,expires_at,testing)
 VALUES(?,?,?,?,?,?,?,?,?)]],{o.key,v.patient,o.life,v.actor,r,id,fp,o.expires,testing(src) and 1 or 0})
 if inserted~=1 or not operationValid(src,o) then
  if inserted==1 then finishOperation(src,o,'failed') else refuse('Operation could not be recorded.') end
  return
 end
 H.capture(src,v,o.key,id,r,o.life)
 if not operationValid(src,o) then return finishOperation(src,o,'failed') end
 local paid,why=inv:RemoveItem(src,def.supply,1,nil,o.key)
 if not paid then
  finishOperation(src,o,'failed')
  if cid(src)==v.actor then notify(src,'Supply payment not confirmed: '..tostring(why)) end
  return
 end
 if not operationValid(src,o) then finishOperation(src,o,'failed');return end
 snapshot(src,v);sendStage(src,o)
end
RegisterNetEvent(E..'operationPress',function(key,stage)
 local src=source;local o=operations[src]
 if not o or o.key~=key or o.stage~=stage or not o.started or o.finishing then return end
 if not operationValid(src,o) then return finishOperation(src,o,'failed') end
 local elapsed=GetGameTimer()-o.started-C.stageLeadMs-o.ping;o.started=nil
 local result=Q.score(elapsed,o.center,o.perfect,o.acceptable,o.duration)
 if result=='failed' or result=='complication' then return finishOperation(src,o,result) end
 o.quality=Q.complete(o.quality,result);o.previous=result
 if o.stage>=o.def.stages then return finishOperation(src,o,o.quality) end
 sendStage(src,o)
end)
local function applyOperations()
 local now=os.time()
 local rows=db('query',[[SELECT o.* FROM frontier_medical_operations o JOIN frontier_inventory_receipts r
 ON r.request_key=o.request_key AND r.completed=TRUE AND BINARY r.actor=BINARY 'resource:frontier_medical' AND BINARY r.fingerprint=BINARY o.fingerprint
 WHERE o.applied=FALSE AND (o.outcome<>'pending' OR o.expires_at<=?) ORDER BY o.expires_at LIMIT 100]],{now}) or {}
 for _,o in ipairs(rows) do
  local state,rev=read(o.patient)
  if state then
   local result=o.outcome=='pending' and 'failed' or o.outcome
   local changed=tonumber(o.life)==state.life and M.applyProcedure(state,o.region,o.procedure_id,result,now)
   local xp=changed and Q.isSuccessful(result) and not (o.testing==true or tonumber(o.testing)==1)
   local n=db('update',[[UPDATE frontier_medical_state m JOIN frontier_medical_operations o ON o.patient=m.character_id
    JOIN frontier_inventory_receipts r ON r.request_key=o.request_key AND r.completed=TRUE AND BINARY r.actor=BINARY 'resource:frontier_medical' AND BINARY r.fingerprint=BINARY o.fingerprint
    LEFT JOIN frontier_medical_charges c ON c.request_key=o.request_key
   SET m.state=?,m.revision=m.revision+1,o.applied=TRUE,o.outcome=?,o.xp_due=?,c.eligible=IF(?=1,TRUE,FALSE)
    WHERE o.request_key=? AND o.applied=FALSE AND m.revision=? AND o.outcome=?]],
    {json.encode(state),result,xp and 1 or 0,xp and 1 or 0,o.request_key,rev,o.outcome})
   if n and n>0 then
    for _,p in pairs(core:GetPlayers()) do
     if p.frontierCharacterId==o.patient then publish(p.source,o.patient,state,rev+1);if changed then notify(p.source,Q.isSuccessful(result) and 'Professional treatment applied.' or 'Treatment complication.') end end
     if p.frontierCharacterId==o.doctor and Q.isSuccessful(result) and not changed then notify(p.source,'Treatment no longer applicable; supplies spent.') end
    end
   end
  end
 end
 local awards=db('query',[[SELECT request_key,doctor,procedure_id,outcome FROM frontier_medical_operations WHERE xp_due=TRUE AND xp_awarded=FALSE LIMIT 100]]) or {}
 for _,o in ipairs(awards) do
  local def=C.procedures[o.procedure_id]
  local xp=def and Q.xp(def.xp,o.outcome) or 0
  if xp>0 and exports.frontier_skills:GrantXP(o.doctor,'doctoring',xp,o.request_key) then
   db('update','UPDATE frontier_medical_operations SET xp_awarded=TRUE WHERE request_key=?',{o.request_key})
  end
 end
 -- Remove only old unpaid attempts, not paid receipts or unresolved outcomes.
 db('update',[[DELETE o FROM frontier_medical_operations o LEFT JOIN frontier_inventory_receipts r ON r.request_key=o.request_key
 WHERE o.applied=FALSE AND o.expires_at<? AND r.request_key IS NULL]],{now-86400})
end
-- The server console is an explicit trusted grant path. It does not depend
-- on transient player ACE principals. The grant is bound to one character
-- session and never grants any unrelated admin privileges.
local function testCommand(src,args)
 local target,mode
 if src==0 then
  target=tonumber(args[1]);mode=args[2]
  if not target or target%1~=0 or target<1 or (mode~='on' and mode~='off') then
   print('[frontier_medical] Usage: medictest <server ID> on|off');return
  end
 else
  target=src;mode=args[1]
  if not admin(src) then return notify(src,'Medic test access denied. Ask the server console to run medictest '..src..' on, or grant '..C.adminAce..'.') end
 end
 local id=cid(target)
 if not id then
  if src==0 then print('[frontier_medical] Player '..target..' has no loaded character.') else notify(src,'Load a character first.') end
  return
 end
 if operations[target] then
  if src==0 then print('[frontier_medical] Finish the operation first.') else notify(src,'Finish the operation first.') end
  return
 end
 if not mode then mode=testing(target) and 'off' or 'on' end
 if mode=='off' then testMedics[target]=nil
 elseif mode=='on' then testMedics[target]={id=id,console=src==0}
 else return notify(src,'Usage: /medictest on|off') end
 local message=mode=='on' and 'Temporary medic access enabled, including self-procedures.' or 'Temporary medic access disabled.'
 notify(target,message)
 print(('[frontier_medical] %s Player %d; professional=%s self-test=%s'):format(message,target,tostring(medic(target)),tostring(testing(target))))
 local view=views[target]
 if view and validView(target,view) then snapshot(target,view) end
end
RegisterCommand('medictest',testCommand,false)
RegisterCommand('medicaltest',testCommand,false)
RegisterCommand('medicstatus',function(src,args)
 local target=src==0 and tonumber(args[1]) or src
 if not target or target<=0 or target%1~=0 then print('[frontier_medical] Usage: medicstatus <server ID>');return end
 local message=('V2 professional access: %s | self-test: %s | medical admin ACE: %s | medic ACE: %s | character loaded: %s'):format(tostring(medic(target)),tostring(testing(target)),tostring(admin(target)),tostring(ace(target,C.medicAce)),tostring(cid(target)~=nil))
 print('[frontier_medical] Player '..target..' '..message)
 if src~=0 then notify(src,message) end
end,false)
RegisterCommand('medicalinjure',function(src,args)
 if src<=0 then return end
 if not admin(src) and not testing(src) then return notify(src,'Test injury access denied.') end
 if not ready or legacy() then return notify(src,'Medical system unavailable.') end
 local id=cid(src);if not id or death(src) or patientLocks[id] or working[src] then return notify(src,'Test character unavailable or undergoing treatment.') end
 local now=GetGameTimer();if testAt[src] and now-testAt[src]<1000 then return end;testAt[src]=now
 local r,kind=args[1],args[2]
 local reset=r=='reset'
 local raw=args[3] and tonumber(args[3]) or (not args[3] and 30)
 if not reset and (not validRegion(r) or type(kind)~='string' or type(raw)~='number' or raw%1~=0 or raw<1 or raw>200) then
  return notify(src,'Usage: /medicalinjure <region> <penetrating|blunt|fall|cut|burn|bite|fracture|internal|organ|bullet|splinter|deep|shock> [raw 1-200], or reset')
 end
 local pending=db('scalar',[[SELECT COUNT(*) FROM frontier_medical_operations o JOIN frontier_inventory_receipts r
 ON r.request_key=o.request_key AND r.completed=TRUE WHERE o.patient=? AND o.applied=FALSE]],{id})
 if pending==nil or tonumber(pending)>0 then return notify(src,'Wait for previous operation to resolve.') end
 for _=1,5 do
  local state,rev=read(id)
  if not state or state.dead or cid(src)~=id then return notify(src,'Test reset cannot resurrect a dead character.') end
  if reset then
   local new=M.new(state.life)
   new.reportToken=state.reportToken;new.reportSeq=state.reportSeq;state=new
  elseif not M.testInjury(state,r,kind,raw,os.time()) then return notify(src,'Invalid preset for region.') end
  if write(id,state,rev) then
   publish(src,id,state,rev+1);notify(src,reset and 'Test injuries reset.' or ('Test injury: '..r..' / '..kind));return
  end
 end
 notify(src,'Test update conflicted; retry.')
end,false)
local function tick(p)
 local src,id=p.source,p.frontierCharacterId
 if cid(src)~=id then return end
 local s,rev=read(id);if not s then return end
 local before=json.encode(s)
 local providerDead=death(src)
 local wasDead=s.dead
 s=M.reconcileProvider(s,providerDead)
 if not wasDead and not s.dead then
  local n=db('single','SELECT hunger,thirst FROM frontier_needs_state WHERE character_id=?',{id})
  M.tick(s,os.time(),n and tonumber(n.hunger)>100 and tonumber(n.thirst)>100)
 end
 if cid(src)~=id then return end
 if before~=json.encode(s) then if not write(id,s,rev) then return end;rev=rev+1 end
 publish(src,id,s,rev)
end
-- Emergency calls are independent of the medical chart, inventory, and native death UI.
-- No client can choose coordinates or declare someone unconscious.
local function position(src)
 local p=GetPlayerPed(src)
 if p==0 or not DoesEntityExist(p) then return end
 local c=GetEntityCoords(p)
 if not c then return end
 return {x=c.x,y=c.y,z=c.z}
end
local function downPatient(src)
 local v=cache[src]
 if not ready or legacy() or not v or cid(src)~=v.id or GetGameTimer()-(v.publishedAt or 0)>=C.stateTimeoutMs or not v.state.down or v.state.dead or death(src) then return end
 return v
end
local function responderReady(src)
 local v=cache[src]
 return board.duty[src]~=nil and board.duty[src]==cid(src) and v and GetGameTimer()-(v.publishedAt or 0)<C.stateTimeoutMs and medic(src) and capable(src)
end
local function marker(src,call)
 TriggerClientEvent(E..'dispatchMarker',src,call.number,call.pos)
end
local function clearMarker(src,call)
 TriggerClientEvent(E..'dispatchClear',src,call.number)
end
local function announce(call,except)
 local count=0
 for src in pairs(board.duty) do
  if src~=except and src~=call.source and responderReady(src) and GetPlayerRoutingBucket(src)==call.bucket then
   count=count+1
   notify(src,('Emergency #%d: unconscious patient (ID %d). /medicaccept %d'):format(call.number,call.source,call.number))
  end
 end
 call.lastNotice=GetGameTimer()
 return count
end
local function closeCall(call,reason)
 if not D.close(board,call) then return end
 if call.responder and cid(call.responder)==call.responderId then
  clearMarker(call.responder,call);notify(call.responder,('Emergency #%d closed: %s.'):format(call.number,reason))
 end
 if cid(call.source)==call.patient then
  TriggerClientEvent(E..'dispatchPatient',call.source,false)
  notify(call.source,('Emergency #%d closed: %s.'):format(call.number,reason))
 end
end
local function releaseCall(call,reason)
 local src,id=D.release(call)
 if src and cid(src)==id then clearMarker(src,call);notify(src,('Emergency #%d released: %s.'):format(call.number,reason)) end
 if cid(call.source)==call.patient then
  TriggerClientEvent(E..'dispatchPatient',call.source,true,'Awaiting an available medic.')
  notify(call.source,'Your emergency call is awaiting another medic.')
 end
 announce(call,src)
end
local function openCall(src,v)
 local pos=position(src);if not pos then return end
 local bucket=GetPlayerRoutingBucket(src)
 local old=board.calls[src]
 if old and not D.same(old,v.id,v.state.life,bucket) then closeCall(old,'patient session changed') end
 local call,created=D.open(board,src,v.id,v.state.life,bucket,pos)
 if created then
  local count=announce(call)
  local msg=count>0 and 'Emergency call sent. Awaiting an available medic.' or 'Emergency call queued. No on-duty medic is currently available.'
  TriggerClientEvent(E..'dispatchPatient',src,true,msg);notify(src,msg)
 end
 return call,created
end
dispatchPublish=function(src,id,state)
 local call=board.calls[src]
 if not state.down or state.dead then
  if call then closeCall(call,state.dead and 'patient died' or 'patient regained consciousness') end
  return
 end
 if death(src) then if call then closeCall(call,'patient died') end;return end
 if C.dispatch.automatic then openCall(src,{id=id,state=state}) end
end
dispatchClear=function(src)
 local own=board.calls[src]
 if own then closeCall(own,'patient disconnected or changed character') end
 board.duty[src]=nil
 for _,call in pairs(board.calls) do if call.responder==src then releaseCall(call,'medic unavailable') end end
end
dispatchTick=function()
 for src in pairs(board.duty) do
  if board.duty[src]~=cid(src) or not medic(src) then board.duty[src]=nil end
 end
 for _,call in pairs(board.calls) do
  local v=downPatient(call.source)
  if not v or not D.same(call,v.id,v.state.life,GetPlayerRoutingBucket(call.source)) then
   closeCall(call,'patient no longer unconscious or unavailable')
  else
   if call.responder and (not responderReady(call.responder) or call.responderId~=cid(call.responder) or GetPlayerRoutingBucket(call.responder)~=call.bucket) then
    releaseCall(call,'medic unavailable')
   end
   local pos=position(call.source)
   if pos then
    local a=call.pos;local distance=(a.x-pos.x)^2+(a.y-pos.y)^2+(a.z-pos.z)^2
    if distance>=C.dispatch.markerMove^2 then call.pos=pos;if call.responder then marker(call.responder,call) end end
   end
   if not call.responder and GetGameTimer()-(call.lastNotice or 0)>=C.dispatch.reminderMs then announce(call) end
  end
 end
end
RegisterCommand('mediccall',function(src,args)
 if src<=0 then return end
 local target=args[1] and tonumber(args[1]) or (not args[1] and src)
 if not target or target%1~=0 or target<1 then return notify(src,'Usage: /mediccall [patient ID]') end
 if target~=src and (not capable(src) or not nearby(src,target)) then return notify(src,'Stand beside the unconscious patient.') end
 local v=downPatient(target)
 if not v then return notify(src,'Only a living unconscious patient can request emergency help.') end
 local call,created=openCall(target,v)
 if not call then return notify(src,'Patient location unavailable.') end
 if target~=src or not created then notify(src,('Emergency #%d %s.'):format(call.number,created and 'sent' or 'already active')) end
end,false)
local function setDuty(src,mode,station)
 if src<=0 then return end
 if not medic(src) then return notify(src,'Medic licence or temporary medic access required.') end
 mode=mode or (board.duty[src] and 'off' or 'on')
 if mode=='off' then
  board.duty[src]=nil;H.dutyStation[src]=nil
  for _,call in pairs(board.calls) do if call.responder==src then releaseCall(call,'medic off duty') end end
  notify(src,'You are off duty.');return true
 end
 if mode~='on' then return notify(src,'Usage: /medicduty on|off') end
 if not capable(src) then return notify(src,'You must be conscious to go on duty.') end
 if board.duty[src]==cid(src) then return true end
 board.duty[src]=cid(src);H.dutyStation[src]=station or 'field';notify(src,'You are on duty. Use /mediccalls to see open emergencies.')
 for _,call in pairs(board.calls) do
  if not call.responder and call.bucket==GetPlayerRoutingBucket(src) and downPatient(call.source) then
   notify(src,('Emergency #%d: unconscious patient (ID %d). /medicaccept %d'):format(call.number,call.source,call.number))
  end
 end
 return true
end
RegisterCommand('medicduty',function(src,args)
 if src<=0 then return end
 if not testing(src) and not admin(src) then return notify(src,'Register for service at a hospital counter.') end
 setDuty(src,args[1])
end,false)
RegisterCommand('mediccalls',function(src)
 if src<=0 then return end
 if not responderReady(src) then return notify(src,'Go on duty with /medicduty on first.') end
 local count=0
 for _,call in pairs(board.calls) do
  if call.bucket==GetPlayerRoutingBucket(src) and downPatient(call.source) then
   count=count+1;notify(src,('Emergency #%d · patient ID %d · %s'):format(call.number,call.source,call.responder==src and 'assigned to you' or call.responder and 'assigned' or 'open'))
  end
 end
 if count==0 then notify(src,'No active emergencies in your area.') end
end,false)
RegisterCommand('medicaccept',function(src,args)
 if src<=0 then return end
 if not responderReady(src) then return notify(src,'Go on duty with /medicduty on first.') end
 local number=tonumber(args[1]);local call=number and D.find(board,number)
 local v=call and downPatient(call.source)
 if not v or not D.same(call,v.id,v.state.life,GetPlayerRoutingBucket(call.source)) then return notify(src,'Emergency no longer available.') end
 local ok,why=D.claim(board,call,src,cid(src),GetPlayerRoutingBucket(src))
 if not ok then return notify(src,why=='busy' and 'Release your current call first.' or 'Emergency already assigned or unavailable.') end
 local pos=position(call.source);if pos then call.pos=pos end
 marker(src,call);notify(src,('Emergency #%d accepted. Patient marked on your map. Use /medical %d when nearby.'):format(call.number,call.source))
 TriggerClientEvent(E..'dispatchPatient',call.source,true,'A medic has accepted your emergency call.')
 notify(call.source,'A medic has accepted your emergency call.')
end,false)
RegisterCommand('medicrelease',function(src)
 if src<=0 then return end
 for _,call in pairs(board.calls) do
  if call.responder==src and call.responderId==cid(src) then releaseCall(call,'medic released the call');return end
 end
 notify(src,'You have no assigned emergency.')
end,false)
local function clear(src)
 dispatchClear(src);H.clear(src)
 local o=operations[src]
 if o then
  -- On disconnect the durable operation expires as a failure. No client
  -- identity or payment can be reused to finish it after reconnect.
  releaseOperation(src,o)
 end
 testMedics[src]=nil;testAt[src]=nil
 cache[src]=nil;views[src]=nil;working[src]=nil;reports[src]=nil;lastOpen[src]=nil;lastAction[src]=nil
end
AddEventHandler('playerDropped',function() clear(tonumber(source) or source) end)
AddEventHandler('frontier:playerUnloaded',function(p) clear(p.source) end)
H.init({db=db,cid=cid,medic=medic,testing=testing,ace=ace,capable=capable,nearby=nearby,validView=validView,notify=notify,
 duty=function(src) return board.duty[src]~=nil and board.duty[src]==cid(src) and medic(src) end,setDuty=setDuty,
 snapshot=snapshot,legacy=legacy,position=position,views=views,working=working,board=board})
MySQL.ready(function()
 while not ready do
  ready=db('query','SELECT character_id FROM frontier_medical_state LIMIT 0')~=nil and db('query','SELECT request_key FROM frontier_medical_treatments LIMIT 0')~=nil and db('query','SELECT request_key FROM frontier_medical_operations LIMIT 0')~=nil and H.schema()
  if not ready then print('[frontier_medical] Apply sql/migrations/001_medical.sql, 002_professional.sql, 003_hospital.sql and economy 007');Wait(5000) end
 end
 CreateThread(function() while true do if not legacy() then applyTreatments();applyOperations() end;Wait(1000) end end)
 while true do
  if not legacy() then
   for _,p in pairs(core:GetPlayers()) do local ok,err=pcall(tick,p);if not ok then print('[frontier_medical] '..tostring(err)) end end
  else cache={};reports={} end
  local dispatchOk,dispatchErr=pcall(dispatchTick)
  if not dispatchOk then print('[frontier_medical] Dispatch refresh failed: '..tostring(dispatchErr)) end
  for src,v in pairs(views) do
   if not validView(src,v) then
    if operations[src] then finishOperation(src,operations[src],'failed') end
    views[src]=nil;working[src]=nil;TriggerClientEvent(E..'closeView',src,v.ticket)
   else
    local ok,err=pcall(snapshot,src,v)
    if not ok then print('[frontier_medical] View refresh failed: '..tostring(err)) end
   end
  end
  Wait(C.tickMs)
 end
end)
