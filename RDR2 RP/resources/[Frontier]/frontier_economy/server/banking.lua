local Bank = FrontierBank
local core = exports.frontier_core
local views, epochs, busy, recent = {}, {}, {}, {}
local maxCounter = 2147483647

local function epoch(playerSource)
    if not epochs[playerSource] then epochs[playerSource] = {} end
    return epochs[playerSource]
end

local function current(playerSource, view)
    return views[playerSource] == view and Economy.IsCurrentCharacter(playerSource, view.character)
end

local function close(playerSource, notify)
    local view = views[playerSource]
    views[playerSource] = nil
    if notify and view then
        TriggerClientEvent(Bank.Event .. 'invalidated', playerSource, view.id, Bank.Text.character_changed)
    end
end

local function reply(playerSource, viewId, request, payload)
    TriggerClientEvent(Bank.Event .. 'result', playerSource, viewId, request, payload)
end

local function errorResult(code)
    return { ok = false, message = Bank.Text[code] or Bank.Text.failed }
end

local function validCounter(value)
    return Economy.PositiveInteger(value, maxCounter)
end

local function admit(playerSource, viewId, request, run)
    if not validCounter(playerSource) or not validCounter(viewId) or not validCounter(request) then return end
    local now, last = GetGameTimer(), recent[playerSource]
    if busy[playerSource] or (last and now >= last and now - last < 200) then
        reply(playerSource, viewId, request, { ok = false, busy = true, message = Bank.Text.busy })
        return
    end
    local token = {}
    recent[playerSource], busy[playerSource] = now, token
    local ok, issue = pcall(run)
    if busy[playerSource] == token then busy[playerSource] = nil end
    if not ok then
        FrontierLib.Log('ERROR', Economy.Resource, 'Unexpected banking request failure',
            { errorType = type(issue) })
        local view = views[playerSource]
        if view and view.id == viewId then
            if view.pending then view.pending.uncertain = true end
            local result = errorResult(view.pending and 'uncertain' or 'database_error')
            result.retry = view.pending ~= nil
            reply(playerSource, viewId, request, result)
        end
    end
end

local function snapshot(playerSource, view)
    local ok, accounts = Economy.GetCharacterAccounts(playerSource)
    if not ok then return false, accounts end
    if accounts.characterId ~= view.character or not current(playerSource, view) then
        return false, 'character_changed'
    end
    return true, {
        name = view.name,
        cash = accounts.cash.balance_minor,
        bank = accounts.bank.balance_minor,
        currency = accounts.cash.currency,
    }
end

RegisterNetEvent(Bank.Event .. 'open', function(viewId, request)
    local playerSource = tonumber(source)
    admit(playerSource, viewId, request, function()
        local player = core:GetPlayer(playerSource)
        if not player then
            reply(playerSource, viewId, request, errorResult('character_unavailable'))
            return
        end
        local view = { id = viewId, character = player.frontierCharacterId, name = player.name, next = 1 }
        views[playerSource] = view
        local gotTicket, ticket = Economy.Db('scalar', 'SELECT UUID()')
        if not current(playerSource, view) then return end
        if not gotTicket or type(ticket) ~= 'string' or #ticket ~= 36 or not ticket:match('^[a-f0-9-]+$') then
            close(playerSource)
            reply(playerSource, viewId, request, errorResult('database_error'))
            return
        end
        local ok, data = snapshot(playerSource, view)
        if not current(playerSource, view) then return end
        if not ok then
            close(playerSource)
            reply(playerSource, viewId, request, errorResult(data))
            return
        end
        view.ticket = ticket
        reply(playerSource, viewId, request, { ok = true, ticket = ticket, next = view.next, balances = data })
    end)
end)

RegisterNetEvent(Bank.Event .. 'close', function(viewId)
    local playerSource = tonumber(source)
    local view = views[playerSource]
    if view and view.id == viewId then close(playerSource) end
end)

local function historyRows(rows)
    local result = {}
    for i, row in ipairs(rows) do
        local action, reason = row.kind, nil
        if type(row.actor) == 'string' and row.actor:sub(1, 5) == 'bank:' then
            if row.metadata_json == '{"action":"deposit"}' then
                action = 'deposit'
            elseif row.metadata_json == '{"action":"withdraw"}' then
                action = 'withdraw'
            else
                reason = row.reason
            end
        end
        result[i] = { date = row.created_at, kind = action, direction = row.entry_type,
            amount = row.amount_minor, balance = row.balance_after, reason = reason }
    end
    return result
end

local function cents(input)
    if type(input) ~= 'string' or #input > 16 then return nil end
    local whole, fraction = input:match('^([0-9]+)[.,]([0-9][0-9]?)$')
    if not whole then whole, fraction = input:match('^([0-9]+)$'), '' end
    if not whole or #whole > 11 then return nil end
    local amount = tonumber(whole) * 100 + tonumber((fraction .. '00'):sub(1, 2))
    if Economy.PositiveInteger(amount, Economy.MaxMinor) then return amount end
end

local function recipientId(input)
    if type(input) == 'string' and #input <= 10 and input:match('^[0-9]+$') then
        local id = tonumber(input)
        if validCounter(id) then return id end
    end
end

