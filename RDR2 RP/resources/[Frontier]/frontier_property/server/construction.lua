local core, inventory = exports.frontier_core, exports.frontier_inventory

local function tell(player, text)
    TriggerClientEvent('chat:addMessage',player,{args={'Frontier Bau',text}})
end

local function valid(value, cap)
    return math.type(value)=='integer' and value>0 and value<=cap
end

local function pos(player)
    local ped=GetPlayerPed(player)
    if ped~=0 and GetPlayerRoutingBucket(player)==0 then return GetEntityCoords(ped),ped end
end

local function distance(a,x,y,z)
    return (a.x-x)^2+(a.y-y)^2+(a.z-z)^2
end

local activeWork = {}

local function runBuild(player,args)
    if player<=0 then return end
    local actor=core:GetPlayerCharacterId(player)
    local point,ped=pos(player)
    if not actor or not point then return tell(player,'Wähle deinen Charakter und gehe zur Baustelle.') end
    local id=tonumber(args[2])
    if not valid(id,9007199254740991) then return tell(player,'Gib die Grundstücks- oder Baustellennummer an.') end
    local params
    if args[1]=='start' then
        local key=args[3]
        local plan=key and PropertyConfig.ConstructionPlans[key]
        if not plan or type(plan.stages)~='table' or not valid(#plan.stages,64) or type(plan.radius)~='number'
            or not (plan.radius>0 and plan.radius<=50) or type(plan.model)~='string' or #plan.model>64 then return tell(player,'Ungültiger Bauplan.') end
        if type(plan.item)~='string' or #plan.item>48 then
            return tell(player,'Für diesen Entwurf fehlt der Bauplan-Gegenstand in der Konfiguration.')
        end
        local ok, held=inventory:HasItem(player,plan.item,1)
        if not ok or not held then return tell(player,'Du brauchst den passenden Bauplan im Inventar.') end
        if core:GetPlayerCharacterId(player)~=actor then return end
        local land=MySQL.single.await([[SELECT polygon_json FROM frontier_land_claims
            WHERE property_id=? AND state='owned']],{id})
        if not land then return tell(player,'Dafür ist ein vermessenes Grundstück erforderlich.') end
        if core:GetPlayerCharacterId(player)~=actor then return end
        point,ped=pos(player)
        if not point then return end
        if not ConstructionFitsProperty(json.decode(land.polygon_json),point,plan.radius) then
            return tell(player,'Der Bauplan passt an dieser Stelle nicht auf das Grundstück.')
        end
        params={id,actor,0,key,plan.model,#plan.stages,point.x,point.y,point.z,
            GetEntityHeading(ped),plan.radius,0,'',0,plan.value or 0}
    elseif args[1]=='arbeiten' then
        local site=MySQL.single.await([[SELECT property_id,blueprint,stage,state,x,y,z
            FROM frontier_property_construction WHERE id=?]],{id})
        if core:GetPlayerCharacterId(player)~=actor then return end
        point=pos(player)
        local plan=site and PropertyConfig.ConstructionPlans[site.blueprint]
        local stage=plan and plan.stages[site.stage]
        if not site or site.state~='building' or not stage or not point or distance(point,site.x,site.y,site.z)>16 then
            return tell(player,'Keine passende Baustufe in Reichweite.')
        end
        if type(stage.item)~='string' or #stage.item>48 or not valid(stage.count,10000) then
            return tell(player,'Diese Baustufe ist nicht korrekt eingerichtet.')
        end
        if stage.tool then
            local ok, held=inventory:HasItem(player,stage.tool,1)
            if not ok or not held then return tell(player,'Das benötigte Werkzeug fehlt.') end
        end
        if core:GetPlayerCharacterId(player)~=actor then return end
        point=pos(player)
        if not point or distance(point,site.x,site.y,site.z)>16 then return end
        local workSeconds=stage.workSeconds or 5
        if not valid(workSeconds,120) then return tell(player,'Ungültige Arbeitsdauer in der Baustufe.') end
        local untilTick=GetGameTimer()+workSeconds*1000
        while GetGameTimer()<untilTick do
            Wait(500)
            if core:GetPlayerCharacterId(player)~=actor then return end
            point=pos(player)
            if not point or distance(point,site.x,site.y,site.z)>16 then
                return tell(player,'Arbeit abgebrochen: Du hast die Baustelle verlassen.')
            end
        end
        if stage.tool then
            local ok, held=inventory:HasItem(player,stage.tool,1)
            if not ok or not held or core:GetPlayerCharacterId(player)~=actor then return end
        end
        point=pos(player)
        if not point or distance(point,site.x,site.y,site.z)>16 then return end
        params={site.property_id,actor,id,'','',0,0,0,0,0,0,site.stage,stage.item,stage.count,0}
    else
        return tell(player,'Verwendung: /grundbau start GRUNDSTÜCK BAUPLAN oder /grundbau arbeiten BAUSTELLE.')
    end
    local rows=MySQL.query.await('CALL frontier_build_action_v1(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',params)
    if core:GetPlayerCharacterId(player)~=actor then return end
    local row=rows and rows[1] and rows[1][1]
    tell(player,row and row.id and ('Bauvorgang #%s gespeichert.'):format(row.id)
        or 'Der Bauvorgang ist momentan nicht erlaubt.')
end

RegisterCommand('grundbau',function(player,args)
    if activeWork[player] then return tell(player,'Ein Bauvorgang läuft bereits.') end
    local task={}
    activeWork[player]=task
    local ok=pcall(runBuild,player,args)
    if activeWork[player]==task then activeWork[player]=nil end
    if not ok and player>0 then tell(player,'Bauvorgang gerade nicht verfügbar.') end
end,false)

AddEventHandler('playerDropped',function() activeWork[source]=nil end)

MySQL.ready(function()
    CreateThread(function()
        while true do
            local ok=pcall(function()
                local characters={}
                for _, raw in ipairs(GetPlayers()) do
                    local player=tonumber(raw)
                    local actor=core:GetPlayerCharacterId(player)
                    if actor then characters[actor]=player end
                end
                local jobs=MySQL.query.await([[SELECT id,character_id,item_key,item_count
                    FROM frontier_property_build_jobs WHERE state='pending' AND retry_at<=NOW()
                    ORDER BY retry_at,id LIMIT 30]])
                for _, job in ipairs(jobs) do
                    MySQL.update.await([[UPDATE frontier_property_build_jobs SET retry_at=DATE_ADD(NOW(),INTERVAL 30 SECOND)
                        WHERE id=? AND state='pending']],{job.id})
                    local player=characters[job.character_id]
                    if player and core:GetPlayerCharacterId(player)==job.character_id then
                        local paid, issue=inventory:RemoveItem(player,job.item_key,job.item_count,nil,'propbuild:'..job.id)
                        if paid or issue=='insufficient_items' or issue=='quantity' or issue=='not_found' then
                            MySQL.query.await('CALL frontier_build_finish_v1(?,?)',{job.id,paid and 1 or 0})
                        end
                    end
                end
            end)
            if not ok then print('[frontier_property] Bauwarteschlange wird wiederholt.') end
            Wait(ok and 5000 or 30000)
        end
    end)
end)
