local config = TradeConfig
local core, economy, inventory = exports.frontier_core, exports.frontier_economy, exports.frontier_inventory
local resource = GetCurrentResourceName()
local submitted = {}

local function integer(value, max)
    return type(value) == 'number' and value > 0 and value <= max and FrontierLib.IsInteger(value)
end

local function reference(value)
    return type(value) == 'string' and #value == 36 and value:match('^[a-f0-9-]+$')
end

local function db(method, statement, params)
    local ok, result = pcall(MySQL[method].await, statement, params)

    if not ok then
        FrontierLib.Log('ERROR', resource, 'Trade query failed', {
            method = method,
            error = tostring(result)
        })

        print(('[frontier_trade] SQL ERROR (%s): %s'):format(
            tostring(method),
            tostring(result)
        ))

        return false, 'database_error'
    end

    return true, result
end

local function create(source, id, market, item, quantity, price, cap)
    cap = cap or price
    if not reference(id) or type(market) ~= 'string' or not config.Markets[market]
        or type(item) ~= 'string' or not config.Products[item]
        or not integer(quantity, math.min(config.MaxQuantity, 1000))
        or not integer(price, math.min(config.MaxUnitMinor, 10000))
        or not integer(cap, math.min(config.MaxUnitMinor, 10000)) or cap < price then return false, 'invalid_request' end

    local character = core:GetPlayerCharacterId(source)
    if not character then return false, 'character_unavailable' end
    local known, definition = inventory:GetTradeItemDefinition(item)
    if not known then return false, definition end
    if not definition.transferable then return false, 'invalid_request' end
    local ready, accounts = economy:GetCharacterAccounts(source)
    if not ready then return false, accounts end
    if accounts.characterId ~= character or core:GetPlayerCharacterId(source) ~= character then
        return false, 'character_unavailable'
    end
    local saved, issue = db('update', [[
        INSERT INTO frontier_trade_requests
          (id, buyer_id, bank_id, market_id, item_id, quantity, price_minor, budget_minor, state, expires_at, retry_at,
           base_quote_minor, quote_minor, next_quote_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'funding', DATE_ADD(UTC_TIMESTAMP(), INTERVAL ? HOUR), UTC_TIMESTAMP(), ?, ?, DATE_ADD(UTC_TIMESTAMP(), INTERVAL ? HOUR))
        ON DUPLICATE KEY UPDATE id = id
    ]], { id, character, accounts.bank.id, market, item, quantity, cap, quantity * cap, config.LifetimeHours, price, price, config.EscalationHours })
    if not saved then return false, issue end
    local read, row = db('single', [[
        SELECT buyer_id, market_id, item_id, quantity, price_minor, base_quote_minor, state
        FROM frontier_trade_requests WHERE id = ?
    ]], { id })
    if not read then return false, row end
    if not row or row.buyer_id ~= character or row.market_id ~= market or row.item_id ~= item
        or tonumber(row.quantity) ~= quantity or tonumber(row.price_minor) ~= cap or (tonumber(row.base_quote_minor) or tonumber(row.price_minor)) ~= price then
        return false, 'request_conflict'
    end
    return true, { id = id, state = row.state }
end

local function cancel(source, id)
    if not reference(id) then return false, 'invalid_request' end
    local character = core:GetPlayerCharacterId(source)
    if not character then return false, 'character_unavailable' end
    local saved, count = db('update', [[
        UPDATE frontier_trade_requests SET state = 'refund', retry_at = UTC_TIMESTAMP(), attempts = 0
        WHERE id = ? AND buyer_id = ? AND state = 'open' AND active_contract IS NULL
    ]], { id, character })
    if not saved then return false, count end
    if count == 1 then return true end
    local read, row = db('single', 'SELECT state FROM frontier_trade_requests WHERE id = ? AND buyer_id = ?',
        { id, character })
    if not read then return false, row end
    if row and (row.state == 'refund' or row.state == 'closed') then return true end
    return false, 'not_open'
end

