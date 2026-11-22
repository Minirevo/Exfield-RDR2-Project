local core = exports.frontier_core
local Config = InventoryConfig
local events = 'frontier_inventory:'
local views, last, worldLast, inFlight = {}, {}, {}, {}

local messages = {
    not_ready = 'Das Inventar ist noch nicht bereit.', character = 'Dein Charakter ist nicht verfügbar.',
    restricted = 'Du kannst das Inventar in diesem Zustand nicht benutzen.', not_found = 'Der Gegenstand ist nicht mehr verfügbar.',
    invalid_request = 'Diese Anfrage ist ungültig.', invalid_slot = 'Dieser Platz ist ungültig.',
    invalid_item = 'Dieser Gegenstand ist unbekannt.', invalid_metadata = 'Die Gegenstandsdaten sind ungültig.',
    quantity = 'Die Menge ist ungültig oder der Stapel ist zu klein.', weight = 'Das Gewichtslimit wäre überschritten.',
    slots = 'Es sind nicht genug Plätze frei.', capacity = 'Das Inventarlimit wäre überschritten.',
    stack_conflict = 'Die Stapel passen nicht zusammen oder der Zielplatz ist belegt.',
    forbidden = 'Diese Aktion ist nicht erlaubt.', distance = 'Du bist zu weit entfernt.',
    recipient = 'Der Empfänger ist nicht verfügbar.', unusable = 'Dieser Gegenstand kann nicht benutzt werden.',
    use_failed = 'Der Gegenstand konnte nicht benutzt werden.', conflict = 'Das Inventar hat sich geändert. Prüfe die Plätze erneut.',
    busy = 'Bitte warte einen Moment.', request_conflict = 'Diese Anfrage wurde bereits anders verwendet.',
    database_error = 'Das Ergebnis ist unklar. Wiederhole denselben Auftrag oder aktualisiere das Inventar.',
    input_error = 'Gib eine gültige Menge und einen gültigen Zielplatz ein.',
}

local function message(code)
    return messages[code] or 'Die Aktion konnte nicht ausgeführt werden.'
end

local function reply(source, view, request, ok, value, state)
    TriggerClientEvent(events .. 'result', source, view, request, { ok = ok, snapshot = state,
        message = ok and (state and 'Inventar aktualisiert.' or 'Aktion erfolgreich. Bitte aktualisiere das Inventar.') or message(value), retry = not ok and value == 'database_error' })
end

local function unload(source)
    local view = views[source]
    views[source] = nil
    Inventory.restricted[source] = nil
    Inventory.generations[source] = nil
    if view then TriggerClientEvent(events .. 'close', source) end
end

local function admit(source, channel, fn, interval)
    local now = GetGameTimer()
    local previous = channel[source]
    if inFlight[source] or (previous and now >= previous and now - previous < (interval or Config.RequestIntervalMs)) then
        return false, 'busy'
    end
    channel[source], inFlight[source] = now, true
    local ok, result, code = pcall(fn)
    inFlight[source] = nil
    if not ok then
        Inventory.Log('ERROR', 'Inventory request failed', { errorType = type(result) })
        return false, 'database_error'
    end
    return result, code
end

