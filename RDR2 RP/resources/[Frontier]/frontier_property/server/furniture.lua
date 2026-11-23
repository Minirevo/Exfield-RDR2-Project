local core = exports.frontier_core
local economy = exports.frontier_economy
local refreshAt = {}

local function message(source, value)
    TriggerClientEvent('chat:addMessage', source, {args={'Frontier Einrichtung',value}})
end

local function propertyId(raw)
    local value = tonumber(raw)
    if math.type(value) == 'integer' and value > 0 and value <= 9007199254740991 then return value end
end

local function within(point, bounds, margin)
    return point.x >= bounds.min.x + margin and point.x <= bounds.max.x - margin
        and point.y >= bounds.min.y + margin and point.y <= bounds.max.y - margin
        and point.z >= bounds.min.z and point.z <= bounds.max.z
end

local function currentPosition(source)
    local ped = GetPlayerPed(source)
    if ped == 0 then return end
    return GetEntityCoords(ped), ped
end

RegisterCommand('grundmoebel', function(source, args)
    if source <= 0 then return end
    local actor = core:GetPlayerCharacterId(source)
    if not actor then return message(source,'Wähle zuerst einen Charakter.') end
    if args[1] == 'lager' then
        if not NearbyPropertyAgent(source) then
            return message(source,'Gehe zum Makler für das Rückgabelager.')
        end
        local rows = MySQL.query.await([[SELECT id,model_key FROM frontier_property_furniture
            WHERE owner_id=? AND state='recovery' ORDER BY id LIMIT 20]], {actor})
        if core:GetPlayerCharacterId(source) ~= actor then return end
        if #rows == 0 then return message(source,'Dein Rückgabelager ist leer.') end
        for _, row in ipairs(rows) do message(source, ('#%s %s'):format(row.id,row.model_key)) end
        return
    end

    local target = propertyId(args[2])
    local room = target and GetPropertyFurnishingRooms()[target]
    if not room or GetPlayerRoutingBucket(source) ~= room.bucket then
        return message(source,'Wähle einen eingerichteten Innenraum.')
    end
    local position, ped = currentPosition(source)
    if not position or not within(position, room, 0) then return message(source,'Gehe in den Innenraum.') end
    local recovering = args[1] == 'auslagern'
    if not recovering and args[1] ~= 'kaufen' then
        return message(source,'Befehle: kaufen OBJEKT MODELL CENT, auslagern OBJEKT MODELL LAGERNUMMER, lager.')
    end
    local model = args[3] and PropertyConfig.FurnitureCatalog[args[3]]
    if not model or type(model.radius) ~= 'number' or not (model.radius > 0 and model.radius <= 10)
        or math.type(model.price) ~= 'integer' or model.price < 1 or model.price > 9000000000000
        or not within(position, room, model.radius) then
        return message(source,'Dieses Modell passt hier nicht.')
    end
    local price, bank, recovered = 0, 0, 0
    if recovering then
        recovered = propertyId(args[4])
        if not recovered then return message(source,'Gib die Möbelnummer aus dem Rückgabelager an.') end
    else
        if tonumber(args[4]) ~= model.price then
            return message(source, ('%s kostet $%.2f. Bestätige mit /grundmoebel kaufen %d %s %d.'):format(
                args[3],model.price / 100,target,args[3],model.price))
        end
        local ok, accounts = economy:GetCharacterAccounts(source)
        if not ok or accounts.characterId ~= actor or core:GetPlayerCharacterId(source) ~= actor then return end
        price, bank = model.price, accounts.bank.id
        position, ped = currentPosition(source)
        if not position or GetPlayerRoutingBucket(source) ~= room.bucket or not within(position,room,model.radius) then
            return
        end
    end

    local response = MySQL.query.await('CALL frontier_property_furniture_place_v1(?,?,?,?,?,?,?,?,?,?,?,?)', {
        target,actor,args[3],position.x,position.y,position.z,GetEntityHeading(ped),room.capacity,recovered,bank,price,model.radius,
    })
    if core:GetPlayerCharacterId(source) ~= actor then return end
    local result = response and response[1] and response[1][1]
    message(source, result and result.id and 'Möbelvorgang gespeichert.' or 'Platz belegt oder Einrichtung nicht erlaubt.')
end,false)

