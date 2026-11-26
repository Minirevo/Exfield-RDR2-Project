local C,R=FarmConfig,FarmRules
local E='frontier_farming:'
local core,inv,prop,biz=exports.frontier_core,exports.frontier_inventory,exports.frontier_property,exports.frontier_business
local ready,busy=false,false
local sessions,rate={},{}
local workLocks,mounts,mountLocks,waterWork={},{},{},{}
local function unlock(src)
 local w=sessions[src];if w then
  for _,ped in ipairs(w.animals or {}) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
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

local function view(src)
 local result={}
 for _,b in ipairs(prop:GetFarmBuildings(src)) do if near(src,b) then
  local f=row(b.id);local detail=prop:FarmBuilding(b.plot,b.id,cid(src))
  if f and authorized(src,f,detail) then
   local s=state(f);if not locked(f.id) then R.advance(s,os.time(),b.size);save(f,s) end
   result[#result+1]={building=b,owner=f.owner_id,ownerType=f.owner_type,storage=f.storage,state=s,stocks=biz:FarmStock(cid(src),f.plot,f.owner_type,f.owner_id),pending=not not locked(f.id)}
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
local function shopView(src)
 local who=cid(src);check(who and supplier(src),'Approach an agricultural supplier')
 local list={}
 for k,v in pairs(C.supplyPrices) do list[#list+1]={id=k,name=C.items[k].name,price=v} end
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
local function beginWater(src)
 tool(src,'bucket');check(not waterWork[src],'Already filling a bucket')
 local q=siteNear(src);check(q,'Approach an approved river or lake collection point')
 local w={actor=cid(src),id=uuid(),site=q.id,started=GetGameTimer()}
 waterWork[src]=w;TriggerClientEvent(E..'waterWork',src,{token=w.id,ms=C.waterFillMs})
end
local function finishWater(src,d)
 local w=waterWork[src];check(w and w.actor==cid(src) and w.id==d.token,'Water collection expired')
 local t=GetGameTimer()-w.started;check(t>=C.waterFillMs and t<=C.waterFillMs+15000,'Invalid filling duration')
 local q=siteNear(src);check(q and q.id==w.site,'Remain near the water source');tool(src,'bucket')
 local ok,e=inv:FarmSupplyDelivery(w.actor,'farm_water',10,'farm_water_'..w.id)
 check(ok,e);waterWork[src]=nil;notice(src,'Filled 10 water units. Carry them back to your farm stock.')
end

local function action(src,a,d,score)
 local who=cid(src);check(who,'Select a character first')
 if a=='open' then return view(src) end
 if a=='riverStart' then return beginWater(src) end
 if a=='riverFinish' then return finishWater(src,d) end
 if a=='returnMount' then check(mounts[src] and mounts[src].actor==who,'No mount checked out');return returnMount(src) end
 if a=='shop' then return shopView(src) end
 if a=='horseMarket' then return horseMarket(src) end
 if a=='buyHorse' then return buyHorse(src,d) end
 if a=='buySupply' then return buySupply(src,d) end
 if a=='cancelWork' then unlock(src);waterWork[src]=nil;if d.reopen then return view(src) end;return end
 if a=='slaughterFinish' then
  local w=sessions[src];check(w and w.actor==who and w.phase=='slaughter' and d.token==w.token,'No slaughter session')
  local f=row(w.id);local b=f and current(src,f);check(b and not pending(w.id),'Facility unavailable')
  tool(src,'knife')
  for _,ped in ipairs(w.animals) do check(DoesEntityExist(ped) and GetEntityHealth(ped)<=0,'All selected physical animals must be slaughtered first') end
  local payload=w.data;local hits=w.hits;unlock(src)
  return action(src,'slaughter',payload,hits+10)
 end
 if a=='workHit' then
  local w=sessions[src];check(w and w.phase~='slaughter' and w.actor==who and w.token==d.token,'Work session expired')
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
 check(not locked(f.id),'Facility busy or pending transaction')
 local s=state(f);R.advance(s,os.time(),b.size);save(f,s)
 if workLocks[f.id] then error('Facility is being worked',0) end
 if C.work[a] and score==nil then
  local key=C.work[a];if a=='collect' and s.species=='sheep' then key='shear' end
  if a~='trainHorse' then tool(src,key) end;check(not sessions[src],'Finish your current work first')
  local w={id=f.id,plot=f.plot,actor=who,token=uuid(),action=a,data=d,hits=0,round=1,started=GetGameTimer(),expires=GetGameTimer()+60000,target=math.random(25,75)/100}
  sessions[src]=w;workLocks[f.id]=src
  TriggerClientEvent(E..'workRound',src,{token=w.token,target=w.target,round=1,action=a})
  return
 end
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
  local units=b.kind=='field' and math.ceil(C.fieldCapacity[b.size]/25) or math.ceil(R.count(s)/4)
  s.water=math.min(172800*(b.kind=='field' and 1 or R.count(s)),s.water+43200*(b.kind=='field' and 1 or R.count(s))*(1+(score or 0)*.05))
  batch(f,s,{{item='farm_water',count=-units}})
 elseif a=='fertilize' then
  check(s.crop and not s.dead and not s.fertilized,'No eligible crop');tool(src,'fork');s.fertilized=true
  batch(f,s,{{item='farm_fertilizer',count=-math.ceil(C.fieldCapacity[b.size]/25)}})
 elseif a=='clearCrop' then
  check(s.crop and s.dead,'Only dead crops can be cleared');tool(src,'hoe');s.crop=nil;s.dead=false;s.growth=0;s.water=0;save(f,s)
 elseif a=='harvest' then
  check(s.crop and not s.dead and s.growth>=1,'Crop not ready');tool(src,'sickle')
  local n=C.fieldCapacity[b.size];local crop=s.crop
  if not s.harvestRemaining then
   s.harvestRemaining=math.floor(n*(s.fertilized and 2.5 or 2)*s.soil/100*(1+(score or 0)*.05))
   s.seedRemaining=n+math.floor(n/10)
  end
  local output=math.min(C.harvestBatch,s.harvestRemaining)
  local seeds=output==s.harvestRemaining and s.seedRemaining or math.floor(s.seedRemaining*output/s.harvestRemaining)
  s.harvestRemaining=s.harvestRemaining-output;s.seedRemaining=s.seedRemaining-seeds
  if s.harvestRemaining==0 then s.crop=nil;s.growth=0;s.water=0;s.soil=math.max(60,s.soil-1);s.harvestRemaining=nil;s.seedRemaining=nil end
  local changes={{item='farm_'..crop,count=output}}
  if seeds>0 then changes[#changes+1]={item='farm_seed_'..crop,count=seeds} end
  batch(f,s,changes)
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
  local n=R.count(s);s.feed=math.min(n*172800,s.feed+n*43200*(1+(score or 0)*.05))
  local food=C.species[s.species].feed;if s.species=='pig' and C.pigFeed[d.food] then food=d.food end
  batch(f,s,{{item=food,count=-n}})
 elseif a=='collect' then
  check(s.species and C.species[s.species].product and s.products>=1,'No products available')
  check(s.species~='chicken','Eggs are automatically deposited')
  tool(src,s.species=='sheep' and 'shear' or 'milk')
  local n=s.products;s.products=0;batch(f,s,{{item=C.species[s.species].product,count=math.floor(n*(1+(score or 0)*.05))}})
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
 if not ok then if src then notice(src,err) else print('[frontier_farming] '..tostring(err)) end end
end
RegisterNetEvent(E..'action',function(a,d)
 local src=source;if type(a)~='string' or type(d)~='table' then return end
 local t=GetGameTimer();if rate[src] and t-rate[src]<400 then return end;rate[src]=t
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
     local f=row(b.id);if f then local s=state(f);if mountLocks[f.id] and s.horses then local m=mounts[mountLocks[f.id]];if m then for i=#s.horses,1,-1 do if s.horses[i].id==m.horse then table.remove(s.horses,i) end end;R.horseCounts(s) end end;local lock=workLocks[f.id] and sessions[workLocks[f.id]];result[#result+1]={b=b,crop=s.crop,growth=s.growth,dead=s.dead,species=(not lock or lock.phase~='slaughter') and s.species or nil,female=s.female,male=s.male,young=s.young,horses=s.horses} end
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
