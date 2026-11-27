local cfg=ProductionConfig
local core,economy,inventory=exports.frontier_core,exports.frontier_economy,exports.frontier_inventory
local resource=GetCurrentResourceName()
local online,views,busy,last={},{},{},{}
local ready=false
local E='frontier_production:'
local texts={database_error='Der Vorgang konnte nicht bestätigt werden. Wiederhole dieselbe Anfrage.',
    forbidden='Dein Charakter ist nicht verfügbar.', unavailable='Für diesen Vorgang fehlt Platz, ein Mitarbeiter oder ein freier Auftrag.',
    invalid='Die Eingabe ist ungültig.', insufficient_stock='Nicht genügend Zutaten oder Produkte vorhanden.',
    storage_full='Das Produktionslager ist voll.', weight='Das Gewichtslimit wäre überschritten.',
    slots='Es sind nicht genug Plätze frei.', conflict='Das Lager hat sich geändert. Wiederhole die Anfrage.',
    busy='Bitte warte kurz.', disabled='Produktion ist momentan deaktiviert.'}
local titles={reserve='Zutatenprüfung',wage='Lohnprüfung',unpaid='Lohn offen',running='In Arbeit',
    output='Wartet auf Lagerplatz',complete='Fertig',cancelled='Storniert',rejected='Zutaten fehlen',["return"]='Zutatenrückgabe'}

local function db(method,sql,args)
    local ok,result=pcall(MySQL[method].await,sql,args)
    if not ok then
        FrontierLib.Log('ERROR',resource,'Production database call failed',{method=method})
        return false,'database_error'
    end
    return true,result
end

local function integer(n,max)
    return type(n)=='number' and n>0 and n<=max and FrontierLib.IsInteger(n)
end

local function uuid(value)
    return type(value)=='string' and #value==36 and value:match('^[a-f0-9-]+$')
end

local function owner(source)
    return core:GetPlayerCharacterId(source)
end

local function present(ownerId)
    local source=online[ownerId]
    return source and owner(source)==ownerId
end

local function storageOptions(items,job)
    return {slots=cfg.StorageSlots,grams=cfg.StorageGrams,units=cfg.StorageUnits,items=items,job=job}
end

local function business(source,id)
    local ok,accounts=economy:GetCharacterAccounts(source)
    if not ok then return false,accounts end
    if accounts.characterId~=id or owner(source)~=id then return false,'forbidden' end
    local saved,err=db('update',[[
        INSERT INTO frontier_production_businesses(owner_id,bank_id) VALUES(?,?)
        ON DUPLICATE KEY UPDATE bank_id=VALUES(bank_id)
    ]],{id,accounts.bank.id})
    if not saved then return false,err end
    local loaded,row=db('single','SELECT employee,bank_id FROM frontier_production_businesses WHERE owner_id=?',{id})
    if not loaded or not row then return false,'database_error' end
    row.balance=accounts.bank.balance_minor
    return true,row
end

local function itemName(item)
    return cfg.Items[item] and cfg.Items[item].name or ({bread='Brot',water='Wasser'})[item] or item
end

