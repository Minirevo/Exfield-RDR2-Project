local C,R=FarmConfig,FarmRules
local E='frontier_farming:'
local core,inv,prop,biz=exports.frontier_core,exports.frontier_inventory,exports.frontier_property,exports.frontier_business
local ready,busy=false,false
local sessions,rate={},{}
local workLocks,mounts,mountLocks,waterWork={},{},{},{}
local function unlock(src)
 local w=sessions[src];if w then
  for _,ped in ipairs(w.animals or {}) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
  if w.phase=='spawning' or w.phase=='slaughter' then TriggerClientEvent(E..'slaughterCleanup',src,w.token) end
  workLocks[w.id]=nil;sessions[src]=nil
 end
end
local function check(ok,msg) if not ok then error(msg or 'Denied',0) end end
local function notice(src,msg) TriggerClientEvent(E..'notice',src,tostring(msg)) end
local function cid(src) return core:GetPlayerCharacterId(src) end
local function row(id) if type(id)~='string' or #id~=32 or not id:match('^[a-f0-9]+$') then return end;return MySQL.single.await('SELECT * FROM ff_facilities WHERE id=?',{id}) end
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

local function itemName(id) return C.items[id] and C.items[id].name or tostring(id) end
local function stockError(err,detail)
 if err=='insufficient_stock' and detail then return ('Not enough %s in linked chest: %d / %d (missing %d)'):format(itemName(detail.item),detail.available,detail.required,detail.required-detail.available) end
 if err=='weight' or err=='slots' or err=='stack_conflict' then return 'Linked chest has insufficient space for '..(detail and itemName(detail.item) or 'the output')..'. Empty it or link a larger chest.' end
 return 'Stock operation: '..tostring(err)
end
local function preflight(f,changes)
 check(stockValid(f),'Link a valid same-owner stock chest first')
 local ok,e,d=inv:CheckFarmBatch(f.storage,changes)
 check(ok,stockError(e,d))
end
local function stockSnapshot(f)
 if not stockValid(f) then return {},false end
 local ok,v=inv:GetStorageContents(f.storage)
 if not ok then return {},false end
 local out={};for _,slot in pairs(v.slots or {}) do out[slot.item]=(out[slot.item] or 0)+slot.quantity end
 return out,true
end

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
 preflight(f,changes)
 local j={id=uuid(),facility=f.id,storage=f.storage,changes=json.encode(changes),after_state=json.encode(s)}
 MySQL.insert.await('INSERT INTO ff_operations(id,facility,storage,changes,after_state) VALUES(?,?,?,?,?)',{j.id,j.facility,j.storage,j.changes,j.after_state})
 local ok,err=finish(j)
 -- Known pre-commit failures do not consume or create items. Uncertain errors retain the journal.
 if not ok and ({insufficient_stock=true,weight=true,slots=true,stack_conflict=true,conflict=true,invalid_item=true})[err] then
  MySQL.update.await('DELETE FROM ff_operations WHERE id=?',{j.id})
 end
 if not ok and err=='insufficient_stock' then preflight(f,changes) end
 check(ok,stockError(err))
end
local function tool(src,key)
 local ok,has=inv:HasTool(src,C.tools[key]);check(ok and has,'Required in satchel or toolbelt: '..itemName(C.tools[key]))
end

local function horsePending(id)
 return MySQL.single.await("SELECT id FROM ff_horse_sales WHERE phase='payment' AND (source_id=? OR dest_id=?) LIMIT 1",{id,id})~=nil
end
local function animalPending(id)
 return MySQL.single.await("SELECT d.order_id FROM ff_animal_orders d JOIN ff_orders o ON o.id=d.order_id WHERE d.facility=? AND o.phase IN ('payment','paid') LIMIT 1",{id})~=nil
end
local function locked(id) return workLocks[id] or mountLocks[id] or pending(id) or horsePending(id) or animalPending(id) end
local function horseById(s,id)
 for i,h in ipairs(s.horses or {}) do if h.id==id then return h,i end end
end
local function farmBank(typ,id)
 local ownerType=typ=='company' and 'business' or 'character'
 return tonumber(MySQL.scalar.await("SELECT id FROM frontier_economy_accounts WHERE owner_type=? AND owner_id=? AND account_type='bank' AND currency='USD'",{ownerType,id}))
end
local function horseSaleStep(j)
 local ok,e=biz:PayFarmHorseSale(j.id)
 if not ok then
  if e=='insufficient_funds' then MySQL.update.await("UPDATE ff_horse_sales SET phase='rejected' WHERE id=?",{j.id}) end
  return false,e
 end
 check(MySQL.transaction.await({
  {query='UPDATE ff_facilities SET state=? WHERE id=?',values={j.source_state,j.source_id}},
  {query='UPDATE ff_facilities SET state=? WHERE id=?',values={j.dest_state,j.dest_id}},
  {query="UPDATE ff_horse_sales SET phase='complete' WHERE id=?",values={j.id}}
 }),'Horse sale commit failed; retry required')
 return true
