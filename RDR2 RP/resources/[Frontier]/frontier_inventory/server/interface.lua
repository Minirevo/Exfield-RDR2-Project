local core = exports.frontier_core
local Config = InventoryConfig
local events = 'frontier_inventory:'
local views, last, worldLast, inFlight = {}, {}, {}, {}
local selectedBelt={}
local equipped,selectTool -- forward declarations; shared by snapshots and quick slots

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
    no_injury = 'No eligible injury to treat.',
    use_failed = 'Der Gegenstand konnte nicht benutzt werden.', conflict = 'Das Inventar hat sich geändert. Prüfe die Plätze erneut.',
    orphan_checkout = 'A previous firearm checkout needs recovery. Reconnect to return its ammunition.',
    weapon_drawn = 'Put away your firearm before moving it or equipping a tool.', no_ammo = 'No compatible ammunition or weapon already full.', cancelled = 'Reload cancelled.',
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
    selectedBelt[source]=nil
    Inventory.WeaponSessions[source]=nil
    Inventory.AmmoRecovered[source]=nil
    TriggerClientEvent(events..'weaponReset',source,'Character session ended.')
    TriggerClientEvent(events..'equipped',source,false)
    if view then TriggerClientEvent(events .. 'close', source) end
end

local function admit(source, channel, fn, interval)
    local now = GetGameTimer()
    local previous = channel[source]
    if inFlight[source] or (previous and now >= previous and now - previous < (interval or Config.RequestIntervalMs)) then
        return false, 'busy'
    end
    channel[source], inFlight[source] = now, true
    local character=core:GetPlayerCharacterId(source)
    if character then Inventory.AmmoWrites[character]=(Inventory.AmmoWrites[character] or 0)+1 end
    local ok, result, code = pcall(fn)
    if character then
        local left=(Inventory.AmmoWrites[character] or 1)-1
        Inventory.AmmoWrites[character]=left>0 and left or nil
    end
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
    local loaded,belt=Inventory.Belt(source,id)
    if not loaded then return false,belt end
    local state = { player = Inventory.Present(player, true), belt=Inventory.Present(belt,true) }
    local got,equipment=Inventory.Equipment(source,id)
    if not got then return false,equipment end
    state.equipment=Inventory.Present(equipment,true)
    state.equipment.ammoCapacity=Config.QuickAmmoCapacity or 30
    local pending,refunds=Inventory.PendingAmmo(id)
    state.pendingAmmo=pending and Inventory.PendingAmmoCount(refunds) or nil
    state.equipped=equipped(source,id,player,belt) or false
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
        or action == 'storageSplit' or action == 'store' or action == 'retrieve' or action=='beltStore' or action=='beltRetrieve' or action=='beltMove' or action=='equipmentStore' or action=='equipmentRetrieve' or action=='equipmentMove'
    if not needsDestination and action ~= 'beltUse' and action ~= 'use' and action ~= 'give' and action ~= 'drop' then return end
    if not Inventory.Int(data.slot, 200) or (action ~= 'use' and action~='beltUse' and not Inventory.Int(data.quantity, 10000))
        or (needsDestination and not Inventory.Int(data.target, 200))
        or (action == 'give' and not Inventory.Int(data.recipient, 2147483647)) then return end
    return { slot = data.slot, quantity = action ~= 'use' and action~='beltUse' and data.quantity or nil,
        target = needsDestination and data.target or nil, recipient = action == 'give' and data.recipient or nil }
end

local function revision(value)
    return value == 0 or Inventory.Int(value, 4294967295)
end

