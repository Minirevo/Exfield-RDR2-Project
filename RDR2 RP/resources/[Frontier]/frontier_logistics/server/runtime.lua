LogisticsRuntime={}
local L=LogisticsRuntime
L.C=LogisticsConfig;L.R=LogisticsRules
L.I=exports.frontier_inventory;L.B=exports.frontier_business;L.P=exports.frontier_property
L.ECO=exports.frontier_economy;L.K=exports.frontier_skills;L.Core=exports.frontier_core
L.Q=MySQL.query.await;L.S=MySQL.single.await;L.U=MySQL.update.await;L.V=MySQL.scalar.await
L.E='frontier_logistics:'
L.ready=false;L.busy=false;L.views={};L.loads={};L.leases={};L.entities={};L.last={};L.lockTests={}
function L.now() return os.time() end
function L.check(ok,msg)if not ok then error(msg or 'Denied',0) end;return ok end
function L.id(id)return type(id)=='string' and #id==32 and id:match('^[a-f0-9]+$')~=nil end
function L.uuid(full)
 local raw=L.V('SELECT UUID()');L.check(type(raw)=='string','UUID unavailable')
 if full then return raw end
 local id=raw:gsub('-',''):lower();L.check(L.id(id),'UUID invalid');return id
end
function L.cid(src)return L.Core:GetPlayerCharacterId(src) end
function L.tell(src,msg)if src then TriggerClientEvent(L.E..'notice',src,tostring(msg)) else print('[frontier_logistics] '..tostring(msg)) end end
function L.run(src,fn)
 if not L.ready then if src then L.tell(src,'Logistics not ready; check SQL migrations') end;return end
 if L.busy then if src then L.tell(src,'Logistics busy, try again') end;return end
 L.busy=true;local ok,err=pcall(fn);L.busy=false
 if not ok then L.tell(src,err) end
end
function L.pos(src)
 if not src or GetPlayerRoutingBucket(src)~=0 or not L.cid(src) then return end
 local ped=GetPlayerPed(src);if ped==0 or not DoesEntityExist(ped) then return end
 local p=GetEntityCoords(ped);return {x=p.x,y=p.y,z=p.z,ped=ped}
end
function L.dist(a,b)
 if not a or not b then return math.huge end
 return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)
end
function L.near(src,p,r)return L.dist(L.pos(src),p)<=r end
function L.wagon(id)return L.id(id) and L.S('SELECT * FROM fl_wagons WHERE id=?',{id}) end
function L.route(id)return 'lg_w_'..id end
function L.crateRoute(id)return 'lg_c_'..id end
function L.freightRoute(id)return 'lg_f_'..id:gsub('-','') end
function L.bag(src)
 local who=L.cid(src);if not who then return end
 local ok,box=L.I:GetInventory(src);if ok then return 'p_'..who,box end
end
function L.account(src,typ,id,perm)
 local who=L.cid(src)
 if typ=='character' and who==id then
  local ok,a=L.ECO:GetCharacterAccounts(src);if ok then return a.bank.id end
 elseif typ=='company' then return L.B:GetCompanyAccount(id,who,perm or 'finance') end
end
function L.right(src,w,perm)
 local who=L.cid(src);if not who or not w then return false end
 if w.owner_type=='character' then return w.owner_id==who end
 return L.B:HasCompanyPermission(w.owner_id,who,perm or 'trade')==true
end
function L.licensed(typ,id)return L.B:VerifyLicense(typ,id,'transport')==true end
function L.point(w)
 local e=L.entities[w.id]
 if e and DoesEntityExist(e.vehicle) then local p=GetEntityCoords(e.vehicle);return {x=p.x,y=p.y,z=p.z} end
end
function L.stationary(w)
 local e=L.entities[w.id];return e and DoesEntityExist(e.vehicle) and GetEntitySpeed(e.vehicle)<.5
end
function L.access(src,w,perm)
 if not w or w.state~='world' or not L.near(src,L.point(w),L.C.InteractionDistance) or not L.stationary(w) then return false end
 if L.right(src,w,'trade') then return L.right(src,w,perm) end
 return tonumber(w.locked)==0
end
function L.freight(wid)
 return L.Q("SELECT * FROM fl_contracts WHERE wagon_id=? AND state IN ('pickup','in_transit','deliver','wreck','steal') ORDER BY id",{wid})