local function createOrder(playerSource, view, action, data)
    if type(data) ~= 'table' then return nil, 'invalid_request' end
    for key in pairs(data) do
        if key ~= 'amount' and (action ~= 'transfer' or (key ~= 'recipient' and key ~= 'reason')) then
            return nil, 'invalid_request'
        end
    end
    local amount = cents(data.amount)
    if not amount then return nil, 'invalid_amount' end

    local order = { action = action, amount = amount, options = {
        key = view.ticket .. ':' .. view.next,
        reason = action == 'deposit' and 'Einzahlung' or 'Auszahlung',
        metadataJson = ('{"action":"%s"}'):format(action),
    } }
    if action ~= 'transfer' then return order end

    local recipient = recipientId(data.recipient)
    if not recipient then return nil, 'invalid_recipient' end
    local character = core:GetPlayerCharacterId(recipient)
    if not character then return nil, 'offline_recipient' end
    if recipient == playerSource or character == view.character then return nil, 'same_account' end

    local reason = data.reason
    if reason ~= nil and (type(reason) ~= 'string' or #reason > 160 or not utf8.len(reason) or reason:find('%c')) then
        return nil, 'invalid_reason'
    end
    reason = FrontierLib.Trim(reason)
    order.options.reason = reason ~= '' and reason or Bank.Text.default_reason
    order.recipient, order.recipientCharacter, order.recipientEpoch = recipient, character, epoch(recipient)
    return order
end

local function submit(playerSource, view, order)
    local function recipientCurrent()
        return epochs[order.recipient] == order.recipientEpoch
            and Economy.IsCurrentCharacter(order.recipient, order.recipientCharacter)
    end
    local function guard(sender, recipient)
        return sender == view.character and current(playerSource, view)
            and (not order.recipient or (recipient == order.recipientCharacter and recipientCurrent()))
    end
    local actor = 'bank:' .. view.character
    if order.action == 'transfer' then
        if not recipientCurrent() then return false, 'recipient_changed' end
        local ok, result = Economy.TransferCharacters(actor, playerSource, order.recipient,
            order.amount, order.options, guard)
        if not ok and result == 'character_changed' and current(playerSource, view) then
            return false, 'recipient_changed'
        end
        return ok, result
    end
    local from = order.action == 'deposit' and 'cash' or 'bank'
    local to = from == 'cash' and 'bank' or 'cash'
    return Economy.MoveCharacterFunds(actor, playerSource, from, to, order.amount, order.options, guard)
end

local function mutate(playerSource, view, action, sequence, data)
    if view.last and sequence == view.last.sequence then
        local result = view.last.result
        if result.ok then
            local loaded, balances = snapshot(playerSource, view)
            result.balances = loaded and balances or nil
            result.message = loaded and Bank.Text[result.action] or Bank.Text.refresh_failed
        end
        return result
    end
    if sequence ~= view.next then return errorResult('stale_request') end

    local order, issue = view.pending
    if order then
        if action ~= order.action then
            local result = errorResult('uncertain')
            result.retry = true
            return result
        end
    else
        order, issue = createOrder(playerSource, view, action, data)
    end
    local result
    if not order then
        result = errorResult(issue)
    else
        view.pending = order
        local ok, outcome = submit(playerSource, view, order)
        if not current(playerSource, view) then return errorResult('character_changed') end
        if not ok and outcome == 'database_error' then
            order.uncertain = true
            result = errorResult('uncertain')
            result.retry = true
            return result
        end
        if not ok and order.uncertain and (outcome == 'recipient_changed' or outcome == 'character_changed'
            or outcome == 'character_unavailable') then
            result = errorResult('unresolved')
            result.blocked = true
            return result
        end
        if ok then
            result = { ok = true, message = Bank.Text[order.action], action = order.action }
        else
            if outcome == 'insufficient_funds' then
                outcome = order.action == 'deposit' and 'insufficient_cash' or 'insufficient_bank'
            elseif outcome == 'character_unavailable' and order.action == 'transfer' then
                outcome = 'offline_recipient'
            end
            result = errorResult(outcome)
        end
    end
    view.next = sequence + 1
    view.pending = nil
    result.next = view.next
    view.last = { sequence = sequence, result = result }
    if result.ok then
        local loaded, balances = snapshot(playerSource, view)
        if loaded then result.balances = balances else result.message = Bank.Text.refresh_failed end
    end
    return result
end

RegisterNetEvent(Bank.Event .. 'request', function(viewId, request, ticket, action, sequence, data)
    local playerSource = tonumber(source)
    admit(playerSource, viewId, request, function()
        local view = views[playerSource]
        if not view or view.id ~= viewId or not view.ticket or view.ticket ~= ticket or not current(playerSource, view) then
            reply(playerSource, viewId, request, errorResult('stale_request'))
            return
        end
        local result
        if action == 'balances' then
            local ok, value = snapshot(playerSource, view)
            result = ok and { ok = true, balances = value } or errorResult(value)
        elseif action == 'history' and (data == 'cash' or data == 'bank') then
            local ok, value = Economy.GetCharacterTransactions(playerSource, data)
            result = ok and { ok = true, history = historyRows(value) } or errorResult(value)
        elseif validCounter(sequence) and (action == 'deposit' or action == 'withdraw' or action == 'transfer') then
            result = mutate(playerSource, view, action, sequence, data)
        else
            result = errorResult('invalid_request')
        end
        if current(playerSource, view) then reply(playerSource, viewId, request, result) end
    end)
end)

AddEventHandler('frontier:playerUnloaded', function(player)
    epochs[player.source] = nil
    close(player.source, true)
end)

AddEventHandler('playerDropped', function()
    local playerSource = tonumber(source)
    if not playerSource then return end
    close(playerSource)
    busy[playerSource], recent[playerSource], epochs[playerSource] = nil, nil, nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= 'frontier_core' then return end
    for playerSource in pairs(views) do close(playerSource, true) end
    epochs = {}
end)
