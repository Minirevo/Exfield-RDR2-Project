local C,R=StationConfig,StationRules
local P,B,I,K,ECO=exports.frontier_property,exports.frontier_business,exports.frontier_inventory,exports.frontier_skills,exports.frontier_economy
local core=exports.frontier_core
local E='frontier_production:station:'
local Q,S,U=MySQL.query.await,MySQL.single.await,MySQL.update.await
local ready,busy=false,false
local views,work,intents,last={},{},{},{}
local active="('queued','reserve','wage','manual','running','output','xp','return')"
local function cid(src)return core:GetPlayerCharacterId(src)end
local function now()return os.time()end
local function tell(src,msg)TriggerClientEvent(E..'notice',src,tostring(msg))end
local function check(ok,msg)if not ok then error(msg or 'Denied',0)end end
local function id(v)return type(v)=='string' and #v==32 and v:match('^[a-f0-9]+$')end
local function uuid()
 local raw=MySQL.scalar.await('SELECT UUID()');check(type(raw)=='string','Database UUID unavailable')
 local k=raw:gsub('-',''):lower();check(id(k),'Invalid database UUID');return k
end
local function run(src,fn)
 if not ready then if src then tell(src,'Production stations not ready. Apply migration 002_stations.sql.') end;return end
 if busy then if src then tell(src,'Production busy; try again.') end;return end
 busy=true;local ok,err=pcall(fn);busy=false
 if not ok then
  print('[frontier_production/stations] '..tostring(err))
  if src then tell(src,err) end
 end
end
local function row(station)return S('SELECT * FROM frontier_production_stations WHERE id=?',{station})end
local function job(k)return S('SELECT * FROM frontier_production_station_jobs WHERE id=?',{k})end
local function count(station)return tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM frontier_production_station_jobs WHERE station_id=? AND state IN '..active,{station})) or 0 end
local function characterBusy(who)return MySQL.scalar.await("SELECT id FROM frontier_production_station_jobs WHERE actor=? AND mode='manual' AND state IN "..active.." LIMIT 1",{who})~=nil end
local function validStock(st,stock)
 return type(stock)=='string' and stock~='' and B:ProductionStockValid(st.plot_id,st.owner_type,st.owner_id,stock)
end
local function ownerAccess(st,who,manage)
 return B:ProductionAccess(who,st.plot_id,st.owner_type,st.owner_id,manage)==true
end
local function canUse(src,st)
 local p=P:ProductionStation(src,st.plot_id,st.id,st.grantor)
 if not p then return nil end
 local who=cid(src);if not who then return nil end
 local own=ownerAccess(st,who,false)
 if not own and not (st.owner_type=='character' and p.canWork) then return nil end
 return p,own,p.isOwner and (st.owner_type=='character' or ownerAccess(st,who,true))
end
local function validStation(st)
 return st and P:ProductionStation(false,st.plot_id,st.id,st.grantor) and (st.owner_type=='character' or ownerAccess(st,st.grantor,false))
end
local function getBank(st,src)
 if st.owner_type=='company' then return B:GetCompanyAccount(st.owner_id,cid(src),'finance') end
 local ok,a=ECO:GetCharacterAccounts(src);if ok and a.characterId==st.owner_id then return a.bank.id end
end
local function getCounts(src,stock)
 local ok,box
 if stock then ok,box=I:GetStorageContents(stock) else ok,box=I:GetInventory(src) end
 local out={};if ok then for _,v in pairs(box.slots or {}) do out[v.item]=(out[v.item] or 0)+v.quantity end end
 return out,ok
