local C,R=FarmConfig,FarmRules
local E='frontier_farming:'
local core,inv,prop,biz=exports.frontier_core,exports.frontier_inventory,exports.frontier_property,exports.frontier_business
local ready,busy=false,false
local sessions,rate={},{}
local workLocks={}
local function unlock(src) local w=sessions[src];if w then workLocks[w.id]=nil;sessions[src]=nil end end
local function check(ok,msg) if not ok then error(msg or 'Denied',0) end end
local function notice(src,msg) TriggerClientEvent(E..'notice',src,tostring(msg)) end
local function cid(src) return core:GetPlayerCharacterId(src) end
local function row(id) return MySQL.single.await('SELECT * FROM ff_facilities WHERE id=?',{id}) end
local function state(f) return json.decode(f.state) end
local function save(f,s) MySQL.update.await('UPDATE ff_facilities SET state=? WHERE id=?',{json.encode(s),f.id}) end
local function uuid() return MySQL.scalar.await('SELECT UUID()'):gsub('-','') end
local function near(src,b)
 local p=GetPlayerPed(src);if p==0 or GetPlayerRoutingBucket(src)~=0 then return false end
 local v=GetEntityCoords(p);return (v.x-b.x)^2+(v.y-b.y)^2<=(math.max(b.width,b.length)/2+C.reach)^2 and math.abs(v.z-b.z)<6
end
local function get(src,id)
 for _,b in ipairs(prop:GetFarmBuildings(src)) do if b.id==id then return b end end
end
local function authorized(src,f,b)
 local who=cid(src);if not who or not b then return false end
 if f.owner_type=='character' then return f.owner_id==who and b.owned end
 return biz:CanUseProperty(f.owner_id,who,f.plot,'farm')
end
local function current(src,f)
 local b=prop:FarmBuilding(f.plot,f.id,cid(src));check(b and near(src,b) and authorized(src,f,b),'Approach an authorized farm facility');return b
end
local function stockValid(f) return biz:FarmStockValid(f.plot,f.owner_type,f.owner_id,f.storage) end
local function pending(id) return MySQL.single.await('SELECT * FROM ff_operations WHERE facility=?',{id}) end
local function finish(j)
 local changes=json.decode(j.changes)
 local ok,err=inv:ApplyFarmBatch(j.storage,'farm_'..j.id,changes)
 if not ok then return false,err end
 local committed=MySQL.transaction.await({
  {query='UPDATE ff_facilities SET state=? WHERE id=?',values={j.after_state,j.facility}},
  {query='DELETE FROM ff_operations WHERE id=?',values={j.id}}
 })
 check(committed,'Farm journal commit failed; replay required');return true
end
local function batch(f,s,changes)
 check(stockValid(f),'Link a valid same-owner stock chest')
 local j={id=uuid(),facility=f.id,storage=f.storage,changes=json.encode(changes),after_state=json.encode(s)}
 MySQL.insert.await('INSERT INTO ff_operations(id,facility,storage,changes,after_state) VALUES(?,?,?,?,?)',{j.id,j.facility,j.storage,j.changes,j.after_state})
 local ok,err=finish(j)
 -- Known pre-commit failures do not consume or create items. Uncertain errors retain the journal.
 if not ok and ({insufficient_stock=true,weight=true,slots=true,stack_conflict=true,conflict=true,invalid_item=true})[err] then
  MySQL.update.await('DELETE FROM ff_operations WHERE id=?',{j.id})
 end
 check(ok,'Stock operation: '..tostring(err))
end
local function tool(src,key)
 local ok,has=inv:HasItem(src,C.tools[key],1);check(ok and has,'Required tool: '..key)
