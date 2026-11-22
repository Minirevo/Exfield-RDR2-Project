local core = exports.frontier_core
local economy = exports.frontier_economy
local inventory = exports.frontier_inventory
local pending = {}

local function db(method, sql, args)
    local ok, result = pcall(MySQL[method].await, sql, args)
    if not ok then
        FrontierLib.Log('ERROR', GetCurrentResourceName(), 'Trade delivery database call failed', { method = method })
        return nil
    end
    return result
end

local function uuid(value)
    return type(value) == 'string' and #value == 36 and value:match('^[a-f0-9-]+$')
end

local function procedure(action, id, parent, actor, value, quote)
    local out = db('query', 'CALL frontier_trade_contract_v1(?, ?, ?, ?, ?, ?)',
        { action, id, parent or '', actor or '', value or 0, quote or 0 })
    return out and out[1] and out[1][1] and out[1][1].code == 'ok'
end

local function say(source, message)
    TriggerClientEvent('chat:addMessage', source, { args = { 'Frontier Handel', message } })
end

local function command(name, callback)
    RegisterCommand(name, function(source, args)
        if source == 0 or pending[source] then return end
        local character = core:GetPlayerCharacterId(source)
        if not character then return end
        pending[source] = true
        local ok, message = pcall(callback, source, character, args)
        pending[source] = nil
        if core:GetPlayerCharacterId(source) == character then
            say(source, ok and message or 'Der Handelsdienst ist momentan nicht erreichbar.')
        end
    end, false)
end

command('handelannehmen', function(source, character, args)
    if not uuid(args[1]) then return 'Verwendung: /handelannehmen <Gesuch-ID>' end
    local ok, accounts = economy:GetCharacterAccounts(source)
    if not ok or accounts.characterId ~= character then return 'Das Bankkonto ist nicht verfügbar.' end
    local id = db('scalar', 'SELECT UUID()')
    if not uuid(id) or core:GetPlayerCharacterId(source) ~= character then return 'Annahme konnte nicht bestätigt werden.' end
    local quote = args[2] and (tonumber(args[2]) or -1) or 0
    if quote < 0 or quote > 10000 or quote ~= math.floor(quote) then return 'Ungültiger Preis.' end
    if procedure('accept', id, args[1], character, accounts.bank.id, quote) then
        return 'Vertrag angenommen. Vertrags-ID: ' .. id
    end
    return 'Annahme nicht bestätigt. Prüfe deine Verträge. Vorgangs-ID: ' .. id
end)

command('handelliefern', function(source, character, args)
    local count = tonumber(args[2])
    if not uuid(args[1]) or not count or count < 1 or count > 1000 or count ~= math.floor(count) then
        return 'Verwendung: /handelliefern <Vertrags-ID> <Menge>'
    end
    local id = db('scalar', 'SELECT UUID()')
    if not uuid(id) or core:GetPlayerCharacterId(source) ~= character then return 'Lieferung konnte nicht bestätigt werden.' end
    if procedure('deliver', id, args[1], character, count) then
        return 'Lieferung vorgemerkt. Liefer-ID: ' .. id
    end
    return 'Lieferung nicht bestätigt. Prüfe den Vertrag. Vorgangs-ID: ' .. id
end)

command('handelsvertragsstorno', function(source, character, args)
    if not uuid(args[1]) then return 'Verwendung: /handelsvertragsstorno <Vertrags-ID>' end
    if procedure('cancel', args[1], nil, character) then return 'Vertrag storniert.' end
    return 'Vertrag nicht verfügbar oder eine Lieferung ist in Abwicklung.'
end)

command('handelsvertraege', function(source, character)
    local rows = db('query', [[
        SELECT c.id,c.state,c.due_at,r.item_id,r.quantity,r.settled_quantity
        FROM frontier_trade_contracts c JOIN frontier_trade_requests r ON r.id=c.request_id
        WHERE c.seller_id=? OR r.buyer_id=? ORDER BY c.due_at DESC LIMIT 20
    ]], { character, character })
    if not rows then return 'Verträge konnten nicht geladen werden.' end
    if core:GetPlayerCharacterId(source) ~= character then return 'Dein Charakter hat gewechselt.' end
    local labels = { active = 'Aktiv', expired = 'Abgelaufen', cancelled = 'Storniert', closed = 'Abgeschlossen' }
    for _, row in ipairs(rows) do
        say(source, ('%s | %s | %s von %s geliefert | Frist: %s UTC'):format(
            row.id, labels[row.state], row.settled_quantity, row.quantity, row.due_at))
    end
    return #rows == 0 and 'Keine Verträge gefunden.' or 'Verträge geladen.'
end)