local function recipeView()
    local result={}
    for id,recipe in pairs(cfg.Recipes) do
        local needs={}
        for item,count in pairs(recipe.inputs) do needs[#needs+1]={id=item,name=itemName(item),count=count} end
        table.sort(needs,function(a,b) return a.name<b.name end)
        result[#result+1]={id=id,name=recipe.name,description=recipe.description,seconds=recipe.seconds,
            output=itemName(recipe.output),quantity=recipe.quantity,inputs=needs,player=recipe.player,npc=recipe.npc}
    end
    table.sort(result,function(a,b) return a.name<b.name end)
    return result
end

local function snapshot(source,id)
    local ok,firm=business(source,id)
    if not ok then return false,firm end
    local stored,box=inventory:GetProductionStorage(id,cfg.StorageSlots,cfg.StorageGrams)
    if not stored then return false,box end
    local read,jobs=db('query',[[
        SELECT id,recipe,mode,batches,state,wage_minor,output_units,duration_seconds,
            IF(mode='npc' AND state='running',
               GREATEST(0,TIMESTAMPDIFF(SECOND,UTC_TIMESTAMP(),completes_at)),remaining_seconds) AS remaining
        FROM frontier_production_jobs WHERE owner_id=? AND state<>'rejected'
        ORDER BY state IN ('complete','cancelled'), created_at DESC,id LIMIT 40
    ]],{id})
    if not read then return false,jobs end
    local known,bag=inventory:GetInventory(source)
    if not known then return false,bag end
    local counts={}
    for _,stack in pairs(bag.slots or {}) do counts[stack.item]=(counts[stack.item] or 0)+stack.quantity end
    local goods={}
    for _,stack in pairs(box.slots or {}) do
        local entry=goods[stack.item]
        if not entry then
            entry={id=stack.item,name=stack.name,description=stack.description,count=0}
            goods[stack.item]=entry
        end
        entry.count=entry.count+stack.quantity
    end
    local list={}
    for _,entry in pairs(goods) do list[#list+1]=entry end
    table.sort(list,function(a,b) return a.name<b.name end)
    for _,row in ipairs(jobs) do
        row.name=cfg.Recipes[row.recipe] and cfg.Recipes[row.recipe].name or row.recipe
        row.status=titles[row.state]
    end
    return true,{legacy=true,employee=firm.employee,balance=firm.balance,recipes=recipeView(),ingredients=counts,
        jobs=jobs,goods=list,units=box.units,capacity=cfg.StorageUnits,maxBatches=cfg.MaxBatches,
        wage=cfg.WageMinor,wageInterval=cfg.WageIntervalSeconds}
end

local function materialSnapshot(recipe,batches)
    local items={}
    for id,count in pairs(recipe.inputs) do items[#items+1]={id=id,count=count*batches} end
    table.sort(items,function(a,b) return a.id<b.id end)
    return items
end

local function start(source,id,key,data)
    if type(data.recipe)~='string' or not integer(data.batches,cfg.MaxBatches)
        or (data.mode~='player' and data.mode~='npc') or data.confirm~=true then return false,'invalid' end
    local recipe=cfg.Recipes[data.recipe]
    if not recipe or recipe[data.mode]~=true then return false,'invalid' end

    -- A repeated request must remain successful even if its ingredients have
    -- already been reserved by the worker after the original submission.
    local checked,existing=db('single',[[SELECT id FROM frontier_production_jobs
        WHERE id=? AND owner_id=? AND recipe=? AND mode=? AND batches=?]],{
        key,id,data.recipe,data.mode,data.batches
    })
    if not checked then return false,existing end
    if existing then return true end

    local known,bag=inventory:GetInventory(source)
    if not known then return false,bag end
    local counts={}
    for _,stack in pairs(bag.slots or {}) do
        counts[stack.item]=(counts[stack.item] or 0)+stack.quantity
    end
    local missing={}
    for item,count in pairs(recipe.inputs) do
        local required=count*data.batches
        local absent=required-(counts[item] or 0)
        if absent>0 then missing[#missing+1]=absent..'x '..itemName(item) end
    end
    if #missing>0 then
        table.sort(missing)
        return false,'missing:Nicht genügend Rohstoffe: '..table.concat(missing,', ')..'.'
    end

    local seconds=recipe.seconds*data.batches
    local cost=data.mode=='npc' and math.ceil(seconds*cfg.WageMinor/cfg.WageIntervalSeconds) or 0
    local saved,result=db('query','CALL frontier_production_start_v1(?,?,?,?,?,?,?,?,?,?,?)',
        {key,id,data.recipe,data.mode,data.batches,json.encode(materialSnapshot(recipe,data.batches)),recipe.output,
            recipe.quantity*data.batches,seconds,cost,cfg.MaxJobs})
    if not saved then return false,result end
    local status=result and result[1] and result[1][1] and result[1][1].code
    return status=='ok',status or 'database_error'
end

local function action(source,id,key,name,data)
    if name=='refresh' then return true end
    if name=='start' then return false,'missing:New production orders require a placed production station. Approach one and press E.' end
    if name=='hire' then return false,'missing:Hire workers at a physical production station.' end
    if name=='dismiss' then
        local ok,rows=db('query','CALL frontier_production_employee_v1(?,?)',{id,name})
        if not ok then return false,rows end
        local code=rows and rows[1] and rows[1][1] and rows[1][1].code
        return code=='ok',code or 'database_error'
    end
    if name=='resume' then
        if not uuid(data.job) then return false,'invalid' end
        local ok,changed=db('update',[[
            UPDATE frontier_production_jobs j JOIN frontier_production_businesses b ON b.owner_id=j.owner_id
            SET j.state='wage',j.retry_at=UTC_TIMESTAMP(),b.employee='hired'
            WHERE j.id=? AND j.owner_id=? AND j.state='unpaid' AND b.employee='unpaid'
        ]],{data.job,id})
        return ok and changed>0,ok and 'unavailable' or changed
    end
    if name=='cancel' then
        if not uuid(data.job) then return false,'invalid' end
        local ok,changed=db('update',[[
            UPDATE frontier_production_jobs j JOIN frontier_production_businesses b ON b.owner_id=j.owner_id
            SET j.state='return',j.retry_at=UTC_TIMESTAMP(),b.employee='hired'
            WHERE j.id=? AND j.owner_id=? AND j.state='unpaid' AND b.employee='unpaid'
        ]],{data.job,id})
        if not ok then return false,changed end
        if changed>0 then return true end
        ok,changed=db('update',[[
            UPDATE frontier_production_jobs SET state='return',retry_at=UTC_TIMESTAMP()
            WHERE id=? AND owner_id=? AND state='running'
        ]],{data.job,id})
        if not ok then return false,changed end
        if changed>0 then return true end
        local read,row=db('single','SELECT state FROM frontier_production_jobs WHERE id=? AND owner_id=?',{data.job,id})
        return read and row and (row.state=='return' or row.state=='cancelled'),'unavailable'
    end
    if name=='collect' then
        local items
        if data.item~=nil then
            if type(data.item)~='string' or #data.item>48 or not integer(data.quantity,cfg.StorageUnits) then
                return false,'invalid'
            end
            items={{id=data.item,count=data.quantity}}
        end
        if owner(source)~=id then return false,'forbidden' end
        local collected,issue=inventory:ApplyProductionInventory('collect',id,key..':collect',storageOptions(items))
        if not collected then return false,issue end

        -- Completed jobs share one output warehouse. Clear their history only
        -- once the warehouse is completely empty, so partial collections keep
        -- the completed jobs visible.
        local stored,box=inventory:GetProductionStorage(id,cfg.StorageSlots,cfg.StorageGrams)
        if stored and tonumber(box.units)==0 then
            local marked,reason=db('update',[[DELETE FROM frontier_production_jobs
                WHERE owner_id=? AND state='complete']],{id})
            if not marked then FrontierLib.Log('WARN',resource,'Could not clear collected production jobs',{owner=id,reason=reason}) end
        end
        return true
    end
    return false,'invalid'
end

local function result(source,ticket,seq,ok,message,state,retry)
    TriggerClientEvent(E..'response',source,ticket,seq,{ok=ok,message=message,snapshot=state,retry=retry})
end

RegisterNetEvent(E..'open',function(clientView)
    local source=tonumber(source)
    if not source or not integer(clientView,2147483647) or busy[source] then return end
    local now=GetGameTimer()
    if last[source] and now>=last[source] and now-last[source]<350 then return end
    last[source]=now
    local id=owner(source)
    if not cfg.Enabled or not ready or not id then
        result(source,clientView,0,false,not cfg.Enabled and texts.disabled or 'Produktion ist noch nicht verfügbar.')
        return
    end
    busy[source]=true
    local ran,ok,state=pcall(snapshot,source,id)
    local issued,ticket=db('scalar','SELECT UUID()')
    busy[source]=nil
    if owner(source)~=id then return end
    if not ran or not ok or not issued or not uuid(ticket) then
        result(source,clientView,0,false,texts.database_error)
        return
    end
    views[source]={id=id,ticket=ticket}
    TriggerClientEvent(E..'opened',source,clientView,ticket,state)
end)

RegisterNetEvent(E..'request',function(ticket,seq,name,data)
    local source=tonumber(source)
    local view=source and views[source]
    if not cfg.Enabled or not ready or not view or ticket~=view.ticket or not integer(seq,2147483647)
        or type(name)~='string' or #name>12 or type(data)~='table' or owner(source)~=view.id then return end
    local now=GetGameTimer()
    if busy[source] or (last[source] and now>=last[source] and now-last[source]<350) then
        result(source,ticket,seq,false,texts.busy);return
    end
    last[source]=now
    busy[source]=true
    local ran,ok,reason=pcall(function()
        local generated,key=db('scalar',"SELECT SUBSTRING(SHA2(CONCAT(?,':',?),256),1,36)",{ticket,seq})
        if not generated then return false,key end
        if views[source]~=view or owner(source)~=view.id then return false,'forbidden' end
        return action(source,view.id,key,name,data)
    end)
    local observed,loaded,state=pcall(snapshot,source,view.id)
    busy[source]=nil
    if views[source]~=view or owner(source)~=view.id then return end
    if not ran then
        FrontierLib.Log('WARN',resource,'Production request interrupted',{action=name})
        ok,reason=false,'database_error'
    end
    result(source,ticket,seq,ok and true or false,ok and (name=='start' and 'Auftrag eingereicht.' or 'Aktualisiert.')
        or (type(reason)=='string' and reason:sub(1,8)=='missing:' and reason:sub(9))
        or (texts[reason] or 'Die Aktion ist derzeit nicht möglich.'),observed and loaded and state or nil,not ok and reason=='database_error')
end)

RegisterNetEvent(E..'close',function(ticket)
    local source=tonumber(source)
    if source and views[source] and views[source].ticket==ticket then views[source]=nil end
end)

local function defer(row)
    db('update',[[
        UPDATE frontier_production_jobs SET retry_at=DATE_ADD(UTC_TIMESTAMP(),INTERVAL 15 SECOND)
        WHERE id=? AND state=?
    ]],{row.id,row.state})
end

local function transition(row,state)
    db('update','UPDATE frontier_production_jobs SET state=?,retry_at=UTC_TIMESTAMP() WHERE id=? AND state=?',
        {state,row.id,row.state})
end

local function begin(row)
    db('update',[[
        UPDATE frontier_production_jobs SET state='running',checkpoint=UTC_TIMESTAMP(),
          completes_at=IF(mode='npc',DATE_ADD(UTC_TIMESTAMP(),INTERVAL duration_seconds SECOND),NULL),
          retry_at=UTC_TIMESTAMP()
        WHERE id=? AND state=?
    ]],{row.id,row.state})
end

local function step(row)
    if row.state=='reserve' then
        if row.mode=='player' and not present(row.owner_id) then defer(row);return end
        local ok,issue=inventory:ApplyProductionInventory('reserve',row.owner_id,row.id..':reserve',
            storageOptions(json.decode(row.materials),row.id))
        if ok then
            if row.mode=='npc' then transition(row,'wage') else begin(row) end
        elseif issue=='insufficient_stock' then transition(row,'rejected') else defer(row) end
    elseif row.state=='wage' then
        if tonumber(row.wage_minor)==0 then begin(row);return end
        local ok,issue=economy:DebitAccount(tonumber(row.bank_id),tonumber(row.wage_minor),{
            key=row.id..':wage',reason='Lohn für Produktionsauftrag',reference=row.id})
        if ok then begin(row)
        elseif issue=='insufficient_funds' then
            db('update',[[
                UPDATE frontier_production_jobs j JOIN frontier_production_businesses b ON b.owner_id=j.owner_id
                SET j.state='unpaid',b.employee='unpaid' WHERE j.id=? AND j.state='wage'
            ]],{row.id})
        else defer(row) end
    elseif row.state=='return' then
        if inventory:ApplyProductionInventory('return',row.owner_id,row.id..':return',storageOptions(nil,row.id)) then
            transition(row,'cancelled')
        else defer(row) end
    elseif row.state=='output' then
        local ok=inventory:ApplyProductionInventory('finish',row.owner_id,row.id..':output',
            storageOptions({{id=row.output_item,count=tonumber(row.output_units)}},row.id))
        if ok then transition(row,'complete') else defer(row) end
    end
end

local function tick()
    db('update',[[
        UPDATE frontier_production_jobs SET state='output',remaining_seconds=0,retry_at=UTC_TIMESTAMP()
        WHERE state='running' AND mode='npc' AND completes_at<=UTC_TIMESTAMP()
    ]])
    local known,active=db('query',"SELECT DISTINCT owner_id FROM frontier_production_jobs WHERE state='running' AND mode='player'")
    for _,row in ipairs(known and active or {}) do
        local id=row.owner_id
        if present(id) then
            db('update',[[
                UPDATE frontier_production_jobs SET
                    remaining_seconds=GREATEST(0,CAST(remaining_seconds AS SIGNED) -
                        IF(TIMESTAMPDIFF(SECOND,checkpoint,UTC_TIMESTAMP()) BETWEEN 1 AND ?,
                            TIMESTAMPDIFF(SECOND,checkpoint,UTC_TIMESTAMP()),0)),
                    checkpoint=UTC_TIMESTAMP()
                WHERE owner_id=? AND mode='player' AND state='running'
            ]],{cfg.MaxCheckpointSeconds,id})
        end
    end
    db('update',[[
        UPDATE frontier_production_jobs SET state='output',retry_at=UTC_TIMESTAMP()
        WHERE state='running' AND mode='player' AND remaining_seconds=0
    ]])
    local ok,rows=db('query',[[
        SELECT j.*,b.bank_id FROM frontier_production_jobs j
        JOIN frontier_production_businesses b ON b.owner_id=j.owner_id
        WHERE j.state IN ('reserve','wage','return','output') AND j.retry_at<=UTC_TIMESTAMP()
        ORDER BY j.retry_at,j.id LIMIT 40
    ]])
    if ok then for _,row in ipairs(rows) do
        local worked=pcall(step,row)
        if not worked then defer(row) end
    end end
end

AddEventHandler('frontier:playerLoaded',function(player)
    local id=player.frontierCharacterId
    if id then
        online[id]=player.source
        if ready then db('update',[[UPDATE frontier_production_jobs SET checkpoint=NULL
            WHERE owner_id=? AND mode='player' AND state='running']],{id}) end
    end
end)
AddEventHandler('frontier:playerUnloaded',function(player)
    local id=player.frontierCharacterId
    if id and online[id]==player.source then online[id]=nil end
    views[player.source]=nil
    TriggerClientEvent(E..'closed',player.source)
    if id and ready then db('update',[[UPDATE frontier_production_jobs SET checkpoint=NULL
        WHERE owner_id=? AND mode='player' AND state='running']],{id}) end
end)
AddEventHandler('playerDropped',function()
    local source=tonumber(source)
    if source then views[source],last[source]=nil,nil end
end)

local function initialize()
    if not db('update',"UPDATE frontier_production_jobs SET checkpoint=NULL WHERE mode='player' AND state='running'") then
        return false
    end
    for id,def in pairs(cfg.Items) do
        local ok,issue=inventory:RegisterItem(id,{name=def.name,description=def.description,
            grams=def.grams,maxStack=20,category='Produktion'})
        if not ok then
            FrontierLib.Log('WARN',resource,'Production item registration not ready',{item=id,reason=issue})
            return false
        end
    end
    for _,player in pairs(core:GetPlayers()) do
        if player.frontierCharacterId then online[player.frontierCharacterId]=player.source end
    end
    return true
end

MySQL.ready(function()
    while cfg.Enabled do
        if not ready then
            local ok,initialized=pcall(initialize)
            ready=ok and initialized
        else
            local ok=pcall(tick)
            if not ok or cfg.Debug then FrontierLib.Log(ok and 'INFO' or 'WARN',resource,'Production worker cycle',{ok=ok}) end
        end
        Wait(cfg.TickMs)
    end
end)