local function fingerprint(action, data, storage)
    local parts={ action, data.slot or false, data.target or false, data.quantity or false,
        data.recipient or false, data.drop or false, data.revision or false, data.storageRevision or false, storage or false }
    if action:sub(1,4)=='belt' then parts[#parts+1]=data.beltRevision or false end
    if action:sub(1,9)=='equipment' then parts[#parts+1]=data.equipmentRevision or false end
    return json.encode(parts)
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
        if action=='equip' then
            if type(payload)~='table' or (payload.side~='player' and payload.side~='belt') or not Inventory.Int(payload.slot,200) or not revision(payload.revision) or not revision(payload.beltRevision) then return false,'invalid_request' end
            local applied,issue=selectTool(source,payload.side,payload.slot,payload.revision,payload.beltRevision)
            local found,updated=snapshot(source,view.id,view.storage);if found then observed=updated end
            return applied,issue
        end
        local data = normalize(action, payload)
        if not data or not revision(payload.revision)
            or (view.storage and not revision(payload.storageRevision)) then
            Inventory.Log('DEBUG', 'Rejected malformed inventory browser action')
            return false, 'invalid_request'
        end
        if action:sub(1,4)=='belt' and not revision(payload.beltRevision) then return false,'invalid_request' end
        if action:sub(1,9)=='equipment' and not revision(payload.equipmentRevision) then return false,'invalid_request' end
        data.equipmentRevision=payload.equipmentRevision
        data.beltRevision=payload.beltRevision
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
    local id,src=player.frontierCharacterId,player.source
    if not Inventory.ready or not Inventory.Id(id,64) or Inventory.AmmoRecovered[src]==id
        or Inventory.AmmoRecoveryBusy[id] or Inventory.AmmoWrites[id] or core:GetPlayerCharacterId(src)~=id then return end
    Inventory.AmmoRecoveryBusy[id]=true
    local ok,saved,pending=pcall(Inventory.RecoverAmmo,id,false)
    Inventory.AmmoRecoveryBusy[id]=nil
    if ok and saved and core:GetPlayerCharacterId(src)==id then
        Inventory.AmmoRecovered[src]=id
        if pending>0 then TriggerClientEvent(events..'notice',src,('%d returned rounds waiting for space. Use /frontierclaimammo.'):format(pending)) end
    elseif not ok then Inventory.Log('ERROR','Session ammunition recovery failed',{reason=tostring(saved)}) end
end
RegisterCommand('frontierclaimammo',function(src)
 if src==0 then return end
 local ok,result=admit(src,last,function()
  local id,why=Inventory.Session(src);if not id then return false,why end
  if Inventory.AmmoRecoveryBusy[id] then return false,'busy' end
  return Inventory.RecoverAmmo(id,true)
 end)
 TriggerClientEvent(events..'notice',src,ok and ('Pending ammunition: '..result..' rounds. Refresh inventory.') or message(result))
end,false)
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
        for src in pairs(Inventory.AmmoRecovered) do unload(src) end
        for src in pairs(views) do unload(src) end
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
            Inventory.RecoveryEnforced = available == true
            Inventory.ready = available == true
        end
        if not Inventory.ready then
            Inventory.Log('ERROR', 'Inventory schema or configured definitions unavailable')
            Wait(5000)
        end
    end
    CreateThread(function()
        while true do
            for _, player in pairs(core:GetPlayers()) do provision(player) end
            Wait(2000)
        end
    end)
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
-- Tools in either personal container; ordinary consumable counts remain bag-only.
trusted('HasTool',function(_,source,item)
    if not Inventory.BeltEligible(item) then return false,'invalid_item' end
    local id,issue=Inventory.Session(source);if not id then return false,issue end
    local ok,bag=Inventory.Player(source,id);if not ok then return false,bag end
    local loaded,belt=Inventory.Belt(source,id);if not loaded then return false,belt end
    for _,box in ipairs({belt,bag}) do for _,entry in pairs(box.slots) do
        if entry.item==item then local m=json.decode(entry.metadata);if not m or m.condition~=0 then return true,true end end
    end end
    return true,false
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

RegisterCommand('frontier_inv_test', function(source, args)
    local allowed = source ~= 0
		and IsPlayerAceAllowed(source, Config.AdminAce)

    Inventory.Log('INFO', 'Test command invoked', {
        source = source,
        development = Config.Development,
        permission = allowed,
        ace = Config.AdminAce,
        item = args[1],
        quantity = args[2]
    })

    if source == 0 then
        return
    end

    if not Config.Development then
        TriggerClientEvent(events .. 'notice', source, 'Development-Modus ist deaktiviert.')
        return
    end

    if not allowed then
        TriggerClientEvent(events .. 'notice', source, 'Keine Berechtigung für diesen Befehl.')
        return
    end

    local ok, issue = change(
        Inventory.resource,
        source,
        false,
        true,
        args[1],
        tonumber(args[2]) or 1
    )

    Inventory.Log('INFO', 'Test command result', {
        success = ok,
        result = issue
    })

    TriggerClientEvent(events .. 'notice', source,
        ok and 'Testgegenstand hinzugefügt.' or message(issue))
end, false)

trusted('GetTradeItemDefinition', function(owner, item)
    if owner ~= 'frontier_trade' and owner ~= 'frontier_business' then return false, 'forbidden' end
    local definition = Inventory.Id(item, 48) and Inventory.items[item]
    if not definition then return false, 'invalid_item' end
    return true, { id = item, name = definition.name, transferable = definition.transfer }
end)

local function tradeUuid(value)
    return type(value) == 'string' and #value == 36 and value:match('^[a-f0-9-]+$') ~= nil
end

local function tradeMove(owner, delivery, character, item, quantity, taking)
    if owner ~= 'frontier_trade' then return false, 'forbidden' end
    if not tradeUuid(delivery) or not Inventory.Id(character,64) or not Inventory.Id(item,48) or not Inventory.Int(quantity,1000) then return false,'invalid_request' end
    local definition=Inventory.items[item]
    if not definition or not definition.transfer then return false,'invalid_item' end
    local key=delivery..(taking and ':stock' or ':claim')
    local actor='resource:'..owner
    local fingerprint=json.encode({delivery,character,item,quantity,taking})
    local ok,replay=Inventory.Replay(key,actor,fingerprint)
    if not ok then return false,replay end
    if replay then return true,key end
    local boxId='trade_'..delivery;local stockId='p_'..character;local confiscate=false
    local wagonSource
    if taking then
        local loaded,source=Inventory.Db('single','SELECT wagon_id,seller_id FROM ft_wagon_deliveries WHERE delivery_id=?',{delivery})
        if not loaded then return false,source end
        if source then
            if source.seller_id~=character or type(source.wagon_id)~='string' or #source.wagon_id~=32 or not source.wagon_id:match('^[a-f0-9]+$') then return false,'forbidden' end
            wagonSource=true;stockId='lg_w_'..source.wagon_id
        end
    end
    if not wagonSource and #character==32 and character:match('^[a-f0-9]+$') then
        local routeOk,route=Inventory.Db('single',[[SELECT f.fixture_id,c.status,c.liquidate_until FROM fb_trade_routes f
          JOIN fb_companies c ON c.id=f.company_id WHERE f.reference_id=? AND f.company_id=?]],{delivery,character})
        if not routeOk then return false,route end
        if not route and not taking then
            routeOk,route=Inventory.Db('single',[[SELECT f.fixture_id,c.status,c.liquidate_until FROM frontier_trade_deliveries d
              JOIN frontier_trade_contracts t ON t.id=d.contract_id JOIN fb_trade_routes f ON f.reference_id=t.request_id AND f.company_id=?
              JOIN fb_companies c ON c.id=f.company_id WHERE d.id=?]],{character,delivery})
            if not routeOk then return false,route end
        end
        if not route then return false,'missing_company_route' end
        stockId='s_business_'..route.fixture_id
        confiscate=not taking and (route.status=='archived' or route.status=='liquidating' and tonumber(route.liquidate_until or 0)<=os.time())
    end
    if taking then ok,replay=Inventory.Ensure(boxId,'storage',200,100000000);if not ok then return false,replay end
    elseif stockId:sub(1,2)=='p_' then ok,replay=Inventory.Ensure(stockId,'player',InventoryConfig.Slots,InventoryConfig.WeightGrams);if not ok then return false,replay end end
    local box,player;ok,box=Inventory.Load(boxId);if not ok then return false,box end
    if not confiscate then ok,player=Inventory.Load(stockId);if not ok then return false,player end end
    local from,to=player,box;if not taking then from,to=box,player end
    local remaining=quantity
    for slot=1,from.slot_limit do local stack=from.slots[slot]
        if stack and stack.item==item then
            local chunk=math.min(remaining,stack.quantity);local removed,value=Inventory.Take(from,slot,chunk);if not removed then return false,value end
            if not confiscate then local placed,issue=Inventory.Place(to,value);if not placed then return false,issue end end
            remaining=remaining-chunk;if remaining==0 then break end
        end
    end
    if remaining~=0 then return false,'insufficient_stock' end
    if confiscate then
        local logged,err=Inventory.Db('update',[[INSERT IGNORE INTO fb_storage_audit(request_id,fixture_id,actor,action,detail,created,company_id)
          VALUES(?,?,?,'trade_confiscated',?,UNIX_TIMESTAMP(),?)]],{key,stockId:sub(12),actor,json.encode({reference=delivery,item=item,quantity=quantity}),character})
        if not logged then return false,err end
        return Inventory.Commit(key,actor,fingerprint,from)
    end
    return Inventory.Commit(key,actor,fingerprint,from,to)
end

trusted('ReserveTradeDelivery', function(owner, delivery, character, item, quantity)
    return tradeMove(owner, delivery, character, item, quantity, true)
end)
trusted('ClaimTradeDelivery', function(owner, delivery, character, item, quantity)
    return tradeMove(owner, delivery, character, item, quantity, false)
end)

trusted('MoveTradeSaleStock', function(owner, sale, offer, item, quantity, reverse)
    if owner ~= 'frontier_trade' then return false, 'forbidden' end
    if not tradeUuid(sale) or not tradeUuid(offer) or sale == offer
        or not Inventory.Id(item,48) or not Inventory.Int(quantity,1000)
        or type(reverse) ~= 'boolean' then return false, 'invalid_request' end
    local key = sale .. (reverse and ':return' or ':allocate')
    local actor = 'resource:' .. owner
    local fingerprint = json.encode({ sale,offer,item,quantity,reverse })
    local ok, result = Inventory.Replay(key,actor,fingerprint)
    if not ok then return false,result end
    if result then return true,key end
    local saleBox = 'trade_' .. sale
    local offerBox = 'trade_' .. offer
    if not reverse then
        ok,result = Inventory.Ensure(saleBox,'storage',200,100000000)
        if not ok then return false,result end
    end
    local from,to
    ok,from = Inventory.Load(reverse and saleBox or offerBox)
    if not ok then return false,from end
    ok,to = Inventory.Load(reverse and offerBox or saleBox)
    if not ok then return false,to end
    local remaining = quantity
    for slot=1,from.slot_limit do
        local stack=from.slots[slot]
        if stack and stack.item == item then
            local count=math.min(remaining,stack.quantity)
            local taken, entry=Inventory.Take(from,slot,count)
            if not taken then return false,entry end
            local placed, issue=Inventory.Place(to,entry)
            if not placed then return false,issue end
            remaining=remaining-count
            if remaining==0 then break end
        end
    end
    if remaining~=0 then return false,'insufficient_stock' end
    return Inventory.Commit(key,actor,fingerprint,from,to)
end)

local function npcBox(owner, character, item)
    if owner ~= 'frontier_trade' then return false,'forbidden' end
    if not Inventory.Id(character,48) or not character:match('^npc_')
        or not Inventory.Id(item,48) or not Inventory.items[item] then return false,'invalid_request' end
    local ready, issue=Inventory.Ensure('p_'..character,'player',InventoryConfig.Slots,InventoryConfig.WeightGrams)
    if not ready then return false,issue end
    return Inventory.Load('p_'..character)
end

trusted('GetTradeNpcStock',function(owner,character,item)
    local ok,box=npcBox(owner,character,item)
    if not ok then return false,box end
    return true,countEntries(box,item)
end)

trusted('ChangeTradeNpcStock',function(owner,character,item,count,add,key)
    if not Inventory.Int(count,1000) or type(add)~='boolean' or not requestKey(key) or type(key)~='string' then
        return false,'invalid_request'
    end
    local ok,box=npcBox(owner,character,item)
    if not ok then return false,box end
    local actor='resource:'..owner
    local fingerprint=json.encode({'npc-stock',character,item,count,add})
    local checked,replay=Inventory.Replay(key,actor,fingerprint)
    if not checked then return false,replay end
    if replay then return true,key end
    return Inventory.Change({key=key,actor=actor,fingerprint=fingerprint},box,add,item,count)
end)

local function productionMove(from,to,requested)
    if requested then
        for _, item in ipairs(requested) do
            local remaining=item.count
            for slot=1,from.slot_limit do
                local entry=from.slots[slot]
                if entry and entry.item==item.id then
                    local amount=math.min(remaining,entry.quantity)
                    local ok,stack=Inventory.Take(from,slot,amount)
                    if not ok then return false,stack end
                    local put,reason=Inventory.Place(to,stack)
                    if not put then return false,reason end
                    remaining=remaining-amount
                    if remaining==0 then break end
                end
            end
            if remaining~=0 then return false,'insufficient_stock' end
        end
    else
        for slot=1,from.slot_limit do
            local stack=from.slots[slot]
            if stack then
                local ok,reason=Inventory.Place(to,stack)
                if not ok then return false,reason end
                from.slots[slot]=nil
            end
        end
    end
    return true
end

local function productionBox(id,kind,slots,grams)
    local ok,reason=Inventory.Ensure(id,kind,slots,grams)
    if not ok then return false,reason end
    return Inventory.Load(id)
end

trusted('GetProductionStorage',function(resource,owner,slots,grams)
    if resource~='frontier_production' then return false,'forbidden' end
    if not Inventory.Id(owner,64) or not Inventory.Int(slots,200) or not Inventory.Int(grams,100000000) then
        return false,'invalid_request'
    end
    local ok,box=productionBox('prod_'..owner,'storage',slots,grams)
    if not ok then return false,box end
    local present=Inventory.Present(box)
    local used=0
    for _,stack in pairs(box.slots) do used=used+stack.quantity end
    present.units=used
    return true,present
end)

trusted('ApplyProductionInventory',function(resource,action,owner,key,options)
    if resource~='frontier_production' then return false,'forbidden' end
    if not Inventory.Id(owner,64) or type(key)~='string' or not requestKey(key)
        or type(options)~='table' then return false,'invalid_request' end
    local holding=action=='reserve' or action=='return' or action=='finish'
    local job=options.job
    if holding and (type(job)~='string' or #job~=36 or not job:match('^[a-f0-9-]+$')) then
        return false,'invalid_request'
    end
    local requested=options.items
    if requested~=nil then
        if type(requested)~='table' or #requested<1 or #requested>12 then return false,'invalid_request' end
        local seen={}
        for _,entry in ipairs(requested) do
            if type(entry)~='table' or not Inventory.Id(entry.id,48) or not Inventory.items[entry.id]
                or seen[entry.id] or not Inventory.Int(entry.count,10000) then return false,'invalid_item' end
            seen[entry.id]=true
        end
    end
    if (action=='reserve' or action=='finish') and not requested then return false,'invalid_request' end
    local parts={action,owner,job or ''}
    for _,entry in ipairs(requested or {}) do
        parts[#parts+1]=entry.id; parts[#parts+1]=tostring(entry.count)
    end
    local actor='resource:'..resource
    local fingerprint=table.concat(parts,':')
    local checked,replay=Inventory.Replay(key,actor,fingerprint)
    if not checked then return false,replay end
    if replay then return true,key end

    local ok,from,to
    if action=='reserve' then
        ok,from=productionBox('p_'..owner,'player',InventoryConfig.Slots,InventoryConfig.WeightGrams)
        if not ok then return false,from end
        ok,to=productionBox('prjob_'..job,'storage',200,100000000)
    elseif action=='return' then
        ok,from=Inventory.Load('prjob_'..job)
        if not ok then return false,from end
        ok,to=productionBox('p_'..owner,'player',InventoryConfig.Slots,InventoryConfig.WeightGrams)
    elseif action=='finish' or action=='collect' then
        if not Inventory.Int(options.slots,200) or not Inventory.Int(options.grams,100000000)
            or not Inventory.Int(options.units,10000) then return false,'invalid_request' end
        if action=='collect' then
            ok,from=productionBox('prod_'..owner,'storage',options.slots,options.grams)
            if not ok then return false,from end
            if not next(from.slots) then return false,'insufficient_stock' end
            ok,to=productionBox('p_'..owner,'player',InventoryConfig.Slots,InventoryConfig.WeightGrams)
        else
            ok,from=Inventory.Load('prjob_'..job)
            if not ok then return false,from end
            if not next(from.slots) then return false,'insufficient_stock' end
            ok,to=productionBox('prod_'..owner,'storage',options.slots,options.grams)
        end
    else
        return false,'invalid_request'
    end
    if not ok then return false,to end

    if action=='finish' then
        local used=0
        for _,entry in pairs(to.slots) do used=used+entry.quantity end
        for _,entry in ipairs(requested) do
            local definition=Inventory.items[entry.id]
            used=used+entry.count
            if used>options.units then return false,'storage_full' end
            if definition.stackable then
                local put,reason=Inventory.Place(to,{item=entry.id,quantity=entry.count,metadata=definition.metadata})
                if not put then return false,reason end
            else
                if entry.count>to.slot_limit then return false,'slots' end
                for _=1,entry.count do
                    local instance=Inventory.Uuid()
                    if not instance then return false,'database_error' end
                    local put,reason=Inventory.Place(to,{item=entry.id,quantity=1,metadata=definition.metadata,instance=instance})
                    if not put then return false,reason end
                end
            end
        end
        from.slots={}
    else
        local wanted=requested
        if action=='return' then wanted=nil end
        local moved,reason=productionMove(from,to,wanted)
        if not moved then return false,reason end
    end
    return Inventory.Commit(key,actor,fingerprint,from,to)
end)

-- Physical production reuses existing atomic reservation and inventory move primitives.
trusted('ApplyStationProduction',function(resource,action,job,key,options)
 if resource~='frontier_production' or type(job)~='string' or #job~=32 or not job:match('^[a-f0-9]+$') or type(key)~='string' or not requestKey(key) or type(options)~='table' then return false,'invalid_request' end
 local route=options.route
 if type(route)~='string' or not (route:match('^p_f_[a-f0-9]+$') or route:match('^s_business_[a-f0-9]+$')) or not ({reserve=true,finish=true,["return"]=true})[action] then return false,'invalid_request' end
 local requested=options.items
 if action~='return' and (type(requested)~='table' or #requested<1 or #requested>100) then return false,'invalid_request' end
 local parts={action,job,route}
 for _,v in ipairs(requested or {}) do
  if type(v)~='table' or not Inventory.items[v.id] or not Inventory.Int(v.count,10000) or (v.metadata and not Inventory.Metadata(v.metadata,Inventory.items[v.id].condition)) then return false,'invalid_item' end
  parts[#parts+1]=v.id;parts[#parts+1]=tostring(v.count);parts[#parts+1]=v.metadata or ''
 end
 local actor='resource:'..resource;local fingerprint=json.encode(parts)
 local checked,replay=Inventory.Replay(key,actor,fingerprint);if not checked then return false,replay end;if replay then return true,key end
 local ok,box
 if route:sub(1,2)=='p_' then ok,box=productionBox(route,'player',Config.Slots,Config.WeightGrams) else ok,box=Inventory.Load(route) end
 if not ok then return false,box end
 local loaded,hold
 if action=='reserve' then loaded,hold=productionBox('prjob_'..job,'storage',200,100000000) else loaded,hold=Inventory.Load('prjob_'..job) end
 if not loaded then return false,hold end
 if action=='reserve' then
  if next(hold.slots) then return false,'conflict' end
  local moved,why=productionMove(box,hold,requested);if not moved then return false,why end
 elseif action=='return' then
  local moved,why=productionMove(hold,box);if not moved then return false,why end
 else
  if not next(hold.slots) then return false,'insufficient_stock' end
  for _,v in ipairs(requested) do
   local def=Inventory.items[v.id];local metadata=v.metadata or def.metadata
   if def.stackable then
    local put,why=Inventory.Place(box,{item=v.id,quantity=v.count,metadata=metadata});if not put then return false,why end
   else
    if v.count>box.slot_limit then return false,'slots' end
    for n=1,v.count do
     local instance=Inventory.Uuid();if not instance then return false,'database_error' end
     local put,why=Inventory.Place(box,{item=v.id,quantity=1,metadata=metadata,instance=instance});if not put then return false,why end
    end
   end
  end
  hold.slots={}
 end
 return Inventory.Commit(key,actor,fingerprint,box,hold)
end)

-- Persistent character identity for idempotent property jobs.
trusted('PropertyChangeCharacter', function(owner, id, item, quantity, add, key)
    if owner ~= 'frontier_property' or not Inventory.Id(id,64) or not id:match('^f_[a-f0-9]+$')
        or type(add) ~= 'boolean' or not Inventory.Id(item,48) or not Inventory.Int(quantity,10000)
        or not requestKey(key) or key==nil then return false,'invalid_request' end
    if not Inventory.items[item] then return false,'invalid_item' end
    local ctx={id=id,key=key,actor='resource:'..owner,fingerprint=json.encode({'property_change',id,item,quantity,add})}
    local ok,replay=Inventory.Replay(key,ctx.actor,ctx.fingerprint)
    if not ok then return false,replay end
    if replay then return true,key end
    local loaded,box=Inventory.Load('p_'..id)
    if not loaded then
        if box~='not_found' then return false,box end
        local made,err=Inventory.Ensure('p_'..id,'player',Config.Slots,Config.WeightGrams)
        if not made then return false,err end
        loaded,box=Inventory.Load('p_'..id)
        if not loaded then return false,box end
    end
    return Inventory.Change(ctx,box,add,item,quantity)
end)

trusted('BusinessMoveStock',function(owner,fixture,sale,character,item,quantity,mode)
    if owner~='frontier_business' or not Inventory.Id(fixture,32) or not Inventory.Id(sale,32) or not Inventory.Id(character,64) or not Inventory.Id(item,48) or not Inventory.Int(quantity,1000) then return false,'invalid_request' end
    if mode~='reserve' and mode~='claim' and mode~='return' and mode~='check' then return false,'invalid_request' end
    -- Dry-run against freshly loaded containers. No receipt or inventory mutation.
    if mode=='check' then
        local ok,from=Inventory.Load('s_business_'..fixture);if not ok then return false,from end
        local made,err=Inventory.Ensure('p_'..character,'player',Config.Slots,Config.WeightGrams);if not made then return false,err end
        local loaded,to=Inventory.Load('p_'..character);if not loaded then return false,to end
        local left=quantity
        for slot=1,from.slot_limit do
            local stack=from.slots[slot]
            if stack and stack.item==item then
                local n=math.min(left,stack.quantity)
                local taken,entry=Inventory.Take(from,slot,n);if not taken then return false,entry end
                local placed,issue=Inventory.Place(to,entry);if not placed then return false,issue end
                left=left-n;if left==0 then return true end
            end
        end
        return false,'insufficient_stock'
    end
    local key='business:'..sale..':'..mode;local actor='resource:'..owner
    local fingerprint=json.encode({fixture,sale,character,item,quantity,mode})
    local ok,replay=Inventory.Replay(key,actor,fingerprint);if not ok then return false,replay end;if replay then return true,key end
    local escrow='besc_'..sale;local stock='s_business_'..fixture
    local confiscate=false;local company
    if mode=='return' then
        local checked,row=Inventory.Db('single',[[SELECT c.id,c.status,c.liquidate_until FROM fb_retail r JOIN fb_companies c ON c.id=r.seller_id WHERE r.id=? AND r.fixture_id=? AND r.seller_type='company']],{sale,fixture})
        if not checked then return false,row end
        company=row and row.id;confiscate=row and row.status=='liquidating' and tonumber(row.liquidate_until or 0)<=os.time()
    end
    if mode=='reserve' then ok,replay=Inventory.Ensure(escrow,'storage',200,100000000);if not ok then return false,replay end end
    local fromId=mode=='reserve' and stock or escrow
    local toId=mode=='reserve' and escrow or mode=='return' and stock or 'p_'..character
    if mode=='claim' then ok,replay=Inventory.Ensure(toId,'player',InventoryConfig.Slots,InventoryConfig.WeightGrams);if not ok then return false,replay end end
    local from,to;ok,from=Inventory.Load(fromId);if not ok then return false,from end
    if not confiscate then ok,to=Inventory.Load(toId);if not ok then return false,to end end
    local left=quantity
    for slot=1,from.slot_limit do local stack=from.slots[slot];if stack and stack.item==item then
        local n=math.min(left,stack.quantity);local taken,entry=Inventory.Take(from,slot,n);if not taken then return false,entry end
        if not confiscate then local placed,issue=Inventory.Place(to,entry);if not placed then return false,issue end end
        left=left-n;if left==0 then break end
    end end
    if left~=0 then return false,'insufficient_stock' end
    if confiscate then
        local logged,err=Inventory.Db('update',[[INSERT IGNORE INTO fb_storage_audit(request_id,fixture_id,actor,action,detail,created,company_id)
          VALUES(?,?,?,'retail_confiscated',?,UNIX_TIMESTAMP(),?)]],{key,fixture,actor,json.encode({reference=sale,item=item,quantity=quantity}),company})
        if not logged then return false,err end
        return Inventory.Commit(key,actor,fingerprint,from)
    end
    return Inventory.Commit(key,actor,fingerprint,from,to)
end)

trusted('ConfiscateBusinessStock',function(owner,company,fixture,operation,revision)
    if owner~='frontier_business' or not Inventory.Id(company,32) or not Inventory.Id(fixture,32) or not Inventory.Id(operation,32) or type(revision)~='number' or revision<0 or revision%1~=0 then return false,'invalid_request' end
    local key='business:seize:'..operation;local actor='resource:'..owner
    local fingerprint=json.encode({'confiscate',company,fixture,operation})
    local ok,replay=Inventory.Replay(key,actor,fingerprint);if not ok then return false,replay end;if replay then return true,key end
    local allowed,row=Inventory.Db('single',[[SELECT f.id FROM fb_fixtures f JOIN fb_companies c ON c.id=f.owner_id JOIN fb_confiscations s ON s.company_id=c.id AND s.fixture_id=f.id
      WHERE f.id=? AND f.owner_type='company' AND c.id=? AND c.status='liquidating' AND c.liquidate_until<=UNIX_TIMESTAMP() AND s.id=? AND s.status='pending']],{fixture,company,operation})
    if not allowed then return false,row end;if not row then return false,'forbidden' end
    local loaded,box=Inventory.Load('s_business_'..fixture);if not loaded then return false,box end
    if box.revision~=revision then return false,'conflict' end
    box.slots={}
    return Inventory.Commit(key,actor,fingerprint,box)
end)

-- Farming can apply a bounded batch to an already-authorized physical stock chest.
trusted('ApplyFarmBatch',function(resource,storage,key,changes)
    if resource~='frontier_farming' or type(storage)~='string' or not storage:match('^business_[a-f0-9]+$') or not requestKey(key) or type(changes)~='table' or #changes<1 or #changes>16 then return false,'invalid_request' end
    local fingerprint={'farm',storage};local seen={}
    for _,v in ipairs(changes) do
        if type(v)~='table' or not Inventory.items[v.item] or not Inventory.items[v.item].stackable or seen[v.item] or type(v.count)~='number' or v.count%1~=0 or v.count==0 or math.abs(v.count)>10000 then return false,'invalid_item' end
        seen[v.item]=true;fingerprint[#fingerprint+1]=v.item;fingerprint[#fingerprint+1]=tostring(v.count)
    end
    local actor='resource:'..resource;fingerprint=table.concat(fingerprint,':')
    local ok,replay=Inventory.Replay(key,actor,fingerprint);if not ok then return false,replay end;if replay then return true,key end
    local loaded,box=Inventory.Load('s_'..storage);if not loaded then return false,box end
    for _,v in ipairs(changes) do if v.count<0 then
        local left=-v.count
        for slot=1,box.slot_limit do local entry=box.slots[slot];if entry and entry.item==v.item then
            local n=math.min(left,entry.quantity);local took,err=Inventory.Take(box,slot,n);if not took then return false,err end;left=left-n;if left==0 then break end
        end end
        if left~=0 then return false,'insufficient_stock' end
    end end
    for _,v in ipairs(changes) do if v.count>0 then local put,err=Inventory.Place(box,{item=v.item,quantity=v.count,metadata=Inventory.items[v.item].metadata});if not put then return false,err end end end
    return Inventory.Commit(key,actor,fingerprint,box)
end)

trusted('FarmSupplyDelivery',function(resource,character,item,count,key)
 if resource~='frontier_farming' or not Inventory.Id(character,64) or not Inventory.items[item] or not Inventory.Int(count,1000) or type(key)~='string' or not requestKey(key) then return false,'invalid_request' end
 local actor='resource:'..resource;local fingerprint=table.concat({'supply',character,item,count},':')
 local ok,replay=Inventory.Replay(key,actor,fingerprint);if not ok then return false,replay end;if replay then return true,key end
 local ok,box=Inventory.Load('p_'..character);if not ok then return false,box end
 local def=Inventory.items[item]
 if def.stackable then
  local put,err=Inventory.Place(box,{item=item,quantity=count,metadata=def.metadata});if not put then return false,err end
 else
  for i=1,count do local instance=Inventory.Uuid();if not instance then return false,'database_error' end
   local put,err=Inventory.Place(box,{item=item,quantity=1,metadata=def.metadata,instance=instance});if not put then return false,err end
  end
 end
 return Inventory.Commit(key,actor,fingerprint,box)
end)

-- Read-only simulation against a fresh stock snapshot. No receipt, no mutation.
trusted('CheckFarmBatch',function(resource,storage,changes)
 if resource~='frontier_farming' or type(storage)~='string' or not storage:match('^business_[a-f0-9]+$') or type(changes)~='table' or #changes>16 then return false,'invalid_request' end
 local ok,box=Inventory.Load('s_'..storage);if not ok then return false,box end
 local seen={}
 for _,v in ipairs(changes) do
  if type(v)~='table' or not Inventory.items[v.item] or not Inventory.items[v.item].stackable or seen[v.item] or type(v.count)~='number' or v.count%1~=0 or v.count==0 or math.abs(v.count)>10000 then return false,'invalid_item' end
  seen[v.item]=true
  if v.count<0 then
   local available=countEntries(box,v.item)
   if available < -v.count then return false,'insufficient_stock',{item=v.item,available=available,required=-v.count} end
   local left=-v.count
   for slot=1,box.slot_limit do local e=box.slots[slot];if e and e.item==v.item then
    local n=math.min(left,e.quantity);local took,err=Inventory.Take(box,slot,n);if not took then return false,err end;left=left-n;if left==0 then break end
   end end
  end
 end
 for _,v in ipairs(changes) do if v.count>0 then local put,err=Inventory.Place(box,{item=v.item,quantity=v.count,metadata=Inventory.items[v.item].metadata});if not put then return false,err,{item=v.item,required=v.count} end end end
 return true
end)


-- Only the gathering resource may consume condition and award materials in a single inventory commit.
local function toolKind(e)
 if not e or not e.instance then return end
 local kind=e.item:match('^gather_([a-z]+)_')
 if not kind then return end
 local m=json.decode(e.metadata)
 if m and type(m.uses)=='number' and m.uses>0 then return kind end
end
local function clearEquipped(src)
 selectedBelt[src]=nil;TriggerClientEvent(events..'equipped',src,false)
end
equipped=function(src,id,bag,belt)
 local p=selectedBelt[src];if not p then return end
 if p.id==id then
  for _,box in ipairs({bag,belt}) do for _,e in pairs(box.slots) do
   if e.instance==p.instance then
    local kind=toolKind(e)
    if kind then return {instance=e.instance,item=e.item,kind=kind,name=Inventory.items[e.item].name} end
   end
  end end
 end
 clearEquipped(src)
end
selectTool=function(src,side,slot,rev,beltRev)
 local id,err=Inventory.Session(src);if not id then return false,err end
 if Inventory.WeaponSessions[src] then return false,'weapon_drawn' end
 local ok,bag=Inventory.Player(src,id);if not ok then return false,bag end
 local loaded,belt=Inventory.Belt(src,id);if not loaded then return false,belt end
 if (rev~=nil and bag.revision~=rev) or (beltRev~=nil and belt.revision~=beltRev) then return false,'conflict' end
 local e=(side=='belt' and belt or bag).slots[slot]
 local prior=selectedBelt[src]
 if not e then clearEquipped(src);return false,'not_found' end
 if prior and prior.id==id and prior.instance==e.instance then
  clearEquipped(src);TriggerClientEvent(events..'notice',src,'Tool put away.');return true
 end
 if not toolKind(e) then return false,'unusable' end
 selectedBelt[src]={id=id,instance=e.instance}
 local state=equipped(src,id,bag,belt)
 TriggerClientEvent(events..'equipped',src,state or false)
 TriggerClientEvent(events..'notice',src,'Equipped '..state.name)
 return true
end
RegisterNetEvent(events..'selectBelt',function(slot)
 local src=source;if not Inventory.Int(slot,Config.BeltSlots) then return end
 local ok,err=admit(src,last,function()return selectTool(src,'belt',slot)end)
 if not ok then TriggerClientEvent(events..'notice',src,message(err)) end
end)
RegisterNetEvent(events..'holsterTool',function()clearEquipped(source)end)

-- Opt-in radial tool selector. The displayed revision and active character bind the selection.
local wheelViews,wheelLast={},{}

-- A draw checks rounds out of the persistent weapon item into one server lease.
-- A normal holster returns remaining rounds; a lost lease deliberately forfeits
-- checked-out ammunition. Never restore client-reported rounds above the lease.
local WR=FrontierWeaponRules
local gunLast,gunReleaseLast,gunCommitLast,gunReportLast,gunReportWrites={},{},{},{},{}
local function gunNotice(src,code) TriggerClientEvent(events..'notice',src,message(code)) end
local function weaponState(src)
 local id=Inventory.Session(src);if not id then return nil,'character' end
 local ok,e=Inventory.Equipment(src,id);if not ok then return nil,e end
 local loaded,b=Inventory.Player(src,id);if not loaded then return nil,b end
 if Inventory.Session(src)~=id then return nil,'character' end
 return id,e,b
end
local function lease(src,token)
 local s=Inventory.WeaponSessions[src]
 if not s or token~=s.token or Inventory.Session(src)~=s.id or Inventory.Generation(src)~=s.generation then return nil end
 return s
end
local function boundWeapon(e,s)
 local row=e.slots[s.slot]
 if not row or row.instance~=s.instance or row.item~=s.item then return nil end
 return row
end
local function weaponCommit(src,id,generation,key,fp,...)
 if Inventory.Session(src)~=id or Inventory.Generation(src)~=generation then return false,'character' end
 return Inventory.Commit(key,'player:'..id,fp,...)
end
local function resetWeapon(src,reason)
 Inventory.WeaponSessions[src]=nil
 TriggerClientEvent(events..'weaponReset',src,reason or 'Weapon session ended.')
end
local function activeRow(src,id,e,b,slot)
 local row=e.slots[slot]
 local def=row and WR.models[row.item]
 if not def or def.slot~=slot or not row.instance then return {kind='disabled',name=slot==1 and 'Primary' or 'Sidearm'} end
 local rounds,m=WR.loaded(row,def)
 if rounds==nil or (m.condition and m.condition<=0) then return {kind='disabled',name=Inventory.items[row.item].name} end
 local s=Inventory.WeaponSessions[src]
 local active=s and s.id==id and s.instance==row.instance
 return {kind='weapon',name=Inventory.items[row.item].name,target=slot,item=row.item,serial=row.instance,
  loaded=active and s.rounds or rounds,quick=WR.count(e,def.ammo,3,4),bag=WR.count(b,def.ammo,1,b.slot_limit),
  equipped=active==true,condition=m.condition or 100}
end
RegisterNetEvent(events..'weaponDraw',function(token,slot,request)
 local src=source
 if type(token)~='string' or #token>80 or not WR.integer(slot,1,2) or not WR.integer(request,1,2147483646) then return end
 local response
 local ok,err=admit(src,gunLast,function()
  for _,name in ipairs({'vorp_inventory','vorp_weaponsv2'}) do
   local state=GetResourceState(name)
   if state=='started' or state=='starting' then return false,'forbidden' end
  end
  local v=wheelViews[src]
  if not v or v.token~=token or GetGameTimer()>v.expires or Inventory.Session(src)~=v.id or not v.weapons[slot] then return false,'conflict' end
  if Inventory.WeaponSessions[src] then return false,'weapon_drawn' end
  wheelViews[src]=nil
  local id,e,b=weaponState(src);if not id then return false,e end
  local row=e.slots[slot];local def=row and WR.models[row.item]
  if not def or def.slot~=slot or row.instance~=v.weapons[slot] then return false,'conflict' end
  local rounds,m=WR.loaded(row,def)
  if rounds==nil or (m.condition and m.condition<=0) then return false,'unusable' end
  if m.checkout then return false,'orphan_checkout' end
  local t=Inventory.Uuid();if not t then return false,'database_error' end
  local generation=Inventory.Generation(src)
  m.loaded=0;m.checkout={token=t,rounds=rounds};row.metadata=json.encode(m)
  local saved,issue=weaponCommit(src,id,generation,t..':draw','weaponDraw:'..row.instance,e)
  if not saved then return false,issue end
  if Inventory.Session(src)~=id or Inventory.Generation(src)~=generation then return false,'character' end
  local s={token=t,id=id,generation=generation,slot=slot,item=row.item,instance=row.instance,rounds=rounds,version=1,drawRequest=request}
  Inventory.WeaponSessions[src]=s
  clearEquipped(src)
  response={lease=t,slot=slot,item=row.item,serial=row.instance,rounds=rounds,version=1}
  return true
 end,100)
 TriggerClientEvent(events..'weaponDrawResult',src,request,ok,response or false,ok and '' or message(err))
end)
RegisterNetEvent(events..'weaponReport',function(token,version,remaining)
 local src=source;local s=lease(src,token)
 if not s or version~=s.version or s.pending or s.releasing then return end
 local now=GetGameTimer()
 if gunReportLast[src] and now-gunReportLast[src]<150 then return end
 gunReportLast[src]=now
 local n=WR.remaining(s.rounds,remaining)
 if n==nil or n==s.rounds then return end
 -- Persist decreasing observations; heartbeat retries a busy/failed write.
 admit(src,gunReportWrites,function()
  if lease(src,token)~=s or s.pending or s.releasing or version~=s.version then return false,'conflict' end
  local id,e=weaponState(src);if not id then return false,e end
  local row=boundWeapon(e,s);if not row then return false,'conflict' end
  local c,m=Inventory.Checkout(row,s);if not c or n>c.rounds then return false,'conflict' end
  if n==c.rounds then s.rounds=n;return true end
  c.rounds=n;row.metadata=json.encode(m)
  local key=Inventory.Uuid();if not key then return false,'database_error' end
  local saved,why=weaponCommit(src,id,s.generation,key,'weaponShot:'..s.instance..':'..n,e)
  if saved and lease(src,token)==s then s.rounds=n end
  return saved,why
 end,150)
end)
local function reloadReply(src,s,request,ok,amount,reason)
 TriggerClientEvent(events..'weaponReloadResult',src,s.token,request,ok,s.version,amount or 0,ok and '' or message(reason))
end
RegisterNetEvent(events..'weaponReload',function(token,request,version,remaining)
 local src=source
 if not WR.integer(request,1,2147483646) then return end
 local s=lease(src,token)
 if not s then TriggerClientEvent(events..'weaponReset',src,'Weapon session expired.');return end
 local pending,delay
 local ok,err=admit(src,gunLast,function()
  if lease(src,token)~=s or s.pending or s.releasing or version~=s.version then return false,'busy' end
  local n=WR.remaining(s.rounds,remaining);if n==nil then return false,'invalid_request' end
  local id,e,b=weaponState(src);if not id then return false,e end
  local row=boundWeapon(e,s);if not row then return false,'conflict' end
  local c,m=Inventory.Checkout(row,s);if not c or n>c.rounds then return false,'conflict' end
  -- Save the latest count before beginning a cancellable retrieval.
  if n<c.rounds then
   c.rounds=n;row.metadata=json.encode(m)
   local key=Inventory.Uuid();if not key then return false,'database_error' end
   local saved,why=weaponCommit(src,id,s.generation,key,'weaponReloadObserve:'..s.instance..':'..n,e)
   if not saved then return false,why end
   if lease(src,token)~=s then return false,'character' end
  end
  s.rounds=n
  local def=WR.models[s.item]
  local from,quantity=WR.plan(e,b,def.ammo,s.rounds,def.capacity)
  if not from then return false,'no_ammo' end
  pending={request=request,from=from,version=s.version,quantity=quantity}
  s.pending=pending
  delay=from=='satchel' and WR.reloadDelayMs or 0
  return true
 end,100)
 if not ok then reloadReply(src,s,request,false,0,err);return end
 TriggerClientEvent(events..'weaponReloadWait',src,s.token,request,pending.from,delay)
 SetTimeout(delay,function()
  if lease(src,token)~=s or s.pending~=pending then return end
  local amount=0
  local saved,issue=admit(src,gunCommitLast,function()
   if lease(src,token)~=s or s.pending~=pending or pending.cancelled or s.releasing or s.version~=pending.version then return false,'conflict' end
   local id,e,b=weaponState(src);if not id then return false,e end
   local row=boundWeapon(e,s);if not row then return false,'conflict' end
   local c,m=Inventory.Checkout(row,s);if not c or s.rounds>c.rounds then return false,'conflict' end
   local def=WR.models[s.item]
   local from,quantity=WR.plan(e,b,def.ammo,s.rounds,def.capacity)
   -- If contents changed during the wait, require a fresh reload rather than bypass the delay.
   if from~=pending.from or quantity==0 then return false,'conflict' end
   quantity=math.min(quantity,pending.quantity)
   local box=from=='quick' and e or b
   local first,last=from=='quick' and 3 or 1,from=='quick' and 4 or b.slot_limit
   local left=quantity
   for i=first,last do
    local stack=box.slots[i]
    if stack and stack.item==def.ammo then
     local take=math.min(left,stack.quantity)
     if take>0 then local removed=Inventory.Take(box,i,take);if not removed then return false,'conflict' end;left=left-take end
     if left==0 then break end
    end
   end
   if left~=0 or pending.cancelled or s.pending~=pending or lease(src,token)~=s then return false,'conflict' end
   c.rounds=s.rounds+quantity;row.metadata=json.encode(m)
   local key,fp=s.token..':reload:'..request,'weaponReload:'..s.instance..':'..request..':'..quantity
   local committed,why
   if box==e then committed,why=weaponCommit(src,id,s.generation,key,fp,e)
   else committed,why=weaponCommit(src,id,s.generation,key,fp,e,box) end
   if not committed then
    if why=='database_error' and lease(src,token)==s then resetWeapon(src,'Reload outcome uncertain; reconnect to recover ammunition.') end
    return false,why
   end
   if lease(src,token)~=s then return false,'character' end
   s.rounds=s.rounds+quantity;s.version=s.version+1;amount=quantity
   return true
  end,0)
  if s.pending==pending then s.pending=nil end
  if lease(src,token)==s then reloadReply(src,s,request,saved,amount,issue) end
 end)
end)
RegisterNetEvent(events..'weaponCancelReload',function(token,request)
 local src=source;local s=lease(src,token)
 if not s or not s.pending or s.pending.request~=request then return end
 s.pending.cancelled=true
 -- A database commit may be in flight; only clear a waiting (not executing) job.
 if not inFlight[src] then s.pending=nil;reloadReply(src,s,request,false,0,'cancelled') end
end)
RegisterNetEvent(events..'weaponRelease',function(token,version,remaining)
 local src=source
 if type(token)~='string' or #token>80 then return end
 local s=lease(src,token)
 if not s then TriggerClientEvent(events..'weaponReleaseResult',src,token,true,'');return end
 if s.pending then s.pending.cancelled=true end
 local ok,err=admit(src,gunReleaseLast,function()
  if lease(src,token)~=s then return false,'character' end
  s.releasing=true;s.pending=nil
  local id,e=weaponState(src);if not id then s.releasing=false;return false,e end
  local row=boundWeapon(e,s);local def=WR.models[s.item]
  if not row then resetWeapon(src,'Weapon no longer available.');return false,'conflict' end
  local c,m=Inventory.Checkout(row,s)
  if not c then
   local checked,replay=Inventory.Replay(token..':release','player:'..id,'weaponRelease:'..s.instance..':'..tostring(remaining))
   if checked and replay then Inventory.WeaponSessions[src]=nil;return true end
   s.releasing=false;return false,'conflict'
  end
  -- Stale version can occur if a reload completed during cancellation. Never credit the unseen new rounds.
  local n=WR.remaining(s.rounds,remaining)
  if not n or n>c.rounds or not WR.integer(version,1,s.version) then s.releasing=false;return false,'invalid_request' end
  m.loaded=n;m.checkout=nil;row.metadata=json.encode(m)
  local saved,why=weaponCommit(src,id,s.generation,token..':release','weaponRelease:'..s.instance..':'..n,e)
  if not saved then s.releasing=false;return false,why end
  if Inventory.WeaponSessions[src]==s then Inventory.WeaponSessions[src]=nil end
  return true
 end,100)
 TriggerClientEvent(events..'weaponReleaseResult',src,token,ok,ok and '' or err)
end)
RegisterNetEvent(events..'weaponAbortDraw',function(request)
 local src=source;local s=Inventory.WeaponSessions[src]
 if s and s.drawRequest==request and lease(src,s.token)==s then resetWeapon(src,'Weapon draw timed out; reconnect to recover checked-out rounds.') end
end)
RegisterNetEvent(events..'weaponAbandon',function(token)
 local src=source;local s=lease(src,token)
 if s then resetWeapon(src,'Weapon lease abandoned; reconnect to recover checked-out rounds.') end
end)
AddEventHandler('playerDropped',function()
 gunLast[source]=nil;gunReleaseLast[source]=nil;gunCommitLast[source]=nil;gunReportLast[source]=nil;gunReportWrites[source]=nil
end)

RegisterNetEvent(events..'wheelOpen',function(sequence)
 local src=source
 if not Inventory.Int(sequence,2147483647) then return end
 local ok,err=admit(src,wheelLast,function()
  wheelViews[src]=nil
  local id,why=Inventory.Session(src);if not id then return false,why end
  local loaded,belt=Inventory.Belt(src,id);if not loaded then return false,belt end
  local got,bag=Inventory.Player(src,id);if not got then return false,bag end
  if Inventory.Session(src)~=id then return false,'character' end
  local token=Inventory.Uuid();if not token then return false,'database_error' end
  local slots={}
  for i=1,Config.BeltSlots do
   local e=belt.slots[i]
   local kind=toolKind(e)
   local def=e and Inventory.items[e.item]
   local m=e and json.decode(e.metadata) or {}
   slots[i]={slot=i,kind=kind or false,name=def and def.name or 'Empty',
    quality=type(m.quality)=='number' and m.quality or nil,
    uses=type(m.uses)=='number' and m.uses or nil,
    maxUses=type(m.maxUses)=='number' and m.maxUses or nil}
  end
  local active=equipped(src,id,bag,belt)
  for i=1,Config.BeltSlots do
   local e=belt.slots[i]
   slots[i].equipped=active and e and e.instance==active.instance or false
  end
  local consumables={food={},drink={},medicine={}}
  local byItem={}
  for i=1,bag.slot_limit do
   local e=bag.slots[i]
   local d=e and Inventory.items[e.item]
   local category=d and ((e.item=='bandage' or e.item=='splint' or e.item=='tonic') and 'medicine' or d.classification)
   if d and d.usable and Inventory.handlers[e.item] and consumables[category] then
    local prior=byItem[e.item]
    if prior then prior.quantity=prior.quantity+e.quantity
    else
     local row={name=d.name,item=e.item,slot=i,quantity=e.quantity,kind='consume'}
     byItem[e.item]=row;table.insert(consumables[category],row)
    end
   end
  end
  local has,e=Inventory.Equipment(src,id);if not has then return false,e end
  if Inventory.Session(src)~=id then return false,'character' end
  local weapons={}
  for i=1,2 do local row=e.slots[i];if row and WR.models[row.item] then weapons[i]=row.instance end end
  -- layout uses index 2 for primary, index 1 for sidearm; actual equipment slots are 1/2.
  local guns={activeRow(src,id,e,bag,2),activeRow(src,id,e,bag,1)}
  wheelViews[src]={id=id,token=token,revision=belt.revision,bagRevision=bag.revision,consumables=byItem,weapons=weapons,expires=GetGameTimer()+15000}
  TriggerClientEvent(events..'wheelSnapshot',src,sequence,token,slots,consumables,guns)
  return true
 end,250)
 if not ok then TriggerClientEvent(events..'wheelError',src,sequence,message(err)) end
end)
RegisterNetEvent(events..'wheelSelect',function(token,slot)
 local src=source
 if type(token)~='string' or #token>80 or (slot~=0 and not Inventory.Int(slot,Config.BeltSlots)) then return end
 local ok,err=admit(src,last,function()
  local v=wheelViews[src];wheelViews[src]=nil
  if not v or token~=v.token or GetGameTimer()>v.expires or Inventory.Session(src)~=v.id then return false,'conflict' end
  if slot==0 then clearEquipped(src);return true end
  return selectTool(src,'belt',slot,nil,v.revision)
 end)
 if not ok then TriggerClientEvent(events..'notice',src,message(err)) end
end)
RegisterNetEvent(events..'wheelConsume',function(token,item)
 local src=source
 if type(token)~='string' or #token>80 or not Inventory.Id(item,48) then return end
 local ok,err=admit(src,last,function()
  local v=wheelViews[src]
  if not v or v.token~=token or GetGameTimer()>v.expires or Inventory.Session(src)~=v.id or not v.consumables[item] then return false,'conflict' end
  wheelViews[src]=nil
  local d={slot=v.consumables[item].slot,revision=v.bagRevision}
  return Inventory.Act({id=v.id,source=src,key=v.token..':consume',actor='player:'..v.id,fingerprint=fingerprint('use',d)},'use',d)
 end)
 if not ok then TriggerClientEvent(events..'notice',src,message(err)) end
end)
AddEventHandler('playerDropped',function() wheelViews[source]=nil;wheelLast[source]=nil end)

AddEventHandler('playerDropped',function() selectedBelt[source]=nil end)
local function findGatherTool(source,id,bag,belt,kind,instance,repair)
 local preferred=selectedBelt[source];local best,bestBox,bestSlot,bestScore
 for _,box in ipairs({belt,bag}) do for slot,e in pairs(box.slots) do
  local def=Inventory.items[e.item]
  if def and def.classification=='tool' and e.instance and e.item:match('^gather_'..kind..'_') and (not instance or e.instance==instance) then
   local m=json.decode(e.metadata)
   if m and type(m.uses)=='number' and (m.uses>0 or repair and m.uses>=0) and type(m.maxUses)=='number' and m.maxUses>=m.uses and type(m.quality)=='number' and m.quality>=0 and m.quality<=100 and type(m.yield)=='number' and m.yield>=.5 and m.yield<=2.2 then
    local score=(preferred and preferred.id==id and preferred.instance==e.instance) and 10000 or (box==belt and 1000 or 0)+(repair and (1-m.uses/m.maxUses)*100 or m.yield*100+m.uses/m.maxUses)
    if not bestScore or score>bestScore then best,bestBox,bestSlot,bestScore=e,box,slot,score end
   end
  end
 end end
 return best,bestBox,bestSlot
end
local function gatheringBoxes(source)
 local id,err=Inventory.Session(source);if not id then return nil,err end
 local ok,bag=Inventory.Player(source,id);if not ok then return nil,bag end
 local loaded,belt=Inventory.Belt(source,id);if not loaded then return nil,belt end
 return id,bag,belt
end
-- Reuse the same character/death policy as ordinary inventory transactions.
trusted('GetGatheringPosition',function(owner,source)
 if owner~='frontier_gathering' then return false,'forbidden' end
 local id,pos=Inventory.Session(source)
 if not id then return false,pos end
 return true,{character=id,x=pos.x,y=pos.y,z=pos.z,bucket=pos.bucket}
end)
trusted('GetEquippedGatheringTool',function(owner,source)
 if owner~='frontier_gathering' then return false,'forbidden' end
 if not selectedBelt[source] then return true,false end
 local id,bag,belt=gatheringBoxes(source)
 if not id then return false,bag end
 return true,equipped(source,id,bag,belt) or false
end)
trusted('GetGatheringTool',function(owner,source,kind,repair,requireEquipped)
 if owner~='frontier_gathering' or not Inventory.Id(kind,24) then return false,'forbidden' end
 local id,bag,belt=gatheringBoxes(source);if not id then return false,bag end
 local active=equipped(source,id,bag,belt)
 if requireEquipped and (not active or active.kind~=kind) then return false,'tool_not_equipped' end
 local e=findGatherTool(source,id,bag,belt,kind,requireEquipped and active.instance or nil,repair==true)
 if not e then return false,'tool_missing' end
 return true,{item=e.item,instance=e.instance,metadata=json.decode(e.metadata)}
end)
trusted('GatheringCommit',function(owner,source,character,kind,instance,item,count,wear,key,preview,extra,metadata)
 -- Table form avoids positional nil arguments crossing the resource boundary.
 if type(kind)=='table' then
  local d=kind;kind,instance,item,count,wear,key,preview,extra,metadata=d.kind,d.instance,d.item,d.count,d.wear,d.key,d.preview,d.extra,d.metadata
 end
 if owner~='frontier_gathering' then return false,'forbidden' end
 if not requestKey(key) then return false,'invalid_request_key' end
 if kind~=nil and (not Inventory.Id(kind,24) or type(instance)~='string') then return false,'invalid_tool_reference' end
 if type(count)~='number' or count%1~=0 or count<0 or count>100 then return false,'invalid_reward_count' end
 if type(wear)~='number' or wear~=wear or wear<0 or wear>1 then return false,'invalid_tool_wear' end
 count=math.tointeger(count)
 if count>0 and (not Inventory.items[item] or not Inventory.items[item].stackable) then return false,'invalid_item' end
 local actor='resource:'..owner
 local fingerprint=json.encode({'gather',character,kind or false,instance or false,item or false,count,wear,extra and extra.item or false,extra and extra.count or false,metadata or false})
 if not preview then
  local ok,replay=Inventory.Replay(key,actor,fingerprint);if not ok then return false,replay end;if replay then return true,key end
 end
 local generation=Inventory.Generation(source)
 local id,bag,belt=gatheringBoxes(source);if not id then return false,bag end
 if id~=character then return false,'character' end
 local changed=bag
 if kind then
  local e,box,slot=findGatherTool(source,id,bag,belt,kind,instance)
  if not e then return false,'tool_missing' end
  local m=json.decode(e.metadata)
  if wear>0 then
   m.uses=math.max(0,m.uses-wear);m.condition=math.ceil(m.uses/m.maxUses*100)
   e.metadata=json.encode(m);box.slots[slot]=e;changed=box
  end
 end
 if count>0 then
  local def=Inventory.items[item];if metadata and not Inventory.Metadata(metadata,def.condition) then return false,'invalid_metadata' end
  local ok,err=Inventory.Place(bag,{item=item,quantity=count,metadata=metadata or def.metadata})
  if not ok then return false,err end
 end
 if extra then
  local def=Inventory.items[extra.item];if not def or not def.stackable or not Inventory.Int(extra.count,100) then return false,'invalid_item' end
  local ok,err=Inventory.Place(bag,{item=extra.item,quantity=extra.count,metadata=def.metadata});if not ok then return false,err end
 end
 if preview then return true end
 if Inventory.Session(source)~=id or Inventory.Generation(source)~=generation then return false,'character' end
 local ok,err
 -- No reward (gold panning): commit only the changed tool container.
 if changed==belt and count==0 and not extra then ok,err=Inventory.Commit(key,actor,fingerprint,belt)
 elseif changed==belt then ok,err=Inventory.Commit(key,actor,fingerprint,bag,belt)
 else ok,err=Inventory.Commit(key,actor,fingerprint,bag) end
 if not ok then
  Inventory.Log('WARN','Gathering commit rejected',{key=key,reason=err,count=count,kind=kind,item=item})
  return false,err=='invalid_request' and 'inventory_sql_invalid_request' or err
 end
 equipped(source,id,bag,belt)
 return true,key
end)

-- Material consumption, unique tool creation or repair, and receipt are one commit.
trusted('GatheringSmith',function(owner,source,character,job,key,preview)
 if owner~='frontier_gathering' or type(job)~='table' or not requestKey(key) or not Inventory.Id(job.kind,24) or not Inventory.Id(job.item,48) then return false,'invalid_request' end
 local def=Inventory.items[job.item]
 if not def or def.owner~=owner or def.classification~='tool' or not job.item:match('^gather_'..job.kind..'_') then return false,'invalid_item' end
 local actor='resource:'..owner
 local fingerprint=json.encode({'smith',character,job.item,job.instance or false,job.metal,job.cost,job.wood,job.metadata or false})
 if not preview then
  local ok,replay=Inventory.Replay(key,actor,fingerprint);if not ok then return false,replay end;if replay then return true,key end
 end
 local generation=Inventory.Generation(source)
 local id,bag,belt=gatheringBoxes(source);if not id then return false,bag end;if id~=character then return false,'character' end
 if (job.metal~='iron_ingot' and job.metal~='gather_steel') or not Inventory.Int(job.cost,10) or not Inventory.Int(job.wood,10) then return false,'invalid_request' end
 for _,req in ipairs({{job.metal,job.cost},{'wood',job.wood}}) do
  local left=req[2];for slot=1,bag.slot_limit do local e=bag.slots[slot];if e and e.item==req[1] then local count=math.min(left,e.quantity);Inventory.Take(bag,slot,count);left=left-count;if left==0 then break end end end
  if left>0 then return false,'insufficient_stock' end
 end
 local changed=bag
 if job.instance then
  local e,box=findGatherTool(source,id,bag,belt,job.kind,job.instance,true);if not e or e.item~=job.item then return false,'tool_missing' end
  local m=json.decode(e.metadata);m.uses=m.maxUses;m.condition=100;e.metadata=json.encode(m);changed=box
 else
  if not Inventory.Metadata(job.metadata,true) then return false,'invalid_metadata' end
  local instance=Inventory.Uuid();if not instance then return false,'database_error' end
  local ok,err=Inventory.Place(bag,{item=job.item,quantity=1,metadata=job.metadata,instance=instance});if not ok then return false,err end
 end
 if preview then return true end
 if Inventory.Session(source)~=id or Inventory.Generation(source)~=generation then return false,'character' end
 if changed==belt then return Inventory.Commit(key,actor,fingerprint,bag,belt) end
 return Inventory.Commit(key,actor,fingerprint,bag)
end)

-- Only frontier_logistics is permitted to use these private routes. They never use the public s_ namespace.
local function logisticsRoute(id)
 return type(id)=='string' and #id<=80 and (id:match('^lg_w_[a-f0-9]+$') or id:match('^lg_c_[a-f0-9]+$') or id:match('^lg_f_[a-f0-9]+$') or id:match('^p_f_[a-f0-9]+$') or id:match('^s_business_[a-f0-9]+$') or id:match('^s_property_[a-f0-9]+$'))
end
local function logisticsLoad(id)
 if not logisticsRoute(id) then return false,'invalid_route' end
 return Inventory.Load(id)
end
trusted('LogisticsEnsure',function(resource,id,slots,grams)
 if resource~='frontier_logistics' or type(id)~='string' or not id:match('^lg_[wcf]_[a-f0-9]+$') or not Inventory.Int(slots,200) or not Inventory.Int(grams,100000000) then return false,'forbidden' end
 return Inventory.Ensure(id,'storage',slots,grams)
end)
trusted('LogisticsRead',function(resource,id)
 if resource~='frontier_logistics' then return false,'forbidden' end
 local ok,box=logisticsLoad(id);return ok,ok and Inventory.Present(box) or box
end)
local function logisticsCommit(key,fingerprint,boxes)
 local changes={}
 for _,box in pairs(boxes) do
  local entries={}
  for slot,r in pairs(box.slots) do entries[#entries+1]={slot=slot,item=r.item,quantity=r.quantity,metadata=r.metadata,instance=r.instance} end
  changes[#changes+1]={id=box.id,revision=box.revision,entries=entries}
 end
 table.sort(changes,function(a,b)return a.id<b.id end)
 local ok,result=Inventory.Db('query','CALL frontier_inventory_logistics_commit_v1(?,?,?,?)',{key,'resource:frontier_logistics',fingerprint,json.encode(changes)})
 local row=ok and result and type(result[1])=='table' and result[1][1]
 if not row then return false,'database_error' end
 return row.code=='ok',row.code
end
local function lgReplay(key,fingerprint)
 return Inventory.Replay(key,'resource:frontier_logistics',fingerprint)
end
-- Optimistic whole-plan commit: all participating revisions must still match after loading.
trusted('LogisticsPlan',function(resource,key,plan,preview)
 if resource~='frontier_logistics' or not requestKey(key) or type(plan)~='table' or type(plan.lines)~='table' or #plan.lines<1 or #plan.lines>80 or type(plan.revisions)~='table' then return false,'invalid_request' end
 local fingerprint=plan.fingerprint
 if type(fingerprint)~='string' or #fingerprint>50000 then return false,'invalid_request' end
 if not preview then local ok,replay=lgReplay(key,fingerprint);if not ok then return false,replay end;if replay then return true,'replayed' end end
 local boxes={};local count=0
 local function load(id)
  if boxes[id] then return boxes[id] end
  if count>=16 then return nil,'too_many_containers' end
  local ok,box=logisticsLoad(id);if not ok then return nil,box end
  if box.revision~=plan.revisions[id] then return nil,'conflict' end
  boxes[id]=box;count=count+1;return box
 end
 local grams,units=0,0
 for _,line in ipairs(plan.lines) do
  if type(line)~='table' or not logisticsRoute(line.from) or not logisticsRoute(line.to) or line.from==line.to then return false,'invalid_route' end
  local from,e=load(line.from);if not from then return false,e end
  local to,why=load(line.to);if not to then return false,why end
  local entry=from.slots[line.slot]
  if not entry or entry.item~=line.item or (entry.instance or '')~=(line.instance or '') or entry.metadata~=line.metadata or not Inventory.Int(line.quantity,entry.quantity) then return false,'conflict' end
  local def=Inventory.items[entry.item];if not def or not def.transfer or not def.store then return false,'forbidden' end
  local ok,stack=Inventory.Take(from,line.slot,line.quantity);if not ok then return false,stack end
  local put,err=Inventory.Place(to,stack);if not put then return false,err end
  grams=grams+def.grams*line.quantity;units=units+line.quantity
 end
 if plan.wagon then
  local box,e=load(plan.wagon);if not box then return false,e end
  local extraWeight=tonumber(plan.freightWeight) or 0;local extraSlots=tonumber(plan.freightSlots) or 0
  local used=0;for _ in pairs(box.slots) do used=used+1 end
  if Inventory.Weight(box)+extraWeight>box.weight_limit or used+extraSlots>box.slot_limit then return false,'reserved_freight_capacity' end
 end
 if preview then return true,{grams=grams,units=units} end
 return logisticsCommit(key,fingerprint,boxes)
end)
-- Exact whole-container move (freight pickup/delivery/refund). Operation receipt survives retries.
trusted('LogisticsMoveAll',function(resource,key,fromId,toId)
 if resource~='frontier_logistics' or not requestKey(key) or not logisticsRoute(fromId) or not logisticsRoute(toId) or fromId==toId then return false,'invalid_request' end
 local fingerprint='move:'..fromId..':'..toId
 local checked,replay=lgReplay(key,fingerprint);if not checked then return false,replay end;if replay then return true,'replayed' end
 local ok,from=logisticsLoad(fromId);if not ok then return false,from end
 local found,to=logisticsLoad(toId);if not found then return false,to end
 if not next(from.slots) then return false,'empty' end
 local moved,why=productionMove(from,to);if not moved then return false,why end
 return logisticsCommit(key,fingerprint,{from,to})
end)
-- Deterministic destruction selection is frozen by operation ID, original stack slot and container.
-- Retry uses the same selection; no reroll after a database failure.
trusted('LogisticsRecover',function(resource,key,fromIds,toId)
 if resource~='frontier_logistics' or not requestKey(key) or type(fromIds)~='table' or #fromIds<1 or #fromIds>14 or not logisticsRoute(toId) then return false,'invalid_request' end
 local fingerprint='wreck:'..table.concat(fromIds,':')..':'..toId
 local checked,replay=lgReplay(key,fingerprint);if not checked then return false,replay end;if replay then return true,'replayed' end
 local ok,to=logisticsLoad(toId);if not ok then return false,to end
 local boxes={to};local seen={[toId]=true}
 for _,id in ipairs(fromIds) do
  if seen[id] then return false,'invalid_route' end;seen[id]=true
  local found,from=logisticsLoad(id);if not found then return false,from end
  for slot,entry in pairs(from.slots) do
   local hash=GetHashKey(key..':'..id..':'..slot) & 0xffffffff
   local numerator=entry.quantity*90
   local keep=math.floor(numerator/100)+(hash%100<numerator%100 and 1 or 0)
   if keep>0 then
    local put,why=Inventory.Place(to,{item=entry.item,quantity=keep,metadata=entry.metadata,instance=entry.instance})
    if not put then return false,why end
   end
  end
  from.slots={};boxes[#boxes+1]=from
 end
 return logisticsCommit(key,fingerprint,boxes)
end)
-- Consume parts and return their frozen weighted quality with one atomic receipt.
trusted('LogisticsConsume',function(resource,key,route,needs,preview,expectedRevision)
 if resource~='frontier_logistics' or not requestKey(key) or not logisticsRoute(route) or type(needs)~='table' or #needs<1 or #needs>20 then return false,'invalid_request' end
 local parts={route,tostring(expectedRevision or '')}
 for _,need in ipairs(needs) do parts[#parts+1]=tostring(need.id)..':'..tostring(need.count) end
 local fingerprint='parts:'..table.concat(parts,':')
 if not preview then local ok,replay=lgReplay(key,fingerprint);if not ok then return false,replay end;if replay then return true,'replayed' end end
 local ok,box=logisticsLoad(route);if not ok then return false,box end
 if expectedRevision and box.revision~=expectedRevision then return false,'conflict' end
 local quality,total=0,0
 for _,need in ipairs(needs) do
  if not Inventory.items[need.id] or not Inventory.Int(need.count,10000) then return false,'invalid_item' end
  local left=need.count
  for slot=1,box.slot_limit do
   local entry=box.slots[slot]
   if entry and entry.item==need.id then
    local n=math.min(left,entry.quantity);local metadata=json.decode(entry.metadata or '{}');local q=math.max(0,math.min(100,tonumber(metadata.quality) or 50))
    quality=quality+q*n;total=total+n
    local taken,why=Inventory.Take(box,slot,n);if not taken then return false,why end
    left=left-n;if left==0 then break end
   end
  end
  if left>0 then return false,'missing '..need.id end
 end
 if preview then return true,{quality=math.floor(quality/total+.5),revision=box.revision} end
 return logisticsCommit(key,fingerprint,{box})
end)