end
function L.freightCapacity(wid)
 local grams,slots=0,0
 for _,c in ipairs(L.freight(wid)) do
  local ok,box=L.I:LogisticsRead(L.freightRoute(c.id))
  L.check(ok,'Reserved freight unavailable')
  grams=grams+box.weight;slots=slots+#box.slots
 end
 return grams,slots
end
function L.job(id)return L.S('SELECT * FROM fl_jobs WHERE id=?',{id})end
function L.jobState(j,state,issue)
 L.U('UPDATE fl_jobs SET state=?,issue=? WHERE id=? AND state=?',{state,tostring(issue or ''):sub(1,255),j.id,j.state})
end
function L.newJob(kind,actor,wagon,payload,state)
 local id=L.uuid()
 L.U('INSERT INTO fl_jobs(id,kind,actor,wagon_id,state,payload,created_at) VALUES(?,?,?,?,?,?,?)',{id,kind,actor,wagon or '',state or 'pending',json.encode(payload),L.now()})
 return id
end
function L.wagonBusy(id)
 return L.V("SELECT id FROM fl_jobs WHERE wagon_id=? AND state IN ('loading','commit','wreck','purchase','assemble','repair') LIMIT 1",{id})~=nil
  or L.V("SELECT x.delivery_id FROM ft_wagon_deliveries x JOIN frontier_trade_deliveries d ON d.id=x.delivery_id WHERE x.wagon_id=? AND d.state='stock' LIMIT 1",{id})~=nil
end

function L.dealer(src)
    for _,p in ipairs(L.C.Depots) do
        if L.near(src,p,L.C.DepotDistance) then
            return p
        end

        if p.spawn and L.near(
            src,p.spawn,L.C.DepotDistance
        ) then
            return p
        end
    end
end

function L.horses(src)
 local p=L.Core:GetPlayer(src);if not p or not p.providerCharacterId then return {} end
 return L.Q("SELECT s.id,s.name,s.modelname,s.injured,h.wagon_id,h.slot_no FROM stables s LEFT JOIN fl_harnesses h ON s.id=h.horse_id WHERE s.charidentifier=? AND s.type='horse' AND (s.status IS NULL OR s.status='' OR s.status='{}')",{p.providerCharacterId})
end
function L.assignments(id)
 return L.Q('SELECT horse_id,slot_no,model,provider_id,character_id FROM fl_harnesses WHERE wagon_id=? ORDER BY slot_no',{id})
end
function L.ownerWagons(src)
 local who=L.cid(src);local out={}
 for _,w in ipairs(L.Q("SELECT * FROM fl_wagons WHERE state<>'destroyed' ORDER BY name,id")) do
  if w.owner_type=='character' and w.owner_id==who or w.owner_type=='company' and L.right(src,w,'trade') then
   w.spawnStatus=(L.spawnStatus or {})[w.id];w.spawned=L.entities[w.id]~=nil;out[#out+1]=w
  end
 end
 return out
end
function L.validateStorage(src,id,direction,w)
 if type(id)~='string' then return false end
 local p=L.point(w)
 for _,v in ipairs(L.P:LogisticsNearbyStorage(src)) do
  if v.id==id and L.dist(v,p)<=L.C.LoadDistance then return true end
 end
 for _,v in ipairs(L.B:LogisticsStock(src,false)) do
  if v.id==id and L.dist(v,p)<=L.C.LoadDistance and (direction=='from' and v.retrieve or direction=='to' and v.deposit or direction=='view') then return true end
 end
 return false
end
function L.broadcastWagon(w)
 local e=L.entities[w.id];if not e or not DoesEntityExist(e.vehicle) then return end
 local ok,box=L.I:LogisticsRead(L.route(w.id));if not ok then return end
 local freight=0
 for _,c in ipairs(L.freight(w.id)) do if c.state=='in_transit' or c.state=='deliver' or c.state=='steal' then local ok,f=L.I:LogisticsRead(L.freightRoute(c.id));if ok then freight=freight+f.weight end end end
 Entity(e.vehicle).state:set('frontierWagon',{id=w.id,model=w.model,locked=tonumber(w.locked)==1,stolen=tonumber(w.stolen)==1,weight=box.weight+freight,limit=box.weightLimit,name=w.name},true)
end