local function nearby(source, position)
    local result = {}
    for _, candidate in pairs(core:GetPlayers()) do
        if candidate.source ~= source and Inventory.CloseEnough(position, Inventory.Position(candidate.source), Config.TransferDistance) then
            result[#result + 1] = { source = candidate.source, name = candidate.name or ('Spieler %d'):format(candidate.source) }
        end
    end
    table.sort(result, function(a, b) return a.source < b.source end)
    return result
end

local function snapshot(source, id, storageId)
    local ok, player = Inventory.Player(source, id)
    if not ok then return false, player end
    local state = { player = Inventory.Present(player, true) }
    if storageId then
        local loaded, storage = Inventory.Storage(source, storageId)
        if not loaded then return false, storage end
        state.storage = Inventory.Present(storage, true)
    end
    local position = Inventory.Position(source)
    if Inventory.Session(source) ~= id or not position then return false, 'character' end
    state.nearby = nearby(source, position)
    local found, drops = Inventory.NearbyDrops(position)
    if Inventory.Session(source) ~= id then return false, 'character' end
    if not found then return false, drops end
    state.drops = {}
    for _, drop in ipairs(drops) do
        drop.bucket = position.bucket
        if Inventory.CloseEnough(position, drop, Config.PickupDistance) then
            state.drops[#state.drops+1] = { id = drop.id, name = Inventory.items[drop.item_id].name, quantity = drop.quantity }
        end
    end
    return true, state
end

local function open(source, viewId, storageId)
    local id, position = Inventory.Session(source)
    if not id then return false, position end
    local view = { id = id, viewId = viewId, storage = storageId }
    views[source] = view
    view.ticket = Inventory.Uuid()
    if not view.ticket then return false, 'database_error' end
    local ok, data = snapshot(source, id, storageId)
    if views[source] ~= view or Inventory.Session(source) ~= id then return false, 'character' end
    if not ok then views[source] = nil; return false, data end
    TriggerClientEvent(events .. 'open', source, viewId, view.ticket, data)
    return true
end

local function normalize(action, data)
    if type(data) ~= 'table' then return end
    if action == 'sort' then return {} end
    if action == 'pickup' then
        if type(data.drop) == 'string' and #data.drop <= 80 then return { drop = data.drop } end
        return
    end
    local needsDestination = action == 'move' or action == 'split' or action == 'storageMove'
        or action == 'storageSplit' or action == 'store' or action == 'retrieve'
    if not needsDestination and action ~= 'use' and action ~= 'give' and action ~= 'drop' then return end
    if not Inventory.Int(data.slot, 200) or (action ~= 'use' and not Inventory.Int(data.quantity, 10000))
        or (needsDestination and not Inventory.Int(data.target, 200))
        or (action == 'give' and not Inventory.Int(data.recipient, 2147483647)) then return end
    return { slot = data.slot, quantity = action ~= 'use' and data.quantity or nil,
        target = needsDestination and data.target or nil, recipient = action == 'give' and data.recipient or nil }
end

local function revision(value)
    return value == 0 or Inventory.Int(value, 4294967295)
end

local function fingerprint(action, data, storage)
    return json.encode({ action, data.slot or false, data.target or false, data.quantity or false,
        data.recipient or false, data.drop or false, data.revision or false, data.storageRevision or false, storage or false })
end

RegisterNetEvent(events .. 'open', function(viewId)
    local source = tonumber(source)
    if not source or not Inventory.Int(viewId, 2147483647) then return end
    local ok, err = admit(source, last, function()
        return open(source, viewId)
    end)
    if not ok then reply(source, viewId, 0, false, err) end
end)

RegisterNetEvent(events .. 'close', function(ticket)
    local source = tonumber(source)
    local view = views[source]
    if view and view.ticket == ticket then views[source] = nil end
end)

RegisterNetEvent(events .. 'request', function(ticket, seq, action, payload)
    local source = tonumber(source)
    local view = views[source]
    if not view or not view.ticket or ticket ~= view.ticket or not Inventory.Int(seq, 2147483647) then return end
    local observed
    local ok, err = admit(source, last, function()
        if Inventory.Session(source) ~= view.id then return false, 'character' end
        if action == 'refresh' then
            local found, data = snapshot(source, view.id, view.storage)
            if found then observed = data end
            return found, data
        end
        local data = normalize(action, payload)
        if not data or not revision(payload.revision)
            or (view.storage and not revision(payload.storageRevision)) then
            Inventory.Log('DEBUG', 'Rejected malformed inventory browser action')
            return false, 'invalid_request'
        end
        data.revision = payload.revision
        data.storageRevision = view.storage and payload.storageRevision or nil
        local applied, issue = Inventory.Act({ id = view.id, source = source, storage = view.storage,
            guard = function() return views[source] == view end, key = view.ticket .. ':' .. seq,
            actor = 'player:' .. view.id, fingerprint = fingerprint(action, data, view.storage) }, action, data)
        local found, dataNow = snapshot(source, view.id, view.storage)
        if found then observed = dataNow end
        return applied, issue
    end)
    if views[source] == view then reply(source, view.viewId, seq, ok, err, observed) end
end)

RegisterNetEvent(events .. 'world', function()
    local source = tonumber(source)
    if not source then return end
    admit(source, worldLast, function()
        local id, position = Inventory.Session(source)
        if not id then
            TriggerClientEvent(events .. 'world', source, {})
            return false, position
        end
        local ok, drops = Inventory.NearbyDrops(position)
        if ok and Inventory.Session(source) == id then TriggerClientEvent(events .. 'world', source, drops) end
        return ok, drops
    end, math.max(Config.RequestIntervalMs, Config.GroundUpdateMs - 250))
end)

RegisterNetEvent(events .. 'pickup', function(drop)
    local source = tonumber(source)
    if not source or type(drop) ~= 'string' or #drop > 72 or not drop:match('^g_[a-z0-9_:%-]+$') then return end
    local id, err = Inventory.Session(source)
    if not id then TriggerClientEvent(events .. 'notice', source, message(err)); return end
    local ok, issue = admit(source, last, function()
        local data = { drop = drop }
        return Inventory.Act({ id = id, source = source, key = 'pickup:' .. drop,
            actor = 'player:' .. id, fingerprint = fingerprint('pickup', data) }, 'pickup', data)
    end)
    if Inventory.Session(source) == id then
        TriggerClientEvent(events .. 'notice', source, ok and 'Gegenstand aufgenommen.' or message(issue))
    end
end)

local function provision(player)
    if Inventory.ready and Inventory.Id(player.frontierCharacterId, 64) then
        Inventory.Ensure('p_' .. player.frontierCharacterId, 'player', Config.Slots, Config.WeightGrams)
    end
end
AddEventHandler('frontier:playerLoaded', provision)
AddEventHandler('frontier:playerUnloaded', function(player) unload(player.source) end)
AddEventHandler('playerDropped', function()
    local source = tonumber(source)
    if not source then return end
    unload(source)
    last[source], worldLast[source] = nil, nil
end)
AddEventHandler('onResourceStop', function(name)
    if name == 'frontier_core' then
        for source in pairs(views) do unload(source) end
    end
    for item, handler in pairs(Inventory.handlers) do
        if handler.owner == name then Inventory.handlers[item] = nil end
    end
end)

MySQL.ready(function()
    while not Inventory.ready do
        local ok, seeded = pcall(Inventory.BootItems)
        if ok and seeded then
            local available = not Config.TestStorage or Inventory.CreateStorage(Config.TestStorage)
            Inventory.ready = available == true
        end
        if not Inventory.ready then
            Inventory.Log('ERROR', 'Inventory schema or configured definitions unavailable')
            Wait(5000)
        end
    end
    for _, player in pairs(core:GetPlayers()) do provision(player) end
    while true do
        Wait(Config.CleanupMs)
        local ok, count = Inventory.Db('update', [[
            DELETE FROM frontier_inventory_containers WHERE kind = 'ground' AND expires_at <= UTC_TIMESTAMP() LIMIT 200
        ]])
        if ok and count > 0 then Inventory.Log('INFO', 'Expired ground drops removed', { count = count }) end
    end
end)

local function trusted(name, fn)
    exports(name, function(...)
        local owner = GetInvokingResource()
        if not owner or #owner > 90 or Config.TrustedResources[owner] ~= true then return false, 'forbidden' end
        if not Inventory.ready then return false, 'not_ready' end
        return fn(owner, ...)
    end)
end

local function playerBox(source)
    local id, issue = Inventory.Session(source)
    if not id then return false, issue end
    return Inventory.Player(source, id)
end

local function countEntries(container, item)
    local count = 0
    for _, entry in pairs(container.slots) do
        if entry.item == item then count = count + entry.quantity end
    end
    return count
end
local function itemCount(source, item)
    if not Inventory.Id(item, 48) or not Inventory.items[item] then return false, 'invalid_item' end
    local ok, box = playerBox(source)
    if not ok then return false, box end
    return true, countEntries(box, item)
end

trusted('GetInventory', function(_, source)
    local ok, box = playerBox(source)
    return ok, ok and Inventory.Present(box) or box
end)
trusted('GetItemCount', function(_, source, item) return itemCount(source, item) end)
trusted('HasItem', function(_, source, item, quantity)
    if not Inventory.Int(quantity, 10000) then return false, 'quantity' end
    local ok, count = itemCount(source, item)
    if not ok then return false, count end
    return true, count >= quantity
end)
trusted('RegisterItem', Inventory.Register)
trusted('RegisterUsableItem', function(owner, item, callback, policy)
    local def = Inventory.Id(item, 48) and Inventory.items[item]
    local prior = Inventory.handlers[item]
    local callable = type(callback) == 'function' or (type(callback) == 'table' and callback.__cfx_functionReference)
    if not def or not def.usable or not callable or (policy ~= 'consume' and policy ~= 'keep') then
        return false, 'invalid_request'
    end
    if (def.owner ~= owner and def.owner ~= Inventory.resource)
        or (prior and prior.owner ~= owner and prior.owner ~= Inventory.resource) then return false, 'forbidden' end
    Inventory.handlers[item] = { owner = owner, callback = callback, consume = policy == 'consume' }
    return true, item
end)
trusted('CreateStorage', function(_, data) return Inventory.CreateStorage(data) end)
trusted('OpenStorage', function(_, source, storage)
    if not Inventory.Id(storage, 48) then return false, 'invalid_request' end
    return open(source, 0, storage)
end)
trusted('GetStorageContents', function(_, storage)
    if not Inventory.Id(storage, 48) then return false, 'invalid_request' end
    local ok, box = Inventory.Load('s_' .. storage)
    return ok, ok and Inventory.Present(box) or box
end)
trusted('GetNearbyPlayers', function(_, source)
    local id, position = Inventory.Session(source)
    if not id then return false, position end
    return true, nearby(source, position)
end)
trusted('SetRestricted', function(_, source, blocked)
    if not Inventory.Int(source, 2147483647) or type(blocked) ~= 'boolean' then return false, 'invalid_request' end
    if blocked then
        unload(source)
        Inventory.restricted[source] = true
    else
        Inventory.restricted[source] = nil
    end
    return true, blocked
end)

local function requestKey(key)
    if key == nil then
        return Inventory.Uuid()
    end
    if type(key) == 'string' and #key <= 64 and key:match('^[a-z0-9_:%-]+$') then return key end
end

local function change(owner, target, storage, add, item, quantity, metadata, request)
    if not Inventory.Id(item, 48) then return false, 'invalid_item' end
    if not Inventory.Int(quantity, 10000) or (metadata ~= nil and (type(metadata) ~= 'string' or #metadata > 8192)) then
        return false, 'invalid_request'
    end
    local id, issue
    if storage then
        if not Inventory.Id(target, 48) then return false, 'invalid_request' end
        id = target
    else
        id, issue = Inventory.Session(target)
        if not id then return false, issue end
    end
    local generation = not storage and Inventory.Generation(target) or nil
    local key = requestKey(request)
    if not key then return false, request and 'invalid_request' or 'database_error' end
    local ctx = { id = id, source = not storage and target or nil, key = key, actor = 'resource:' .. owner,
        fingerprint = json.encode({ 'change', storage, id, add, item, quantity, metadata or false }) }
    ctx.generation = generation
    local checked, replay = Inventory.Replay(key, ctx.actor, ctx.fingerprint)
    if not checked then return false, replay end
    if replay then return true, key end
    local ok, container
    if storage then ok, container = Inventory.Load('s_' .. id) else ok, container = Inventory.Player(target, id) end
    if not ok then return false, container end
    return Inventory.Change(ctx, container, add, item, quantity, metadata)
end

for name, changeType in pairs({
    AddItem = { false, true }, RemoveItem = { false, false },
    AddItemToStorage = { true, true }, RemoveItemFromStorage = { true, false },
}) do
    trusted(name, function(owner, target, item, quantity, metadata, request)
        return change(owner, target, changeType[1], changeType[2], item, quantity, metadata, request)
    end)
end

for name, action in pairs({ MoveItem = 'move', SplitItem = 'split', UseItem = 'use', DropItem = 'drop', GiveItem = 'give' }) do
    trusted(name, function(owner, source, payload, request)
        local data = normalize(action, payload)
        if not data then return false, 'invalid_request' end
        local key = requestKey(request)
        if not key then return false, request and 'invalid_request' or 'database_error' end
        local id, issue = Inventory.Session(source)
        if not id then return false, issue end
        if revision(payload.revision) then data.revision = payload.revision end
        return Inventory.Act({ source = source, id = id, key = key, actor = 'resource:' .. owner,
            fingerprint = fingerprint(action, data) }, action, data)
    end)
end

RegisterCommand('inventarlager', function(source)
    if source == 0 or not Config.TestStorage then return end
    local ok, issue = admit(source, last, function()
        return open(source, 0, Config.TestStorage.id)
    end)
    if not ok then TriggerClientEvent(events .. 'notice', source, message(issue)) end
end, false)

RegisterCommand('frontier_inv_permission_test', function(source)
    if source == 0 then
        print('[FRONTIER][DEBUG] This command must be run in-game.')
        return
    end

    local permission = Config.AdminAce

    local aceAllowed = IsPlayerAceAllowed(source, permission)
    local coreOk, coreAllowed = pcall(function()
        return core:HasPermission(source, permission)
    end)

    print(('[FRONTIER][DEBUG] Permission diagnostic for player %s'):format(source))
    print(('[FRONTIER][DEBUG] Permission: %s'):format(permission))
    print(('[FRONTIER][DEBUG] Direct ACE: %s'):format(tostring(aceAllowed)))
    print(('[FRONTIER][DEBUG] Core call succeeded: %s'):format(tostring(coreOk)))
    print(('[FRONTIER][DEBUG] Core permission result: %s'):format(tostring(coreAllowed)))

    TriggerClientEvent(events .. 'notice', source,
        ('ACE: %s | Core: %s'):format(
            tostring(aceAllowed),
            coreOk and tostring(coreAllowed) or 'ERROR'
        )
    )
end, false)

RegisterCommand('frontier_inv_test', function(source, args)
    if source == 0 or not Config.Development or not core:HasPermission(source, Config.AdminAce) then return end
    local ok, issue = change(Inventory.resource, source, false, true, args[1], tonumber(args[2]) or 1)
    TriggerClientEvent(events .. 'notice', source, ok and 'Testgegenstand hinzugefügt.' or message(issue))
end, false)