end
local function view(src)
 local result={}
 for _,b in ipairs(prop:GetFarmBuildings(src)) do if near(src,b) then
  local f=row(b.id);local detail=prop:FarmBuilding(b.plot,b.id,cid(src))
  if f and authorized(src,f,detail) then
   local s=state(f);if not pending(f.id) then R.advance(s,os.time(),b.size);save(f,s) end
   result[#result+1]={building=b,owner=f.owner_id,ownerType=f.owner_type,storage=f.storage,state=s,stocks=biz:FarmStock(cid(src),f.plot,f.owner_type,f.owner_id),pending=pending(f.id)~=nil}
  elseif not f and detail and detail.owned then result[#result+1]={building=b,unbound=true} end
 end end
 TriggerClientEvent(E..'menu',src,{facilities=result,crops=C.crops,species=C.species,capacity=C.fieldCapacity})
end
local function action(src,a,d,score)
 local who=cid(src);check(who,'Select a character first')
 if a=='open' then return view(src) end
 if a=='cancelWork' then unlock(src);return end
 if a=='workHit' then
  local w=sessions[src];check(w and w.actor==who and w.token==d.token,'Work session expired')
  local now=GetGameTimer();check(now<=w.expires,'Work session expired')
  local b=prop:FarmBuilding(w.plot,w.id,who);local f=row(w.id)
  check(f and b and near(src,b) and authorized(src,f,b),'Return to facility')
  local elapsed=now-w.started
  check(elapsed>=300,'Wait for the marker')
  local phase=(elapsed%1800)/1800
  if math.abs(phase-w.target)<=.13 then w.hits=w.hits+1 end
  w.round=w.round+1
  if w.round>5 then
   unlock(src);TriggerClientEvent(E..'workEnd',src)
   return action(src,w.action,w.data,w.hits)
  end
  w.started=GetGameTimer();w.target=math.random(25,75)/100
  TriggerClientEvent(E..'workRound',src,{token=w.token,target=w.target,round=w.round})
  return
 end
 check(type(d.id)=='string' and #d.id==32,'Invalid facility')
 local b=get(src,d.id);check(b and near(src,b),'Approach a completed farm building')
 if a=='bind' then
  check(not row(b.id),'Already registered')
  local detail=prop:FarmBuilding(b.plot,b.id,who);check(detail and detail.owned,'Only a plot owner can register a facility')
  local typ,id='character',who
  if type(d.company)=='string' and d.company~='' then typ,id='company',d.company;check(biz:CanUseProperty(id,who,b.plot,'farm'),'Company farm grant required') end
  MySQL.insert.await('INSERT INTO ff_facilities(id,plot,owner_type,owner_id,kind,size,state) VALUES(?,?,?,?,?,?,?)',{b.id,b.plot,typ,id,b.kind,b.size,json.encode(R.new(b.kind,os.time()))})
  return view(src)
 end
 local f=row(b.id);check(f,'Register facility first');b=current(src,f)
 check(not pending(f.id),'Pending stock operation; recovery required')
 local s=state(f);R.advance(s,os.time(),b.size);save(f,s)
 if workLocks[f.id] then error('Facility is being worked',0) end
 if C.work[a] and score==nil then
  local key=C.work[a];if a=='collect' and s.species=='sheep' then key='shear' end
  tool(src,key);check(not sessions[src],'Finish your current work first')
  local w={id=f.id,plot=f.plot,actor=who,token=uuid(),action=a,data=d,hits=0,round=1,started=GetGameTimer(),expires=GetGameTimer()+60000,target=math.random(25,75)/100}
  sessions[src]=w;workLocks[f.id]=src
  TriggerClientEvent(E..'workRound',src,{token=w.token,target=w.target,round=1})
  return
 end
 if a=='link' then
  check(biz:FarmStockValid(f.plot,f.owner_type,f.owner_id,d.storage),'Invalid stock chest')
  MySQL.update.await('UPDATE ff_facilities SET storage=? WHERE id=?',{d.storage,f.id})
 elseif a=='release' then
  check(not s.crop and R.count(s)==0 and s.products==0 and math.floor(s.manure)==0,'Empty facility before releasing')
  MySQL.update.await('DELETE FROM ff_facilities WHERE id=?',{f.id})
 elseif a=='plant' then
  check(b.kind=='field' and not s.crop and C.crops[d.crop],'Invalid crop or occupied field');tool(src,'hoe')
  s.crop=d.crop;s.growth=0;s.dead=false;s.fertilized=false;s.neglect=0;s.water=0
  batch(f,s,{{item='farm_seed_'..d.crop,count=-C.fieldCapacity[b.size]}})
 elseif a=='water' then
  check(s.crop and not s.dead or R.count(s)>0,'Nothing to water');tool(src,'water')
  local units=b.kind=='field' and math.ceil(C.fieldCapacity[b.size]/25) or math.ceil(R.count(s)/4)
  s.water=math.min(172800*(b.kind=='field' and 1 or R.count(s)),s.water+43200*(b.kind=='field' and 1 or R.count(s)))
  batch(f,s,{{item='farm_water',count=-units}})
 elseif a=='fertilize' then
  check(s.crop and not s.dead and not s.fertilized,'No eligible crop');tool(src,'fork');s.fertilized=true
  batch(f,s,{{item='farm_fertilizer',count=-math.ceil(C.fieldCapacity[b.size]/25)}})
 elseif a=='clearCrop' then
  check(s.crop and s.dead,'Only dead crops can be cleared');tool(src,'hoe');s.crop=nil;s.dead=false;s.growth=0;s.water=0;save(f,s)
 elseif a=='harvest' then
  check(s.crop and not s.dead and s.growth>=1,'Crop not ready');tool(src,'sickle')
  local n=C.fieldCapacity[b.size];local crop=s.crop
  local output=math.floor(n*(s.fertilized and 2.5 or 2)*s.soil/100*(1+(score or 0)*.05))
  s.crop=nil;s.growth=0;s.water=0;s.soil=math.max(60,s.soil-1)
  batch(f,s,{{item='farm_'..crop,count=output},{item='farm_seed_'..crop,count=n+math.floor(n/10)}})
 elseif a=='animal' then
  local c=C.species[d.species]
  check(c and d.species~='horse' and (b.kind=='chicken' and d.species=='chicken' or b.kind=='livestock' and d.species~='chicken'),'Species not supported in this facility')
  check(not s.species or s.species==d.species or R.count(s)==0 and s.products==0 and math.floor(s.manure)==0,'Empty existing species first')
  check(d.sex=='female' or d.sex=='male','Invalid sex');check(R.count(s)<c.capacity[b.size],'Enclosure full')
  s.species=d.species;s[d.sex]=s[d.sex]+1
  batch(f,s,{{item='farm_'..d.species..'_'..d.sex,count=-1}})
 elseif a=='feed' then
  check(s.species and R.count(s)>0,'No animals');tool(src,'fork')
  local n=R.count(s);s.feed=math.min(n*172800,s.feed+n*43200)
  batch(f,s,{{item=C.species[s.species].feed,count=-n}})
 elseif a=='collect' then
  check(s.species and C.species[s.species].product and s.products>=1,'No products available')
  check(s.species~='chicken','Eggs are automatically deposited')
  tool(src,s.species=='sheep' and 'shear' or 'milk')
  local n=s.products;s.products=0;batch(f,s,{{item=C.species[s.species].product,count=n}})
 elseif a=='manure' then
  tool(src,'fork');local n=math.floor(s.manure);check(n>0,'No manure available');s.manure=s.manure-n;batch(f,s,{{item='farm_manure',count=n}})
 elseif a=='slaughter' then
  check(s.species and s.species~='horse','No eligible livestock');tool(src,'knife')
  local n=tonumber(d.count);local sex=d.sex
  check((sex=='female' or sex=='male') and n and n%1==0 and n>=1 and n<=s[sex],'Invalid animal selection')
  local yield=({chicken=1,pig=4,sheep=3,cattle=8})[s.species]
  s[sex]=s[sex]-n
  local changes={{item='meat',count=math.floor(n*yield*(1+(score or 0)*.05))}}
  if s.species~='chicken' then changes[#changes+1]={item='farm_hide',count=n} end
  batch(f,s,changes)
 elseif a=='fill' then
  check(b.kind=='well','Approach a constructed well');tool(src,'bucket')
  batch(f,s,{{item='farm_water',count=10}})
 elseif a=='fertilizer' then
  check(b.kind=='field','Use at a field');batch(f,s,{{item='farm_manure',count=-5},{item='farm_fertilizer',count=1}})
 else error('Action not available in this build',0) end
 view(src)
end
local function run(src,fn)
 if not ready or busy then if src then notice(src,'Farming busy or unavailable') end;return end
 busy=true;local ok,err=pcall(fn);busy=false
 if not ok then if src then notice(src,err) else print('[frontier_farming] '..tostring(err)) end end
end
RegisterNetEvent(E..'action',function(a,d)
 local src=source;if type(a)~='string' or type(d)~='table' then return end
 local t=GetGameTimer();if rate[src] and t-rate[src]<400 then return end;rate[src]=t
 run(src,function() action(src,a,d) end)
end)
AddEventHandler('playerDropped',function() unlock(source);rate[source]=nil end)
AddEventHandler('frontier:playerUnloaded',function(p) unlock(p.source) end)
CreateThread(function() while true do Wait(1000);for src,w in pairs(sessions) do if GetGameTimer()>w.expires then unlock(src);TriggerClientEvent(E..'workEnd',src) end end end end)
exports('FacilityBound',function(id) return not ready or row(id)~=nil end)
exports('DrainCompany',function(id)
 if GetInvokingResource()~='frontier_business' or not ready or busy then return false end
 busy=true
 local ok,result=pcall(function()
  for _,f in ipairs(MySQL.query.await("SELECT * FROM ff_facilities WHERE owner_type='company' AND owner_id=?",{id})) do
   if pending(f.id) then return false end
   MySQL.update.await('DELETE FROM ff_facilities WHERE id=?',{f.id})
  end
  return true
 end)
 busy=false;return ok and result==true
end)
MySQL.ready(function()
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS ff_facilities(id CHAR(32) PRIMARY KEY,plot CHAR(32) NOT NULL,owner_type VARCHAR(16) NOT NULL,owner_id VARCHAR(64) NOT NULL,kind VARCHAR(16) NOT NULL,size VARCHAR(16) NOT NULL,storage VARCHAR(80),state LONGTEXT NOT NULL,INDEX(owner_type,owner_id))]])
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS ff_operations(id CHAR(32) PRIMARY KEY,facility CHAR(32) NOT NULL UNIQUE,storage VARCHAR(80) NOT NULL,changes LONGTEXT NOT NULL,after_state LONGTEXT NOT NULL)]])
 for key,d in pairs(C.items) do
  local def={name=d.name,description=d.name,grams=d.grams,maxStack=d.maxStack or 100,category='Farming'}
  while true do local ok,err=inv:RegisterItem(key,def);if ok then break end;print('[frontier_farming] item '..key..': '..tostring(err));Wait(5000) end
 end
 ready=true
 while true do
  run(nil,function()
   for _,j in ipairs(MySQL.query.await('SELECT * FROM ff_operations')) do
    local ok,err=finish(j)
    if not ok and ({insufficient_stock=true,weight=true,slots=true,stack_conflict=true,conflict=true,invalid_item=true})[err] then MySQL.update.await('DELETE FROM ff_operations WHERE id=?',{j.id}) end
   end
   for _,f in ipairs(MySQL.query.await('SELECT * FROM ff_facilities')) do if not pending(f.id) and not workLocks[f.id] then
    local s=state(f);local b=prop:FarmBuilding(f.plot,f.id,f.owner_id)
    if b then R.advance(s,os.time(),f.size);save(f,s)
     if s.species=='chicken' and s.products>=1 and stockValid(f) then
      local n=s.products;s.products=0;local ok,err=pcall(batch,f,s,{{item='farm_egg',count=n}});if not ok then print('[frontier_farming] eggs: '..tostring(err)) end
     end
    end
   end end
  end)
  Wait(C.tick*1000)
 end
end)
CreateThread(function()
 while true do
  Wait(3000)
  if ready and not busy then
   for _,p in pairs(core:GetPlayers()) do
    local result={}
    for _,b in ipairs(prop:GetFarmBuildings(p.source)) do
     local f=row(b.id);if f then local s=state(f);result[#result+1]={b=b,crop=s.crop,growth=s.growth,dead=s.dead,species=s.species,female=s.female,male=s.male,young=s.young} end
    end
    TriggerClientEvent(E..'world',p.source,result)
   end
  end
 end
end)
