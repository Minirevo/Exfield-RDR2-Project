local focused, active, ready = false, nil, false
local sequence = 0

local function close()
    active = nil
    if focused then SetNuiFocus(false, false) end
    focused = false
    SendNUIMessage({ type = 'close' })
end

local function load(market)
    sequence = sequence + 1
    local request = sequence
    active = request
    TriggerServerEvent('frontier_trade:marketSnapshot', request, market)
    SetTimeout(10000, function()
        if active ~= request then return end
        active = nil
        if focused then
            SendNUIMessage({ type = 'status', message = 'Der Markt antwortet gerade nicht.' })
        else
            TriggerEvent('chat:addMessage', { args = { 'Frontier Handel', 'Kein Markt verfügbar. Ist dein Charakter geladen?' } })
        end
    end)
end

RegisterCommand('handel', function()
    if focused then close(); return end
    if not ready or active or (type(IsNuiFocused) == 'function' and IsNuiFocused()) then return end
    load('valentine')
end, false)

RegisterNetEvent('frontier_trade:marketSnapshot', function(request, data)
    if source ~= 65535 or active ~= request then return end
    active = nil
    if not focused then SetNuiFocus(true, true); SetNuiFocusKeepInput(false); focused = true end
    SendNUIMessage({ type = 'snapshot', data = data })
end)
RegisterNetEvent('frontier_trade:closeMarket', function()
    if source == 65535 then close() end
end)
RegisterNUICallback('ready', function(_, cb) ready = true; if focused then close() end; cb({ ok = true }) end)
RegisterNUICallback('close', function(_, cb) close(); cb({ ok = true }) end)
RegisterNUICallback('refresh', function(data, cb)
    local allowed = focused and type(data) == 'table' and type(data.market) == 'string'
        and #data.market < 48 and data.market:match('^[a-z_]+$')
    if allowed then load(data.market) end
    cb({ ok = allowed and true or false })
end)

local actions = { create = { 'handelsgesuch', 4, 5 }, accept = { 'handelannehmen', 2 },
    deliver = { 'handelliefern', 2 }, claim = { 'handelsabholung', 1 }, cancel = { 'handelsstorno', 1 }, cancelContract = { 'handelsvertragsstorno', 1 },
    sell = { 'handelsangebot', 4 }, buy = { 'handelskaufen', 2 },
    cancelOffer = { 'handelsangebotstorno', 1 }, claimSale = { 'handelskaufabholung', 1 } }
RegisterNUICallback('action', function(data, cb)
    local spec = focused and type(data) == 'table' and actions[data.action]
    local args = spec and data.args
    if type(args) ~= 'table' or #args ~= spec[2] and #args ~= spec[3] then cb({ ok = false }); return end
    for _, arg in ipairs(args) do
        if type(arg) ~= 'string' or #arg > 48 or not arg:match('^[a-z0-9_%-]+$') then cb({ ok = false }); return end
    end
    ExecuteCommand(spec[1] .. ' ' .. table.concat(args, ' '))
    cb({ ok = true })
end)
AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() and focused then SetNuiFocus(false, false) end
end)

RegisterNUICallback('propertyMarket',function(_,cb)
    if not focused or GetResourceState('frontier_property')~='started' then cb({ok=false});return end
    close(); ExecuteCommand('propertymarket'); cb({ok=true})
end)
