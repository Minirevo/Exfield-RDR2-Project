-- Relational persistence with row-level diffs. The runtime cache is reconstructed from SQL.
PropertyDB={}
local D=PropertyDB
local previous={}
local function rows(t) return MySQL.query.await('SELECT * FROM '..t) or {} end
local function num(v) return tonumber(v) end
local function flag(v) return v==true or tonumber(v)==1 end
local function decode(v) return json.decode(v) end
local function nullable(v) return v==nil and '' or v end
local function encode(v) return json.encode(v) end
-- Deterministic JSON for row comparison; SQL receives ordinary JSON.
local function canonical(v)
    if type(v)~='table' then return encode(v) end
    local keys={};for k in pairs(v) do keys[#keys+1]=k end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    local out={}
    for _,k in ipairs(keys) do out[#out+1]=encode(tostring(k))..':'..canonical(v[k]) end
    return '{'..table.concat(out,',')..'}'
end
local specs={
 {'fp_settlements',{'id','name','x','y','z','radius','primary_owner','status','map_public'},1},
 {'fp_owners',{'settlement_id','character_id'},2},
 {'fp_permissions',{'settlement_id','character_id','rights_json'},2},
 {'fp_camps',{'settlement_id','storage_id'},1},
 {'fp_buildings',{'id','settlement_id','exterior','x','y','z','heading','radius','complete','locked','asset_value'},1},
 {'fp_interiors',{'building_id','template_id','routing_bucket','capacity'},1},
 {'fp_furniture',{'id','building_id','item_id','x','y','z','heading'},1},
 {'fp_construction',{'building_id','stage_no','progress_seconds'},1},
 {'fp_stages',{'building_id','stage_no','label','seconds','tools_json'},2},
 {'fp_materials',{'building_id','stage_no','item_id','required_qty','delivered_qty'},3},
 {'fp_taxes',{'settlement_id','debt','next_tax','overdue'},1},
 {'fp_listings',{'settlement_id','price','active'},1},
 {'fp_approvals',{'settlement_id','character_id'},2},
 {'fp_operations',{'id','kind','settlement_id','payload'},1},
 {'fp_visits',{'character_id','settlement_id','building_id','x','y','z'},1},
}
local function project(S)
    local result={}
    for _,spec in ipairs(specs) do result[spec[1]]={} end
    local function put(t,key,...)
        local a={...};result[t][key]={values=a,signature=canonical(a)}
    end
    local function key(...) local a={...};for i,v in ipairs(a) do a[i]=tostring(v) end;return table.concat(a,':') end
    for sid,s in pairs(S.settlements) do
        put('fp_settlements',sid,sid,s.name,s.x,s.y,s.z,s.radius,s.primary,s.status,s.map and 1 or 0)
        put('fp_camps',sid,sid,'property_'..sid)
        put('fp_taxes',sid,sid,s.debt,s.nextTax,nullable(s.overdue))
        for id in pairs(s.owners) do put('fp_owners',key(sid,id),sid,id) end
        for id,r in pairs(s.members) do put('fp_permissions',key(sid,id),sid,id,canonical(r)) end
        if s.listing then
            put('fp_listings',sid,sid,s.listing.price,s.listing.active and 1 or 0)
            for id in pairs(s.listing.approvals) do put('fp_approvals',key(sid,id),sid,id) end
        end
        for bid,b in pairs(s.buildings) do
            put('fp_buildings',bid,bid,sid,b.exterior,b.x,b.y,b.z,b.heading,b.radius,b.complete and 1 or 0,b.locked and 1 or 0,b.value)
            if b.interior then put('fp_interiors',bid,bid,b.interior,b.bucket,b.capacity) end
            for fid,f in pairs(b.furniture) do put('fp_furniture',fid,fid,bid,f.item,f.x,f.y,f.z,f.heading) end
            put('fp_construction',bid,bid,b.stage,b.progress)
            for n,stage in ipairs(b.stages) do
                put('fp_stages',key(bid,n),bid,n,stage.label,stage.seconds,encode(stage.tools))
                for item,qty in pairs(stage.materials) do
                    put('fp_materials',key(bid,n,item),bid,n,item,qty,n<b.stage and qty or n==b.stage and (b.delivered[item] or 0) or 0)
                end
            end
        end
    end
    for id,j in pairs(S.jobs) do put('fp_operations',id,id,j.kind,nullable(j.sid),encode(j)) end
    for id,v in pairs(S.visits) do put('fp_visits',id,id,v.sid,v.bid,v.x,v.y,v.z) end
    return result
end
function D.load()
    local meta=assert(MySQL.single.await('SELECT revision,next_bucket FROM fp_meta WHERE id=1'),'Apply relational property migration')
    local S={settlements={},jobs={},visits={},nextBucket=num(meta.next_bucket)}
    local buildings={}
    for _,r in ipairs(rows('fp_settlements')) do
        S.settlements[r.id]={id=r.id,name=r.name,x=num(r.x),y=num(r.y),z=num(r.z),radius=num(r.radius),primary=r.primary_owner,status=r.status,map=flag(r.map_public),owners={},members={},buildings={}}
    end
    for _,r in ipairs(rows('fp_owners')) do S.settlements[r.settlement_id].owners[r.character_id]=true end
    for _,r in ipairs(rows('fp_permissions')) do S.settlements[r.settlement_id].members[r.character_id]=decode(r.rights_json) end
    for _,r in ipairs(rows('fp_taxes')) do local s=S.settlements[r.settlement_id];s.debt=num(r.debt);s.nextTax=num(r.next_tax);s.overdue=num(r.overdue) end
    for _,r in ipairs(rows('fp_listings')) do S.settlements[r.settlement_id].listing={price=num(r.price),active=flag(r.active),approvals={}} end
    for _,r in ipairs(rows('fp_approvals')) do S.settlements[r.settlement_id].listing.approvals[r.character_id]=true end
    for _,r in ipairs(rows('fp_buildings')) do
        local b={id=r.id,exterior=r.exterior,x=num(r.x),y=num(r.y),z=num(r.z),heading=num(r.heading),radius=num(r.radius),complete=flag(r.complete),locked=flag(r.locked),value=num(r.asset_value),capacity=0,stages={},delivered={},furniture={}}
        buildings[r.id]=b;S.settlements[r.settlement_id].buildings[r.id]=b
    end
    for _,r in ipairs(rows('fp_interiors')) do local b=buildings[r.building_id];b.interior=r.template_id;b.bucket=num(r.routing_bucket);b.capacity=num(r.capacity) end
    for _,r in ipairs(rows('fp_furniture')) do buildings[r.building_id].furniture[r.id]={item=r.item_id,x=num(r.x),y=num(r.y),z=num(r.z),heading=num(r.heading)} end
    for _,r in ipairs(rows('fp_construction')) do local b=buildings[r.building_id];b.stage=num(r.stage_no);b.progress=num(r.progress_seconds) end
    for _,r in ipairs(rows('fp_stages')) do buildings[r.building_id].stages[num(r.stage_no)]={label=r.label,seconds=num(r.seconds),tools=decode(r.tools_json),materials={}} end
    for _,r in ipairs(rows('fp_materials')) do local b=buildings[r.building_id];local n=num(r.stage_no);b.stages[n].materials[r.item_id]=num(r.required_qty);if n==b.stage then b.delivered[r.item_id]=num(r.delivered_qty) end end
    for _,r in ipairs(rows('fp_operations')) do S.jobs[r.id]=decode(r.payload) end
    for _,r in ipairs(rows('fp_visits')) do S.visits[r.character_id]={actor=r.character_id,sid=r.settlement_id,bid=r.building_id,x=num(r.x),y=num(r.y),z=num(r.z)} end
    previous=project(S)
    return S,num(meta.revision)
end
local function statement(spec,record,delete)
    local name,cols,n=spec[1],spec[2],spec[3];local values={}
    if delete then
        local where={};for i=1,n do where[i]=cols[i]..'=?';values[i]=record.values[i] end
        return {query='DELETE FROM '..name..' WHERE '..table.concat(where,' AND '),values=values}
    end
    local params,updates={},{}
    for i,col in ipairs(cols) do
        params[i]=(col=='overdue' or (name=='fp_operations' and col=='settlement_id')) and "NULLIF(?, '')" or '?'
        if i>n then updates[#updates+1]=col..'=VALUES('..col..')' end
    end
    if #updates==0 then updates[1]=cols[1]..'='..cols[1] end
    return {query='INSERT INTO '..name..' ('..table.concat(cols,',')..') VALUES ('..table.concat(params,',')..') ON DUPLICATE KEY UPDATE '..table.concat(updates,','),values=record.values}
end
function D.save(S,revision)
    local current=project(S);local queries={}
    -- Child deletes first; parent inserts first. Only changed rows are written.
    for i=#specs,1,-1 do local spec=specs[i];local t=spec[1]
        for key,record in pairs(previous[t] or {}) do if not current[t][key] then
            if t=='fp_operations' then
                queries[#queries+1]={query="INSERT IGNORE INTO fp_history(operation_id,settlement_id,kind,details) VALUES (?,NULLIF(?,''),?,?)",values={record.values[1],record.values[3],record.values[2],record.values[4]}}
            end
            queries[#queries+1]=statement(spec,record,true)
        end end
    end
    for _,spec in ipairs(specs) do local t=spec[1]
        for key,record in pairs(current[t]) do local old=previous[t] and previous[t][key]
            if not old or old.signature~=record.signature then queries[#queries+1]=statement(spec,record,false) end
        end
    end
    queries[#queries+1]={query='UPDATE fp_meta SET revision=revision+1,next_bucket=? WHERE id=1',values={S.nextBucket}}
    assert(MySQL.transaction.await(queries),'Property relational transaction failed')
    previous=current
    return revision+1
end