RegisterNetEvent('frontier_property:furnitureRefresh', function()
    local player = source
    local now = GetGameTimer()
    if now < (refreshAt[player] or 0) then return end
    refreshAt[player] = now + 2500
    local position = currentPosition(player)
    local character = core:GetPlayerCharacterId(player)
    if not position or not character then
        return TriggerClientEvent('frontier_property:furnitureSnapshot',player,{})
    end
    local bucket, visible = GetPlayerRoutingBucket(player), {}
    for id, room in pairs(GetPropertyFurnishingRooms()) do
        if bucket == room.bucket and within(position,room,0) then
            local rows = MySQL.query.await([[SELECT id,model_key,x,y,z,heading
                FROM frontier_property_furniture WHERE property_id=? AND state='placed' LIMIT 100]],{id})
            for _, row in ipairs(rows) do
                local model = PropertyConfig.FurnitureCatalog[row.model_key]
                if model then row.model = model.model; visible[#visible+1]=row end
            end
        end
    end
    if bucket == 0 then
        local buildings = MySQL.query.await([[SELECT CONCAT('building:',s.id) AS id,s.model_name AS model,
            s.x,s.y,s.z,s.heading FROM frontier_property_construction s
            JOIN frontier_properties p ON p.id=s.property_id
            WHERE s.state='complete' AND p.status='active'
              AND s.x BETWEEN ? AND ? AND s.y BETWEEN ? AND ? LIMIT 100]],
            {position.x-75,position.x+75,position.y-75,position.y+75})
        for _, row in ipairs(buildings) do visible[#visible+1]=row end
    end
    if core:GetPlayerCharacterId(player) ~= character or GetPlayerRoutingBucket(player) ~= bucket then return end
    TriggerClientEvent('frontier_property:furnitureSnapshot',player,visible)
end)

AddEventHandler('playerDropped',function() refreshAt[source]=nil end)

MySQL.ready(function()
    CreateThread(function()
        while true do
            local ok = pcall(function()
                MySQL.update.await([[UPDATE frontier_property_furniture f JOIN frontier_property_rentals r
                    ON r.id=f.lease_id SET f.state='recovery' WHERE f.state='placed'
                    AND (r.state<>'active' OR r.ends_at<=UTC_TIMESTAMP())]])
                local rows = MySQL.query.await([[SELECT id,account_id,price_cents FROM frontier_property_furniture
                    WHERE state='pending' AND retry_at<=NOW() ORDER BY retry_at,id LIMIT 20]])
                for _, row in ipairs(rows) do
                    MySQL.update.await([[UPDATE frontier_property_furniture
                        SET retry_at=DATE_ADD(NOW(),INTERVAL 30 SECOND) WHERE id=? AND state='pending']],{row.id})
                    local paid, issue = economy:DebitAccount(row.account_id,row.price_cents,
                        { key='property:furniture:'..row.id,reason='Möbelkauf',reference=tostring(row.id) })
                    if paid then
                        MySQL.update.await([[UPDATE frontier_property_furniture f LEFT JOIN frontier_property_rentals r
                            ON r.id=f.lease_id SET f.state=IF(f.lease_id IS NULL OR
                            (r.state='active' AND r.ends_at>UTC_TIMESTAMP()),'placed','recovery')
                            WHERE f.id=? AND f.state='pending']],{row.id})
                    elseif issue=='insufficient_funds' then
                        MySQL.update.await([[UPDATE frontier_property_furniture SET state='void'
                            WHERE id=? AND state='pending']],{row.id})
                    end
                end
            end)
            if not ok then print('[frontier_property] Möbelwarteschlange wird wiederholt.') end
            Wait(ok and 5000 or 30000)
        end
    end)
end)