end
local function horseMarket(src)
 local who=cid(src);check(who,'Select a character')
 local listings={}
 for _,f in ipairs(MySQL.query.await("SELECT * FROM ff_facilities WHERE kind='livestock'")) do
  if not locked(f.id) and biz:VerifyLicense(f.owner_type,f.owner_id,'agriculture') and prop:FarmBuilding(f.plot,f.id,f.owner_id) then
   local v=state(f)
   for _,h in ipairs(v.horses or {}) do if h.listed then listings[#listings+1]={facility=f.id,horse=h,price=h.listed} end end
  end
 end
 local destinations={}
 for _,b in ipairs(prop:GetFarmBuildings(src)) do
  local f=row(b.id)
  if f and b.kind=='livestock' and authorized(src,f,prop:FarmBuilding(f.plot,f.id,who)) and near(src,b) and not locked(f.id) then
   local v=state(f);if (not v.species or v.species=='horse' or R.count(v)==0 and v.products==0 and math.floor(v.manure)==0) and R.count(v)<C.species.horse.capacity[f.size] then destinations[#destinations+1]={id=f.id,name=b.size..' horse pen'} end
  end
 end
 TriggerClientEvent(E..'horseMarket',src,{listings=listings,destinations=destinations})
end
local function buyHorse(src,d)
 local from,to=row(d.source),row(d.dest)
 check(from and to and from.id~=to.id and from.owner_id~=to.owner_id and to.kind=='livestock','Invalid horse sale')
 check(not locked(from.id) and not locked(to.id),'Facility busy')
 local target=current(src,to);check(target,'Approach destination enclosure')
 check(prop:FarmBuilding(from.plot,from.id,from.owner_id) and biz:VerifyLicense(from.owner_type,from.owner_id,'agriculture'),'Seller license or property unavailable')
 local fs,ts=state(from),state(to);R.advance(fs,os.time(),from.size);R.advance(ts,os.time(),to.size)
 local h,i=horseById(fs,d.horse)
 check(h and h.listed and h.health>0,'Listing unavailable')
 check(not ts.species or ts.species=='horse' or R.count(ts)==0 and ts.products==0 and math.floor(ts.manure)==0,'Destination must be empty or horses')
 check(R.count(ts)<C.species.horse.capacity[to.size],'Destination full')
 local amount=h.listed;check(tonumber(d.price)==amount,'Price changed')
 local debit,credit=farmBank(to.owner_type,to.owner_id),farmBank(from.owner_type,from.owner_id)
 check(debit and credit and debit~=credit,'Bank unavailable')
 table.remove(fs.horses,i);h.listed=nil;ts.species='horse';ts.horses=ts.horses or {};ts.horses[#ts.horses+1]=h;R.horseCounts(fs);R.horseCounts(ts)
 local j={id=uuid(),source_id=from.id,dest_id=to.id,source_state=json.encode(fs),dest_state=json.encode(ts),debit=debit,credit=credit,amount=amount}
 MySQL.insert.await("INSERT INTO ff_horse_sales(id,source_id,dest_id,source_state,dest_state,debit,credit,amount,phase) VALUES(?,?,?,?,?,?,?,?,'payment')",{j.id,j.source_id,j.dest_id,j.source_state,j.dest_state,j.debit,j.credit,j.amount})
 local ok,e=horseSaleStep(j);notice(src,ok and 'Horse certificate transferred' or ('Horse purchase: '..tostring(e)));horseMarket(src)
end

local function view(src,preferred)
 local result={}
 for _,b in ipairs(prop:GetFarmBuildings(src)) do if near(src,b) then
  local f=row(b.id);local detail=prop:FarmBuilding(b.plot,b.id,cid(src))
  if f and authorized(src,f,detail) then
   local s=state(f);if not locked(f.id) then R.advance(s,os.time(),b.size);save(f,s) end
   local counts,available=stockSnapshot(f)
   result[#result+1]={building=b,owner=f.owner_id,ownerType=f.owner_type,storage=f.storage,state=s,stocks=biz:FarmStock(cid(src),f.plot,f.owner_type,f.owner_id),counts=counts,stockAvailable=available,pending=not not locked(f.id)}
  elseif not f and detail and detail.owned then result[#result+1]={building=b,unbound=true} end
 end end
 if preferred then
  local found=false;for _,v in ipairs(result) do if v.building.id==preferred then found=true;break end end
  check(found,'Approach an authorized farm facility')
 end
 local tools={};for k,id in pairs(C.tools) do local ok,has=inv:HasTool(src,id);tools[k]=ok and has or false end
 TriggerClientEvent(E..'menu',src,{facilities=result,selected=preferred,crops=C.crops,species=C.species,capacity=C.fieldCapacity,tools=tools,items=C.items,trainingInterval=C.horseTrainingInterval,now=os.time()})
end

local eco=exports.frontier_economy
local function supplier(src)
 if GetResourceState('frontier_shops')=='started' then return exports.frontier_shops:NearGeneralStore(src) end
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
  local destination=MySQL.single.await('SELECT * FROM ff_animal_orders WHERE order_id=?',{j.id})
  if destination then
   check(MySQL.transaction.await({{query='UPDATE ff_facilities SET state=? WHERE id=?',values={destination.after_state,destination.facility}},{query="UPDATE ff_orders SET phase='complete' WHERE id=?",values={j.id}}}),'Animal delivery retry required');return true
  end
  local ok,e
  if j.owner_type=='company' then ok,e=inv:ApplyFarmBatch(j.storage,'farm_supply_'..j.id,{{item=j.item,count=tonumber(j.quantity)}})
  else ok,e=inv:FarmSupplyDelivery(j.actor,j.item,tonumber(j.quantity),'farm_supply_'..j.id) end
  if not ok then
   if j.owner_type=='company' and ({weight=true,slots=true,stack_conflict=true,not_found=true})[e] then
    local status=MySQL.scalar.await("SELECT status FROM fb_companies WHERE id=?",{j.owner_id})
    if status=='liquidating' then
     local refunded=biz:RefundFarmOrder(j.id);if refunded then MySQL.update.await("UPDATE ff_orders SET phase='refunded' WHERE id=?",{j.id});return true end
    end
   end
   return false,e
  end
  MySQL.update.await("UPDATE ff_orders SET phase='complete' WHERE id=?",{j.id})
 end
 return true
end
local function shopData(src)
 local who=cid(src);check(who and supplier(src),'Approach an agricultural supplier')
 local list={}
 for k,v in pairs(C.supplyPrices) do list[#list+1]={id=k,name=C.items[k].name,price=v,maxStack=C.items[k].maxStack or 100,animal=(function() local species,sex=k:match('^farm_(%a+)_(%a+) end
 table.sort(list,function(a,b)return a.name<b.name end)
 local orders=MySQL.query.await("SELECT id,item,quantity,amount,phase FROM ff_orders WHERE actor=? AND phase IN ('payment','paid') ORDER BY created DESC",{who})
 local destinations={}
 for _,f in ipairs(MySQL.query.await('SELECT * FROM ff_facilities ORDER BY kind,size')) do
  local b=prop:FarmBuilding(f.plot,f.id,who)
  if b and authorized(src,f,b) then destinations[#destinations+1]={id=f.id,name=f.size..' '..f.kind..' · '..f.owner_type,kind=f.kind,ownerType=f.owner_type} end
 end
 return {items=list,orders=orders,destinations=destinations,breeds=C.horseBreeds}
end
local function shopView(src) TriggerClientEvent(E..'shop',src,shopData(src)) end
local function buySupply(src,d,merged,orderId)
 local who=cid(src);check(who and supplier(src),'Approach an agricultural supplier')
 if merged then
  check(type(orderId)=='string' and #orderId==32 and orderId:match('^[a-f0-9]+
 check(price and qty and qty%1==0 and qty>=1 and qty<=1000,'Invalid purchase')
 check(not MySQL.single.await("SELECT id FROM ff_orders WHERE actor=? AND phase IN ('payment','paid')",{who}),'Resolve your pending order first')
 local typ,owner,storage,bank='character',who,'',0
 local animal,sex=d.item:match('^farm_(%a+)_(%a+)$')
 if not C.species[animal] or (sex~='female' and sex~='male') then animal=nil end
 local delivery
 if animal then
  local f=row(d.facility);check(f and not locked(f.id),'Choose an available destination facility ID')
  local b=prop:FarmBuilding(f.plot,f.id,who);check(b and authorized(src,f,b),'Unauthorized destination')
  check((b.kind=='chicken' and animal=='chicken') or (b.kind=='livestock' and animal~='chicken'),'Wrong enclosure type')
  local st=state(f);R.advance(st,os.time(),f.size)
  check(not st.species or st.species==animal or R.count(st)==0 and st.products==0 and math.floor(st.manure)==0,'Different species in enclosure')
  check(R.count(st)+qty<=C.species[animal].capacity[f.size],'Not enough capacity')
  typ,owner,storage=f.owner_type,f.owner_id,''
  if typ=='character' then local ok,a=eco:GetCharacterAccounts(src);check(ok and a.characterId==who,'Bank unavailable');bank=merged and a.cash.id or a.bank.id end
  st.species=animal
  if animal=='horse' then
   local breed=d.breed or 'turkoman';check(C.horseBreeds[breed],'Unknown breed')
   st.horses=st.horses or {}
   for i=1,qty do st.horses[#st.horses+1]=R.newHorse(uuid(),breed,sex,d.juvenile==true) end
   R.horseCounts(st)
  elseif d.juvenile then if st.young==0 then st.matureClock=0 end;st.young=st.young+qty
  else st[sex]=st[sex]+qty end
  if d.juvenile then price=math.max(1,math.floor(price*.6)) end
  delivery={facility=f.id,after_state=json.encode(st)}
 end
 if not delivery and type(d.facility)=='string' and d.facility~='' then
  local f=row(d.facility);check(f and f.owner_type=='company' and biz:CanUseProperty(f.owner_id,who,f.plot,'farm') and stockValid(f),'Authorized company facility and linked chest required')
  check(C.items[d.item].maxStack~=1,'Purchase personal tools separately')
  typ,owner,storage='company',f.owner_id,f.storage
 elseif not delivery then
  local ok,accounts=eco:GetCharacterAccounts(src);check(ok and accounts.characterId==who,'Bank unavailable');bank=accounts.bank.id
 end
 local j={id=orderId or uuid(),actor=who,owner_type=typ,owner_id=owner,storage=storage,bank=bank,item=d.item,quantity=qty,amount=price*qty,phase='payment'}
 local statements={{query='INSERT INTO ff_orders(id,actor,owner_type,owner_id,storage,bank,item,quantity,amount,phase,created) VALUES(?,?,?,?,?,?,?,?,?,?,?)',values={j.id,who,typ,owner,storage,bank,j.item,qty,j.amount,j.phase,os.time()}}}
 if delivery then statements[#statements+1]={query='INSERT INTO ff_animal_orders(order_id,facility,after_state) VALUES(?,?,?)',values={j.id,delivery.facility,delivery.after_state}} end
 check(MySQL.transaction.await(statements),'Could not persist order')
 local ok,e=orderStep(j)
 if merged then return ok,ok and 'Farm delivery purchased.' or ('Order pending or rejected: '..tostring(e)) end
 notice(src,ok and 'Supplies purchased' or ('Order pending or rejected: '..tostring(e)));shopView(src)
end


local function returnMount(src)
 local m=mounts[src];if not m then return end
 local f=row(m.facility)
 if f then
  local st=state(f);R.advance(st,os.time(),f.size)
  local h,i=horseById(st,m.horse)
  if h and DoesEntityExist(m.ped) and GetEntityHealth(m.ped)<=0 then table.remove(st.horses,i);R.horseCounts(st) end
  save(f,st)
 end
 if DoesEntityExist(m.ped) then DeleteEntity(m.ped) end
 mounts[src]=nil;mountLocks[m.facility]=nil
 TriggerClientEvent(E..'mountReturned',src)
end
local function checkout(src,f,b,st,id)
 check(not mounts[src],'Return your current mount first')
 local h=horseById(st,id)
 check(h and not h.listed and h.health>=30 and h.age>=C.species.horse.mature*3600,'Horse is not available to ride')
 local p=GetEntityCoords(GetPlayerPed(src))
 local ped=CreatePed(joaat(C.horseBreeds[h.breed].model),p.x+2.0,p.y,p.z+0.4,b.heading,true,true)
 check(ped and ped~=0 and DoesEntityExist(ped),'Network mount unavailable')
 SetEntityRoutingBucket(ped,GetPlayerRoutingBucket(src))
 local net=NetworkGetNetworkIdFromEntity(ped)
 if not net or net==0 then DeleteEntity(ped);error('Mount network ID unavailable',0) end
 mounts[src]={actor=cid(src),horse=h.id,facility=f.id,ped=ped,expires=os.time()+C.mountMaxSeconds}
 mountLocks[f.id]=src
 TriggerClientEvent(E..'mount',src,{id=net,horse=h})
end
local function siteNear(src)
 local ped=GetPlayerPed(src);if ped==0 or GetPlayerRoutingBucket(src)~=0 then return end
 local v=GetEntityCoords(ped)
 for _,q in ipairs(MySQL.query.await('SELECT * FROM ff_water_sites')) do
  if (v.x-q.x)^2+(v.y-q.y)^2+(v.z-q.z)^2<=C.waterSiteRadius^2 then return q end
 end
end
local function farmWork(src,a,key)
 check(GetResourceState('frontier_needs')=='started','Needs unavailable')
 local ok,why
 if key then ok,why=exports.frontier_needs:SpendLabour(src,a,key,1)
 else ok,why=exports.frontier_needs:CanWork(src,a,1) end
 check(ok,why)
end
local function beginWater(src)
 tool(src,'bucket');check(not waterWork[src],'Already filling a bucket')
 local q=siteNear(src);check(q,'Approach an approved river or lake collection point')
 farmWork(src,'fill')
 local w={actor=cid(src),id=uuid(),site=q.id,started=GetGameTimer()}
 waterWork[src]=w;TriggerClientEvent(E..'waterWork',src,{token=w.id,ms=C.waterFillMs})
end
local function finishWater(src,d)
 local w=waterWork[src];check(w and w.actor==cid(src) and w.id==d.token,'Water collection expired')
 local t=GetGameTimer()-w.started;check(t>=C.waterFillMs and t<=C.waterFillMs+15000,'Invalid filling duration')
 local q=siteNear(src);check(q and q.id==w.site,'Remain near the water source');tool(src,'bucket')
 farmWork(src,'fill',w.id)
 local ok,e=inv:FarmSupplyDelivery(w.actor,'farm_water',10,'farm_water_'..w.id)
 check(ok,e);waterWork[src]=nil;notice(src,'Filled 10 water units. Carry them back to your farm stock.')
end


local function validateWork(src,f,b,s,a,d)
 local changes={}
 local key=C.work[a]
 if a=='collect' then
  check(s.species and C.species[s.species] and C.species[s.species].product and s.products>=1,'No products ready to collect')
  key=s.species=='chicken' and nil or s.species=='sheep' and 'shear' or 'milk'
  if s.species=='chicken' then key=nil end
  changes={{item=C.species[s.species].product,count=math.floor(s.products*(s.species=='chicken' and 1 or 1.25))}}
 elseif a=='plant' then
  check(b.kind=='field' and not s.crop and C.crops[d.crop],'Choose a crop for an empty field')
  changes={{item='farm_seed_'..d.crop,count=-C.fieldCapacity[b.size]}}
 elseif a=='water' or a=='feed' then
  local plan,err=R.supply(s,b,a,d.quantity);check(plan,err)
  local item='farm_water'
  if a=='feed' then item=C.species[s.species].feed;if s.species=='pig' and C.pigFeed[d.food] then item=d.food end end
  changes={{item=item,count=-plan.units}}
 elseif a=='fertilize' then
  check(b.kind=='field' and s.crop and not s.dead and not s.fertilized and s.growth<1,'Only an unfertilized growing crop can be fertilized')
  changes={{item='farm_fertilizer',count=-math.ceil(C.fieldCapacity[b.size]/25)}}
 elseif a=='clearCrop' then check(b.kind=='field' and s.crop and s.dead,'No dead crops to clear')
 elseif a=='harvest' then
  check(b.kind=='field' and s.crop and not s.dead and s.growth>=1,'Crop not ready to harvest')
  local output,seeds=R.harvest(s,b.size,5)
  changes={{item='farm_'..s.crop,count=output}}
  if seeds>0 then changes[#changes+1]={item='farm_seed_'..s.crop,count=seeds} end
 elseif a=='manure' then
  check(math.floor(s.manure)>0,'No manure ready to collect')
  changes={{item='farm_manure',count=math.floor(s.manure)}}
 elseif a=='slaughter' then
  check(s.species and s.species~='horse','No eligible livestock')
  local n,sex=tonumber(d.count),d.sex
  check((sex=='male' or sex=='female') and n and n%1==0 and n>=1 and n<=s[sex],'Choose a valid number of adult animals')
  changes={{item='farm_meat',count=math.floor(n*({chicken=1,pig=4,sheep=3,cattle=8})[s.species]*1.25)}}
  if s.species~='chicken' then changes[#changes+1]={item='farm_hide',count=n} end
 elseif a=='trainHorse' then
  local h=horseById(s,d.horse)
  check(s.species=='horse' and h and not h.listed and h.health>=60 and h.training<100 and h.age>=C.species.horse.mature*3600 and os.time()-(h.trainedAt or 0)>=C.horseTrainingInterval,'Horse not eligible for training (adult, healthy, unlisted, cooldown complete, training below 100)')
  key=nil
 elseif a=='fill' then
  check(b.kind=='well','Approach a constructed well');key='bucket';changes={{item='farm_water',count=10}}
 elseif a=='fertilizer' then
  check(b.kind=='field','Use at a field');changes={{item='farm_manure',count=-5},{item='farm_fertilizer',count=1}}
 end
 if key then tool(src,key) end
 if #changes>0 then preflight(f,changes) end
end

local function action(src,a,d,score,workKey)
 local who=cid(src);check(who,'Select a character first')
 if a=='open' then return view(src) end
 if a=='openFacility' then
  if sessions[src] then notice(src,'Finish or cancel your current farm work first');return end
  local b=get(src,d.id);check(b and near(src,b),'Approach a completed farm facility')
  return view(src,b.id)
 end
 if a=='riverStart' then return beginWater(src) end
 if a=='riverFinish' then return finishWater(src,d) end
 if a=='returnMount' then check(mounts[src] and mounts[src].actor==who,'No mount checked out');return returnMount(src) end
 if a=='shop' then if GetResourceState('frontier_shops')=='started' then return notice(src,'Use /shop at the general store.') end;return shopView(src) end
 if a=='horseMarket' then return horseMarket(src) end
 if a=='buyHorse' then return buyHorse(src,d) end
 if a=='buySupply' then if GetResourceState('frontier_shops')=='started' then return notice(src,'Use the general store for new purchases.') end;return buySupply(src,d) end
 if a=='cancelWork' then unlock(src);waterWork[src]=nil;TriggerClientEvent(E..'workEnd',src);if d.reopen then return view(src) end;return end
 if a=='slaughterSpawnFailed' then
  local w=sessions[src];check(w and w.actor==who and w.phase=='spawning' and d.token==w.token,'No pending animal spawn')
  unlock(src);TriggerClientEvent(E..'workEnd',src)
  error('Could not create networked animals on your client. No livestock consumed. Check client F8 console.',0)
 end
 if a=='slaughterSpawned' then
  local w=sessions[src];check(w and w.actor==who and w.phase=='spawning' and d.token==w.token,'No pending animal spawn')
  check(GetGameTimer()<=w.expires,'Animal spawn timed out')
  local f=row(w.id);local b=f and current(src,f);check(b and not pending(w.id),'Facility unavailable')
  check(type(d.ids)=='table' and #d.ids==#w.points,'Incorrect number of networked animals')
  local seen={};local deadline=GetGameTimer()+4000
  for i,id in ipairs(d.ids) do
   check(type(id)=='number' and id%1==0 and id>0 and not seen[id],'Invalid or duplicate animal network ID')
   seen[id]=true
   local ped=NetworkGetEntityFromNetworkId(id)
   while (not ped or ped==0 or not DoesEntityExist(ped)) and GetGameTimer()<deadline do Wait(50);ped=NetworkGetEntityFromNetworkId(id) end
   check(sessions[src]==w,'Animal spawn cancelled')
   check(ped and ped~=0 and DoesEntityExist(ped),'Network animal did not replicate to server (check OneSync and entity lockdown)')
   local validationDeadline = GetGameTimer() + 3000

while GetGameTimer() < validationDeadline do
    check(sessions[src] == w, 'Animal spawn cancelled')

    if GetEntityType(ped) == 1
        and NetworkGetEntityOwner(ped) == src
        and GetEntityModel(ped) == joaat(w.model)
        then
        break
    end

    Wait(50)
end

check(not w.existing[ped], 'Animal already existed')
check(GetEntityType(ped) == 1, 'Invalid animal entity type')
check(NetworkGetEntityOwner(ped) == src, 'Invalid animal network owner')
check(GetEntityModel(ped) == joaat(w.model), 'Animal model mismatch')
   check(GetEntityRoutingBucket(ped)==GetPlayerRoutingBucket(src),'Animal is in the wrong routing bucket')
   local pos=GetEntityCoords(ped);local p=w.points[i]
   check((pos.x-p.x)^2+(pos.y-p.y)^2<=9 and math.abs(pos.z-p.z)<5,'Animal spawned outside the assigned position')
   w.animals[#w.animals+1]=ped
  end
  w.phase='slaughter';w.expires=GetGameTimer()+300000;w.existing=nil;w.points=nil
  TriggerClientEvent(E..'slaughter',src,{token=w.token,ids=d.ids,count=#w.animals});return
 end
 if a == 'slaughterFinish' then
    local w = sessions[src]

    check(
        w and w.actor == who
        and w.phase == 'slaughter'
        and d.token == w.token
        and GetGameTimer() <= w.expires,
        'No active slaughter session'
    )

    local f = row(w.id)
    local b = f and current(src, f)

    check(b and not pending(w.id), 'Facility unavailable')
    check(near(src, b), 'Return to the slaughter facility')

    tool(src, 'knife')

    check(
        type(d.deadIds) == 'table'
        and #d.deadIds == #w.animals,
        'All selected animals must be slaughtered first'
    )

    local reported = {}

    for _, id in ipairs(d.deadIds) do
        check(
            type(id) == 'number'
            and id > 0
            and id % 1 == 0
            and not reported[id],
            'Invalid or duplicate animal network ID'
        )

        reported[id] = true
    end

    for _, ped in ipairs(w.animals) do
        check(
            DoesEntityExist(ped),
            'Slaughter animal no longer exists'
        )

        local id = NetworkGetNetworkIdFromEntity(ped)

        check(reported[id], 'Animal not reported as slaughtered')
        check(GetEntityType(ped) == 1, 'Invalid animal entity')
        check(GetEntityModel(ped) == joaat(w.model), 'Animal model mismatch')
        check(NetworkGetEntityOwner(ped) == src, 'Invalid animal owner')

        check(
            GetEntityRoutingBucket(ped) == GetPlayerRoutingBucket(src),
            'Invalid animal routing bucket'
        )

        local pos = GetEntityCoords(ped)
        local playerPos = GetEntityCoords(GetPlayerPed(src))

        local distance = (pos.x - playerPos.x)^2
            + (pos.y - playerPos.y)^2
            + (pos.z - playerPos.z)^2

        check(distance <= 625, 'Animal is too far away')
    end

    local payload = w.data
    local hits = w.hits

    unlock(src)

    return action(src, 'slaughter', payload, hits + 10,w.token)
end
 if a=='workHit' then
  local w=sessions[src];check(w and w.phase==nil and w.actor==who and w.token==d.token,'Work session expired')
  local now=GetGameTimer();check(now<=w.expires,'Work session expired')
  local b=prop:FarmBuilding(w.plot,w.id,who);local f=row(w.id)
  check(f and b and near(src,b) and authorized(src,f,b),'Return to facility')
  local elapsed=now-w.started
  if elapsed<300 then w.started=now;TriggerClientEvent(E..'workRound',src,{token=w.token,target=w.target,round=w.round,action=w.action});return end
  local phase=(elapsed%1800)/1800
  if math.abs(phase-w.target)<=.13 then w.hits=w.hits+1 end
  w.round=w.round+1
  if w.round>5 then
   if w.action=='slaughter' then
    local ss=state(f);local n=tonumber(w.data.count);local sex=w.data.sex
    check(ss.species and ss.species~='horse' and (sex=='male' or sex=='female') and n and n%1==0 and n>=1 and n<=ss[sex],'Invalid selection')
    local model=C.species[ss.species][sex];local amount=n
    -- RedM client native loads the model and creates the networked ped.
    -- Server chooses all models/locations, records preexisting peds and validates replication.
    w.animals={};w.points={};w.model=model;w.existing={}
    for _,ped in ipairs(GetAllPeds()) do w.existing[ped]=true end
    for i=1,amount do
     local angle=i*2.39996;local x,y=R.world(b,math.cos(angle)*b.width*.25,math.sin(angle)*b.length*.25)
     w.points[i]={x=x,y=y,z=b.z,heading=b.heading}
    end
    w.phase='spawning';w.expires=GetGameTimer()+30000
    TriggerClientEvent(E..'slaughterSpawn',src,{token=w.token,model=model,points=w.points,facility=w.id});return
   end
   unlock(src);TriggerClientEvent(E..'workEnd',src)
   return action(src,w.action,w.data,w.hits,w.token)
  end
  w.started=GetGameTimer();w.target=math.random(25,75)/100
  TriggerClientEvent(E..'workRound',src,{token=w.token,target=w.target,round=w.round,action=w.action})
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
 check(not locked(f.id),'Facility busy or pending transaction')
 local s=state(f)
 -- Keep the validated action snapshot stable for the five-round work session.
 if score==nil then R.advance(s,os.time(),b.size);save(f,s) end
 if workLocks[f.id] then error('Facility is being worked',0) end
 local physical=C.work[a] or a=='fill' or a=='fertilizer'
 if physical then validateWork(src,f,b,s,a,d);if score==nil then farmWork(src,a) end end
 if C.work[a] and score==nil and not (a=='collect' and s.species=='chicken') then
  check(not sessions[src],'Finish your current work first')
  if a=='water' or a=='feed' then d.quantity=R.supply(s,b,a,d.quantity).units end
  local w={id=f.id,plot=f.plot,actor=who,token=uuid(),action=a,data=d,hits=0,round=1,started=GetGameTimer(),expires=GetGameTimer()+60000,target=math.random(25,75)/100}
  sessions[src]=w;workLocks[f.id]=src
  TriggerClientEvent(E..'workRound',src,{token=w.token,target=w.target,round=1,action=a})
  return
 end
 if physical then farmWork(src,a,workKey or uuid()) end
 if a=='link' then
  check(biz:FarmStockValid(f.plot,f.owner_type,f.owner_id,d.storage),'Invalid stock chest')
  MySQL.update.await('UPDATE ff_facilities SET storage=? WHERE id=?',{d.storage,f.id})
 elseif a=='unlink' then
  MySQL.update.await('UPDATE ff_facilities SET storage=NULL WHERE id=?',{f.id})
 elseif a=='release' then
  check(not s.crop and R.count(s)==0 and s.products==0 and math.floor(s.manure)==0,'Empty facility before releasing')
  MySQL.update.await('DELETE FROM ff_facilities WHERE id=?',{f.id})
 elseif a=='plant' then
  check(b.kind=='field' and not s.crop and C.crops[d.crop],'Invalid crop or occupied field');tool(src,'hoe')
  s.crop=d.crop;s.growth=0;s.dead=false;s.fertilized=false;s.neglect=0;s.water=0;s.harvestRemaining=nil;s.seedRemaining=nil
  batch(f,s,{{item='farm_seed_'..d.crop,count=-C.fieldCapacity[b.size]}})
 elseif a=='water' then
  check(s.crop and not s.dead or R.count(s)>0,'Nothing to water');tool(src,'water')
  local plan,e=R.supply(s,b,'water',d.quantity);check(plan,e)
  s.water=math.min(plan.maximum,s.water+plan.perUnit*plan.units*(1+(score or 0)*.05))
  batch(f,s,{{item='farm_water',count=-plan.units}})
  notice(src,('Added %d water units.'):format(plan.units))
 elseif a=='fertilize' then
  check(s.crop and not s.dead and not s.fertilized,'No eligible crop');tool(src,'fork');s.fertilized=true
  batch(f,s,{{item='farm_fertilizer',count=-math.ceil(C.fieldCapacity[b.size]/25)}})
 elseif a=='clearCrop' then
  check(s.crop and s.dead,'Only dead crops can be cleared');tool(src,'hoe');s.crop=nil;s.dead=false;s.growth=0;s.water=0;save(f,s)
 elseif a=='harvest' then
  check(s.crop and not s.dead and s.growth>=1,'Crop not ready');tool(src,'sickle')
  local crop=s.crop;local output,seeds=R.harvest(s,b.size,score)
  local changes={{item='farm_'..crop,count=output}}
  if seeds>0 then changes[#changes+1]={item='farm_seed_'..crop,count=seeds} end
  s.crop=nil;s.growth=0;s.water=0;s.soil=math.max(60,s.soil-1);s.harvestRemaining=nil;s.seedRemaining=nil;s.fertilized=false
  batch(f,s,changes)
  notice(src,('Harvest complete: %d %s and %d seeds deposited into linked chest.'):format(output,itemName('farm_'..crop),seeds))
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
 elseif a=='mountHorse' then
  return checkout(src,f,b,s,d.horse)
 elseif a=='listHorse' or a=='unlistHorse' then
  local h=horseById(s,d.horse);check(s.species=='horse' and h,'Horse unavailable')
  if a=='listHorse' then
   check(biz:VerifyLicense(f.owner_type,f.owner_id,'agriculture'),'Agriculture license required')
   local price=tonumber(d.price);check(price and price%1==0 and price>=1 and price<=100000000,'Invalid price')
   h.listed=price
  else h.listed=nil end
  save(f,s)
 elseif a=='trainHorse' then
  check(s.species=='horse','Horse enclosure required')
  local h;for _,v in ipairs(s.horses or {}) do if v.id==d.horse then h=v;break end end
  check(h and not h.listed and h.health>=60 and h.age>=C.species.horse.mature*3600 and os.time()-(h.trainedAt or 0)>=C.horseTrainingInterval,'Horse cannot train now')
  h.training=math.min(100,h.training+2+(score or 0));h.trainedAt=os.time();save(f,s)
 elseif a=='feed' then
  check(s.species and R.count(s)>0,'No animals');tool(src,'fork')
  local plan,e=R.supply(s,b,'feed',d.quantity);check(plan,e)
  s.feed=math.min(plan.maximum,s.feed+plan.units*plan.perUnit*(1+(score or 0)*.05))
  local food=C.species[s.species].feed;if s.species=='pig' and C.pigFeed[d.food] then food=d.food end
  batch(f,s,{{item=food,count=-plan.units}})
  notice(src,('Added %d %s.'):format(plan.units,itemName(food)))
 elseif a=='collect' then
  check(s.species and C.species[s.species].product and s.products>=1,'No products available')
  if s.species~='chicken' then tool(src,s.species=='sheep' and 'shear' or 'milk') end
  local n=math.floor(s.products*(s.species=='chicken' and 1 or (1+(score or 0)*.05)));s.products=0
  local item=C.species[s.species].product;batch(f,s,{{item=item,count=n}});notice(src,('Collected %d %s into linked chest.'):format(n,itemName(item)))
 elseif a=='manure' then
  tool(src,'fork');local n=math.floor(s.manure);check(n>0,'No manure available');s.manure=s.manure-n;batch(f,s,{{item='farm_manure',count=n}})
 elseif a=='slaughter' then
  check(score and score>=10 and s.species and s.species~='horse','Complete physical slaughter first');tool(src,'knife')
  local n=tonumber(d.count);local sex=d.sex
  check((sex=='female' or sex=='male') and n and n%1==0 and n>=1 and n<=s[sex],'Invalid animal selection')
  local yield=({chicken=1,pig=4,sheep=3,cattle=8})[s.species]
  s[sex]=s[sex]-n
  local changes={{item='farm_meat',count=math.floor(n*yield*(1+(score-10)*.05))}}
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
 if not ok then if src then notice(src,err);if sessions[src] and sessions[src].phase~='slaughter' then unlock(src);TriggerClientEvent(E..'workEnd',src) end else print('[frontier_farming] '..tostring(err)) end end
end
RegisterNetEvent(E..'action',function(a,d)
 local src=source;if type(a)~='string' or type(d)~='table' then return end
 local t=GetGameTimer();if a~='slaughterSpawned' and a~='slaughterSpawnFailed' and a~='cancelWork' and rate[src] and t-rate[src]<400 then return end;rate[src]=t
 run(src,function() action(src,a,d) end)
end)
AddEventHandler('playerDropped',function() local src=source;unlock(src);waterWork[src]=nil;rate[src]=nil;CreateThread(function() if ready then while busy do Wait(100) end;run(nil,function() returnMount(src) end) end end) end)
AddEventHandler('frontier:playerUnloaded',function(p) local src=p.source;unlock(src);waterWork[src]=nil;CreateThread(function() if ready then while busy do Wait(100) end;run(nil,function() returnMount(src) end) end end) end)
CreateThread(function() while true do Wait(1000);for src,w in pairs(sessions) do if GetGameTimer()>w.expires then unlock(src);TriggerClientEvent(E..'workEnd',src) end end end end)
exports('FacilityBound',function(id) return not ready or busy or row(id)~=nil end)
exports('DrainCompany',function(id)
 if GetInvokingResource()~='frontier_business' or not ready or busy then return false end
 busy=true
 local ok,result=pcall(function()
  for _,f in ipairs(MySQL.query.await("SELECT * FROM ff_facilities WHERE owner_type='company' AND owner_id=?",{id})) do
   if locked(f.id) then return false end
   check(MySQL.transaction.await({{query='INSERT INTO ff_confiscations(id,facility,plot,owner_type,owner_id,snapshot,reason,created) VALUES(?,?,?,?,?,?,?,?)',values={uuid(),f.id,f.plot,f.owner_type,f.owner_id,f.state,'company_liquidation',os.time()}},{query='DELETE FROM ff_facilities WHERE id=?',values={f.id}}}),'Liquidation audit failed')
  end
  return true
 end)
 busy=false;return ok and result==true
end)
MySQL.ready(function()
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS ff_water_sites(id CHAR(32) PRIMARY KEY,x DOUBLE NOT NULL,y DOUBLE NOT NULL,z DOUBLE NOT NULL,name VARCHAR(64) NOT NULL)]])
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS ff_confiscations(id CHAR(32) PRIMARY KEY,facility CHAR(32) NOT NULL,plot CHAR(32) NOT NULL,owner_type VARCHAR(16) NOT NULL,owner_id VARCHAR(64) NOT NULL,snapshot LONGTEXT NOT NULL,reason VARCHAR(32) NOT NULL,created BIGINT NOT NULL)]])
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS ff_horse_sales(id CHAR(32) PRIMARY KEY,source_id CHAR(32) NOT NULL,dest_id CHAR(32) NOT NULL,source_state LONGTEXT NOT NULL,dest_state LONGTEXT NOT NULL,debit BIGINT NOT NULL,credit BIGINT NOT NULL,amount BIGINT NOT NULL,phase VARCHAR(16) NOT NULL,INDEX(source_id,phase),INDEX(dest_id,phase))]])
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS ff_animal_orders(order_id CHAR(32) PRIMARY KEY,facility CHAR(32) NOT NULL,after_state LONGTEXT NOT NULL,INDEX(facility))]])
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
   for _,j in ipairs(MySQL.query.await("SELECT * FROM ff_horse_sales WHERE phase='payment' LIMIT 50")) do local ok,e=horseSaleStep(j);if not ok then print('[frontier_farming] horse sale '..j.id..': '..tostring(e)) end end
   for _,j in ipairs(MySQL.query.await("SELECT * FROM ff_orders WHERE phase IN ('payment','paid') ORDER BY created LIMIT 50")) do local ok,e=orderStep(j);if not ok then print('[frontier_farming] supply order '..j.id..': '..tostring(e)) end end
   for _,j in ipairs(MySQL.query.await('SELECT * FROM ff_operations')) do
    local ok,err=finish(j)
    if not ok and ({insufficient_stock=true,weight=true,slots=true,stack_conflict=true,conflict=true,invalid_item=true})[err] then MySQL.update.await('DELETE FROM ff_operations WHERE id=?',{j.id}) end
   end
   for _,f in ipairs(MySQL.query.await('SELECT * FROM ff_facilities')) do if not locked(f.id) then
    local s=state(f);local b=prop:FarmBuilding(f.plot,f.id,f.owner_id)
    if b then R.advance(s,os.time(),f.size);save(f,s)
     -- Eggs remain in the enclosure until the player selects Collect eggs.
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
     local f=row(b.id);if f then local s=state(f);if mountLocks[f.id] and s.horses then local m=mounts[mountLocks[f.id]];if m then for i=#s.horses,1,-1 do if s.horses[i].id==m.horse then table.remove(s.horses,i) end end;R.horseCounts(s) end end;local lock=workLocks[f.id] and sessions[workLocks[f.id]];result[#result+1]={b=b,crop=s.crop,growth=s.growth,dead=s.dead,species=(not lock or (lock.phase~='slaughter' and lock.phase~='spawning')) and s.species or nil,female=s.female,male=s.male,young=s.young,horses=s.horses} elseif b.kind=='field' then result[#result+1]={b=b,growth=0} end
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

AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then for src in pairs(sessions) do unlock(src) end;for _,m in pairs(mounts) do if DoesEntityExist(m.ped) then DeleteEntity(m.ped) end end end end)

exports('OpenHorseMarket',function(src)
 if GetInvokingResource()~='frontier_trade' then return false end
 run(src,function() horseMarket(src) end);return true
end)

CreateThread(function()
 while true do Wait(2000)
  if ready and not busy then
   run(nil,function()
    for src,m in pairs(mounts) do if cid(src)~=m.actor or os.time()>=m.expires or not DoesEntityExist(m.ped) or GetEntityHealth(m.ped)<=0 then returnMount(src) end end
    for src,w in pairs(waterWork) do if GetGameTimer()-w.started>C.waterFillMs+15000 then waterWork[src]=nil end end
   end)
  end
 end
end)
RegisterCommand('farmwatersite',function(src,args)
 if src==0 or not IsPlayerAceAllowed(src,'frontier.farming.admin') then return end
 run(src,function()
  local ped=GetPlayerPed(src);check(ped~=0 and GetPlayerRoutingBucket(src)==0,'Stand at a real water access point')
  local v=GetEntityCoords(ped);local name=table.concat(args,' '):sub(1,64)
  if name=='' then name='River access' end
  MySQL.insert.await('INSERT INTO ff_water_sites(id,x,y,z,name) VALUES(?,?,?,?,?)',{uuid(),v.x,v.y,v.z,name})
  notice(src,'Water collection point registered: '..name)
 end)
end,false)
RegisterCommand('farmwaterremove',function(src,args)
 if src==0 or not IsPlayerAceAllowed(src,'frontier.farming.admin') then return end
 run(src,function() local q=siteNear(src);check(q,'No nearby collection point');MySQL.update.await('DELETE FROM ff_water_sites WHERE id=?',{q.id});notice(src,'Water collection point removed') end)
end,false)
exports('StorageBound',function(storage)
 if GetInvokingResource()~='frontier_business' or not ready then return true end
 return MySQL.single.await('SELECT id FROM ff_facilities WHERE storage=? LIMIT 1',{storage})~=nil or MySQL.single.await("SELECT id FROM ff_orders WHERE storage=? AND phase IN ('payment','paid') LIMIT 1",{storage})~=nil
end)
exports('DrainPlot',function(plot)
 if GetInvokingResource()~='frontier_property' or not ready or busy then return false end
 busy=true
 local ok,result=pcall(function()
  for _,f in ipairs(MySQL.query.await('SELECT * FROM ff_facilities WHERE plot=?',{plot})) do
   if locked(f.id) then return false end
   check(MySQL.transaction.await({{query='INSERT INTO ff_confiscations(id,facility,plot,owner_type,owner_id,snapshot,reason,created) VALUES(?,?,?,?,?,?,?,?)',values={uuid(),f.id,f.plot,f.owner_type,f.owner_id,f.state,'plot_foreclosure',os.time()}},{query='DELETE FROM ff_facilities WHERE id=?',values={f.id}}}),'Foreclosure audit failed')
  end
  return true
 end)
 busy=false;return ok and result==true
end)
);return species and C.species[species] and (sex=='male' or sex=='female') and species or false end)()} end
 table.sort(list,function(a,b)return a.name<b.name end)
 local orders=MySQL.query.await("SELECT id,item,quantity,amount,phase FROM ff_orders WHERE actor=? AND phase IN ('payment','paid') ORDER BY created DESC",{who})
 local destinations={}
 for _,f in ipairs(MySQL.query.await('SELECT * FROM ff_facilities ORDER BY kind,size')) do
  local b=prop:FarmBuilding(f.plot,f.id,who)
  if b and authorized(src,f,b) then destinations[#destinations+1]={id=f.id,name=f.size..' '..f.kind..' · '..f.owner_type,kind=f.kind} end
 end
 TriggerClientEvent(E..'shop',src,{items=list,orders=orders,destinations=destinations})
end
local function buySupply(src,d)
 local who=cid(src);check(who and supplier(src),'Approach an agricultural supplier')
 local price=C.supplyPrices[d.item];local qty=tonumber(d.quantity)
 check(price and qty and qty%1==0 and qty>=1 and qty<=1000,'Invalid purchase')
 check(not MySQL.single.await("SELECT id FROM ff_orders WHERE actor=? AND phase IN ('payment','paid')",{who}),'Resolve your pending order first')
 local typ,owner,storage,bank='character',who,'',0
 local animal,sex=d.item:match('^farm_(%a+)_(%a+)$')
 if not C.species[animal] or (sex~='female' and sex~='male') then animal=nil end
 local delivery
 if animal then
  local f=row(d.facility);check(f and not locked(f.id),'Choose an available destination facility ID')
  local b=prop:FarmBuilding(f.plot,f.id,who);check(b and authorized(src,f,b),'Unauthorized destination')
  check((b.kind=='chicken' and animal=='chicken') or (b.kind=='livestock' and animal~='chicken'),'Wrong enclosure type')
  local st=state(f);R.advance(st,os.time(),f.size)
  check(not st.species or st.species==animal or R.count(st)==0 and st.products==0 and math.floor(st.manure)==0,'Different species in enclosure')
  check(R.count(st)+qty<=C.species[animal].capacity[f.size],'Not enough capacity')
  typ,owner,storage=f.owner_type,f.owner_id,''
  if typ=='character' then local ok,a=eco:GetCharacterAccounts(src);check(ok and a.characterId==who,'Bank unavailable');bank=a.bank.id end
  st.species=animal
  if animal=='horse' then
   local breed=d.breed or 'turkoman';check(C.horseBreeds[breed],'Unknown breed')
   st.horses=st.horses or {}
   for i=1,qty do st.horses[#st.horses+1]=R.newHorse(uuid(),breed,sex,d.juvenile==true) end
   R.horseCounts(st)
  elseif d.juvenile then if st.young==0 then st.matureClock=0 end;st.young=st.young+qty
  else st[sex]=st[sex]+qty end
  if d.juvenile then price=math.max(1,math.floor(price*.6)) end
  delivery={facility=f.id,after_state=json.encode(st)}
 end
 if not delivery and type(d.facility)=='string' and d.facility~='' then
  local f=row(d.facility);check(f and f.owner_type=='company' and biz:CanUseProperty(f.owner_id,who,f.plot,'farm') and stockValid(f),'Authorized company facility and linked chest required')
  check(C.items[d.item].maxStack~=1,'Purchase personal tools separately')
  typ,owner,storage='company',f.owner_id,f.storage
 elseif not delivery then
  local ok,accounts=eco:GetCharacterAccounts(src);check(ok and accounts.characterId==who,'Bank unavailable');bank=accounts.bank.id
 end
 local j={id=uuid(),actor=who,owner_type=typ,owner_id=owner,storage=storage,bank=bank,item=d.item,quantity=qty,amount=price*qty,phase='payment'}
 local statements={{query='INSERT INTO ff_orders(id,actor,owner_type,owner_id,storage,bank,item,quantity,amount,phase,created) VALUES(?,?,?,?,?,?,?,?,?,?,?)',values={j.id,who,typ,owner,storage,bank,j.item,qty,j.amount,j.phase,os.time()}}}
 if delivery then statements[#statements+1]={query='INSERT INTO ff_animal_orders(order_id,facility,after_state) VALUES(?,?,?)',values={j.id,delivery.facility,delivery.after_state}} end
 check(MySQL.transaction.await(statements),'Could not persist order')
 local ok,e=orderStep(j);notice(src,ok and 'Supplies purchased' or ('Order pending or rejected: '..tostring(e)));shopView(src)
end


local function returnMount(src)
 local m=mounts[src];if not m then return end
 local f=row(m.facility)
 if f then
  local st=state(f);R.advance(st,os.time(),f.size)
  local h,i=horseById(st,m.horse)
  if h and DoesEntityExist(m.ped) and GetEntityHealth(m.ped)<=0 then table.remove(st.horses,i);R.horseCounts(st) end
  save(f,st)
 end
 if DoesEntityExist(m.ped) then DeleteEntity(m.ped) end
 mounts[src]=nil;mountLocks[m.facility]=nil
 TriggerClientEvent(E..'mountReturned',src)
end
local function checkout(src,f,b,st,id)
 check(not mounts[src],'Return your current mount first')
 local h=horseById(st,id)
 check(h and not h.listed and h.health>=30 and h.age>=C.species.horse.mature*3600,'Horse is not available to ride')
 local p=GetEntityCoords(GetPlayerPed(src))
 local ped=CreatePed(joaat(C.horseBreeds[h.breed].model),p.x+2.0,p.y,p.z+0.4,b.heading,true,true)
 check(ped and ped~=0 and DoesEntityExist(ped),'Network mount unavailable')
 SetEntityRoutingBucket(ped,GetPlayerRoutingBucket(src))
 local net=NetworkGetNetworkIdFromEntity(ped)
 if not net or net==0 then DeleteEntity(ped);error('Mount network ID unavailable',0) end
 mounts[src]={actor=cid(src),horse=h.id,facility=f.id,ped=ped,expires=os.time()+C.mountMaxSeconds}
 mountLocks[f.id]=src
 TriggerClientEvent(E..'mount',src,{id=net,horse=h})
end
local function siteNear(src)
 local ped=GetPlayerPed(src);if ped==0 or GetPlayerRoutingBucket(src)~=0 then return end
 local v=GetEntityCoords(ped)
 for _,q in ipairs(MySQL.query.await('SELECT * FROM ff_water_sites')) do
  if (v.x-q.x)^2+(v.y-q.y)^2+(v.z-q.z)^2<=C.waterSiteRadius^2 then return q end
 end
end
local function farmWork(src,a,key)
 check(GetResourceState('frontier_needs')=='started','Needs unavailable')
 local ok,why
 if key then ok,why=exports.frontier_needs:SpendLabour(src,a,key,1)
 else ok,why=exports.frontier_needs:CanWork(src,a,1) end
 check(ok,why)
end
local function beginWater(src)
 tool(src,'bucket');check(not waterWork[src],'Already filling a bucket')
 local q=siteNear(src);check(q,'Approach an approved river or lake collection point')
 farmWork(src,'fill')
 local w={actor=cid(src),id=uuid(),site=q.id,started=GetGameTimer()}
 waterWork[src]=w;TriggerClientEvent(E..'waterWork',src,{token=w.id,ms=C.waterFillMs})
end
local function finishWater(src,d)
 local w=waterWork[src];check(w and w.actor==cid(src) and w.id==d.token,'Water collection expired')
 local t=GetGameTimer()-w.started;check(t>=C.waterFillMs and t<=C.waterFillMs+15000,'Invalid filling duration')
 local q=siteNear(src);check(q and q.id==w.site,'Remain near the water source');tool(src,'bucket')
 farmWork(src,'fill',w.id)
 local ok,e=inv:FarmSupplyDelivery(w.actor,'farm_water',10,'farm_water_'..w.id)
 check(ok,e);waterWork[src]=nil;notice(src,'Filled 10 water units. Carry them back to your farm stock.')
end


local function validateWork(src,f,b,s,a,d)
 local changes={}
 local key=C.work[a]
 if a=='collect' then
  check(s.species and C.species[s.species] and C.species[s.species].product and s.products>=1,'No products ready to collect')
  key=s.species=='chicken' and nil or s.species=='sheep' and 'shear' or 'milk'
  if s.species=='chicken' then key=nil end
  changes={{item=C.species[s.species].product,count=math.floor(s.products*(s.species=='chicken' and 1 or 1.25))}}
 elseif a=='plant' then
  check(b.kind=='field' and not s.crop and C.crops[d.crop],'Choose a crop for an empty field')
  changes={{item='farm_seed_'..d.crop,count=-C.fieldCapacity[b.size]}}
 elseif a=='water' or a=='feed' then
  local plan,err=R.supply(s,b,a,d.quantity);check(plan,err)
  local item='farm_water'
  if a=='feed' then item=C.species[s.species].feed;if s.species=='pig' and C.pigFeed[d.food] then item=d.food end end
  changes={{item=item,count=-plan.units}}
 elseif a=='fertilize' then
  check(b.kind=='field' and s.crop and not s.dead and not s.fertilized and s.growth<1,'Only an unfertilized growing crop can be fertilized')
  changes={{item='farm_fertilizer',count=-math.ceil(C.fieldCapacity[b.size]/25)}}
 elseif a=='clearCrop' then check(b.kind=='field' and s.crop and s.dead,'No dead crops to clear')
 elseif a=='harvest' then
  check(b.kind=='field' and s.crop and not s.dead and s.growth>=1,'Crop not ready to harvest')
  local output,seeds=R.harvest(s,b.size,5)
  changes={{item='farm_'..s.crop,count=output}}
  if seeds>0 then changes[#changes+1]={item='farm_seed_'..s.crop,count=seeds} end
 elseif a=='manure' then
  check(math.floor(s.manure)>0,'No manure ready to collect')
  changes={{item='farm_manure',count=math.floor(s.manure)}}
 elseif a=='slaughter' then
  check(s.species and s.species~='horse','No eligible livestock')
  local n,sex=tonumber(d.count),d.sex
  check((sex=='male' or sex=='female') and n and n%1==0 and n>=1 and n<=s[sex],'Choose a valid number of adult animals')
  changes={{item='farm_meat',count=math.floor(n*({chicken=1,pig=4,sheep=3,cattle=8})[s.species]*1.25)}}
  if s.species~='chicken' then changes[#changes+1]={item='farm_hide',count=n} end
 elseif a=='trainHorse' then
  local h=horseById(s,d.horse)
  check(s.species=='horse' and h and not h.listed and h.health>=60 and h.training<100 and h.age>=C.species.horse.mature*3600 and os.time()-(h.trainedAt or 0)>=C.horseTrainingInterval,'Horse not eligible for training (adult, healthy, unlisted, cooldown complete, training below 100)')
  key=nil
 elseif a=='fill' then
  check(b.kind=='well','Approach a constructed well');key='bucket';changes={{item='farm_water',count=10}}
 elseif a=='fertilizer' then
  check(b.kind=='field','Use at a field');changes={{item='farm_manure',count=-5},{item='farm_fertilizer',count=1}}
 end
 if key then tool(src,key) end
 if #changes>0 then preflight(f,changes) end
end

local function action(src,a,d,score,workKey)
 local who=cid(src);check(who,'Select a character first')
 if a=='open' then return view(src) end
 if a=='openFacility' then
  if sessions[src] then notice(src,'Finish or cancel your current farm work first');return end
  local b=get(src,d.id);check(b and near(src,b),'Approach a completed farm facility')
  return view(src,b.id)
 end
 if a=='riverStart' then return beginWater(src) end
 if a=='riverFinish' then return finishWater(src,d) end
 if a=='returnMount' then check(mounts[src] and mounts[src].actor==who,'No mount checked out');return returnMount(src) end
 if a=='shop' then return shopView(src) end
 if a=='horseMarket' then return horseMarket(src) end
 if a=='buyHorse' then return buyHorse(src,d) end
 if a=='buySupply' then return buySupply(src,d) end
 if a=='cancelWork' then unlock(src);waterWork[src]=nil;TriggerClientEvent(E..'workEnd',src);if d.reopen then return view(src) end;return end
 if a=='slaughterSpawnFailed' then
  local w=sessions[src];check(w and w.actor==who and w.phase=='spawning' and d.token==w.token,'No pending animal spawn')
  unlock(src);TriggerClientEvent(E..'workEnd',src)
  error('Could not create networked animals on your client. No livestock consumed. Check client F8 console.',0)
 end
 if a=='slaughterSpawned' then
  local w=sessions[src];check(w and w.actor==who and w.phase=='spawning' and d.token==w.token,'No pending animal spawn')
  check(GetGameTimer()<=w.expires,'Animal spawn timed out')
  local f=row(w.id);local b=f and current(src,f);check(b and not pending(w.id),'Facility unavailable')
  check(type(d.ids)=='table' and #d.ids==#w.points,'Incorrect number of networked animals')
  local seen={};local deadline=GetGameTimer()+4000
  for i,id in ipairs(d.ids) do
   check(type(id)=='number' and id%1==0 and id>0 and not seen[id],'Invalid or duplicate animal network ID')
   seen[id]=true
   local ped=NetworkGetEntityFromNetworkId(id)
   while (not ped or ped==0 or not DoesEntityExist(ped)) and GetGameTimer()<deadline do Wait(50);ped=NetworkGetEntityFromNetworkId(id) end
   check(sessions[src]==w,'Animal spawn cancelled')
   check(ped and ped~=0 and DoesEntityExist(ped),'Network animal did not replicate to server (check OneSync and entity lockdown)')
   local validationDeadline = GetGameTimer() + 3000

while GetGameTimer() < validationDeadline do
    check(sessions[src] == w, 'Animal spawn cancelled')

    if GetEntityType(ped) == 1
        and NetworkGetEntityOwner(ped) == src
        and GetEntityModel(ped) == joaat(w.model)
        then
        break
    end

    Wait(50)
end

check(not w.existing[ped], 'Animal already existed')
check(GetEntityType(ped) == 1, 'Invalid animal entity type')
check(NetworkGetEntityOwner(ped) == src, 'Invalid animal network owner')
check(GetEntityModel(ped) == joaat(w.model), 'Animal model mismatch')
   check(GetEntityRoutingBucket(ped)==GetPlayerRoutingBucket(src),'Animal is in the wrong routing bucket')
   local pos=GetEntityCoords(ped);local p=w.points[i]
   check((pos.x-p.x)^2+(pos.y-p.y)^2<=9 and math.abs(pos.z-p.z)<5,'Animal spawned outside the assigned position')
   w.animals[#w.animals+1]=ped
  end
  w.phase='slaughter';w.expires=GetGameTimer()+300000;w.existing=nil;w.points=nil
  TriggerClientEvent(E..'slaughter',src,{token=w.token,ids=d.ids,count=#w.animals});return
 end
 if a == 'slaughterFinish' then
    local w = sessions[src]

    check(
        w and w.actor == who
        and w.phase == 'slaughter'
        and d.token == w.token
        and GetGameTimer() <= w.expires,
        'No active slaughter session'
    )

    local f = row(w.id)
    local b = f and current(src, f)

    check(b and not pending(w.id), 'Facility unavailable')
    check(near(src, b), 'Return to the slaughter facility')

    tool(src, 'knife')

    check(
        type(d.deadIds) == 'table'
        and #d.deadIds == #w.animals,
        'All selected animals must be slaughtered first'
    )

    local reported = {}

    for _, id in ipairs(d.deadIds) do
        check(
            type(id) == 'number'
            and id > 0
            and id % 1 == 0
            and not reported[id],
            'Invalid or duplicate animal network ID'
        )

        reported[id] = true
    end

    for _, ped in ipairs(w.animals) do
        check(
            DoesEntityExist(ped),
            'Slaughter animal no longer exists'
        )

        local id = NetworkGetNetworkIdFromEntity(ped)

        check(reported[id], 'Animal not reported as slaughtered')
        check(GetEntityType(ped) == 1, 'Invalid animal entity')
        check(GetEntityModel(ped) == joaat(w.model), 'Animal model mismatch')
        check(NetworkGetEntityOwner(ped) == src, 'Invalid animal owner')

        check(
            GetEntityRoutingBucket(ped) == GetPlayerRoutingBucket(src),
            'Invalid animal routing bucket'
        )

        local pos = GetEntityCoords(ped)
        local playerPos = GetEntityCoords(GetPlayerPed(src))

        local distance = (pos.x - playerPos.x)^2
            + (pos.y - playerPos.y)^2
            + (pos.z - playerPos.z)^2

        check(distance <= 625, 'Animal is too far away')
    end

    local payload = w.data
    local hits = w.hits

    unlock(src)

    return action(src, 'slaughter', payload, hits + 10,w.token)
end
 if a=='workHit' then
  local w=sessions[src];check(w and w.phase==nil and w.actor==who and w.token==d.token,'Work session expired')
  local now=GetGameTimer();check(now<=w.expires,'Work session expired')
  local b=prop:FarmBuilding(w.plot,w.id,who);local f=row(w.id)
  check(f and b and near(src,b) and authorized(src,f,b),'Return to facility')
  local elapsed=now-w.started
  if elapsed<300 then w.started=now;TriggerClientEvent(E..'workRound',src,{token=w.token,target=w.target,round=w.round,action=w.action});return end
  local phase=(elapsed%1800)/1800
  if math.abs(phase-w.target)<=.13 then w.hits=w.hits+1 end
  w.round=w.round+1
  if w.round>5 then
   if w.action=='slaughter' then
    local ss=state(f);local n=tonumber(w.data.count);local sex=w.data.sex
    check(ss.species and ss.species~='horse' and (sex=='male' or sex=='female') and n and n%1==0 and n>=1 and n<=ss[sex],'Invalid selection')
    local model=C.species[ss.species][sex];local amount=n
    -- RedM client native loads the model and creates the networked ped.
    -- Server chooses all models/locations, records preexisting peds and validates replication.
    w.animals={};w.points={};w.model=model;w.existing={}
    for _,ped in ipairs(GetAllPeds()) do w.existing[ped]=true end
    for i=1,amount do
     local angle=i*2.39996;local x,y=R.world(b,math.cos(angle)*b.width*.25,math.sin(angle)*b.length*.25)
     w.points[i]={x=x,y=y,z=b.z,heading=b.heading}
    end
    w.phase='spawning';w.expires=GetGameTimer()+30000
    TriggerClientEvent(E..'slaughterSpawn',src,{token=w.token,model=model,points=w.points,facility=w.id});return
   end
   unlock(src);TriggerClientEvent(E..'workEnd',src)
   return action(src,w.action,w.data,w.hits,w.token)
  end
  w.started=GetGameTimer();w.target=math.random(25,75)/100
  TriggerClientEvent(E..'workRound',src,{token=w.token,target=w.target,round=w.round,action=w.action})
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
 check(not locked(f.id),'Facility busy or pending transaction')
 local s=state(f)
 -- Keep the validated action snapshot stable for the five-round work session.
 if score==nil then R.advance(s,os.time(),b.size);save(f,s) end
 if workLocks[f.id] then error('Facility is being worked',0) end
 local physical=C.work[a] or a=='fill' or a=='fertilizer'
 if physical then validateWork(src,f,b,s,a,d);if score==nil then farmWork(src,a) end end
 if C.work[a] and score==nil and not (a=='collect' and s.species=='chicken') then
  check(not sessions[src],'Finish your current work first')
  if a=='water' or a=='feed' then d.quantity=R.supply(s,b,a,d.quantity).units end
  local w={id=f.id,plot=f.plot,actor=who,token=uuid(),action=a,data=d,hits=0,round=1,started=GetGameTimer(),expires=GetGameTimer()+60000,target=math.random(25,75)/100}
  sessions[src]=w;workLocks[f.id]=src
  TriggerClientEvent(E..'workRound',src,{token=w.token,target=w.target,round=1,action=a})
  return
 end
 if physical then farmWork(src,a,workKey or uuid()) end
 if a=='link' then
  check(biz:FarmStockValid(f.plot,f.owner_type,f.owner_id,d.storage),'Invalid stock chest')
  MySQL.update.await('UPDATE ff_facilities SET storage=? WHERE id=?',{d.storage,f.id})
 elseif a=='unlink' then
  MySQL.update.await('UPDATE ff_facilities SET storage=NULL WHERE id=?',{f.id})
 elseif a=='release' then
  check(not s.crop and R.count(s)==0 and s.products==0 and math.floor(s.manure)==0,'Empty facility before releasing')
  MySQL.update.await('DELETE FROM ff_facilities WHERE id=?',{f.id})
 elseif a=='plant' then
  check(b.kind=='field' and not s.crop and C.crops[d.crop],'Invalid crop or occupied field');tool(src,'hoe')
  s.crop=d.crop;s.growth=0;s.dead=false;s.fertilized=false;s.neglect=0;s.water=0;s.harvestRemaining=nil;s.seedRemaining=nil
  batch(f,s,{{item='farm_seed_'..d.crop,count=-C.fieldCapacity[b.size]}})
 elseif a=='water' then
  check(s.crop and not s.dead or R.count(s)>0,'Nothing to water');tool(src,'water')
  local plan,e=R.supply(s,b,'water',d.quantity);check(plan,e)
  s.water=math.min(plan.maximum,s.water+plan.perUnit*plan.units*(1+(score or 0)*.05))
  batch(f,s,{{item='farm_water',count=-plan.units}})
  notice(src,('Added %d water units.'):format(plan.units))
 elseif a=='fertilize' then
  check(s.crop and not s.dead and not s.fertilized,'No eligible crop');tool(src,'fork');s.fertilized=true
  batch(f,s,{{item='farm_fertilizer',count=-math.ceil(C.fieldCapacity[b.size]/25)}})
 elseif a=='clearCrop' then
  check(s.crop and s.dead,'Only dead crops can be cleared');tool(src,'hoe');s.crop=nil;s.dead=false;s.growth=0;s.water=0;save(f,s)
 elseif a=='harvest' then
  check(s.crop and not s.dead and s.growth>=1,'Crop not ready');tool(src,'sickle')
  local crop=s.crop;local output,seeds=R.harvest(s,b.size,score)
  local changes={{item='farm_'..crop,count=output}}
  if seeds>0 then changes[#changes+1]={item='farm_seed_'..crop,count=seeds} end
  s.crop=nil;s.growth=0;s.water=0;s.soil=math.max(60,s.soil-1);s.harvestRemaining=nil;s.seedRemaining=nil;s.fertilized=false
  batch(f,s,changes)
  notice(src,('Harvest complete: %d %s and %d seeds deposited into linked chest.'):format(output,itemName('farm_'..crop),seeds))
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
 elseif a=='mountHorse' then
  return checkout(src,f,b,s,d.horse)
 elseif a=='listHorse' or a=='unlistHorse' then
  local h=horseById(s,d.horse);check(s.species=='horse' and h,'Horse unavailable')
  if a=='listHorse' then
   check(biz:VerifyLicense(f.owner_type,f.owner_id,'agriculture'),'Agriculture license required')
   local price=tonumber(d.price);check(price and price%1==0 and price>=1 and price<=100000000,'Invalid price')
   h.listed=price
  else h.listed=nil end
  save(f,s)
 elseif a=='trainHorse' then
  check(s.species=='horse','Horse enclosure required')
  local h;for _,v in ipairs(s.horses or {}) do if v.id==d.horse then h=v;break end end
  check(h and not h.listed and h.health>=60 and h.age>=C.species.horse.mature*3600 and os.time()-(h.trainedAt or 0)>=C.horseTrainingInterval,'Horse cannot train now')
  h.training=math.min(100,h.training+2+(score or 0));h.trainedAt=os.time();save(f,s)
 elseif a=='feed' then
  check(s.species and R.count(s)>0,'No animals');tool(src,'fork')
  local plan,e=R.supply(s,b,'feed',d.quantity);check(plan,e)
  s.feed=math.min(plan.maximum,s.feed+plan.units*plan.perUnit*(1+(score or 0)*.05))
  local food=C.species[s.species].feed;if s.species=='pig' and C.pigFeed[d.food] then food=d.food end
  batch(f,s,{{item=food,count=-plan.units}})
  notice(src,('Added %d %s.'):format(plan.units,itemName(food)))
 elseif a=='collect' then
  check(s.species and C.species[s.species].product and s.products>=1,'No products available')
  if s.species~='chicken' then tool(src,s.species=='sheep' and 'shear' or 'milk') end
  local n=math.floor(s.products*(s.species=='chicken' and 1 or (1+(score or 0)*.05)));s.products=0
  local item=C.species[s.species].product;batch(f,s,{{item=item,count=n}});notice(src,('Collected %d %s into linked chest.'):format(n,itemName(item)))
 elseif a=='manure' then
  tool(src,'fork');local n=math.floor(s.manure);check(n>0,'No manure available');s.manure=s.manure-n;batch(f,s,{{item='farm_manure',count=n}})
 elseif a=='slaughter' then
  check(score and score>=10 and s.species and s.species~='horse','Complete physical slaughter first');tool(src,'knife')
  local n=tonumber(d.count);local sex=d.sex
  check((sex=='female' or sex=='male') and n and n%1==0 and n>=1 and n<=s[sex],'Invalid animal selection')
  local yield=({chicken=1,pig=4,sheep=3,cattle=8})[s.species]
  s[sex]=s[sex]-n
  local changes={{item='farm_meat',count=math.floor(n*yield*(1+(score-10)*.05))}}
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
 if not ok then if src then notice(src,err);if sessions[src] and sessions[src].phase~='slaughter' then unlock(src);TriggerClientEvent(E..'workEnd',src) end else print('[frontier_farming] '..tostring(err)) end end
end
RegisterNetEvent(E..'action',function(a,d)
 local src=source;if type(a)~='string' or type(d)~='table' then return end
 local t=GetGameTimer();if a~='slaughterSpawned' and a~='slaughterSpawnFailed' and a~='cancelWork' and rate[src] and t-rate[src]<400 then return end;rate[src]=t
 run(src,function() action(src,a,d) end)
end)
AddEventHandler('playerDropped',function() local src=source;unlock(src);waterWork[src]=nil;rate[src]=nil;CreateThread(function() if ready then while busy do Wait(100) end;run(nil,function() returnMount(src) end) end end) end)
AddEventHandler('frontier:playerUnloaded',function(p) local src=p.source;unlock(src);waterWork[src]=nil;CreateThread(function() if ready then while busy do Wait(100) end;run(nil,function() returnMount(src) end) end end) end)
CreateThread(function() while true do Wait(1000);for src,w in pairs(sessions) do if GetGameTimer()>w.expires then unlock(src);TriggerClientEvent(E..'workEnd',src) end end end end)
exports('FacilityBound',function(id) return not ready or busy or row(id)~=nil end)
exports('DrainCompany',function(id)
 if GetInvokingResource()~='frontier_business' or not ready or busy then return false end
 busy=true
 local ok,result=pcall(function()
  for _,f in ipairs(MySQL.query.await("SELECT * FROM ff_facilities WHERE owner_type='company' AND owner_id=?",{id})) do
   if locked(f.id) then return false end
   check(MySQL.transaction.await({{query='INSERT INTO ff_confiscations(id,facility,plot,owner_type,owner_id,snapshot,reason,created) VALUES(?,?,?,?,?,?,?,?)',values={uuid(),f.id,f.plot,f.owner_type,f.owner_id,f.state,'company_liquidation',os.time()}},{query='DELETE FROM ff_facilities WHERE id=?',values={f.id}}}),'Liquidation audit failed')
  end
  return true
 end)
 busy=false;return ok and result==true
end)
MySQL.ready(function()
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS ff_water_sites(id CHAR(32) PRIMARY KEY,x DOUBLE NOT NULL,y DOUBLE NOT NULL,z DOUBLE NOT NULL,name VARCHAR(64) NOT NULL)]])
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS ff_confiscations(id CHAR(32) PRIMARY KEY,facility CHAR(32) NOT NULL,plot CHAR(32) NOT NULL,owner_type VARCHAR(16) NOT NULL,owner_id VARCHAR(64) NOT NULL,snapshot LONGTEXT NOT NULL,reason VARCHAR(32) NOT NULL,created BIGINT NOT NULL)]])
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS ff_horse_sales(id CHAR(32) PRIMARY KEY,source_id CHAR(32) NOT NULL,dest_id CHAR(32) NOT NULL,source_state LONGTEXT NOT NULL,dest_state LONGTEXT NOT NULL,debit BIGINT NOT NULL,credit BIGINT NOT NULL,amount BIGINT NOT NULL,phase VARCHAR(16) NOT NULL,INDEX(source_id,phase),INDEX(dest_id,phase))]])
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS ff_animal_orders(order_id CHAR(32) PRIMARY KEY,facility CHAR(32) NOT NULL,after_state LONGTEXT NOT NULL,INDEX(facility))]])
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
   for _,j in ipairs(MySQL.query.await("SELECT * FROM ff_horse_sales WHERE phase='payment' LIMIT 50")) do local ok,e=horseSaleStep(j);if not ok then print('[frontier_farming] horse sale '..j.id..': '..tostring(e)) end end
   for _,j in ipairs(MySQL.query.await("SELECT * FROM ff_orders WHERE phase IN ('payment','paid') ORDER BY created LIMIT 50")) do local ok,e=orderStep(j);if not ok then print('[frontier_farming] supply order '..j.id..': '..tostring(e)) end end
   for _,j in ipairs(MySQL.query.await('SELECT * FROM ff_operations')) do
    local ok,err=finish(j)
    if not ok and ({insufficient_stock=true,weight=true,slots=true,stack_conflict=true,conflict=true,invalid_item=true})[err] then MySQL.update.await('DELETE FROM ff_operations WHERE id=?',{j.id}) end
   end
   for _,f in ipairs(MySQL.query.await('SELECT * FROM ff_facilities')) do if not locked(f.id) then
    local s=state(f);local b=prop:FarmBuilding(f.plot,f.id,f.owner_id)
    if b then R.advance(s,os.time(),f.size);save(f,s)
     -- Eggs remain in the enclosure until the player selects Collect eggs.
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
     local f=row(b.id);if f then local s=state(f);if mountLocks[f.id] and s.horses then local m=mounts[mountLocks[f.id]];if m then for i=#s.horses,1,-1 do if s.horses[i].id==m.horse then table.remove(s.horses,i) end end;R.horseCounts(s) end end;local lock=workLocks[f.id] and sessions[workLocks[f.id]];result[#result+1]={b=b,crop=s.crop,growth=s.growth,dead=s.dead,species=(not lock or (lock.phase~='slaughter' and lock.phase~='spawning')) and s.species or nil,female=s.female,male=s.male,young=s.young,horses=s.horses} elseif b.kind=='field' then result[#result+1]={b=b,growth=0} end
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

AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then for src in pairs(sessions) do unlock(src) end;for _,m in pairs(mounts) do if DoesEntityExist(m.ped) then DeleteEntity(m.ped) end end end end)

