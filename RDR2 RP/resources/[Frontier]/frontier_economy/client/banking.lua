local Bank = FrontierBank
local active, pending, ticket, waitingOpen
local viewId, requestId = 0, 0
local focused = false

local function notify(message)
    TriggerEvent('chat:addMessage', { args = { 'Frontier Bank', message } })
end

local function close()
    if active then TriggerServerEvent(Bank.Event .. 'close', active) end
    active, pending, ticket, waitingOpen = nil, nil, nil, nil
    if focused then
        focused = false
        SetNuiFocus(false, false)
        SendNUIMessage({ type = 'close' })
    end
end

local function begin(action, data, sequence, uiRequest)
    requestId = requestId + 1
    local request = { id = requestId, view = active, action = action, uiRequest = uiRequest }
    pending = request
    if action == 'open' then
        TriggerServerEvent(Bank.Event .. 'open', active, request.id)
    else
        TriggerServerEvent(Bank.Event .. 'request', active, request.id, ticket, action, sequence, data)
    end
    SetTimeout(Bank.TimeoutMs, function()
        if pending ~= request then return end
        pending = nil
        if request.action == 'open' then
            close()
            notify(Bank.Text.database_error)
        else
            local mutation = action == 'deposit' or action == 'withdraw' or action == 'transfer'
            SendNUIMessage({ type = 'result', uiRequest = request.uiRequest, ok = false, retry = mutation,
                message = mutation and Bank.Text.uncertain or Bank.Text.database_error })
        end
    end)
end

local function present(result)
    waitingOpen = nil
    focused = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ type = 'open', balances = result.balances, next = result.next })
end

RegisterCommand(Bank.Command, function()
    if active then return end
    viewId = viewId + 1
    active = viewId
    begin('open')
end, false)

RegisterNetEvent(Bank.Event .. 'result', function(view, id, result)
    if source ~= 65535 or view ~= active or not pending or pending.id ~= id or type(result) ~= 'table' then return end
    local request = pending
    local action = request.action
    pending = nil
    if action == 'open' then
        if not result.ok or not result.ticket or not result.balances then
            close()
            notify(result.message or Bank.Text.failed)
            return
        end
        ticket = result.ticket
        present(result)
        return
    end
    SendNUIMessage({ type = 'result', uiRequest = request.uiRequest, next = result.next,
        ok = result.ok, message = result.message, retry = result.retry,
        busy = result.busy, blocked = result.blocked, balances = result.balances, history = result.history })
end)

RegisterNetEvent(Bank.Event .. 'invalidated', function(view, message)
    if source ~= 65535 or view ~= active then return end
    close()
    notify(message)
end)

RegisterNUICallback('bankClose', function(_, cb)
    close()
    cb({ ok = true })
end)

RegisterNUICallback('bankRequest', function(payload, cb)
    if not focused or not ticket or pending then
        cb({ ok = false, message = Bank.Text.busy })
        return
    end
    if type(payload) ~= 'table' then
        cb({ ok = false, message = Bank.Text.invalid_request })
        return
    end
    begin(payload.action, payload.data, payload.sequence, payload.uiRequest)
    cb({ ok = true })
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() and focused then
        SetNuiFocus(false, false)
    end
end)
