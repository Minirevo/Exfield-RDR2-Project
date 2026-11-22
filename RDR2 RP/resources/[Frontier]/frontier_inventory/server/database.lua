Inventory = { resource = GetCurrentResourceName(), items = {}, handlers = {}, ready = false }

function Inventory.Int(value, max)
    return type(value) == 'number' and value >= 1 and value <= max and FrontierLib.IsInteger(value)
end

function Inventory.Id(value, max)
    return type(value) == 'string' and #value <= max and value:match('^[a-z0-9_]+$') ~= nil
end

function Inventory.Log(level, message, context)
    if level ~= 'DEBUG' or InventoryConfig.Debug then
        FrontierLib.Log(level == 'DEBUG' and 'INFO' or level, Inventory.resource, message, context)
    end
end

function Inventory.Db(method, statement, args)
    local ok, value = pcall(MySQL[method].await, statement, args)
    if not ok then
        Inventory.Log('ERROR', 'Inventory database operation failed', { method = method })
        return false, 'database_error'
    end
    return true, value
end

function Inventory.Uuid()
    local ok, id = Inventory.Db('scalar', 'SELECT UUID()')
    if ok and type(id) == 'string' and #id == 36 and id:match('^[a-f0-9-]+$') then return id end
end

function Inventory.Ensure(id, kind, slots, grams)
    return Inventory.Db('update', [[
        INSERT INTO frontier_inventory_containers (id, kind, slot_limit, weight_limit)
        VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE id = id
    ]], { id, kind, slots, grams })
end

function Inventory.Load(id)
    local ok, rows = Inventory.Db('query', [[
        SELECT c.id, c.kind, c.slot_limit, c.weight_limit, c.revision, c.label, c.access_ace,
               c.x, c.y, c.z, c.bucket, c.distance_limit, s.slot, s.item_id, s.quantity, s.metadata, s.instance_id
        FROM frontier_inventory_containers c LEFT JOIN frontier_inventory_slots s ON s.container_id = c.id
        WHERE c.id = ? AND (c.expires_at IS NULL OR c.expires_at > UTC_TIMESTAMP())
        ORDER BY s.slot
    ]], { id })
    if not ok then return false, rows end
    local container = rows[1]
    if not container then return false, 'not_found' end
    container.revision = tonumber(container.revision)
    container.slot_limit = tonumber(container.slot_limit)
    container.weight_limit = tonumber(container.weight_limit)
    container.slots = {}
    for _, row in ipairs(rows) do
        if row.slot then
            container.slots[tonumber(row.slot)] = { item = row.item_id, quantity = tonumber(row.quantity),
                metadata = row.metadata, instance = row.instance_id }
        end
    end
    return true, container
end

function Inventory.Replay(key, actor, fingerprint)
    local ok, result = Inventory.Db('single',
        'SELECT actor, fingerprint FROM frontier_inventory_receipts WHERE request_key = ? AND completed = TRUE',
        { key })
    if not ok then return false, result end
    if not result then return true, false end
    if result.actor ~= actor or result.fingerprint ~= fingerprint then return false, 'request_conflict' end
    return true, true
end

function Inventory.Commit(key, actor, fingerprint, ...)
    local changes = {}
    for _, container in ipairs({ ... }) do
        local entries = {}
        for slot, row in pairs(container.slots) do
            entries[#entries + 1] = { slot = slot, item = row.item, quantity = row.quantity,
                metadata = row.metadata, instance = row.instance or '' }
        end
        changes[#changes + 1] = { id = container.id, revision = container.revision, entries = entries }
    end
    table.sort(changes, function(a, b) return a.id < b.id end)
    local ok, result = Inventory.Db('query', 'CALL frontier_inventory_commit_v1(?, ?, ?, ?)',
        { key, actor, fingerprint, json.encode(changes) })
    if not ok then return false, result end
    local row = result and type(result[1]) == 'table' and result[1][1]
    if not row then return false, 'database_error' end
    if row.code ~= 'ok' then return false, row.code end
    return true, key, tonumber(row.replayed) == 1
end