command('handelslieferungen', function(source, character)
    local rows = db('query', [[
        SELECT d.id,d.state,d.quantity,r.item_id,c.seller_id
        FROM frontier_trade_deliveries d JOIN frontier_trade_contracts c ON c.id=d.contract_id
        JOIN frontier_trade_requests r ON r.id=c.request_id
        WHERE c.seller_id=? OR r.buyer_id=? ORDER BY d.retry_at DESC,d.id LIMIT 20
    ]], { character, character })
    if not rows then return 'Lieferungen konnten nicht geladen werden.' end
    if core:GetPlayerCharacterId(source) ~= character then return 'Dein Charakter hat gewechselt.' end
    local labels = { stock = 'Warenprüfung', payment = 'Zahlung ausstehend',
        complete = 'Abgerechnet', rejected = 'Abgelehnt' }
    for _, row in ipairs(rows) do
        say(source, ('%s | %s × %s | %s'):format(row.id, row.quantity,
            TradeConfig.Products[row.item_id] or row.item_id, labels[row.state]))
    end
    return #rows == 0 and 'Keine Lieferungen gefunden.' or 'Lieferungen geladen.'
end)

command('handelsabholung', function(source, character, args)
    if not uuid(args[1]) then return 'Verwendung: /handelsabholung <Liefer-ID>' end
    local row = db('single', [[
        SELECT d.id,d.quantity,r.item_id,d.claimed_at
        FROM frontier_trade_deliveries d JOIN frontier_trade_contracts c ON c.id=d.contract_id
        JOIN frontier_trade_requests r ON r.id=c.request_id
        WHERE d.id=? AND r.buyer_id=? AND d.state='complete'
    ]], { args[1], character })
    if not row or core:GetPlayerCharacterId(source) ~= character then return 'Diese Lieferung ist nicht verfügbar.' end
    if row.claimed_at then return 'Diese Lieferung wurde bereits abgeholt.' end
    local ok = inventory:ClaimTradeDelivery(row.id, character, row.item_id, tonumber(row.quantity))
    if not ok then return 'Abholung nicht bestätigt. Prüfe freie Plätze und Gewicht und wiederhole denselben Auftrag.' end
    db('update', 'UPDATE frontier_trade_deliveries SET claimed_at=UTC_TIMESTAMP() WHERE id=? AND claimed_at IS NULL', { row.id })
    return 'Lieferung erhalten.'
end)

local reject = { insufficient_stock = true, not_found = true, weight = true, slots = true, invalid_item = true }
local function step(row)
    if row.state == 'stock' then
        local ok, reason = inventory:ReserveTradeDelivery(row.id, row.seller_id, row.item_id, tonumber(row.quantity))
        if ok then
            db('update', "UPDATE frontier_trade_deliveries SET state='payment' WHERE id=? AND state='stock'", { row.id })
            return
        end
        if reject[reason] then procedure('reject', row.id); return end
    else
        local ok = economy:PayTradeDelivery(row.request_id, row.id, row.seller_id, tonumber(row.seller_bank),
            tonumber(row.quantity) * tonumber(row.price_minor))
        if ok then procedure('complete', row.id); return end
    end
    db('update', [[
        UPDATE frontier_trade_deliveries SET retry_at=DATE_ADD(UTC_TIMESTAMP(), INTERVAL 30 SECOND)
        WHERE id=? AND state=?
    ]], { row.id, row.state })
end

local function run()
    local expired = db('query', [[
        SELECT id FROM frontier_trade_contracts WHERE state='active' AND due_at<=UTC_TIMESTAMP()
          AND active_delivery IS NULL ORDER BY due_at,id LIMIT 20
    ]])
    if expired then for _, row in ipairs(expired) do procedure('expire', row.id) end end
    local rows = db('query', [[
        SELECT d.id,d.state,d.quantity,c.seller_id,c.seller_bank,r.id AS request_id,r.item_id,c.unit_minor AS price_minor
        FROM frontier_trade_deliveries d JOIN frontier_trade_contracts c ON c.id=d.contract_id
        JOIN frontier_trade_requests r ON r.id=c.request_id
        WHERE d.state IN ('stock','payment') AND d.retry_at<=UTC_TIMESTAMP()
        ORDER BY d.retry_at,d.id LIMIT 20
    ]])
    if rows then
        for _, row in ipairs(rows) do
            local ok = pcall(step, row)
            if not ok then FrontierLib.Log('WARN', GetCurrentResourceName(), 'Delivery will be retried', { id = row.id }) end
        end
    end
end

MySQL.ready(function()
    while true do
        run()
        Wait(TradeConfig.WorkerIntervalMs)
    end
end)

