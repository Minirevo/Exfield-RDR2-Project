local C,R=FarmConfig,FarmRules
local E='frontier_farming:'
local core,inv,prop,biz=exports.frontier_core,exports.frontier_inventory,exports.frontier_property,exports.frontier_business
local ready,busy=false,false
local sessions,rate={},{}
local workLocks={}
local function unlock(src)
 local w=sessions[src];if w then
  for _,ped in ipairs(w.animals or {}) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
  workLocks[w.id]=nil;sessions[src]=nil
 end
end
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
   local s=state(f);if not pending(f.id) and not workLocks[f.id] then R.advance(s,os.time(),b.size);save(f,s) end
   result[#result+1]={building=b,owner=f.owner_id,ownerType=f.owner_type,storage=f.storage,state=s,stocks=biz:FarmStock(cid(src),f.plot,f.owner_type,f.owner_id),pending=pending(f.id)~=nil}
  elseif not f and detail and detail.owned then result[#result+1]={building=b,unbound=true} end
 end end
 TriggerClientEvent(E..'menu',src,{facilities=result,crops=C.crops,species=C.species,capacity=C.fieldCapacity})
end

local eco=exports.frontier_economy
local function supplier(src)
 local p=GetPlayerPed(src);if p==0 or GetPlayerRoutingBucket(src)~=0 then return false end
 local v=GetEntityCoords(p)
 for _,q in ipairs(C.suppliers) do if (v.x-q.x)^2+(v.y-q.y)^2+(v.z-q.z)^2<144 then return true end end
 return false
end
local function orderStep(j)
 if j.phase=='payment' then
  local ok,e
  if j.owner_type=='company' then ok,e=biz:PayFarmOrder(j.id)
  else ok,e=eco:DebitAccount(tonumber(j.bank),tonumber(j.amount),{key='farm_order_'..j.id,reason='Agricultural supplies',reference=j.id}) end
  if not ok then
   if e=='insufficient_funds' or e=='insufficient_balance' then MySQL.update.await("UPDATE ff_orders SET phase='rejected' WHERE id=?",{j.id}) end
   return false,e
  end
  MySQL.update.await("UPDATE ff_orders SET phase='paid' WHERE id=?",{j.id});j.phase='paid'
 end
 if j.phase=='paid' then
  local ok,e
  if j.owner_type=='company' then ok,e=inv:ApplyFarmBatch(j.storage,'farm_supply_'..j.id,{{item=j.item,count=tonumber(j.quantity)}})
  else ok,e=inv:FarmSupplyDelivery(j.actor,j.item,tonumber(j.quantity),'farm_supply_'..j.id) end
  if not ok then return false,e end
  MySQL.update.await("UPDATE ff_orders SET phase='complete' WHERE id=?",{j.id})
 end
 return true
end
local function shopView(src)
 local who=cid(src);check(who and supplier(src),'Approach an agricultural supplier')
 local list={}
 for k,v in pairs(C.supplyPrices) do list[#list+1]={id=k,name=C.items[k].name,price=v} end
 table.sort(list,function(a,b)return a.name<b.name end)
 local orders=MySQL.query.await("SELECT id,item,quantity,amount,phase FROM ff_orders WHERE actor=? AND phase IN ('payment','paid') ORDER BY created DESC",{who})
 TriggerClientEvent(E..'shop',src,{items=list,orders=orders})
end
local function buySupply(src,d)
 local who=cid(src);check(who and supplier(src),'Approach an agricultural supplier')
 local price=C.supplyPrices[d.item];local qty=tonumber(d.quantity)
 check(price and qty and qty%1==0 and qty>=1 and qty<=1000,'Invalid purchase')
 check(not MySQL.single.await("SELECT id FROM ff_orders WHERE actor=? AND phase IN ('payment','paid')",{who}),'Resolve your pending order first')
 local typ,owner,storage,bank='character',who,'',0
 if type(d.facility)=='string' and d.facility~='' then
  local f=row(d.facility);check(f and f.owner_type=='company' and biz:CanUseProperty(f.owner_id,who,f.plot,'farm') and stockValid(f),'Authorized company facility and linked chest required')
  check(C.items[d.item].maxStack~=1,'Purchase personal tools separately')
  typ,owner,storage='company',f.owner_id,f.storage
 else
  local ok,accounts=eco:GetCharacterAccounts(src);check(ok and accounts.characterId==who,'Bank unavailable');bank=accounts.bank.id
 end
 local j={id=uuid(),actor=who,owner_type=typ,owner_id=owner,storage=storage,bank=bank,item=d.item,quantity=qty,amount=price*qty,phase='payment'}
 MySQL.insert.await('INSERT INTO ff_orders(id,actor,owner_type,owner_id,storage,bank,item,quantity,amount,phase,created) VALUES(?,?,?,?,?,?,?,?,?,?,?)',{j.id,who,typ,owner,storage,bank,j.item,qty,j.amount,j.phase,os.time()})
 local ok,e=orderStep(j);notice(src,ok and 'Supplies purchased' or ('Order pending or rejected: '..tostring(e)));shopView(src)
end

local function action(src,a,d,score)
 local who=cid(src);check(who,'Select a character first')
 if a=='open' then return view(src) end
 if a=='shop' then return shopView(src) end
 if a=='buySupply' then return buySupply(src,d) end
 if a=='cancelWork' then unlock(src);return end
 if a=='slaughterFinish' then
  local w=sessions[src];check(w and w.actor==who and w.phase=='slaughter' and d.token==w.token,'No slaughter session')
  local f=row(w.id);local b=f and current(src,f);check(b and not pending(w.id),'Facility unavailable')
  tool(src,'knife')
  for _,ped in ipairs(w.animals) do check(DoesEntityExist(ped) and GetEntityHealth(ped)<=0,'All selected physical animals must be slaughtered first') end
  local payload=w.data;local hits=w.hits;unlock(src)
  return action(src,'slaughter',payload,hits+10)
 end
 if a=='workHit' then
  local w=sessions[src];check(w and w.actor==who and w.token==d.token,'Work session expired')
  local now=GetGameTimer();check(now<=w.expires,'Work session expired')
  local b=prop:FarmBuilding(w.plot,w.id,who);local f=row(w.id)
  check(f and b and near(src,b) and authorized(src,f,b),'Return to facility')
  local elapsed=now-w.started
  if elapsed<300 then w.started=now;TriggerClientEvent(E..'workRound',src,{token=w.token,target=w.target,round=w.round});return end
  local phase=(elapsed%1800)/1800
  if math.abs(phase-w.target)<=.13 then w.hits=w.hits+1 end
  w.round=w.round+1
  if w.round>5 then
   if w.action=='slaughter' then
    local ss=state(f);local n=tonumber(w.data.count);local sex=w.data.sex
    check(ss.species and ss.species~='horse' and (sex=='male' or sex=='female') and n and n%1==0 and n>=1 and n<=ss[sex],'Invalid selection')
    local model=C.species[ss.species][sex];local amount=math.max(1,math.ceil(n*C.slaughterFractions[w.hits+1]))
    w.animals={};local ids={}
    local ok,err=pcall(function()
     for i=1,amount do
      local angle=i*2.39996;local x,y=R.world(b,math.cos(angle)*b.width*.25,math.sin(angle)*b.length*.25)
      local ped=CreatePed(joaat(model),x,y,b.z+0.4,0.0,true,true)
      check(ped and ped~=0 and DoesEntityExist(ped),'Network animal spawn unavailable')
      w.animals[#w.animals+1]=ped
      SetEntityRoutingBucket(ped,GetPlayerRoutingBucket(src))
      ids[#ids+1]=NetworkGetNetworkIdFromEntity(ped)
     end
    end)
    if not ok then unlock(src);TriggerClientEvent(E..'workEnd',src);error(err,0) end
    w.phase='slaughter';w.expires=GetGameTimer()+300000
    TriggerClientEvent(E..'slaughter',src,{token=w.token,ids=ids,count=amount});return
   end
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
  if a~='trainHorse' then tool(src,key) end;check(not sessions[src],'Finish your current work first')
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
  check(c and (b.kind=='chicken' and d.species=='chicken' or b.kind=='livestock' and d.species~='chicken'),'Species not supported in this facility')
  check(not s.species or s.species==d.species or R.count(s)==0 and s.products==0 and math.floor(s.manure)==0,'Empty existing species first')
  check(d.sex=='female' or d.sex=='male','Invalid sex');check(R.count(s)<c.capacity[b.size],'Enclosure full')
  s.species=d.species
  if d.species=='horse' then
   local breed=d.breed or 'turkoman';check(C.horseBreeds[breed],'Invalid breed')
   s.horses=s.horses or {};s.horses[#s.horses+1]=R.newHorse(uuid(),breed,d.sex,d.juvenile==true);R.horseCounts(s)
  else s[d.sex]=s[d.sex]+1 end
  batch(f,s,{{item='farm_'..d.species..'_'..d.sex,count=-1}})
 elseif a=='trainHorse' then
  check(s.species=='horse','Horse enclosure required')
  local h;for _,v in ipairs(s.horses or {}) do if v.id==d.horse then h=v;break end end
  check(h and not h.listed and h.health>=60 and h.age>=C.species.horse.mature*3600 and os.time()-(h.trainedAt or 0)>=C.horseTrainingInterval,'Horse cannot train now')
  h.training=math.min(100,h.training+2+(score or 0));h.trainedAt=os.time();save(f,s)
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
  check(score and score>=10 and s.species and s.species~='horse','Complete physical slaughter first');tool(src,'knife')
  local n=tonumber(d.count);local sex=d.sex
  check((sex=='female' or sex=='male') and n and n%1==0 and n>=1 and n<=s[sex],'Invalid animal selection')
  local yield=({chicken=1,pig=4,sheep=3,cattle=8})[s.species]
  s[sex]=s[sex]-n
  local changes={{item='meat',count=math.floor(n*yield*(1+(score-10)*.05))}}
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
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS ff_orders(id CHAR(32) PRIMARY KEY,actor VARCHAR(64) NOT NULL,owner_type VARCHAR(16) NOT NULL,owner_id VARCHAR(64) NOT NULL,storage VARCHAR(80) NOT NULL,bank BIGINT NOT NULL,item VARCHAR(48) NOT NULL,quantity INT NOT NULL,amount INT NOT NULL,phase VARCHAR(16) NOT NULL,created BIGINT NOT NULL,INDEX(actor,phase),INDEX(owner_id,phase))]])
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS ff_facilities(id CHAR(32) PRIMARY KEY,plot CHAR(32) NOT NULL,owner_type VARCHAR(16) NOT NULL,owner_id VARCHAR(64) NOT NULL,kind VARCHAR(16) NOT NULL,size VARCHAR(16) NOT NULL,storage VARCHAR(80),state LONGTEXT NOT NULL,INDEX(owner_type,owner_id))]])
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS ff_operations(id CHAR(32) PRIMARY KEY,facility CHAR(32) NOT NULL UNIQUE,storage VARCHAR(80) NOT NULL,changes LONGTEXT NOT NULL,after_state LONGTEXT NOT NULL)]])
 for key,d in pairs(C.items) do
  local def={name=d.name,description=d.name,grams=d.grams,maxStack=d.maxStack or 100,category='Farming'}
  while true do local ok,err=inv:RegisterItem(key,def);if ok then break end;print('[frontier_farming] item '..key..': '..tostring(err));Wait(5000) end
 end
 ready=true
 while true do
  run(nil,function()
   for _,j in ipairs(MySQL.query.await("SELECT * FROM ff_orders WHERE phase IN ('payment','paid') ORDER BY created LIMIT 50")) do local ok,e=orderStep(j);if not ok then print('[frontier_farming] supply order '..j.id..': '..tostring(e)) end end
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
     local f=row(b.id);if f then local s=state(f);local lock=workLocks[f.id] and sessions[workLocks[f.id]];result[#result+1]={b=b,crop=s.crop,growth=s.growth,dead=s.dead,species=(not lock or lock.phase~='slaughter') and s.species or nil,female=s.female,male=s.male,young=s.young,horses=s.horses} end
    end
    TriggerClientEvent(E..'world',p.source,result)
   end
  end
 end
end)

exports('CompanyOrdersPending',function(id)
 if GetInvokingResource()~='frontier_business' or not ready then return true end
 return MySQL.single.await("SELECT id FROM ff_orders WHERE owner_type='company' AND owner_id=? AND phase IN ('payment','paid') LIMIT 1",{id})~=nil
end)

AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then for src in pairs(sessions) do unlock(src) end end end)