exports('OpenHorseMarket',function(src)
 if GetInvokingResource()~='frontier_trade' then return false end
 run(src,function() horseMarket(src) end);return true
end)

CreateThread(function()
 while true do Wait(2000)
  if ready and not busy then
   run(nil,function()
    for src,m in pairs(mounts) do if cid(src)~=m.actor or os.time()>=m.expires or not DoesEntityExist(m.ped) or GetEntityHealth(m.ped)<=0 then returnMount(src) end end
    for src,w in pairs(waterWork) do if GetGameTimer()-w.started>C.waterFillMs+15000 then waterWork[src]=nil end end
   end)
  end
 end
end)
RegisterCommand('farmwatersite',function(src,args)
 if src==0 or not IsPlayerAceAllowed(src,'frontier.farming.admin') then return end
 run(src,function()
  local ped=GetPlayerPed(src);check(ped~=0 and GetPlayerRoutingBucket(src)==0,'Stand at a real water access point')
  local v=GetEntityCoords(ped);local name=table.concat(args,' '):sub(1,64)
  if name=='' then name='River access' end
  MySQL.insert.await('INSERT INTO ff_water_sites(id,x,y,z,name) VALUES(?,?,?,?,?)',{uuid(),v.x,v.y,v.z,name})
  notice(src,'Water collection point registered: '..name)
 end)
end,false)
RegisterCommand('farmwaterremove',function(src,args)
 if src==0 or not IsPlayerAceAllowed(src,'frontier.farming.admin') then return end
 run(src,function() local q=siteNear(src);check(q,'No nearby collection point');MySQL.update.await('DELETE FROM ff_water_sites WHERE id=?',{q.id});notice(src,'Water collection point removed') end)
end,false)
exports('StorageBound',function(storage)
 if GetInvokingResource()~='frontier_business' or not ready then return true end
 return MySQL.single.await('SELECT id FROM ff_facilities WHERE storage=? LIMIT 1',{storage})~=nil or MySQL.single.await("SELECT id FROM ff_orders WHERE storage=? AND phase IN ('payment','paid') LIMIT 1",{storage})~=nil
end)
exports('DrainPlot',function(plot)
 if GetInvokingResource()~='frontier_property' or not ready or busy then return false end
 busy=true
 local ok,result=pcall(function()
  for _,f in ipairs(MySQL.query.await('SELECT * FROM ff_facilities WHERE plot=?',{plot})) do
   if locked(f.id) then return false end
   check(MySQL.transaction.await({{query='INSERT INTO ff_confiscations(id,facility,plot,owner_type,owner_id,snapshot,reason,created) VALUES(?,?,?,?,?,?,?,?)',values={uuid(),f.id,f.plot,f.owner_type,f.owner_id,f.state,'plot_foreclosure',os.time()}},{query='DELETE FROM ff_facilities WHERE id=?',values={f.id}}}),'Foreclosure audit failed')
  end
  return true
 end)
 busy=false;return ok and result==true
end)
),'Invalid order reference')
  local prior=MySQL.single.await('SELECT * FROM ff_orders WHERE id=? AND actor=?',{orderId,who})
  if prior then local ok,e=orderStep(prior);return ok,ok and 'Existing farm order recovered.' or ('Farm order pending: '..tostring(e)) end
  check(type(d.facility)=='string' and d.facility~='','Select a destination for farm deliveries. Use the regular basket for personal supplies.')
 end
 local price=C.supplyPrices[d.item];local qty=tonumber(d.quantity)
 check(price and qty and qty%1==0 and qty>=1 and qty<=1000,'Invalid purchase')
 check(not MySQL.single.await("SELECT id FROM ff_orders WHERE actor=? AND phase IN ('payment','paid')",{who}),'Resolve your pending order first')
 local typ,owner,storage,bank='character',who,'',0
 local animal,sex=d.item:match('^farm_(%a+)_(%a+)$')
 if not C.species[animal] or (sex~='female' and sex~='male') then animal=nil end
 local delivery
 if animal then
  local f=row(d.facility);check(f and not locked(f.id),'Choose an available destination facility ID')
  local b=prop:FarmBuilding(f.plot,f.id,who);check(b and authorized(src,f,b),'Unauthorized destination')
  check((b.kind=='chicken' and animal=='chicken') or (b.kind=='livestock' and animal~='chicken'),'Wrong enclosure type')
  local st=state(f);R.advance(st,os.time(),f.size)
  check(not st.species or st.species==animal or R.count(st)==0 and st.products==0 and math.floor(st.manure)==0,'Different species in enclosure')
  check(R.count(st)+qty<=C.species[animal].capacity[f.size],'Not enough capacity')
  typ,owner,storage=f.owner_type,f.owner_id,''
  if typ=='character' then local ok,a=eco:GetCharacterAccounts(src);check(ok and a.characterId==who,'Bank unavailable');bank=a.bank.id end
  st.species=animal
  if animal=='horse' then
   local breed=d.breed or 'turkoman';check(C.horseBreeds[breed],'Unknown breed')
   st.horses=st.horses or {}
   for i=1,qty do st.horses[#st.horses+1]=R.newHorse(uuid(),breed,sex,d.juvenile==true) end
   R.horseCounts(st)
  elseif d.juvenile then if st.young==0 then st.matureClock=0 end;st.young=st.young+qty
  else st[sex]=st[sex]+qty end
  if d.juvenile then price=math.max(1,math.floor(price*.6)) end
  delivery={facility=f.id,after_state=json.encode(st)}
 end
 if not delivery and type(d.facility)=='string' and d.facility~='' then
  local f=row(d.facility);check(f and f.owner_type=='company' and biz:CanUseProperty(f.owner_id,who,f.plot,'farm') and stockValid(f),'Authorized company facility and linked chest required')
  check(C.items[d.item].maxStack~=1,'Purchase personal tools separately')
  typ,owner,storage='company',f.owner_id,f.storage
 elseif not delivery then
  local ok,accounts=eco:GetCharacterAccounts(src);check(ok and accounts.characterId==who,'Bank unavailable');bank=accounts.bank.id
 end
 local j={id=uuid(),actor=who,owner_type=typ,owner_id=owner,storage=storage,bank=bank,item=d.item,quantity=qty,amount=price*qty,phase='payment'}
 local statements={{query='INSERT INTO ff_orders(id,actor,owner_type,owner_id,storage,bank,item,quantity,amount,phase,created) VALUES(?,?,?,?,?,?,?,?,?,?,?)',values={j.id,who,typ,owner,storage,bank,j.item,qty,j.amount,j.phase,os.time()}}}
 if delivery then statements[#statements+1]={query='INSERT INTO ff_animal_orders(order_id,facility,after_state) VALUES(?,?,?)',values={j.id,delivery.facility,delivery.after_state}} end
 check(MySQL.transaction.await(statements),'Could not persist order')
 local ok,e=orderStep(j);notice(src,ok and 'Supplies purchased' or ('Order pending or rejected: '..tostring(e)));shopView(src)
end


local function returnMount(src)
 local m=mounts[src];if not m then return end
 local f=row(m.facility)
 if f then
  local st=state(f);R.advance(st,os.time(),f.size)
  local h,i=horseById(st,m.horse)
  if h and DoesEntityExist(m.ped) and GetEntityHealth(m.ped)<=0 then table.remove(st.horses,i);R.horseCounts(st) end
  save(f,st)
 end
 if DoesEntityExist(m.ped) then DeleteEntity(m.ped) end
 mounts[src]=nil;mountLocks[m.facility]=nil
 TriggerClientEvent(E..'mountReturned',src)
end
local function checkout(src,f,b,st,id)
 check(not mounts[src],'Return your current mount first')
 local h=horseById(st,id)
 check(h and not h.listed and h.health>=30 and h.age>=C.species.horse.mature*3600,'Horse is not available to ride')
 local p=GetEntityCoords(GetPlayerPed(src))
 local ped=CreatePed(joaat(C.horseBreeds[h.breed].model),p.x+2.0,p.y,p.z+0.4,b.heading,true,true)
 check(ped and ped~=0 and DoesEntityExist(ped),'Network mount unavailable')
 SetEntityRoutingBucket(ped,GetPlayerRoutingBucket(src))
 local net=NetworkGetNetworkIdFromEntity(ped)
 if not net or net==0 then DeleteEntity(ped);error('Mount network ID unavailable',0) end
 mounts[src]={actor=cid(src),horse=h.id,facility=f.id,ped=ped,expires=os.time()+C.mountMaxSeconds}
 mountLocks[f.id]=src
 TriggerClientEvent(E..'mount',src,{id=net,horse=h})
end
local function siteNear(src)
 local ped=GetPlayerPed(src);if ped==0 or GetPlayerRoutingBucket(src)~=0 then return end
 local v=GetEntityCoords(ped)
 for _,q in ipairs(MySQL.query.await('SELECT * FROM ff_water_sites')) do
  if (v.x-q.x)^2+(v.y-q.y)^2+(v.z-q.z)^2<=C.waterSiteRadius^2 then return q end
 end
end
local function farmWork(src,a,key)
 check(GetResourceState('frontier_needs')=='started','Needs unavailable')
 local ok,why
 if key then ok,why=exports.frontier_needs:SpendLabour(src,a,key,1)
 else ok,why=exports.frontier_needs:CanWork(src,a,1) end
 check(ok,why)
end
local function beginWater(src)
 tool(src,'bucket');check(not waterWork[src],'Already filling a bucket')
 local q=siteNear(src);check(q,'Approach an approved river or lake collection point')
 farmWork(src,'fill')
 local w={actor=cid(src),id=uuid(),site=q.id,started=GetGameTimer()}
 waterWork[src]=w;TriggerClientEvent(E..'waterWork',src,{token=w.id,ms=C.waterFillMs})
end
local function finishWater(src,d)
 local w=waterWork[src];check(w and w.actor==cid(src) and w.id==d.token,'Water collection expired')
 local t=GetGameTimer()-w.started;check(t>=C.waterFillMs and t<=C.waterFillMs+15000,'Invalid filling duration')
 local q=siteNear(src);check(q and q.id==w.site,'Remain near the water source');tool(src,'bucket')
 farmWork(src,'fill',w.id)
 local ok,e=inv:FarmSupplyDelivery(w.actor,'farm_water',10,'farm_water_'..w.id)
 check(ok,e);waterWork[src]=nil;notice(src,'Filled 10 water units. Carry them back to your farm stock.')
end


local function validateWork(src,f,b,s,a,d)
 local changes={}
 local key=C.work[a]
 if a=='collect' then
  check(s.species and C.species[s.species] and C.species[s.species].product and s.products>=1,'No products ready to collect')
  key=s.species=='chicken' and nil or s.species=='sheep' and 'shear' or 'milk'
  if s.species=='chicken' then key=nil end
  changes={{item=C.species[s.species].product,count=math.floor(s.products*(s.species=='chicken' and 1 or 1.25))}}
 elseif a=='plant' then
  check(b.kind=='field' and not s.crop and C.crops[d.crop],'Choose a crop for an empty field')
  changes={{item='farm_seed_'..d.crop,count=-C.fieldCapacity[b.size]}}
 elseif a=='water' or a=='feed' then
  local plan,err=R.supply(s,b,a,d.quantity);check(plan,err)
  local item='farm_water'
  if a=='feed' then item=C.species[s.species].feed;if s.species=='pig' and C.pigFeed[d.food] then item=d.food end end
  changes={{item=item,count=-plan.units}}
 elseif a=='fertilize' then
  check(b.kind=='field' and s.crop and not s.dead and not s.fertilized and s.growth<1,'Only an unfertilized growing crop can be fertilized')
  changes={{item='farm_fertilizer',count=-math.ceil(C.fieldCapacity[b.size]/25)}}
 elseif a=='clearCrop' then check(b.kind=='field' and s.crop and s.dead,'No dead crops to clear')
 elseif a=='harvest' then
  check(b.kind=='field' and s.crop and not s.dead and s.growth>=1,'Crop not ready to harvest')
  local output,seeds=R.harvest(s,b.size,5)
  changes={{item='farm_'..s.crop,count=output}}
  if seeds>0 then changes[#changes+1]={item='farm_seed_'..s.crop,count=seeds} end
 elseif a=='manure' then
  check(math.floor(s.manure)>0,'No manure ready to collect')
  changes={{item='farm_manure',count=math.floor(s.manure)}}
 elseif a=='slaughter' then
  check(s.species and s.species~='horse','No eligible livestock')
  local n,sex=tonumber(d.count),d.sex
  check((sex=='male' or sex=='female') and n and n%1==0 and n>=1 and n<=s[sex],'Choose a valid number of adult animals')
  changes={{item='farm_meat',count=math.floor(n*({chicken=1,pig=4,sheep=3,cattle=8})[s.species]*1.25)}}
  if s.species~='chicken' then changes[#changes+1]={item='farm_hide',count=n} end
 elseif a=='trainHorse' then
  local h=horseById(s,d.horse)
  check(s.species=='horse' and h and not h.listed and h.health>=60 and h.training<100 and h.age>=C.species.horse.mature*3600 and os.time()-(h.trainedAt or 0)>=C.horseTrainingInterval,'Horse not eligible for training (adult, healthy, unlisted, cooldown complete, training below 100)')
  key=nil
 elseif a=='fill' then
  check(b.kind=='well','Approach a constructed well');key='bucket';changes={{item='farm_water',count=10}}
 elseif a=='fertilizer' then
  check(b.kind=='field','Use at a field');changes={{item='farm_manure',count=-5},{item='farm_fertilizer',count=1}}
 end
 if key then tool(src,key) end
 if #changes>0 then preflight(f,changes) end
end

local function action(src,a,d,score,workKey)
 local who=cid(src);check(who,'Select a character first')
 if a=='open' then return view(src) end
 if a=='openFacility' then
  if sessions[src] then notice(src,'Finish or cancel your current farm work first');return end
  local b=get(src,d.id);check(b and near(src,b),'Approach a completed farm facility')
  return view(src,b.id)
 end
 if a=='riverStart' then return beginWater(src) end
 if a=='riverFinish' then return finishWater(src,d) end
 if a=='returnMount' then check(mounts[src] and mounts[src].actor==who,'No mount checked out');return returnMount(src) end
 if a=='shop' then return shopView(src) end
 if a=='horseMarket' then return horseMarket(src) end
 if a=='buyHorse' then return buyHorse(src,d) end
 if a=='buySupply' then return buySupply(src,d) end
 if a=='cancelWork' then unlock(src);waterWork[src]=nil;TriggerClientEvent(E..'workEnd',src);if d.reopen then return view(src) end;return end
 if a=='slaughterSpawnFailed' then
  local w=sessions[src];check(w and w.actor==who and w.phase=='spawning' and d.token==w.token,'No pending animal spawn')
  unlock(src);TriggerClientEvent(E..'workEnd',src)
  error('Could not create networked animals on your client. No livestock consumed. Check client F8 console.',0)
 end
 if a=='slaughterSpawned' then
  local w=sessions[src];check(w and w.actor==who and w.phase=='spawning' and d.token==w.token,'No pending animal spawn')
  check(GetGameTimer()<=w.expires,'Animal spawn timed out')
  local f=row(w.id);local b=f and current(src,f);check(b and not pending(w.id),'Facility unavailable')
  check(type(d.ids)=='table' and #d.ids==#w.points,'Incorrect number of networked animals')
  local seen={};local deadline=GetGameTimer()+4000
  for i,id in ipairs(d.ids) do
   check(type(id)=='number' and id%1==0 and id>0 and not seen[id],'Invalid or duplicate animal network ID')
   seen[id]=true
   local ped=NetworkGetEntityFromNetworkId(id)
   while (not ped or ped==0 or not DoesEntityExist(ped)) and GetGameTimer()<deadline do Wait(50);ped=NetworkGetEntityFromNetworkId(id) end
   check(sessions[src]==w,'Animal spawn cancelled')
   check(ped and ped~=0 and DoesEntityExist(ped),'Network animal did not replicate to server (check OneSync and entity lockdown)')
   local validationDeadline = GetGameTimer() + 3000

while GetGameTimer() < validationDeadline do
    check(sessions[src] == w, 'Animal spawn cancelled')

    if GetEntityType(ped) == 1
        and NetworkGetEntityOwner(ped) == src
        and GetEntityModel(ped) == joaat(w.model)
        then
        break
    end

    Wait(50)
end

check(not w.existing[ped], 'Animal already existed')
check(GetEntityType(ped) == 1, 'Invalid animal entity type')
check(NetworkGetEntityOwner(ped) == src, 'Invalid animal network owner')
check(GetEntityModel(ped) == joaat(w.model), 'Animal model mismatch')
   check(GetEntityRoutingBucket(ped)==GetPlayerRoutingBucket(src),'Animal is in the wrong routing bucket')
   local pos=GetEntityCoords(ped);local p=w.points[i]
   check((pos.x-p.x)^2+(pos.y-p.y)^2<=9 and math.abs(pos.z-p.z)<5,'Animal spawned outside the assigned position')
   w.animals[#w.animals+1]=ped
  end
  w.phase='slaughter';w.expires=GetGameTimer()+300000;w.existing=nil;w.points=nil
  TriggerClientEvent(E..'slaughter',src,{token=w.token,ids=d.ids,count=#w.animals});return
 end
 if a == 'slaughterFinish' then
    local w = sessions[src]

    check(
        w and w.actor == who
        and w.phase == 'slaughter'
        and d.token == w.token
        and GetGameTimer() <= w.expires,
        'No active slaughter session'
    )

    local f = row(w.id)
    local b = f and current(src, f)

    check(b and not pending(w.id), 'Facility unavailable')
    check(near(src, b), 'Return to the slaughter facility')

    tool(src, 'knife')

    check(
        type(d.deadIds) == 'table'
        and #d.deadIds == #w.animals,
        'All selected animals must be slaughtered first'
    )

    local reported = {}

    for _, id in ipairs(d.deadIds) do
        check(
            type(id) == 'number'
            and id > 0
            and id % 1 == 0
            and not reported[id],
            'Invalid or duplicate animal network ID'
        )

        reported[id] = true
    end

    for _, ped in ipairs(w.animals) do
        check(
            DoesEntityExist(ped),
            'Slaughter animal no longer exists'
        )

        local id = NetworkGetNetworkIdFromEntity(ped)

        check(reported[id], 'Animal not reported as slaughtered')
        check(GetEntityType(ped) == 1, 'Invalid animal entity')
        check(GetEntityModel(ped) == joaat(w.model), 'Animal model mismatch')
        check(NetworkGetEntityOwner(ped) == src, 'Invalid animal owner')

        check(
            GetEntityRoutingBucket(ped) == GetPlayerRoutingBucket(src),
            'Invalid animal routing bucket'
        )

        local pos = GetEntityCoords(ped)
        local playerPos = GetEntityCoords(GetPlayerPed(src))

        local distance = (pos.x - playerPos.x)^2
            + (pos.y - playerPos.y)^2
            + (pos.z - playerPos.z)^2

        check(distance <= 625, 'Animal is too far away')
    end

    local payload = w.data
    local hits = w.hits

    unlock(src)

    return action(src, 'slaughter', payload, hits + 10,w.token)
end
 if a=='workHit' then
  local w=sessions[src];check(w and w.phase==nil and w.actor==who and w.token==d.token,'Work session expired')
  local now=GetGameTimer();check(now<=w.expires,'Work session expired')
  local b=prop:FarmBuilding(w.plot,w.id,who);local f=row(w.id)
  check(f and b and near(src,b) and authorized(src,f,b),'Return to facility')
  local elapsed=now-w.started
  if elapsed<300 then w.started=now;TriggerClientEvent(E..'workRound',src,{token=w.token,target=w.target,round=w.round,action=w.action});return end
  local phase=(elapsed%1800)/1800
  if math.abs(phase-w.target)<=.13 then w.hits=w.hits+1 end
  w.round=w.round+1
  if w.round>5 then
   if w.action=='slaughter' then
    local ss=state(f);local n=tonumber(w.data.count);local sex=w.data.sex
    check(ss.species and ss.species~='horse' and (sex=='male' or sex=='female') and n and n%1==0 and n>=1 and n<=ss[sex],'Invalid selection')
    local model=C.species[ss.species][sex];local amount=n
    -- RedM client native loads the model and creates the networked ped.
    -- Server chooses all models/locations, records preexisting peds and validates replication.
    w.animals={};w.points={};w.model=model;w.existing={}
    for _,ped in ipairs(GetAllPeds()) do w.existing[ped]=true end
    for i=1,amount do
     local angle=i*2.39996;local x,y=R.world(b,math.cos(angle)*b.width*.25,math.sin(angle)*b.length*.25)
     w.points[i]={x=x,y=y,z=b.z,heading=b.heading}
    end
    w.phase='spawning';w.expires=GetGameTimer()+30000
    TriggerClientEvent(E..'slaughterSpawn',src,{token=w.token,model=model,points=w.points,facility=w.id});return
   end
   unlock(src);TriggerClientEvent(E..'workEnd',src)
   return action(src,w.action,w.data,w.hits,w.token)
  end
  w.started=GetGameTimer();w.target=math.random(25,75)/100
  TriggerClientEvent(E..'workRound',src,{token=w.token,target=w.target,round=w.round,action=w.action})
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
 check(not locked(f.id),'Facility busy or pending transaction')
 local s=state(f)
 -- Keep the validated action snapshot stable for the five-round work session.
 if score==nil then R.advance(s,os.time(),b.size);save(f,s) end
 if workLocks[f.id] then error('Facility is being worked',0) end
 local physical=C.work[a] or a=='fill' or a=='fertilizer'
 if physical then validateWork(src,f,b,s,a,d);if score==nil then farmWork(src,a) end end
 if C.work[a] and score==nil and not (a=='collect' and s.species=='chicken') then
  check(not sessions[src],'Finish your current work first')
  if a=='water' or a=='feed' then d.quantity=R.supply(s,b,a,d.quantity).units end
  local w={id=f.id,plot=f.plot,actor=who,token=uuid(),action=a,data=d,hits=0,round=1,started=GetGameTimer(),expires=GetGameTimer()+60000,target=math.random(25,75)/100}
  sessions[src]=w;workLocks[f.id]=src
  TriggerClientEvent(E..'workRound',src,{token=w.token,target=w.target,round=1,action=a})
  return
 end
 if physical then farmWork(src,a,workKey or uuid()) end
 if a=='link' then
  check(biz:FarmStockValid(f.plot,f.owner_type,f.owner_id,d.storage),'Invalid stock chest')
  MySQL.update.await('UPDATE ff_facilities SET storage=? WHERE id=?',{d.storage,f.id})
 elseif a=='unlink' then
  MySQL.update.await('UPDATE ff_facilities SET storage=NULL WHERE id=?',{f.id})
 elseif a=='release' then
  check(not s.crop and R.count(s)==0 and s.products==0 and math.floor(s.manure)==0,'Empty facility before releasing')
  MySQL.update.await('DELETE FROM ff_facilities WHERE id=?',{f.id})
 elseif a=='plant' then
  check(b.kind=='field' and not s.crop and C.crops[d.crop],'Invalid crop or occupied field');tool(src,'hoe')
  s.crop=d.crop;s.growth=0;s.dead=false;s.fertilized=false;s.neglect=0;s.water=0;s.harvestRemaining=nil;s.seedRemaining=nil
  batch(f,s,{{item='farm_seed_'..d.crop,count=-C.fieldCapacity[b.size]}})
 elseif a=='water' then
  check(s.crop and not s.dead or R.count(s)>0,'Nothing to water');tool(src,'water')
  local plan,e=R.supply(s,b,'water',d.quantity);check(plan,e)
  s.water=math.min(plan.maximum,s.water+plan.perUnit*plan.units*(1+(score or 0)*.05))
  batch(f,s,{{item='farm_water',count=-plan.units}})
  notice(src,('Added %d water units.'):format(plan.units))
 elseif a=='fertilize' then
  check(s.crop and not s.dead and not s.fertilized,'No eligible crop');tool(src,'fork');s.fertilized=true
  batch(f,s,{{item='farm_fertilizer',count=-math.ceil(C.fieldCapacity[b.size]/25)}})
 elseif a=='clearCrop' then
  check(s.crop and s.dead,'Only dead crops can be cleared');tool(src,'hoe');s.crop=nil;s.dead=false;s.growth=0;s.water=0;save(f,s)
 elseif a=='harvest' then
  check(s.crop and not s.dead and s.growth>=1,'Crop not ready');tool(src,'sickle')
  local crop=s.crop;local output,seeds=R.harvest(s,b.size,score)
  local changes={{item='farm_'..crop,count=output}}
  if seeds>0 then changes[#changes+1]={item='farm_seed_'..crop,count=seeds} end
  s.crop=nil;s.growth=0;s.water=0;s.soil=math.max(60,s.soil-1);s.harvestRemaining=nil;s.seedRemaining=nil;s.fertilized=false
  batch(f,s,changes)
  notice(src,('Harvest complete: %d %s and %d seeds deposited into linked chest.'):format(output,itemName('farm_'..crop),seeds))
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
 elseif a=='mountHorse' then
  return checkout(src,f,b,s,d.horse)
 elseif a=='listHorse' or a=='unlistHorse' then
  local h=horseById(s,d.horse);check(s.species=='horse' and h,'Horse unavailable')
  if a=='listHorse' then
   check(biz:VerifyLicense(f.owner_type,f.owner_id,'agriculture'),'Agriculture license required')
   local price=tonumber(d.price);check(price and price%1==0 and price>=1 and price<=100000000,'Invalid price')
   h.listed=price
  else h.listed=nil end
  save(f,s)
 elseif a=='trainHorse' then
  check(s.species=='horse','Horse enclosure required')
  local h;for _,v in ipairs(s.horses or {}) do if v.id==d.horse then h=v;break end end
  check(h and not h.listed and h.health>=60 and h.age>=C.species.horse.mature*3600 and os.time()-(h.trainedAt or 0)>=C.horseTrainingInterval,'Horse cannot train now')
  h.training=math.min(100,h.training+2+(score or 0));h.trainedAt=os.time();save(f,s)
 elseif a=='feed' then
  check(s.species and R.count(s)>0,'No animals');tool(src,'fork')
  local plan,e=R.supply(s,b,'feed',d.quantity);check(plan,e)
  s.feed=math.min(plan.maximum,s.feed+plan.units*plan.perUnit*(1+(score or 0)*.05))
  local food=C.species[s.species].feed;if s.species=='pig' and C.pigFeed[d.food] then food=d.food end
  batch(f,s,{{item=food,count=-plan.units}})
  notice(src,('Added %d %s.'):format(plan.units,itemName(food)))
 elseif a=='collect' then
  check(s.species and C.species[s.species].product and s.products>=1,'No products available')
  if s.species~='chicken' then tool(src,s.species=='sheep' and 'shear' or 'milk') end
  local n=math.floor(s.products*(s.species=='chicken' and 1 or (1+(score or 0)*.05)));s.products=0
  local item=C.species[s.species].product;batch(f,s,{{item=item,count=n}});notice(src,('Collected %d %s into linked chest.'):format(n,itemName(item)))
 elseif a=='manure' then
  tool(src,'fork');local n=math.floor(s.manure);check(n>0,'No manure available');s.manure=s.manure-n;batch(f,s,{{item='farm_manure',count=n}})
 elseif a=='slaughter' then
  check(score and score>=10 and s.species and s.species~='horse','Complete physical slaughter first');tool(src,'knife')
  local n=tonumber(d.count);local sex=d.sex
  check((sex=='female' or sex=='male') and n and n%1==0 and n>=1 and n<=s[sex],'Invalid animal selection')
  local yield=({chicken=1,pig=4,sheep=3,cattle=8})[s.species]
  s[sex]=s[sex]-n
  local changes={{item='farm_meat',count=math.floor(n*yield*(1+(score-10)*.05))}}
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
 if not ok then if src then notice(src,err);if sessions[src] and sessions[src].phase~='slaughter' then unlock(src);TriggerClientEvent(E..'workEnd',src) end else print('[frontier_farming] '..tostring(err)) end end
end
RegisterNetEvent(E..'action',function(a,d)
 local src=source;if type(a)~='string' or type(d)~='table' then return end
 local t=GetGameTimer();if a~='slaughterSpawned' and a~='slaughterSpawnFailed' and a~='cancelWork' and rate[src] and t-rate[src]<400 then return end;rate[src]=t
 run(src,function() action(src,a,d) end)
end)
AddEventHandler('playerDropped',function() local src=source;unlock(src);waterWork[src]=nil;rate[src]=nil;CreateThread(function() if ready then while busy do Wait(100) end;run(nil,function() returnMount(src) end) end end) end)
AddEventHandler('frontier:playerUnloaded',function(p) local src=p.source;unlock(src);waterWork[src]=nil;CreateThread(function() if ready then while busy do Wait(100) end;run(nil,function() returnMount(src) end) end end) end)
CreateThread(function() while true do Wait(1000);for src,w in pairs(sessions) do if GetGameTimer()>w.expires then unlock(src);TriggerClientEvent(E..'workEnd',src) end end end end)
exports('FacilityBound',function(id) return not ready or busy or row(id)~=nil end)
exports('DrainCompany',function(id)
 if GetInvokingResource()~='frontier_business' or not ready or busy then return false end
 busy=true
 local ok,result=pcall(function()
  for _,f in ipairs(MySQL.query.await("SELECT * FROM ff_facilities WHERE owner_type='company' AND owner_id=?",{id})) do
   if locked(f.id) then return false end
   check(MySQL.transaction.await({{query='INSERT INTO ff_confiscations(id,facility,plot,owner_type,owner_id,snapshot,reason,created) VALUES(?,?,?,?,?,?,?,?)',values={uuid(),f.id,f.plot,f.owner_type,f.owner_id,f.state,'company_liquidation',os.time()}},{query='DELETE FROM ff_facilities WHERE id=?',values={f.id}}}),'Liquidation audit failed')
  end
  return true
 end)
 busy=false;return ok and result==true
end)
MySQL.ready(function()
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS ff_water_sites(id CHAR(32) PRIMARY KEY,x DOUBLE NOT NULL,y DOUBLE NOT NULL,z DOUBLE NOT NULL,name VARCHAR(64) NOT NULL)]])
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS ff_confiscations(id CHAR(32) PRIMARY KEY,facility CHAR(32) NOT NULL,plot CHAR(32) NOT NULL,owner_type VARCHAR(16) NOT NULL,owner_id VARCHAR(64) NOT NULL,snapshot LONGTEXT NOT NULL,reason VARCHAR(32) NOT NULL,created BIGINT NOT NULL)]])
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS ff_horse_sales(id CHAR(32) PRIMARY KEY,source_id CHAR(32) NOT NULL,dest_id CHAR(32) NOT NULL,source_state LONGTEXT NOT NULL,dest_state LONGTEXT NOT NULL,debit BIGINT NOT NULL,credit BIGINT NOT NULL,amount BIGINT NOT NULL,phase VARCHAR(16) NOT NULL,INDEX(source_id,phase),INDEX(dest_id,phase))]])
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS ff_animal_orders(order_id CHAR(32) PRIMARY KEY,facility CHAR(32) NOT NULL,after_state LONGTEXT NOT NULL,INDEX(facility))]])
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
   for _,j in ipairs(MySQL.query.await("SELECT * FROM ff_horse_sales WHERE phase='payment' LIMIT 50")) do local ok,e=horseSaleStep(j);if not ok then print('[frontier_farming] horse sale '..j.id..': '..tostring(e)) end end
   for _,j in ipairs(MySQL.query.await("SELECT * FROM ff_orders WHERE phase IN ('payment','paid') ORDER BY created LIMIT 50")) do local ok,e=orderStep(j);if not ok then print('[frontier_farming] supply order '..j.id..': '..tostring(e)) end end
   for _,j in ipairs(MySQL.query.await('SELECT * FROM ff_operations')) do
    local ok,err=finish(j)
    if not ok and ({insufficient_stock=true,weight=true,slots=true,stack_conflict=true,conflict=true,invalid_item=true})[err] then MySQL.update.await('DELETE FROM ff_operations WHERE id=?',{j.id}) end
   end
   for _,f in ipairs(MySQL.query.await('SELECT * FROM ff_facilities')) do if not locked(f.id) then
    local s=state(f);local b=prop:FarmBuilding(f.plot,f.id,f.owner_id)
    if b then R.advance(s,os.time(),f.size);save(f,s)
     -- Eggs remain in the enclosure until the player selects Collect eggs.
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
     local f=row(b.id);if f then local s=state(f);if mountLocks[f.id] and s.horses then local m=mounts[mountLocks[f.id]];if m then for i=#s.horses,1,-1 do if s.horses[i].id==m.horse then table.remove(s.horses,i) end end;R.horseCounts(s) end end;local lock=workLocks[f.id] and sessions[workLocks[f.id]];result[#result+1]={b=b,crop=s.crop,growth=s.growth,dead=s.dead,species=(not lock or (lock.phase~='slaughter' and lock.phase~='spawning')) and s.species or nil,female=s.female,male=s.male,young=s.young,horses=s.horses} elseif b.kind=='field' then result[#result+1]={b=b,growth=0} end
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

AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then for src in pairs(sessions) do unlock(src) end;for _,m in pairs(mounts) do if DoesEntityExist(m.ped) then DeleteEntity(m.ped) end end end end)

exports('OpenHorseMarket',function(src)
 if GetInvokingResource()~='frontier_trade' then return false end
 run(src,function() horseMarket(src) end);return true
end)

CreateThread(function()
 while true do Wait(2000)
  if ready and not busy then
   run(nil,function()
    for src,m in pairs(mounts) do if cid(src)~=m.actor or os.time()>=m.expires or not DoesEntityExist(m.ped) or GetEntityHealth(m.ped)<=0 then returnMount(src) end end
    for src,w in pairs(waterWork) do if GetGameTimer()-w.started>C.waterFillMs+15000 then waterWork[src]=nil end end
   end)
  end
 end
end)
RegisterCommand('farmwatersite',function(src,args)
 if src==0 or not IsPlayerAceAllowed(src,'frontier.farming.admin') then return end
 run(src,function()
  local ped=GetPlayerPed(src);check(ped~=0 and GetPlayerRoutingBucket(src)==0,'Stand at a real water access point')
  local v=GetEntityCoords(ped);local name=table.concat(args,' '):sub(1,64)
  if name=='' then name='River access' end
  MySQL.insert.await('INSERT INTO ff_water_sites(id,x,y,z,name) VALUES(?,?,?,?,?)',{uuid(),v.x,v.y,v.z,name})
  notice(src,'Water collection point registered: '..name)
 end)
end,false)
RegisterCommand('farmwaterremove',function(src,args)
 if src==0 or not IsPlayerAceAllowed(src,'frontier.farming.admin') then return end
 run(src,function() local q=siteNear(src);check(q,'No nearby collection point');MySQL.update.await('DELETE FROM ff_water_sites WHERE id=?',{q.id});notice(src,'Water collection point removed') end)
end,false)
exports('StorageBound',function(storage)
 if GetInvokingResource()~='frontier_business' or not ready then return true end
 return MySQL.single.await('SELECT id FROM ff_facilities WHERE storage=? LIMIT 1',{storage})~=nil or MySQL.single.await("SELECT id FROM ff_orders WHERE storage=? AND phase IN ('payment','paid') LIMIT 1",{storage})~=nil
end)
exports('DrainPlot',function(plot)
 if GetInvokingResource()~='frontier_property' or not ready or busy then return false end
 busy=true
 local ok,result=pcall(function()
  for _,f in ipairs(MySQL.query.await('SELECT * FROM ff_facilities WHERE plot=?',{plot})) do
   if locked(f.id) then return false end
   check(MySQL.transaction.await({{query='INSERT INTO ff_confiscations(id,facility,plot,owner_type,owner_id,snapshot,reason,created) VALUES(?,?,?,?,?,?,?,?)',values={uuid(),f.id,f.plot,f.owner_type,f.owner_id,f.state,'plot_foreclosure',os.time()}},{query='DELETE FROM ff_facilities WHERE id=?',values={f.id}}}),'Foreclosure audit failed')
  end
  return true
 end)
 busy=false;return ok and result==true
end)
);return species and C.species[species] and (sex=='male' or sex=='female') and species or false end)()} end
 table.sort(list,function(a,b)return a.name<b.name end)
 local orders=MySQL.query.await("SELECT id,item,quantity,amount,phase FROM ff_orders WHERE actor=? AND phase IN ('payment','paid') ORDER BY created DESC",{who})
 local destinations={}
 for _,f in ipairs(MySQL.query.await('SELECT * FROM ff_facilities ORDER BY kind,size')) do
  local b=prop:FarmBuilding(f.plot,f.id,who)
  if b and authorized(src,f,b) then destinations[#destinations+1]={id=f.id,name=f.size..' '..f.kind..' · '..f.owner_type,kind=f.kind} end
 end
 TriggerClientEvent(E..'shop',src,{items=list,orders=orders,destinations=destinations})
end
local function buySupply(src,d)
 local who=cid(src);check(who and supplier(src),'Approach an agricultural supplier')
 local price=C.supplyPrices[d.item];local qty=tonumber(d.quantity)
 check(price and qty and qty%1==0 and qty>=1 and qty<=1000,'Invalid purchase')
 check(not MySQL.single.await("SELECT id FROM ff_orders WHERE actor=? AND phase IN ('payment','paid')",{who}),'Resolve your pending order first')
 local typ,owner,storage,bank='character',who,'',0
 local animal,sex=d.item:match('^farm_(%a+)_(%a+)$')
 if not C.species[animal] or (sex~='female' and sex~='male') then animal=nil end
 local delivery
 if animal then
  local f=row(d.facility);check(f and not locked(f.id),'Choose an available destination facility ID')
  local b=prop:FarmBuilding(f.plot,f.id,who);check(b and authorized(src,f,b),'Unauthorized destination')
  check((b.kind=='chicken' and animal=='chicken') or (b.kind=='livestock' and animal~='chicken'),'Wrong enclosure type')
  local st=state(f);R.advance(st,os.time(),f.size)
  check(not st.species or st.species==animal or R.count(st)==0 and st.products==0 and math.floor(st.manure)==0,'Different species in enclosure')
  check(R.count(st)+qty<=C.species[animal].capacity[f.size],'Not enough capacity')
  typ,owner,storage=f.owner_type,f.owner_id,''
  if typ=='character' then local ok,a=eco:GetCharacterAccounts(src);check(ok and a.characterId==who,'Bank unavailable');bank=a.bank.id end
  st.species=animal
  if animal=='horse' then
   local breed=d.breed or 'turkoman';check(C.horseBreeds[breed],'Unknown breed')
   st.horses=st.horses or {}
   for i=1,qty do st.horses[#st.horses+1]=R.newHorse(uuid(),breed,sex,d.juvenile==true) end
   R.horseCounts(st)
  elseif d.juvenile then if st.young==0 then st.matureClock=0 end;st.young=st.young+qty
  else st[sex]=st[sex]+qty end
  if d.juvenile then price=math.max(1,math.floor(price*.6)) end
  delivery={facility=f.id,after_state=json.encode(st)}
 end
 if not delivery and type(d.facility)=='string' and d.facility~='' then
  local f=row(d.facility);check(f and f.owner_type=='company' and biz:CanUseProperty(f.owner_id,who,f.plot,'farm') and stockValid(f),'Authorized company facility and linked chest required')
  check(C.items[d.item].maxStack~=1,'Purchase personal tools separately')
  typ,owner,storage='company',f.owner_id,f.storage
 elseif not delivery then
  local ok,accounts=eco:GetCharacterAccounts(src);check(ok and accounts.characterId==who,'Bank unavailable');bank=accounts.bank.id
 end
 local j={id=uuid(),actor=who,owner_type=typ,owner_id=owner,storage=storage,bank=bank,item=d.item,quantity=qty,amount=price*qty,phase='payment'}
 local statements={{query='INSERT INTO ff_orders(id,actor,owner_type,owner_id,storage,bank,item,quantity,amount,phase,created) VALUES(?,?,?,?,?,?,?,?,?,?,?)',values={j.id,who,typ,owner,storage,bank,j.item,qty,j.amount,j.phase,os.time()}}}
 if delivery then statements[#statements+1]={query='INSERT INTO ff_animal_orders(order_id,facility,after_state) VALUES(?,?,?)',values={j.id,delivery.facility,delivery.after_state}} end
 check(MySQL.transaction.await(statements),'Could not persist order')
 local ok,e=orderStep(j);notice(src,ok and 'Supplies purchased' or ('Order pending or rejected: '..tostring(e)));shopView(src)
end


local function returnMount(src)
 local m=mounts[src];if not m then return end
 local f=row(m.facility)
 if f then
  local st=state(f);R.advance(st,os.time(),f.size)
  local h,i=horseById(st,m.horse)
  if h and DoesEntityExist(m.ped) and GetEntityHealth(m.ped)<=0 then table.remove(st.horses,i);R.horseCounts(st) end
  save(f,st)
 end
 if DoesEntityExist(m.ped) then DeleteEntity(m.ped) end
 mounts[src]=nil;mountLocks[m.facility]=nil
 TriggerClientEvent(E..'mountReturned',src)
end
local function checkout(src,f,b,st,id)
 check(not mounts[src],'Return your current mount first')
 local h=horseById(st,id)
 check(h and not h.listed and h.health>=30 and h.age>=C.species.horse.mature*3600,'Horse is not available to ride')
 local p=GetEntityCoords(GetPlayerPed(src))
 local ped=CreatePed(joaat(C.horseBreeds[h.breed].model),p.x+2.0,p.y,p.z+0.4,b.heading,true,true)
 check(ped and ped~=0 and DoesEntityExist(ped),'Network mount unavailable')
 SetEntityRoutingBucket(ped,GetPlayerRoutingBucket(src))
 local net=NetworkGetNetworkIdFromEntity(ped)
 if not net or net==0 then DeleteEntity(ped);error('Mount network ID unavailable',0) end
 mounts[src]={actor=cid(src),horse=h.id,facility=f.id,ped=ped,expires=os.time()+C.mountMaxSeconds}
 mountLocks[f.id]=src
 TriggerClientEvent(E..'mount',src,{id=net,horse=h})
end
local function siteNear(src)
 local ped=GetPlayerPed(src);if ped==0 or GetPlayerRoutingBucket(src)~=0 then return end
 local v=GetEntityCoords(ped)
 for _,q in ipairs(MySQL.query.await('SELECT * FROM ff_water_sites')) do
  if (v.x-q.x)^2+(v.y-q.y)^2+(v.z-q.z)^2<=C.waterSiteRadius^2 then return q end
 end
end
local function farmWork(src,a,key)
 check(GetResourceState('frontier_needs')=='started','Needs unavailable')
 local ok,why
 if key then ok,why=exports.frontier_needs:SpendLabour(src,a,key,1)
 else ok,why=exports.frontier_needs:CanWork(src,a,1) end
 check(ok,why)
end
local function beginWater(src)
 tool(src,'bucket');check(not waterWork[src],'Already filling a bucket')
 local q=siteNear(src);check(q,'Approach an approved river or lake collection point')
 farmWork(src,'fill')
 local w={actor=cid(src),id=uuid(),site=q.id,started=GetGameTimer()}
 waterWork[src]=w;TriggerClientEvent(E..'waterWork',src,{token=w.id,ms=C.waterFillMs})
end
local function finishWater(src,d)
 local w=waterWork[src];check(w and w.actor==cid(src) and w.id==d.token,'Water collection expired')
 local t=GetGameTimer()-w.started;check(t>=C.waterFillMs and t<=C.waterFillMs+15000,'Invalid filling duration')
 local q=siteNear(src);check(q and q.id==w.site,'Remain near the water source');tool(src,'bucket')
 farmWork(src,'fill',w.id)
 local ok,e=inv:FarmSupplyDelivery(w.actor,'farm_water',10,'farm_water_'..w.id)
 check(ok,e);waterWork[src]=nil;notice(src,'Filled 10 water units. Carry them back to your farm stock.')
end


local function validateWork(src,f,b,s,a,d)
 local changes={}
 local key=C.work[a]
 if a=='collect' then
  check(s.species and C.species[s.species] and C.species[s.species].product and s.products>=1,'No products ready to collect')
  key=s.species=='chicken' and nil or s.species=='sheep' and 'shear' or 'milk'
  if s.species=='chicken' then key=nil end
  changes={{item=C.species[s.species].product,count=math.floor(s.products*(s.species=='chicken' and 1 or 1.25))}}
 elseif a=='plant' then
  check(b.kind=='field' and not s.crop and C.crops[d.crop],'Choose a crop for an empty field')
  changes={{item='farm_seed_'..d.crop,count=-C.fieldCapacity[b.size]}}
 elseif a=='water' or a=='feed' then
  local plan,err=R.supply(s,b,a,d.quantity);check(plan,err)
  local item='farm_water'
  if a=='feed' then item=C.species[s.species].feed;if s.species=='pig' and C.pigFeed[d.food] then item=d.food end end
  changes={{item=item,count=-plan.units}}
 elseif a=='fertilize' then
  check(b.kind=='field' and s.crop and not s.dead and not s.fertilized and s.growth<1,'Only an unfertilized growing crop can be fertilized')
  changes={{item='farm_fertilizer',count=-math.ceil(C.fieldCapacity[b.size]/25)}}
 elseif a=='clearCrop' then check(b.kind=='field' and s.crop and s.dead,'No dead crops to clear')
 elseif a=='harvest' then
  check(b.kind=='field' and s.crop and not s.dead and s.growth>=1,'Crop not ready to harvest')
  local output,seeds=R.harvest(s,b.size,5)
  changes={{item='farm_'..s.crop,count=output}}
  if seeds>0 then changes[#changes+1]={item='farm_seed_'..s.crop,count=seeds} end
 elseif a=='manure' then
  check(math.floor(s.manure)>0,'No manure ready to collect')
  changes={{item='farm_manure',count=math.floor(s.manure)}}
 elseif a=='slaughter' then
  check(s.species and s.species~='horse','No eligible livestock')
  local n,sex=tonumber(d.count),d.sex
  check((sex=='male' or sex=='female') and n and n%1==0 and n>=1 and n<=s[sex],'Choose a valid number of adult animals')
  changes={{item='farm_meat',count=math.floor(n*({chicken=1,pig=4,sheep=3,cattle=8})[s.species]*1.25)}}
  if s.species~='chicken' then changes[#changes+1]={item='farm_hide',count=n} end
 elseif a=='trainHorse' then
  local h=horseById(s,d.horse)
  check(s.species=='horse' and h and not h.listed and h.health>=60 and h.training<100 and h.age>=C.species.horse.mature*3600 and os.time()-(h.trainedAt or 0)>=C.horseTrainingInterval,'Horse not eligible for training (adult, healthy, unlisted, cooldown complete, training below 100)')
  key=nil
 elseif a=='fill' then
  check(b.kind=='well','Approach a constructed well');key='bucket';changes={{item='farm_water',count=10}}
 elseif a=='fertilizer' then
  check(b.kind=='field','Use at a field');changes={{item='farm_manure',count=-5},{item='farm_fertilizer',count=1}}
 end
 if key then tool(src,key) end
 if #changes>0 then preflight(f,changes) end
end

local function action(src,a,d,score,workKey)
 local who=cid(src);check(who,'Select a character first')
 if a=='open' then return view(src) end
 if a=='openFacility' then
  if sessions[src] then notice(src,'Finish or cancel your current farm work first');return end
  local b=get(src,d.id);check(b and near(src,b),'Approach a completed farm facility')
  return view(src,b.id)
 end
 if a=='riverStart' then return beginWater(src) end
 if a=='riverFinish' then return finishWater(src,d) end
 if a=='returnMount' then check(mounts[src] and mounts[src].actor==who,'No mount checked out');return returnMount(src) end
 if a=='shop' then return shopView(src) end
 if a=='horseMarket' then return horseMarket(src) end
 if a=='buyHorse' then return buyHorse(src,d) end
 if a=='buySupply' then return buySupply(src,d) end
 if a=='cancelWork' then unlock(src);waterWork[src]=nil;TriggerClientEvent(E..'workEnd',src);if d.reopen then return view(src) end;return end
 if a=='slaughterSpawnFailed' then
  local w=sessions[src];check(w and w.actor==who and w.phase=='spawning' and d.token==w.token,'No pending animal spawn')
  unlock(src);TriggerClientEvent(E..'workEnd',src)
  error('Could not create networked animals on your client. No livestock consumed. Check client F8 console.',0)
 end
 if a=='slaughterSpawned' then
  local w=sessions[src];check(w and w.actor==who and w.phase=='spawning' and d.token==w.token,'No pending animal spawn')
  check(GetGameTimer()<=w.expires,'Animal spawn timed out')
  local f=row(w.id);local b=f and current(src,f);check(b and not pending(w.id),'Facility unavailable')
  check(type(d.ids)=='table' and #d.ids==#w.points,'Incorrect number of networked animals')
  local seen={};local deadline=GetGameTimer()+4000
  for i,id in ipairs(d.ids) do
   check(type(id)=='number' and id%1==0 and id>0 and not seen[id],'Invalid or duplicate animal network ID')
   seen[id]=true
   local ped=NetworkGetEntityFromNetworkId(id)
   while (not ped or ped==0 or not DoesEntityExist(ped)) and GetGameTimer()<deadline do Wait(50);ped=NetworkGetEntityFromNetworkId(id) end
   check(sessions[src]==w,'Animal spawn cancelled')
   check(ped and ped~=0 and DoesEntityExist(ped),'Network animal did not replicate to server (check OneSync and entity lockdown)')
   local validationDeadline = GetGameTimer() + 3000

while GetGameTimer() < validationDeadline do
    check(sessions[src] == w, 'Animal spawn cancelled')

    if GetEntityType(ped) == 1
        and NetworkGetEntityOwner(ped) == src
        and GetEntityModel(ped) == joaat(w.model)
        then
        break
    end

    Wait(50)
end

check(not w.existing[ped], 'Animal already existed')
check(GetEntityType(ped) == 1, 'Invalid animal entity type')
check(NetworkGetEntityOwner(ped) == src, 'Invalid animal network owner')
check(GetEntityModel(ped) == joaat(w.model), 'Animal model mismatch')
   check(GetEntityRoutingBucket(ped)==GetPlayerRoutingBucket(src),'Animal is in the wrong routing bucket')
   local pos=GetEntityCoords(ped);local p=w.points[i]
   check((pos.x-p.x)^2+(pos.y-p.y)^2<=9 and math.abs(pos.z-p.z)<5,'Animal spawned outside the assigned position')
   w.animals[#w.animals+1]=ped
  end
  w.phase='slaughter';w.expires=GetGameTimer()+300000;w.existing=nil;w.points=nil
  TriggerClientEvent(E..'slaughter',src,{token=w.token,ids=d.ids,count=#w.animals});return
 end
 if a == 'slaughterFinish' then
    local w = sessions[src]

    check(
        w and w.actor == who
        and w.phase == 'slaughter'
        and d.token == w.token
        and GetGameTimer() <= w.expires,
        'No active slaughter session'
    )

    local f = row(w.id)
    local b = f and current(src, f)

    check(b and not pending(w.id), 'Facility unavailable')
    check(near(src, b), 'Return to the slaughter facility')

    tool(src, 'knife')

    check(
        type(d.deadIds) == 'table'
        and #d.deadIds == #w.animals,
        'All selected animals must be slaughtered first'
    )

    local reported = {}

    for _, id in ipairs(d.deadIds) do
        check(
            type(id) == 'number'
            and id > 0
            and id % 1 == 0
            and not reported[id],
            'Invalid or duplicate animal network ID'
        )

        reported[id] = true
    end

    for _, ped in ipairs(w.animals) do
        check(
            DoesEntityExist(ped),
            'Slaughter animal no longer exists'
        )

        local id = NetworkGetNetworkIdFromEntity(ped)

        check(reported[id], 'Animal not reported as slaughtered')
        check(GetEntityType(ped) == 1, 'Invalid animal entity')
        check(GetEntityModel(ped) == joaat(w.model), 'Animal model mismatch')
        check(NetworkGetEntityOwner(ped) == src, 'Invalid animal owner')

        check(
            GetEntityRoutingBucket(ped) == GetPlayerRoutingBucket(src),
            'Invalid animal routing bucket'
        )

        local pos = GetEntityCoords(ped)
        local playerPos = GetEntityCoords(GetPlayerPed(src))

        local distance = (pos.x - playerPos.x)^2
            + (pos.y - playerPos.y)^2
            + (pos.z - playerPos.z)^2

        check(distance <= 625, 'Animal is too far away')
    end

    local payload = w.data
    local hits = w.hits

    unlock(src)

    return action(src, 'slaughter', payload, hits + 10,w.token)
end
 if a=='workHit' then
  local w=sessions[src];check(w and w.phase==nil and w.actor==who and w.token==d.token,'Work session expired')
  local now=GetGameTimer();check(now<=w.expires,'Work session expired')
  local b=prop:FarmBuilding(w.plot,w.id,who);local f=row(w.id)
  check(f and b and near(src,b) and authorized(src,f,b),'Return to facility')
  local elapsed=now-w.started
  if elapsed<300 then w.started=now;TriggerClientEvent(E..'workRound',src,{token=w.token,target=w.target,round=w.round,action=w.action});return end
  local phase=(elapsed%1800)/1800
  if math.abs(phase-w.target)<=.13 then w.hits=w.hits+1 end
  w.round=w.round+1
  if w.round>5 then
   if w.action=='slaughter' then
    local ss=state(f);local n=tonumber(w.data.count);local sex=w.data.sex
    check(ss.species and ss.species~='horse' and (sex=='male' or sex=='female') and n and n%1==0 and n>=1 and n<=ss[sex],'Invalid selection')
    local model=C.species[ss.species][sex];local amount=n
    -- RedM client native loads the model and creates the networked ped.
    -- Server chooses all models/locations, records preexisting peds and validates replication.
    w.animals={};w.points={};w.model=model;w.existing={}
    for _,ped in ipairs(GetAllPeds()) do w.existing[ped]=true end
    for i=1,amount do
     local angle=i*2.39996;local x,y=R.world(b,math.cos(angle)*b.width*.25,math.sin(angle)*b.length*.25)
     w.points[i]={x=x,y=y,z=b.z,heading=b.heading}
    end
    w.phase='spawning';w.expires=GetGameTimer()+30000
    TriggerClientEvent(E..'slaughterSpawn',src,{token=w.token,model=model,points=w.points,facility=w.id});return
   end
   unlock(src);TriggerClientEvent(E..'workEnd',src)
   return action(src,w.action,w.data,w.hits,w.token)
  end
  w.started=GetGameTimer();w.target=math.random(25,75)/100
  TriggerClientEvent(E..'workRound',src,{token=w.token,target=w.target,round=w.round,action=w.action})
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
 check(not locked(f.id),'Facility busy or pending transaction')
 local s=state(f)
 -- Keep the validated action snapshot stable for the five-round work session.
 if score==nil then R.advance(s,os.time(),b.size);save(f,s) end
 if workLocks[f.id] then error('Facility is being worked',0) end
 local physical=C.work[a] or a=='fill' or a=='fertilizer'
 if physical then validateWork(src,f,b,s,a,d);if score==nil then farmWork(src,a) end end
 if C.work[a] and score==nil and not (a=='collect' and s.species=='chicken') then
  check(not sessions[src],'Finish your current work first')
  if a=='water' or a=='feed' then d.quantity=R.supply(s,b,a,d.quantity).units end
  local w={id=f.id,plot=f.plot,actor=who,token=uuid(),action=a,data=d,hits=0,round=1,started=GetGameTimer(),expires=GetGameTimer()+60000,target=math.random(25,75)/100}
  sessions[src]=w;workLocks[f.id]=src
  TriggerClientEvent(E..'workRound',src,{token=w.token,target=w.target,round=1,action=a})
  return
 end
 if physical then farmWork(src,a,workKey or uuid()) end
 if a=='link' then
  check(biz:FarmStockValid(f.plot,f.owner_type,f.owner_id,d.storage),'Invalid stock chest')
  MySQL.update.await('UPDATE ff_facilities SET storage=? WHERE id=?',{d.storage,f.id})
 elseif a=='unlink' then
  MySQL.update.await('UPDATE ff_facilities SET storage=NULL WHERE id=?',{f.id})
 elseif a=='release' then
  check(not s.crop and R.count(s)==0 and s.products==0 and math.floor(s.manure)==0,'Empty facility before releasing')
  MySQL.update.await('DELETE FROM ff_facilities WHERE id=?',{f.id})
 elseif a=='plant' then
  check(b.kind=='field' and not s.crop and C.crops[d.crop],'Invalid crop or occupied field');tool(src,'hoe')
  s.crop=d.crop;s.growth=0;s.dead=false;s.fertilized=false;s.neglect=0;s.water=0;s.harvestRemaining=nil;s.seedRemaining=nil
  batch(f,s,{{item='farm_seed_'..d.crop,count=-C.fieldCapacity[b.size]}})
 elseif a=='water' then
  check(s.crop and not s.dead or R.count(s)>0,'Nothing to water');tool(src,'water')
  local plan,e=R.supply(s,b,'water',d.quantity);check(plan,e)
  s.water=math.min(plan.maximum,s.water+plan.perUnit*plan.units*(1+(score or 0)*.05))
  batch(f,s,{{item='farm_water',count=-plan.units}})
  notice(src,('Added %d water units.'):format(plan.units))
 elseif a=='fertilize' then
  check(s.crop and not s.dead and not s.fertilized,'No eligible crop');tool(src,'fork');s.fertilized=true
  batch(f,s,{{item='farm_fertilizer',count=-math.ceil(C.fieldCapacity[b.size]/25)}})
 elseif a=='clearCrop' then
  check(s.crop and s.dead,'Only dead crops can be cleared');tool(src,'hoe');s.crop=nil;s.dead=false;s.growth=0;s.water=0;save(f,s)
 elseif a=='harvest' then
  check(s.crop and not s.dead and s.growth>=1,'Crop not ready');tool(src,'sickle')
  local crop=s.crop;local output,seeds=R.harvest(s,b.size,score)
  local changes={{item='farm_'..crop,count=output}}
  if seeds>0 then changes[#changes+1]={item='farm_seed_'..crop,count=seeds} end
  s.crop=nil;s.growth=0;s.water=0;s.soil=math.max(60,s.soil-1);s.harvestRemaining=nil;s.seedRemaining=nil;s.fertilized=false
  batch(f,s,changes)
  notice(src,('Harvest complete: %d %s and %d seeds deposited into linked chest.'):format(output,itemName('farm_'..crop),seeds))
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
 elseif a=='mountHorse' then
  return checkout(src,f,b,s,d.horse)
 elseif a=='listHorse' or a=='unlistHorse' then
  local h=horseById(s,d.horse);check(s.species=='horse' and h,'Horse unavailable')
  if a=='listHorse' then
   check(biz:VerifyLicense(f.owner_type,f.owner_id,'agriculture'),'Agriculture license required')
   local price=tonumber(d.price);check(price and price%1==0 and price>=1 and price<=100000000,'Invalid price')
   h.listed=price
  else h.listed=nil end
  save(f,s)
 elseif a=='trainHorse' then
  check(s.species=='horse','Horse enclosure required')
  local h;for _,v in ipairs(s.horses or {}) do if v.id==d.horse then h=v;break end end
  check(h and not h.listed and h.health>=60 and h.age>=C.species.horse.mature*3600 and os.time()-(h.trainedAt or 0)>=C.horseTrainingInterval,'Horse cannot train now')
  h.training=math.min(100,h.training+2+(score or 0));h.trainedAt=os.time();save(f,s)
 elseif a=='feed' then
  check(s.species and R.count(s)>0,'No animals');tool(src,'fork')
  local plan,e=R.supply(s,b,'feed',d.quantity);check(plan,e)
  s.feed=math.min(plan.maximum,s.feed+plan.units*plan.perUnit*(1+(score or 0)*.05))
  local food=C.species[s.species].feed;if s.species=='pig' and C.pigFeed[d.food] then food=d.food end
  batch(f,s,{{item=food,count=-plan.units}})
  notice(src,('Added %d %s.'):format(plan.units,itemName(food)))
 elseif a=='collect' then
  check(s.species and C.species[s.species].product and s.products>=1,'No products available')
  if s.species~='chicken' then tool(src,s.species=='sheep' and 'shear' or 'milk') end
  local n=math.floor(s.products*(s.species=='chicken' and 1 or (1+(score or 0)*.05)));s.products=0
  local item=C.species[s.species].product;batch(f,s,{{item=item,count=n}});notice(src,('Collected %d %s into linked chest.'):format(n,itemName(item)))
 elseif a=='manure' then
  tool(src,'fork');local n=math.floor(s.manure);check(n>0,'No manure available');s.manure=s.manure-n;batch(f,s,{{item='farm_manure',count=n}})
 elseif a=='slaughter' then
  check(score and score>=10 and s.species and s.species~='horse','Complete physical slaughter first');tool(src,'knife')
  local n=tonumber(d.count);local sex=d.sex
  check((sex=='female' or sex=='male') and n and n%1==0 and n>=1 and n<=s[sex],'Invalid animal selection')
  local yield=({chicken=1,pig=4,sheep=3,cattle=8})[s.species]
  s[sex]=s[sex]-n
  local changes={{item='farm_meat',count=math.floor(n*yield*(1+(score-10)*.05))}}
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
 if not ok then if src then notice(src,err);if sessions[src] and sessions[src].phase~='slaughter' then unlock(src);TriggerClientEvent(E..'workEnd',src) end else print('[frontier_farming] '..tostring(err)) end end
end
RegisterNetEvent(E..'action',function(a,d)
 local src=source;if type(a)~='string' or type(d)~='table' then return end
 local t=GetGameTimer();if a~='slaughterSpawned' and a~='slaughterSpawnFailed' and a~='cancelWork' and rate[src] and t-rate[src]<400 then return end;rate[src]=t
 run(src,function() action(src,a,d) end)
end)
AddEventHandler('playerDropped',function() local src=source;unlock(src);waterWork[src]=nil;rate[src]=nil;CreateThread(function() if ready then while busy do Wait(100) end;run(nil,function() returnMount(src) end) end end) end)
AddEventHandler('frontier:playerUnloaded',function(p) local src=p.source;unlock(src);waterWork[src]=nil;CreateThread(function() if ready then while busy do Wait(100) end;run(nil,function() returnMount(src) end) end end) end)
CreateThread(function() while true do Wait(1000);for src,w in pairs(sessions) do if GetGameTimer()>w.expires then unlock(src);TriggerClientEvent(E..'workEnd',src) end end end end)
exports('FacilityBound',function(id) return not ready or busy or row(id)~=nil end)
exports('DrainCompany',function(id)
 if GetInvokingResource()~='frontier_business' or not ready or busy then return false end
 busy=true
 local ok,result=pcall(function()
  for _,f in ipairs(MySQL.query.await("SELECT * FROM ff_facilities WHERE owner_type='company' AND owner_id=?",{id})) do
   if locked(f.id) then return false end
   check(MySQL.transaction.await({{query='INSERT INTO ff_confiscations(id,facility,plot,owner_type,owner_id,snapshot,reason,created) VALUES(?,?,?,?,?,?,?,?)',values={uuid(),f.id,f.plot,f.owner_type,f.owner_id,f.state,'company_liquidation',os.time()}},{query='DELETE FROM ff_facilities WHERE id=?',values={f.id}}}),'Liquidation audit failed')
  end
  return true
 end)
 busy=false;return ok and result==true
end)
MySQL.ready(function()
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS ff_water_sites(id CHAR(32) PRIMARY KEY,x DOUBLE NOT NULL,y DOUBLE NOT NULL,z DOUBLE NOT NULL,name VARCHAR(64) NOT NULL)]])
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS ff_confiscations(id CHAR(32) PRIMARY KEY,facility CHAR(32) NOT NULL,plot CHAR(32) NOT NULL,owner_type VARCHAR(16) NOT NULL,owner_id VARCHAR(64) NOT NULL,snapshot LONGTEXT NOT NULL,reason VARCHAR(32) NOT NULL,created BIGINT NOT NULL)]])
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS ff_horse_sales(id CHAR(32) PRIMARY KEY,source_id CHAR(32) NOT NULL,dest_id CHAR(32) NOT NULL,source_state LONGTEXT NOT NULL,dest_state LONGTEXT NOT NULL,debit BIGINT NOT NULL,credit BIGINT NOT NULL,amount BIGINT NOT NULL,phase VARCHAR(16) NOT NULL,INDEX(source_id,phase),INDEX(dest_id,phase))]])
 MySQL.query.await([[CREATE TABLE IF NOT EXISTS ff_animal_orders(order_id CHAR(32) PRIMARY KEY,facility CHAR(32) NOT NULL,after_state LONGTEXT NOT NULL,INDEX(facility))]])
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
   for _,j in ipairs(MySQL.query.await("SELECT * FROM ff_horse_sales WHERE phase='payment' LIMIT 50")) do local ok,e=horseSaleStep(j);if not ok then print('[frontier_farming] horse sale '..j.id..': '..tostring(e)) end end
   for _,j in ipairs(MySQL.query.await("SELECT * FROM ff_orders WHERE phase IN ('payment','paid') ORDER BY created LIMIT 50")) do local ok,e=orderStep(j);if not ok then print('[frontier_farming] supply order '..j.id..': '..tostring(e)) end end
   for _,j in ipairs(MySQL.query.await('SELECT * FROM ff_operations')) do
    local ok,err=finish(j)
    if not ok and ({insufficient_stock=true,weight=true,slots=true,stack_conflict=true,conflict=true,invalid_item=true})[err] then MySQL.update.await('DELETE FROM ff_operations WHERE id=?',{j.id}) end
   end
   for _,f in ipairs(MySQL.query.await('SELECT * FROM ff_facilities')) do if not locked(f.id) then
    local s=state(f);local b=prop:FarmBuilding(f.plot,f.id,f.owner_id)
    if b then R.advance(s,os.time(),f.size);save(f,s)
     -- Eggs remain in the enclosure until the player selects Collect eggs.
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
     local f=row(b.id);if f then local s=state(f);if mountLocks[f.id] and s.horses then local m=mounts[mountLocks[f.id]];if m then for i=#s.horses,1,-1 do if s.horses[i].id==m.horse then table.remove(s.horses,i) end end;R.horseCounts(s) end end;local lock=workLocks[f.id] and sessions[workLocks[f.id]];result[#result+1]={b=b,crop=s.crop,growth=s.growth,dead=s.dead,species=(not lock or (lock.phase~='slaughter' and lock.phase~='spawning')) and s.species or nil,female=s.female,male=s.male,young=s.young,horses=s.horses} elseif b.kind=='field' then result[#result+1]={b=b,growth=0} end
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

AddEventHandler('onResourceStop',function(name) if name==GetCurrentResourceName() then for src in pairs(sessions) do unlock(src) end;for _,m in pairs(mounts) do if DoesEntityExist(m.ped) then DeleteEntity(m.ped) end end end end)

exports('OpenHorseMarket',function(src)
 if GetInvokingResource()~='frontier_trade' then return false end
 run(src,function() horseMarket(src) end);return true
end)

CreateThread(function()
 while true do Wait(2000)
  if ready and not busy then
   run(nil,function()
    for src,m in pairs(mounts) do if cid(src)~=m.actor or os.time()>=m.expires or not DoesEntityExist(m.ped) or GetEntityHealth(m.ped)<=0 then returnMount(src) end end
    for src,w in pairs(waterWork) do if GetGameTimer()-w.started>C.waterFillMs+15000 then waterWork[src]=nil end end
   end)
  end
 end
end)
RegisterCommand('farmwatersite',function(src,args)
 if src==0 or not IsPlayerAceAllowed(src,'frontier.farming.admin') then return end
 run(src,function()
  local ped=GetPlayerPed(src);check(ped~=0 and GetPlayerRoutingBucket(src)==0,'Stand at a real water access point')
  local v=GetEntityCoords(ped);local name=table.concat(args,' '):sub(1,64)
  if name=='' then name='River access' end
  MySQL.insert.await('INSERT INTO ff_water_sites(id,x,y,z,name) VALUES(?,?,?,?,?)',{uuid(),v.x,v.y,v.z,name})
  notice(src,'Water collection point registered: '..name)
 end)
end,false)
RegisterCommand('farmwaterremove',function(src,args)
 if src==0 or not IsPlayerAceAllowed(src,'frontier.farming.admin') then return end
 run(src,function() local q=siteNear(src);check(q,'No nearby collection point');MySQL.update.await('DELETE FROM ff_water_sites WHERE id=?',{q.id});notice(src,'Water collection point removed') end)
end,false)
exports('StorageBound',function(storage)
 if GetInvokingResource()~='frontier_business' or not ready then return true end
 return MySQL.single.await('SELECT id FROM ff_facilities WHERE storage=? LIMIT 1',{storage})~=nil or MySQL.single.await("SELECT id FROM ff_orders WHERE storage=? AND phase IN ('payment','paid') LIMIT 1",{storage})~=nil
end)
exports('DrainPlot',function(plot)
 if GetInvokingResource()~='frontier_property' or not ready or busy then return false end
 busy=true
 local ok,result=pcall(function()
  for _,f in ipairs(MySQL.query.await('SELECT * FROM ff_facilities WHERE plot=?',{plot})) do
   if locked(f.id) then return false end
   check(MySQL.transaction.await({{query='INSERT INTO ff_confiscations(id,facility,plot,owner_type,owner_id,snapshot,reason,created) VALUES(?,?,?,?,?,?,?,?)',values={uuid(),f.id,f.plot,f.owner_type,f.owner_id,f.state,'plot_foreclosure',os.time()}},{query='DELETE FROM ff_facilities WHERE id=?',values={f.id}}}),'Foreclosure audit failed')
  end
  return true
 end)
 busy=false;return ok and result==true
end)

exports('ShopSupplies',function()
 if GetInvokingResource()~='frontier_shops' or not ready then return false,'Farming unavailable' end
 local out={}
 for id,price in pairs(C.supplyPrices) do
  local species,sex=id:match('^farm_(%a+)_(%a+)$')
  if not (species and C.species[species] and (sex=='male' or sex=='female')) then
   local d=C.items[id]
   out[id]={id=id,name=d.name,category=id:match('^farm_seed_') and 'Seeds' or (d.maxStack==1 and 'Farm tools' or 'Farm supplies'),buy=price}
  end
 end
 return true,out
end)
exports('ShopFarmData',function(src)
 if GetInvokingResource()~='frontier_shops' or not ready then return false,'Farming unavailable' end
 local ok,d=pcall(shopData,src)
 return ok,d
end)
exports('ShopFarmOrder',function(src,d,order)
 if GetInvokingResource()~='frontier_shops' or not ready or busy then return false,'Farming busy or unavailable' end
 if type(d)~='table' or type(d.item)~='string' then return false,'Invalid farm order' end
 busy=true
 local ok,done,message=pcall(buySupply,src,d,true,order)
 busy=false
 if not ok then return false,tostring(done) end
 return done,message
end)
