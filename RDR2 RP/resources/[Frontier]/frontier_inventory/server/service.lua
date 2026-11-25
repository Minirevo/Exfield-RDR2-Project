local core = exports.frontier_core
local Config = InventoryConfig
Inventory.restricted = {}
Inventory.generations = {}

function Inventory.Generation(source)
    if not Inventory.generations[source] then Inventory.generations[source] = {} end
    return Inventory.generations[source]
end

local function finite(value)
    return type(value) == 'number' and value == value and math.abs(value) < 100000
end

function Inventory.Position(source)
    local ped = GetPlayerPed(source)
    if ped == 0 or not DoesEntityExist(ped) then return end
    local coords = GetEntityCoords(ped)
    if not coords or not finite(coords.x) or not finite(coords.y) or not finite(coords.z) then return end
    return { x = coords.x, y = coords.y, z = coords.z, bucket = GetPlayerRoutingBucket(source), ped = ped }
end

function Inventory.Session(source)
    if not Inventory.ready then return nil, 'not_ready' end
    if not Inventory.Int(source, 2147483647) then return nil, 'character' end
    local id = core:GetPlayerCharacterId(source)
    if not Inventory.Id(id, 64) then return nil, 'character' end
    if Inventory.restricted[source] then return nil, 'restricted' end
    local position = Inventory.Position(source)
    if not position then return nil, 'character' end
    local health = GetEntityHealth(position.ped)
    if Config.RestrictDead then
        -- RedM/RDR2 health values can be misleading during player state transitions.
        -- Prefer the native death-state check; use health only if the native is unavailable/errors.
        local dead
        if type(IsPedDeadOrDying) == 'function' then
            local ok, result = pcall(IsPedDeadOrDying, position.ped, true)
            if ok then dead = result == true or result == 1 end
        end
        if dead == nil then dead = health <= 0 end
        if dead then return nil, 'restricted' end
    end
    if Config.IncapacitatedHealth > 0 and health <= Config.IncapacitatedHealth then
        return nil, 'restricted'
    end
    return id, position
end

function Inventory.CloseEnough(a, b, distance)
    return a and b and a.bucket == b.bucket
        and (a.x-b.x)^2 + (a.y-b.y)^2 + (a.z-b.z)^2 <= distance^2
end

function Inventory.Player(source, id)
    local owner = 'p_' .. id
    local ok, container = Inventory.Load(owner)
    if not ok and container == 'not_found' then
        ok, container = Inventory.Ensure(owner, 'player', Config.Slots, Config.WeightGrams)
        if ok then ok, container = Inventory.Load(owner) end
    end
    if not ok then return false, container end
    if Inventory.Session(source) ~= id then return false, 'character' end
    return true, container
end

function Inventory.Storage(source, id)
    if not Inventory.Id(id, 48) then return false, 'invalid_request' end
    if id:match('^property_') then
        if GetResourceState('frontier_property')~='started' or not exports.frontier_property:CanAccessCampStorage(source,id) then return false,'forbidden' end
    end
    if id:match('^business_') and (GetResourceState('frontier_business')~='started' or not exports.frontier_business:CanAccessStorage(source,id,'view')) then return false,'forbidden' end
    local owner, position = Inventory.Session(source)
    if not owner then return false, position end
    local ok, storage = Inventory.Load('s_' .. id)
    if not ok then return false, storage end
    if storage.access_ace and not core:HasPermission(source, storage.access_ace) then return false, 'forbidden' end
    if storage.x and not Inventory.CloseEnough(position, storage, storage.distance_limit) then return false, 'distance' end
    return true, storage
end