end
local function recipes(kind)
 local out={}
 for _,v in pairs(C.recipes) do if v.station==kind then out[#out+1]=v end end
 table.sort(out,function(a,b)return a.name<b.name end);return out
end
local function snapshot(src,st,p,owns,manage)
 local who=cid(src)
 local bag=getCounts(src)
 local stocks=owns and B:ProductionStocks(who,st.plot_id,st.owner_type,st.owner_id) or {}
 local input=owns and validStock(st,st.input_stock) and getCounts(src,st.input_stock) or {}
 local jobs=Q('SELECT id,actor,mode,state,payload,due_at,issue FROM frontier_production_station_jobs WHERE station_id=? ORDER BY created_at DESC,id DESC LIMIT 25',{st.id})
 local list={}
 for _,j in ipairs(jobs) do
  local d=json.decode(j.payload)
  if owns or j.actor==who then list[#list+1]={id=j.id,mode=j.mode,state=j.state,name=d.name,batches=d.batches,duration=d.duration,remaining=math.max(0,tonumber(j.due_at)-now()),issue=j.issue,cancel=(manage or owns or j.actor==who) and (j.state=='queued' or j.state=='manual' or j.state=='running')} end
 end
 local companies=p.isOwner and B:ProductionCompanies(who,st.plot_id) or {}
 local ok,skill=K:GetSkill(src,p.skill)
 local readyInput=owns and validStock(st,st.input_stock) or false
 local readyOutput=owns and validStock(st,st.output_stock) or false
 return {station={id=st.id,name=p.name,plot=p.plotName,kind=p.kind,ownerType=st.owner_type,ownerId=st.owner_id,employee=tonumber(st.employee)==1,input=st.input_stock,output=st.output_stock},
  recipes=recipes(p.kind),bag=bag,inputCounts=input,stocks=stocks,companies=companies,manage=manage==true,owns=owns==true,canNpc=owns and readyInput and readyOutput and tonumber(st.employee)==1 and getBank(st,src)~=nil,
  inputReady=readyInput,outputReady=readyOutput,skill=ok and skill.level or 1,jobs=list,maxBatches=C.maxBatches,wage=ProductionConfig.WageMinor,wageInterval=ProductionConfig.WageIntervalSeconds}
end
local function reply(src,view,seq,ok,msg,state)
 TriggerClientEvent(E..'response',src,view.ticket,seq,{ok=ok,message=msg,snapshot=state})
end
local function state(j,to,issue,due)
 U('UPDATE frontier_production_station_jobs SET state=?,issue=?,due_at=?,retry_at=0 WHERE id=? AND state=?',{to,issue or '',due or 0,j.id,j.state})
end
local function defer(j,issue)
 U('UPDATE frontier_production_station_jobs SET issue=?,retry_at=? WHERE id=? AND state=?',{tostring(issue):sub(1,100),now()+5,j.id,j.state})
end
local function transfer(j,action,route,items)
 return I:ApplyStationProduction(action,j.id,'station:'..j.id..':'..action,{route=route,items=items})
end
local function clearWork(src,msg)
 local w=work[src];work[src]=nil
 if w then TriggerClientEvent(E..'end',src,msg or '') end
end
local function stockRoute(st,d,which,src)
 local choice=d[which]
 if choice=='bag' then return 'p_'..cid(src) end
 local stock=which=='input' and st.input_stock or st.output_stock
 if choice=='storage' and validStock(st,stock) then return 's_'..stock end
end
local function routeValid(st,route)
 return route:sub(1,2)=='p_' or validStock(st,route:sub(3))
end
local function companyStockRight(st,who,perm)
 return st.owner_type~='company' or B:HasCompanyPermission(st.owner_id,who,perm)==true
end
local function labour(src,skill,batches,key)
 if GetResourceState('frontier_needs')~='started' then return false,'Needs unavailable' end
 if key then return exports.frontier_needs:SpendLabour(src,skill,key,batches) end
 return exports.frontier_needs:CanWork(src,skill,batches)
end
local function start(src,st,p,owns,d,key)
 local who=cid(src);local r=C.recipes[d.recipe];local n=tonumber(d.batches)
 check(r and r.station==p.kind and n and n%1==0 and n>=1 and n<=C.maxBatches,'Invalid recipe or batch count')
 check(d.mode=='manual' or d.mode=='npc','Invalid production mode')
 local npc=d.mode=='npc'
 if r.manualOnly then check(not npc and n==1,'Specialist work requires one manual item') end
 local design
 if r.quality=='weapon' then local why;design,why=GunCraft.design(r,d.design);check(design,why) end
 if npc then
  check(owns and tonumber(st.employee)==1 and validStock(st,st.input_stock) and validStock(st,st.output_stock),'Hire a worker and link both stock chests')
  check(count(st.id)<C.maxQueue,'Station queue full')
  check(not MySQL.scalar.await("SELECT id FROM frontier_production_station_jobs WHERE station_id=? AND mode='manual' AND state IN "..active.." LIMIT 1",{st.id}),'Manual work in progress')
 else
  check(count(st.id)==0 and not characterBusy(who),'Finish the current work first')
  check(owns or (d.input=='bag' and d.output=='bag'),'Members must use their own inventory')
  local fit,why=labour(src,r.skill,n);check(fit,why)
 end
 local input=npc and 's_'..st.input_stock or stockRoute(st,d,'input',src)
 local output=npc and 's_'..st.output_stock or stockRoute(st,d,'output',src)
 check(input and output,'Select valid input and output')
 if input:sub(1,2)=='s_' then check(companyStockRight(st,who,'stock'),'Stock permission required') end
 if output:sub(1,2)=='s_' then check(companyStockRight(st,who,'deposit'),'Deposit permission required') end
 if input:sub(1,2)=='s_' and output:sub(1,2)=='p_' then check(companyStockRight(st,who,'retrieve'),'Retrieve permission required') end
 local bank=npc and getBank(st,src) or 0;check(bank,'Wage account unavailable or finance permission missing')
 local ok,skill
 if npc then ok,skill=K:GetCharacterSkill(st.grantor,r.skill) else ok,skill=K:GetSkill(src,r.skill) end
 check(ok,'Skill data unavailable')
 if design then local copy={};for k,v in pairs(r) do copy[k]=v end;copy.inputs=design.inputs;copy.design=design;r=copy end
 local roundMs,sweepMs,width=R.timing(r,skill.level)
 local m=R.materials(r,n);local counts,known=getCounts(src,input:sub(1,2)=='s_' and input:sub(3) or nil)
 check(known,'Input stock unavailable')
 for _,v in ipairs(m) do check((counts[v.id] or 0)>=v.count,'Missing '..v.id..': '..(v.count-(counts[v.id] or 0))) end
 local duration=(npc and r.npc or r.rounds*roundMs/1000)*n
 local payload={recipe=r.id,recipeSnapshot={output=r.output,quantity=r.quantity,quality=r.quality,material=r.material,design=design},rounds=r.rounds,roundMs=roundMs,sweepMs=sweepMs,width=width,stages=r.stages,name=r.name,batches=n,inputs=m,input=input,output=output,skill=r.skill,level=skill.level,equipment=p.equipment,
  maker=p.plotName or 'Workshop',duration=duration,wage=npc and math.ceil(duration*ProductionConfig.WageMinor/ProductionConfig.WageIntervalSeconds) or 0,bank=bank}
 if npc then payload.outputs=R.outputs(r,n,skill.level,'npc',0,p.equipment,payload.maker) end
 U("INSERT INTO frontier_production_station_jobs(id,station_id,actor,mode,state,payload,created_at) VALUES(?,?,?,?,'queued',?,?)",{key,st.id,who,d.mode,json.encode(payload),now()})
 if not npc then intents[key]=src end
 return 'Order submitted'
end
local function action(src,st,p,owns,manage,name,d,key)
 local who=cid(src)
 if name=='refresh' then return 'Updated' end
 if name=='setup' then
  check(p.isOwner and manage and count(st.id)==0,'Plot owner and idle station required')
  local company=d.company or '';check(type(company)=='string','Invalid company')
  local typ,owner='character',who
  if company~='' then
   check(id(company) and B:ProductionAccess(who,st.plot_id,'company',company,true) and B:ProductionAccess(who,st.plot_id,'company',company,false),'Company manufacturing grant/license required')
   typ,owner='company',company
  end
  U("UPDATE frontier_production_stations SET owner_type=?,owner_id=?,grantor=?,input_stock='',output_stock='',employee=0 WHERE id=?",{typ,owner,who,st.id})
  return 'Ownership updated; link stock again'
 elseif name=='link' then
  check(manage and owns and count(st.id)==0,'Only management may link an idle station')
  local input,output=d.input or '',d.output or ''
  check(type(input)=='string' and type(output)=='string' and (input=='' or validStock(st,input)) and (output=='' or validStock(st,output)),'Select same-owner registered stock on this plot')
  U('UPDATE frontier_production_stations SET input_stock=?,output_stock=? WHERE id=?',{input,output,st.id})
  return 'Storage linked'
 elseif name=='hire' or name=='dismiss' then
  check(manage and owns and count(st.id)==0,'Management and idle station required')
  if name=='hire' then check(validStock(st,st.input_stock) and validStock(st,st.output_stock) and getBank(st,src),'Link storage and authorize wage account first') end
  U('UPDATE frontier_production_stations SET employee=? WHERE id=?',{name=='hire' and 1 or 0,st.id});return 'Staff updated'
 elseif name=='release' then
  check(manage and count(st.id)==0,'Resolve all outstanding jobs before release')
  U('DELETE FROM frontier_production_stations WHERE id=?',{st.id});views[src]=nil;TriggerClientEvent(E..'close',src);return 'Station released'
 elseif name=='start' then return start(src,st,p,owns,d,key)
 elseif name=='cancel' then
  check(id(d.job),'Invalid job');local j=job(d.job)
  check(j and j.station_id==st.id and (manage or owns or j.actor==who),'Denied')
  if j.state=='queued' then intents[j.id]=nil;state(j,'cancelled')
  elseif j.state=='running' or j.state=='manual' then
   for player,w in pairs(work) do if w.id==j.id then clearWork(player,'Work cancelled') end end
   state(j,'return')
  else check(false,'Job cannot be cancelled during an atomic transfer or completed output') end
  return 'Cancellation requested'
 end
 check(false,'Unknown action')
end
RegisterNetEvent(E..'open',function(sid,fid)
 local src=source;if not id(sid) or not id(fid) then return end
 run(src,function()
  local who=cid(src);local p=P:ProductionStation(src,sid,fid)
  check(who and p,'Approach a placed station')
  local st=row(fid)
  if not st then
   check(p.isOwner,'Plot owner must initialize this station first')
   U("INSERT INTO frontier_production_stations(id,plot_id,owner_type,owner_id,grantor) VALUES(?,?,'character',?,?)",{fid,sid,who,who})
   st=row(fid)
  end
  check(st and st.plot_id==sid,'Station unavailable')
  local physical,owns,manage=canUse(src,st);check(physical,'No permission to operate this station')
  local view={station=fid,ticket=uuid(),actor=who,seq=0};views[src]=view
  TriggerClientEvent(E..'view',src,view.ticket,snapshot(src,st,physical,owns,manage))
 end)
end)
RegisterNetEvent(E..'request',function(ticket,seq,name,d)
 local src=source;local v=views[src]
 if not v or v.ticket~=ticket or v.actor~=cid(src) or type(seq)~='number' or seq%1~=0 or seq<1 or seq>2147483647 or type(name)~='string' or type(d)~='table' then return end
 if busy then return reply(src,v,seq,false,'Production busy; try again') end
 if seq==v.seq and v.response then return reply(src,v,seq,v.response.ok,v.response.msg,v.response.snapshot) end
 if seq<=v.seq then return end
 local tick=GetGameTimer();if last[src] and tick-last[src]<250 then return reply(src,v,seq,false,'Please wait briefly') end;last[src]=tick
 run(src,function()
  local st=row(v.station)
  local p,owns,manage;if st then p,owns,manage=canUse(src,st) end
  if not p then return reply(src,v,seq,false,'Move closer or check station permission') end
  local key=v.ticket:sub(1,24)..('%08x'):format(seq)
  local ok,msg=pcall(action,src,st,p,owns,manage,name,d,key)
  local fresh
  if views[src]==v then
   local loaded=row(st.id);local np,no,nm;if loaded then np,no,nm=canUse(src,loaded) end
   if np then local worked,x=pcall(snapshot,src,loaded,np,no,nm);if worked then fresh=x end end
   v.seq=seq;v.response={ok=ok,msg=tostring(msg),snapshot=fresh};reply(src,v,seq,ok,tostring(msg),fresh)
  end
 end)
end)
RegisterNetEvent(E..'close',function(ticket)local src=source;if views[src] and views[src].ticket==ticket then views[src]=nil end end)
RegisterNetEvent(E..'strike',function(k,round)
 local src=source;local w=work[src]
 if not w or w.id~=k or w.actor~=cid(src) or type(round)~='number' or round%1~=0 or round<1 or round>#w.targets or w.scores[round]~=nil then return end
 local elapsed=GetGameTimer()-w.started
 -- Server clock only. No client-provided score, hit location or timestamp.
 local score=R.roundScore(elapsed,round,w.roundMs,w.sweepMs,w.targets[round],w.width)
 if score==nil then return end
 w.scores[round]=score
 TriggerClientEvent(E..'strikeResult',src,k,round,score)
end)
RegisterNetEvent(E..'finish',function(k)
 local src=source;local w=work[src];if not w or w.id~=k then return end
 run(src,function()
  local j=job(k);local st=j and row(j.station_id)
  if not j or j.state~='manual' or j.actor~=cid(src) then clearWork(src,'Work unavailable');return end
  local d=json.decode(j.payload);local p=st and canUse(src,st)
  local elapsed=GetGameTimer()-w.started
  if elapsed<w.ms then return end -- early finish request cannot consume or cancel an active batch
  if not p or elapsed>w.ms+12000 then state(j,'return','Work interrupted');clearWork(src,'Work interrupted; ingredients will be returned');return end
  local r=d.recipeSnapshot or C.recipes[d.recipe];check(r,'Recipe unavailable')
  local paid,why=labour(src,d.skill,d.batches,j.id)
  if not paid then state(j,'return',why);clearWork(src,why..'; ingredients will be returned');return end
  local scores={};for batch=1,d.batches do scores[batch]=R.batchScore(w.scores,batch,w.rounds) end
  if r.quality=='weapon' then d.outputs=GunCraft.output(r,d.level,scores[1],d.equipment,d.maker,j.actor,w.scores)
  else d.outputs=R.outputs(r,d.batches,d.level,'manual',scores,d.equipment,d.maker) end
  U("UPDATE frontier_production_station_jobs SET payload=?,state='output',due_at=0,retry_at=0 WHERE id=? AND state='manual'",{json.encode(d),k})
  clearWork(src,'Work finished; delivering product')
 end)
end)
RegisterNetEvent(E..'cancel',function(k)
 local src=source;local w=work[src];if not w or w.id~=k then return end
 run(src,function()local j=job(k);if j and j.state=='manual' then state(j,'return','Manual work cancelled') end;clearWork(src,'Ingredients will be returned')end)
end)
local function step(j)
 local st=row(j.station_id);local d=json.decode(j.payload)
 if j.state=='queued' then
  local earlier=MySQL.scalar.await("SELECT id FROM frontier_production_station_jobs WHERE station_id=? AND id<>? AND state IN ('reserve','wage','manual','running','output','xp','return') LIMIT 1",{j.station_id,j.id})
  if earlier then return defer(j,'Waiting for station') end
  local first=MySQL.scalar.await("SELECT id FROM frontier_production_station_jobs WHERE station_id=? AND state='queued' ORDER BY created_at,id LIMIT 1",{j.station_id})
  if first~=j.id then return defer(j,'Waiting for earlier order') end
  if not validStation(st) or not routeValid(st,d.input) or not routeValid(st,d.output) then return state(j,'rejected','Station or storage no longer authorized') end
  if j.mode=='manual' and (not intents[j.id] or cid(intents[j.id])~=j.actor or not canUse(intents[j.id],st)) then intents[j.id]=nil;return state(j,'cancelled','Manual work not started') end
  state(j,'reserve')
 elseif j.state=='reserve' then
  -- Resolve the persisted reservation intent even after restart, then return if no longer authorized.
  local ok,err=transfer(j,'reserve',d.input,d.inputs)
  if not ok then
   if err=='insufficient_stock' then intents[j.id]=nil;state(j,'rejected',err) else defer(j,err) end;return
  end
  if not validStation(st) or not routeValid(st,d.input) or not routeValid(st,d.output) then return state(j,'return','Authorization changed') end
  if j.mode=='npc' then state(j,'wage')
  else
   local src=intents[j.id];intents[j.id]=nil
   if not src or cid(src)~=j.actor or not canUse(src,st) then return state(j,'return','Player unavailable') end
   local fit,why=labour(src,d.skill,d.batches);if not fit then return state(j,'return',why) end
   local rounds=d.rounds or 1;local roundMs=d.roundMs or C.roundMs;local sweepMs=d.sweepMs or C.sweepMs
   local targets={};for i=1,rounds*d.batches do targets[i]=math.random(25,75)/100 end
   local w={id=j.id,actor=j.actor,ms=roundMs*#targets,rounds=rounds,roundMs=roundMs,sweepMs=sweepMs,width=d.width or .18,targets=targets,scores={},station=j.station_id}
   state(j,'manual','',now()+math.ceil(w.ms/1000)+12)
   w.started=GetGameTimer();work[src]=w;views[src]=nil
   TriggerClientEvent(E..'work',src,{id=j.id,label=d.name,ms=w.ms,targets=targets,rounds=rounds,batches=d.batches,roundMs=roundMs,sweepMs=sweepMs,width=d.width or C.targetWidth,stages=d.stages,kind=(C.recipes[d.recipe] or {}).station})
  end
 elseif j.state=='wage' then
  -- Ledger receipt makes a crash between debit and state transition safe.
  local ok,err=ECO:DebitAccount(tonumber(d.bank),d.wage,{key='station:'..j.id..':wage',reason='Production worker wage',reference=j.id})
  if ok then state(j,'running','',now()+d.duration)
  elseif err=='insufficient_funds' then state(j,'return','Insufficient wage funds') else defer(j,err) end
 elseif j.state=='running' then
  if not validStation(st) then return state(j,'return','Station authorization revoked') end
  if tonumber(j.due_at)<=now() then state(j,'output') end
 elseif j.state=='manual' then
  local player
  for src,w in pairs(work) do if w.id==j.id then player=src;break end end
  if not player or not st or not canUse(player,st) or cid(player)~=j.actor or now()>tonumber(j.due_at) then
   if player then clearWork(player,'Work interrupted') end;state(j,'return','Manual work interrupted')
  end
 elseif j.state=='output' then
  if not validStation(st) or not routeValid(st,d.output) then return defer(j,'Output destination unavailable; restore authorization') end
  local ok,err=transfer(j,'finish',d.output,d.outputs)
  if ok then state(j,j.mode=='manual' and 'xp' or 'complete');for _,player in pairs(core:GetPlayers()) do if player.frontierCharacterId==j.actor then tell(player.source,'Finished: '..d.name..' × '..d.batches) end end else defer(j,err) end
 elseif j.state=='xp' then
  local ok,err=K:GrantXP(j.actor,d.skill,20*d.batches,j.id)
  if ok then state(j,'complete') else defer(j,err) end
 elseif j.state=='return' then
  -- Always return reserved ingredients to the original container, never to a new owner.
  local ok,err=transfer(j,'return',d.input)
  if ok then state(j,'cancelled',j.issue) else defer(j,err) end
 end
end
exports('StationBound',function(fid)
 if GetInvokingResource()~='frontier_property' or not ready then return true end
 return row(fid)~=nil
end)
exports('StorageBound',function(stock)
 if GetInvokingResource()~='frontier_business' or not ready then return true end
 return MySQL.scalar.await('SELECT id FROM frontier_production_stations WHERE input_stock=? OR output_stock=? LIMIT 1',{stock,stock})~=nil
end)
AddEventHandler('frontier:playerUnloaded',function(p)views[p.source]=nil;work[p.source]=nil end)
AddEventHandler('playerDropped',function()local src=source;views[src]=nil;work[src]=nil;last[src]=nil end)
MySQL.ready(function()
 while not ready do
  local ok,err=pcall(function()
   Q('SELECT id FROM frontier_production_stations LIMIT 1');Q('SELECT id FROM frontier_production_station_jobs LIMIT 1')
   for key,def in pairs(C.items) do local saved,why=I:RegisterItem(key,def);check(saved,key..': '..tostring(why)) end
  end)
  if ok then ready=true;print('[frontier_production/stations] ready') else print('[frontier_production/stations] '..tostring(err));Wait(5000) end
 end
 while true do
  Wait(C.tickMs)
  if ProductionConfig.Enabled then run(nil,function()
   local jobs=Q('SELECT * FROM frontier_production_station_jobs WHERE state IN '..active..' AND retry_at<=? ORDER BY created_at,id LIMIT 100',{now()})
   for _,j in ipairs(jobs) do local ok,err=pcall(step,j);if not ok then print('[frontier_production/stations] job '..j.id..': '..tostring(err));defer(j,'Worker error; see server console') end end
  end) end
 end
end)

RegisterCommand('productiondiagnostics',function(src)
 if src~=0 and not core:HasPermission(src,'frontier.production.admin') then return end
 local function report(msg)if src==0 then print(msg) else tell(src,msg) end end
 if not ready then return report('Production stations not ready') end
 for _,j in ipairs(Q("SELECT id,station_id,mode,state,issue FROM frontier_production_station_jobs WHERE state IN "..active.." ORDER BY created_at LIMIT 50")) do
  report(j.id..' station='..j.station_id..' '..j.mode..' '..j.state..' '..j.issue)
 end
 report('Do not delete pending jobs or change recorded routes. Restore authorization or storage capacity to recover.')
end,false)