local function list(market)
    if type(market) ~= 'string' or not config.Markets[market] then return false, 'invalid_request' end
    return db('query', [[
        SELECT id, item_id, quantity - settled_quantity AS quantity, COALESCE(quote_minor,price_minor) AS price_minor FROM frontier_trade_requests
        WHERE market_id = ? AND state = 'open' AND expires_at > UTC_TIMESTAMP()
        ORDER BY expires_at, id LIMIT 20
    ]], { market })
end

local decline = { insufficient_funds = true }
local function step(row)
    local funding = row.state == 'funding'
    local handler = funding and economy.FundTradeHold or economy.ReleaseTradeHold
    local amount = tonumber(row.budget_minor)
    if not funding and (tonumber(row.settled_quantity) or 0) > 0 then
        handler = economy.RefundTradeRemainder
        amount = amount - tonumber(row.spent_minor)
    end
    local ok, result = handler(economy, row.id, row.buyer_id, tonumber(row.bank_id), amount)
    if ok or (funding and decline[result]) then
        local nextState = ok and (funding and 'open' or 'closed') or 'rejected'
        db('update', [[
            UPDATE frontier_trade_requests SET state = ?, attempts = 0, last_error = NULL
            WHERE id = ? AND state = ?
        ]], { nextState, row.id, row.state })
    else
        local attempts = math.min(tonumber(row.attempts) + 1, 100000)
        if attempts == 1 or attempts == 10 then
            FrontierLib.Log('WARN', resource, 'Trade operation awaiting retry',
                { request = row.id, state = row.state, issue = tostring(result):sub(1, 64) })
        end
        db('update', [[
            UPDATE frontier_trade_requests SET attempts = ?, last_error = ?,
                retry_at = DATE_ADD(UTC_TIMESTAMP(), INTERVAL ? SECOND)
            WHERE id = ? AND state = ?
        ]], { attempts, tostring(result):sub(1, 64), math.min(300, 2 ^ math.min(attempts, 8)), row.id, row.state })
    end
end

local function tick()
    if config.EscalationPercent > 0 then
        local due, quotes = db('query', [[
            SELECT id,market_id,item_id,quote_minor,
                (SELECT COALESCE(SUM(o.available),0) FROM frontier_trade_offers o
                 WHERE o.market_id=r.market_id AND o.item_id=r.item_id AND o.state='open'
                   AND o.active_sale IS NULL AND o.expires_at>UTC_TIMESTAMP()) AS supply,
                (SELECT COALESCE(SUM(d.quantity-d.settled_quantity),0) FROM frontier_trade_requests d
                 WHERE d.market_id=r.market_id AND d.item_id=r.item_id AND d.state='open'
                   AND d.active_contract IS NULL AND d.expires_at>UTC_TIMESTAMP()) AS demand
            FROM frontier_trade_requests r
            WHERE r.state='open' AND r.active_contract IS NULL AND r.next_quote_at<=UTC_TIMESTAMP()
              AND r.quote_minor<r.price_minor AND r.expires_at>UTC_TIMESTAMP()
            ORDER BY r.next_quote_at,r.id LIMIT ?
        ]], {config.Batch})
        if due then for _,row in ipairs(quotes) do
            local pressure = tonumber(row.demand) > tonumber(row.supply) and 1.25 or 0.75
            local modifier = (config.RegionalPricePercent or {})[row.market_id] or 100
            local rate = config.EscalationPercent * pressure * modifier / 100
            db('update', [[
                UPDATE frontier_trade_requests
                SET quote_minor=LEAST(price_minor,quote_minor+GREATEST(1,FLOOR(quote_minor*?/100))),
                    next_quote_at=DATE_ADD(UTC_TIMESTAMP(),INTERVAL ? HOUR)
                WHERE id=? AND quote_minor=? AND state='open' AND active_contract IS NULL
                  AND next_quote_at<=UTC_TIMESTAMP() AND expires_at>UTC_TIMESTAMP()
            ]], {rate,config.EscalationHours,row.id,tonumber(row.quote_minor)})
        end end
    end
    local expired = db('update', [[
        UPDATE frontier_trade_requests SET state = 'refund', retry_at = UTC_TIMESTAMP(), attempts = 0
        WHERE state = 'open' AND active_contract IS NULL AND expires_at <= UTC_TIMESTAMP()
        ORDER BY expires_at, id LIMIT ?
    ]], { config.Batch })
    if not expired then return end
    local known, rows = db('query', [[
        SELECT id, buyer_id, bank_id, budget_minor, state, attempts, settled_quantity, spent_minor FROM frontier_trade_requests
        WHERE state IN ('funding','refund') AND retry_at <= UTC_TIMESTAMP()
        ORDER BY retry_at, id LIMIT ?
    ]], { config.Batch })
    if known then for _, row in ipairs(rows) do step(row) end end