function Inventory.CreateStorage(input)
    if type(input) ~= 'table' or not Inventory.Id(input.id, 48) or not Inventory.Text(input.name, 100) then
        return false, 'invalid_request'
    end
    local slots = input.slots or Config.StorageSlots
    local grams = input.grams or Config.StorageWeightGrams
    local ace = input.ace or Config.AdminAce
    local distance = input.distance or Config.PickupDistance
    local located = input.x ~= nil or input.y ~= nil or input.z ~= nil
    local bucket = input.bucket or 0
    if not Inventory.Int(slots, 200) or not Inventory.Int(grams, 100000000)
        or (ace ~= '' and not Inventory.Text(ace, 128)) or not finite(distance) or distance <= 0 or distance > 30
        or (bucket ~= 0 and not Inventory.Int(bucket, 2147483647))
        or (located and not (finite(input.x) and finite(input.y) and finite(input.z))) then
        return false, 'invalid_request'
    end
    local ok, result = Inventory.Db('update', [[
        INSERT INTO frontier_inventory_containers
            (id, kind, slot_limit, weight_limit, label, access_ace, x, y, z, bucket, distance_limit)
        VALUES (?, 'storage', ?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''), ?, ?)
        ON DUPLICATE KEY UPDATE id = id
    ]], { 's_' .. input.id, slots, grams, input.name, ace, input.x and tostring(input.x) or '', input.y and tostring(input.y) or '',
        input.z and tostring(input.z) or '', bucket, distance })
    if not ok then return false, result end
    local found, saved = Inventory.Load('s_' .. input.id)
    if not found then return false, saved end
    if saved.slot_limit ~= slots or saved.weight_limit ~= grams or saved.label ~= input.name
        or (saved.access_ace or '') ~= ace or saved.x ~= input.x or saved.y ~= input.y or saved.z ~= input.z
        or saved.bucket ~= bucket or saved.distance_limit ~= distance then
        return false, 'definition_conflict'
    end
    return true, input.id
end

function Inventory.NearbyDrops(position)
    local range = Config.VisibilityDistance
    return Inventory.Db('query', [[
        SELECT c.id, c.x, c.y, c.z, s.item_id, s.quantity FROM frontier_inventory_containers c
        JOIN frontier_inventory_slots s ON s.container_id = c.id AND s.slot = 1
        WHERE c.kind = 'ground' AND c.bucket = ? AND c.expires_at > UTC_TIMESTAMP()
            AND c.x BETWEEN ? AND ? AND c.y BETWEEN ? AND ? AND c.z BETWEEN ? AND ?
        ORDER BY POW(c.x - ?, 2) + POW(c.y - ?, 2) + POW(c.z - ?, 2)
        LIMIT 40
    ]], { position.bucket, position.x-range, position.x+range, position.y-range, position.y+range,
        position.z-range, position.z+range, position.x, position.y, position.z })
end

local function newDrop(key, position)
    local id = 'g_' .. key
    local ok, issue = Inventory.Db('update', [[
        INSERT INTO frontier_inventory_containers
            (id, kind, slot_limit, weight_limit, x, y, z, bucket, expires_at)
        VALUES (?, 'ground', 1, 100000000, ?, ?, ?, ?, DATE_ADD(UTC_TIMESTAMP(), INTERVAL ? SECOND))
        ON DUPLICATE KEY UPDATE id = id
    ]], { id, position.x, position.y, position.z, position.bucket, Config.GroundExpirySeconds })
    if not ok then return false, issue end
    return Inventory.Load(id)
end

local function latest(source, id, guard)
    return Inventory.Session(source) == id and (not guard or guard())
end

local function commit(ctx, ...)
    if ctx.source and type(ctx.storage)=='string' and ctx.storage:match('^property_') then
        if GetResourceState('frontier_property')~='started' or not exports.frontier_property:CanAccessCampStorage(ctx.source,ctx.storage) then return false,'forbidden' end
    end
    local businessStorage=ctx.source and type(ctx.storage)=='string' and ctx.storage:match('^business_')
    local stockAction=({store=true,retrieve=true,storageMove=true,storageSplit=true})[ctx.businessAction]
    if businessStorage then
        if GetResourceState('frontier_business')~='started' or not exports.frontier_business:CanAccessStorage(ctx.source,ctx.storage,stockAction and ctx.businessAction or 'view') then return false,'forbidden' end
    end
    if ctx.source and (Inventory.Generation(ctx.source) ~= ctx.generation or not latest(ctx.source, ctx.id, ctx.guard)) then
        return false, 'character'
    end
    if businessStorage and stockAction then
        local fid=ctx.storage:match('^business_([a-f0-9]+)$')
        local logged,result=Inventory.Db('update',[[INSERT IGNORE INTO fb_storage_audit(request_id,fixture_id,actor,action,detail,created,company_id)
          SELECT ?,id,?,?,?,UNIX_TIMESTAMP(),IF(owner_type='company',owner_id,NULL) FROM fb_fixtures WHERE id=?]],
          {ctx.key,ctx.actor,ctx.businessAction,json.encode(ctx.businessDetail or {}),fid})
        if not logged then return false,result end
    end
    return Inventory.Commit(ctx.key, ctx.actor, ctx.fingerprint, ...)