local marketRequestAt = {}
RegisterNetEvent('frontier_trade:marketSnapshot', function(view, market)
    local player = tonumber(source)
    if not player or type(view) ~= 'number' or view < 1 or view > 2147483647 or view ~= math.floor(view)
        or type(market) ~= 'string' or not TradeConfig.Markets[market] then return end
    local character = core:GetPlayerCharacterId(player)
    if not character then return end
    local now = GetGameTimer()
    local last = marketRequestAt[player]
    if last and now >= last and now - last < 500 then return end
    marketRequestAt[player] = now
    local requests = db('query', [[
        SELECT id,item_id,quantity-settled_quantity AS remaining,COALESCE(quote_minor,price_minor) AS price_minor,
            IF(active_contract IS NULL AND buyer_id<>?,1,0) AS available,
            IF(buyer_id=? AND active_contract IS NULL,1,0) AS cancellable
        FROM frontier_trade_requests WHERE state='open' AND market_id=? AND expires_at>UTC_TIMESTAMP()
        ORDER BY expires_at,id LIMIT 40
    ]], { character, character, market })
    local contracts = db('query', [[
        SELECT c.id,c.state,DATE_FORMAT(c.due_at,'%Y-%m-%d %H:%i') AS due_at,
            r.item_id,r.quantity-r.settled_quantity AS remaining,
            IF(c.seller_id=? AND c.state='active' AND c.active_delivery IS NULL,1,0) AS deliverable,
            IF(c.state='active' AND c.active_delivery IS NULL,1,0) AS cancellable
        FROM frontier_trade_contracts c JOIN frontier_trade_requests r ON r.id=c.request_id
        WHERE c.seller_id=? OR r.buyer_id=? ORDER BY c.due_at DESC LIMIT 40
    ]], { character, character, character })
    local deliveries = db('query', [[
        SELECT d.id,d.quantity,d.state,r.item_id,d.claimed_at,IF(r.buyer_id=? AND d.state='complete' AND d.claimed_at IS NULL,1,0) AS claimable
        FROM frontier_trade_deliveries d JOIN frontier_trade_contracts c ON c.id=d.contract_id
        JOIN frontier_trade_requests r ON r.id=c.request_id WHERE c.seller_id=? OR r.buyer_id=?
        ORDER BY d.retry_at DESC,d.id LIMIT 40
    ]], { character, character, character })
    local offers = db('query', [[
        SELECT id,item_id,available,unit_minor, state,
          IF(seller_id<>? AND active_sale IS NULL AND state='open',1,0) AS buyable,
          IF(seller_id=? AND active_sale IS NULL AND state='open',1,0) AS cancellable
        FROM frontier_trade_offers
        WHERE market_id=? AND ((state='open' AND expires_at>UTC_TIMESTAMP()) OR seller_id=?)
        ORDER BY expires_at DESC,id LIMIT 40
    ]], { character,character,market,character })
    local sales = db('query', [[
        SELECT s.id,s.quantity,s.state,s.claimed_at,o.item_id,
          IF(s.buyer_id=? AND s.state='complete' AND s.claimed_at IS NULL,1,0) AS claimable
        FROM frontier_trade_sales s JOIN frontier_trade_offers o ON o.id=s.offer_id
        WHERE s.buyer_id=? OR o.seller_id=? ORDER BY s.retry_at DESC,s.id LIMIT 40
    ]], { character,character,character })
    local prices = db('query', [[
        SELECT item_id,price_minor,DATE_FORMAT(quoted_at,'%Y-%m-%d %H:%i') AS quoted_at
        FROM frontier_trade_price_history WHERE market_id=? ORDER BY id DESC LIMIT 25
    ]], { market })
    if core:GetPlayerCharacterId(player) ~= character or marketRequestAt[player] ~= now then return end
    TriggerClientEvent('frontier_trade:marketSnapshot', player, view, {
        market = market, markets = TradeConfig.Markets, products = TradeConfig.Products,
        requests = requests or {}, contracts = contracts or {}, deliveries = deliveries or {}, prices = prices or {}, offers = offers or {}, sales = sales or {},
        available = requests ~= nil and contracts ~= nil and deliveries ~= nil and prices ~= nil and offers ~= nil and sales ~= nil,
    })
end)
AddEventHandler('playerDropped', function() marketRequestAt[tonumber(source) or 0] = nil end)
AddEventHandler('frontier:playerUnloaded', function(player)
    marketRequestAt[player.source] = nil
    TriggerClientEvent('frontier_trade:closeMarket', player.source)
end)

RegisterCommand('handelspruefung', function(source)
    if source ~= 0 and not core:HasPermission(source, 'frontier.trade.admin') then return end
    local rows = db('query', [[
        SELECT id,state,retry_at FROM frontier_trade_deliveries
        WHERE state IN ('stock','payment') ORDER BY retry_at,id LIMIT 20
    ]])
    local function report(message)
        if source == 0 then print('[FRONTIER TRADE] ' .. message) else say(source, message) end
    end
    if not rows then report('Die Handelsdatenbank ist nicht verfügbar.'); return end
    if #rows == 0 then report('Keine Lieferungen in Abwicklung.'); return end
    for _, row in ipairs(rows) do report(('%s | %s | %s'):format(row.id,
        row.state == 'stock' and 'Warenprüfung' or 'Zahlung ausstehend', row.retry_at)) end
end, false)