end

MySQL.ready(function()
    while true do
        local ok = pcall(tick)
        if not ok then FrontierLib.Log('ERROR', resource, 'Trade worker failed') end
        Wait(config.WorkerIntervalMs)
    end
end)

local function notify(source, text)
    TriggerClientEvent('chat:addMessage', source, { args = { 'Frontier Handel', text } })
end

RegisterCommand('handelsgesuch', function(source, args)
    if source == 0 then return end
    local now, previous = GetGameTimer(), submitted[source]
    if previous and now >= previous and now - previous < 2000 then
        notify(source, 'Bitte warte kurz, bevor du ein weiteres Gesuch erstellst.')
        return
    end
    submitted[source] = now
    local market, item, quantity, price = args[1], args[2], tonumber(args[3]), tonumber(args[4])
    if not market or not item or not quantity or not price then
        notify(source, 'Verwendung: /handelsgesuch <Markt> <Ware> <Menge> <Cent je Stück> [Höchstpreis in Cent]')
        return
    end
    local ok, id = db('scalar', 'SELECT UUID()')
    if not ok then notify(source, 'Der Markt ist momentan nicht erreichbar.'); return end
    local accepted = create(source, id, market, item, quantity, price, args[5] and (tonumber(args[5]) or 0))
    if accepted then
        notify(source, 'Gesuch eingereicht. Die Budgetprüfung läuft. Vorgang: ' .. id)
    else
        notify(source, 'Das Gesuch konnte nicht bestätigt werden. Prüfe den Vorgang: ' .. id)
    end
end, false)

RegisterCommand('handelsstorno', function(source, args)
    if source == 0 then return end
    local ok = cancel(source, args[1])
    notify(source, ok and 'Die Rückzahlung wurde vorgemerkt.' or 'Dieses Gesuch kann nicht storniert werden.')
end, false)

RegisterCommand('handelsmarkt', function(source, args)
    if source == 0 then return end
    local ok, rows = list(args[1] or 'valentine')
    if not ok then notify(source, 'Dieser Markt ist momentan nicht verfügbar.'); return end
    if #rows == 0 then notify(source, 'Aktuell gibt es keine offenen Gesuche.'); return end
    for _, row in ipairs(rows) do
        notify(source, ('%s × %s, %s Cent je Stück | %s'):format(
            row.quantity, config.Products[row.item_id] or row.item_id, row.price_minor, row.id))
    end
end, false)

RegisterCommand('handelsstatus', function(source, args)
    if source == 0 or not reference(args[1]) then return end
    local character = core:GetPlayerCharacterId(source)
    if not character then return end
    local ok, row = db('single', 'SELECT state FROM frontier_trade_requests WHERE id = ? AND buyer_id = ?',
        { args[1], character })
    if core:GetPlayerCharacterId(source) ~= character then return end
    local labels = { funding = 'Budgetprüfung läuft', open = 'Veröffentlicht', refund = 'Rückzahlung läuft',
        closed = 'Abgeschlossen', rejected = 'Abgelehnt: Guthaben reicht nicht' }
    notify(source, ok and row and labels[row.state] or 'Dieser Vorgang ist nicht verfügbar.')
end, false)

AddEventHandler('playerDropped', function() submitted[tonumber(source) or 0] = nil end)