end

local function moveBetween(from, to, slot, quantity, target, permission)
    local ok, item = Inventory.Take(from, slot, quantity)
    if not ok then return false, item end
    if permission and not Inventory.items[item.item][permission] then return false, 'forbidden' end
    return Inventory.Place(to, item, target)
end

local function revise(container, revision)
    return revision == nil or container.revision == revision
end

local function use(ctx, container, slot)
    local stack = container.slots[slot]
    if not stack then return false, 'not_found' end
    local def = Inventory.items[stack.item]
    local handler = def.usable and Inventory.handlers[stack.item]
    if not handler then return false, 'unusable' end
    if Inventory.Generation(ctx.source) ~= ctx.generation or not latest(ctx.source, ctx.id, ctx.guard) then
        return false, 'character'
    end
    local worker = coroutine.create(function()
        return handler.callback(ctx.source, { item = stack.item, slot = slot, metadata = json.decode(stack.metadata),
            instance = stack.instance, requestId = ctx.key })
    end)
    local ok, accepted = coroutine.resume(worker)
    if coroutine.status(worker) ~= 'dead' then
        coroutine.close(worker)
        Inventory.Log('WARN', 'Usable inventory callback attempted to yield', { item = stack.item })
        return false, 'use_failed'
    end
    if not ok or accepted ~= true then return false, 'use_failed' end
    if handler.consume then Inventory.Take(container, slot, 1) end
    local saved, result, replayed = commit(ctx, container)
    if saved and not replayed then TriggerEvent('frontier:inventoryItemUsed', ctx.source, ctx.id, stack.item, ctx.key) end
    return saved, result
end

function Inventory.Act(ctx, action, data)
    ctx.businessAction=action;ctx.businessDetail=data
    local id, position = Inventory.Session(ctx.source)
    if not id or id ~= ctx.id then return false, id and 'character' or position end
    ctx.generation = Inventory.Generation(ctx.source)
    local checked, replay = Inventory.Replay(ctx.key, ctx.actor, ctx.fingerprint)
    if not checked then return false, replay end
    if replay then return true, ctx.key end
    local ok, player = Inventory.Player(ctx.source, ctx.id)
    if not ok then return false, player end
    if not revise(player, data.revision) then return false, 'conflict' end

    if action == 'sort' then
        local sorted = Inventory.Present(player).slots
        table.sort(sorted, function(a, b)
            if a.item == b.item then return a.slot < b.slot end
            return a.item < b.item
        end)
        local packed = {}
        for i, item in ipairs(sorted) do packed[i] = player.slots[item.slot] end
        player.slots = packed
        return commit(ctx, player)
    end

    if action == 'move' or action == 'split' then
        local moved, issue = Inventory.Move(player, data.slot, data.target, data.quantity, action == 'split')
        if not moved then return false, issue end
        return commit(ctx, player)
    end
    if action == 'use' then return use(ctx, player, data.slot) end

    local other, moved, issue
    if action == 'give' then
        local recipient, targetPosition = Inventory.Session(data.recipient)
        if not recipient or recipient == id then return false, 'recipient' end
        if not Inventory.CloseEnough(position, targetPosition, Config.TransferDistance) then return false, 'distance' end
        local generation = Inventory.Generation(data.recipient)
        ok, other = Inventory.Player(data.recipient, recipient)
        if not ok then return false, other end
        moved, issue = moveBetween(player, other, data.slot, data.quantity, nil, 'transfer')
        if not moved then return false, issue end
        local current, where = Inventory.Session(data.recipient)
        if current ~= recipient or Inventory.Generation(data.recipient) ~= generation
            or not Inventory.CloseEnough(Inventory.Position(ctx.source), where, Config.TransferDistance) then
            return false, 'distance'
        end
    elseif action == 'drop' then
        local stack = player.slots[data.slot]
        if not stack then return false, 'not_found' end
        if not Inventory.items[stack.item].drop then return false, 'forbidden' end
        if not Inventory.Int(data.quantity, stack.quantity) then return false, 'quantity' end
        position = Inventory.Position(ctx.source)
        if not position then return false, 'character' end
        ok, other = newDrop(ctx.key, position)
        if not ok then return false, other end
        if next(other.slots) then return false, 'conflict' end
        moved, issue = moveBetween(player, other, data.slot, data.quantity, 1, 'drop')
        if not Inventory.CloseEnough(Inventory.Position(ctx.source), other, Config.PickupDistance) then return false, 'distance' end
    elseif action == 'pickup' then
        if type(data.drop) ~= 'string' or #data.drop > 80 or not data.drop:match('^g_[a-zA-Z0-9_%-:]+$') then
            return false, 'invalid_request'
        end
        ok, other = Inventory.Load(data.drop)
        if not ok then return false, other end
        if other.kind ~= 'ground' or not Inventory.CloseEnough(Inventory.Position(ctx.source), other, Config.PickupDistance) then
            return false, 'distance'
        end
        local stack = other.slots[1]
        if not stack then return false, 'not_found' end
        moved, issue = moveBetween(other, player, 1, stack.quantity)
    elseif action == 'store' or action == 'retrieve' or action == 'storageMove' or action == 'storageSplit' then
        ok, other = Inventory.Storage(ctx.source, ctx.storage)
        if not ok then return false, other end
        if not revise(other, data.storageRevision) then return false, 'conflict' end
        if other.x and not Inventory.CloseEnough(Inventory.Position(ctx.source), other, other.distance_limit) then
            return false, 'distance'
        end
        if ctx.storage:match('^business_') then
            local origin=action=='store' and player or other;local stack=origin.slots[data.slot]
            ctx.businessDetail={character=ctx.id,item=stack and stack.item,quantity=data.quantity or (stack and stack.quantity),slot=data.slot,target=data.target}
        end
        if action == 'store' then
            moved, issue = moveBetween(player, other, data.slot, data.quantity, data.target, 'store')
        elseif action == 'retrieve' then
            moved, issue = moveBetween(other, player, data.slot, data.quantity, data.target)
        else
            moved, issue = Inventory.Move(other, data.slot, data.target, data.quantity, action == 'storageSplit')
        end
    else
        return false, 'invalid_request'
    end
    if not moved then return false, issue end
    return commit(ctx, player, other)
end

function Inventory.Change(ctx, container, add, item, quantity, metadata)
    local def = Inventory.items[item]
    if not def then return false, 'invalid_item' end
    if not Inventory.Int(quantity, 10000) then return false, 'quantity' end
    if metadata ~= nil and not Inventory.Metadata(metadata, def.condition) then return false, 'invalid_metadata' end
    if add then
        metadata = metadata or def.metadata
        if container.kind == 'storage' and not def.store then return false, 'forbidden' end
        if def.stackable then
            local ok, err = Inventory.Place(container, { item = item, quantity = quantity, metadata = metadata })
            if not ok then return false, err end
        else
            if quantity > container.slot_limit then return false, 'slots' end
            for _ = 1, quantity do
                local instance = Inventory.Uuid()
                if not instance then return false, 'database_error' end
                local ok, err = Inventory.Place(container,
                    { item = item, quantity = 1, metadata = metadata, instance = instance })
                if not ok then return false, err end
            end
        end
    else
        for slot = 1, container.slot_limit do
            local entry = container.slots[slot]
            if entry and entry.item == item and (not metadata or metadata == entry.metadata) then
                local count = math.min(entry.quantity, quantity)
                Inventory.Take(container, slot, count)
                quantity = quantity - count
                if quantity == 0 then break end
            end
        end
        if quantity > 0 then return false, 'quantity' end
    end
    return commit(ctx, container)
end
