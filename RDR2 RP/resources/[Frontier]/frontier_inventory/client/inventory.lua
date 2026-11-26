local Config = InventoryConfig
local E = 'frontier_inventory:'
local active, awaiting, pageReady, held, ticket, opening, request
local view, activeId = 0, nil
local drops = {}
local dropTime = 0
local keys = { F5 = 0x74, F6 = 0x75, F7 = 0x76, F8 = 0x77, F9 = 0x78, F10 = 0x79, F11 = 0x7A }
local chosen = GetResourceKvpString('inventory_open_key') or Config.DefaultKey
local keyMapping = false
local marker = 0x94FDAE17 -- prop_mk_cylinder

local function notice(text)
    TriggerEvent('chat:addMessage', { args = { 'Frontier Inventar', text } })
end

local function otherNuiFocused()
    return not active and type(IsNuiFocused) == 'function' and IsNuiFocused()
end

local function close()
    local hadFocus = active
    if ticket then TriggerServerEvent(E .. 'close', ticket) end
    active, awaiting, held, ticket, opening, request, activeId = nil, nil, nil, nil, nil, nil, nil
    if hadFocus then SetNuiFocus(false, false) end
    SendNUIMessage({ type = 'close' })
end

local function present(data)
    if otherNuiFocused() then
        close()
        notice('Schließe zuerst das andere Fenster.')
        return
    end
    held = nil
    active = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ type = 'open', data = data })
end

local function open()
    if active or awaiting or held or otherNuiFocused() or IsPauseMenuActive() then return end
    view = view + 1
    local requested = view
    opening, awaiting = requested, true
    TriggerServerEvent(E .. 'open', requested)
    SetTimeout(Config.RequestTimeoutMs, function()
        if opening ~= requested or active then return end
        close()
        notice('Das Inventar antwortet gerade nicht.')
    end)
end

RegisterCommand(Config.Command, open, false)

if type(RegisterKeyMapping) == 'function' then
    keyMapping = pcall(RegisterKeyMapping, Config.Command, 'Frontier-Inventar öffnen', 'keyboard', Config.DefaultKey:lower())
end
if not keyMapping and type(RegisterRawKeymap) == 'function' then
    for name, key in pairs(keys) do
        RegisterRawKeymap('frontier_inventory_' .. name, nil, function()
            if chosen == name then open() end
        end, key, true)
    end
end

RegisterCommand(Config.KeyCommand, function(_, args)
    if keyMapping then notice('Ändere die Frontier-Belegung in den Tastatureinstellungen.'); return end
    local key = (args[1] or ''):upper()
    if not keys[key] or key == Config.PickupKey then
        notice(('Wähle eine Taste von F5 bis F11. %s ist fürs Aufheben reserviert.'):format(Config.PickupKey))
        return
    end
    chosen = key
    SetResourceKvp('inventory_open_key', key)
    notice(('Inventartaste gespeichert (%s).'):format(key))
end, false)

RegisterNetEvent(E .. 'open', function(id, token, data)
    if source ~= 65535 or (id ~= 0 and (not awaiting or id ~= opening)) then return end
    awaiting, opening, ticket, request, activeId = nil, nil, token, nil, id
    if pageReady then
        present(data)
    else
        held = data
        SetTimeout(Config.RequestTimeoutMs, function()
            if held ~= data then return end
            close()
            notice('Die Inventaroberfläche konnte nicht geladen werden.')
        end)
    end
end)

RegisterNetEvent(E .. 'result', function(id, seq, result)
    if source ~= 65535 then return end
    if seq == 0 then
        if id == opening then close(); notice(result.message) end
        return
    end
    if not active or id ~= activeId or not request or seq ~= request.seq then return end
    request = nil
    result.type, result.sequence = 'result', seq
    SendNUIMessage(result)
end)
RegisterNetEvent(E .. 'close', function()
    if source == 65535 and (active or awaiting or held) then close() end
end)
RegisterNetEvent(E .. 'notice', function(text)
    if source == 65535 then notice(text) end
end)
RegisterNetEvent(E .. 'world', function(payload)
    if source ~= 65535 then return end
    drops, dropTime = type(payload) == 'table' and payload or {}, GetGameTimer()
end)

RegisterNUICallback('ready', function(_, cb)
    pageReady = true
    if active then close() end
    if held then present(held) end
    cb({ ok = true })
end)
RegisterNUICallback('close', function(_, cb) close(); cb({ ok = true }) end)
RegisterNUICallback('action', function(payload, cb)
    if not active or request or type(payload) ~= 'table' or type(payload.sequence) ~= 'number' then
        cb({ ok = false }); return
    end
    local seq = payload.sequence
    local pending = { seq = seq }
    request = pending
    TriggerServerEvent(E .. 'request', ticket, seq, payload.action, payload.data)
    SetTimeout(Config.RequestTimeoutMs, function()
        if request ~= pending then return end
        request = nil
        SendNUIMessage({ type = 'result', sequence = seq, ok = false, retry = true,
            message = 'Keine Antwort. Wiederhole denselben Auftrag.' })
    end)
    cb({ ok = true })
end)

CreateThread(function()
    while true do
        TriggerServerEvent(E .. 'world')
        Wait(Config.GroundUpdateMs)
    end
end)

local function closest()
    if GetGameTimer() - dropTime > Config.GroundUpdateMs * 3 then return end
    local where = GetEntityCoords(PlayerPedId())
    local nearest, limit = nil, Config.PickupDistance ^ 2
    for _, row in pairs(drops) do
        local d = (where.x - row.x)^2 + (where.y - row.y)^2 + (where.z - row.z)^2
        if d < limit then nearest, limit = row, d end
    end
    return nearest
end

if type(RegisterRawKeymap) == 'function' and keys[Config.PickupKey] then
    RegisterRawKeymap('frontier_inventory_pickup', nil, function()
        if active or awaiting or otherNuiFocused() or IsPauseMenuActive() then return end
        local item = closest()
        if item then TriggerServerEvent(E .. 'pickup', item.id) end
    end, keys[Config.PickupKey], true)
end

CreateThread(function()
    while true do
        local delay = 500
        if not active and next(drops) and GetGameTimer() - dropTime <= Config.GroundUpdateMs * 3 then
            local where = GetEntityCoords(PlayerPedId())
            for _, drop in pairs(drops) do
                if (where.x-drop.x)^2 + (where.y-drop.y)^2 + (where.z-drop.z)^2 <= Config.VisibilityDistance^2 then
                    delay = 0
                    Citizen.InvokeNative(0x2A32FAA57B937173, marker, drop.x, drop.y, drop.z + 0.15,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.28, 0.28, 0.18,
                        220, 220, 220, 145, 0, 0, 2, 0, 0, 0, 0)
                end
            end
        end
        Wait(delay)
    end
end)
AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() and active then SetNuiFocus(false, false) end
end)

-- Closes this UI before an authorized blueprint opens the property catalogue.
exports('CloseForProperty',function()
    if GetInvokingResource()=='frontier_property' and active then close() end
end)

-- Quick selection uses remappable commands; avoid overriding RedM's weapon keys.
for i=1,6 do
 local slot=i;local name='frontier_belt_'..slot
 RegisterCommand(name,function()
  if not active and not otherNuiFocused() and not IsPauseMenuActive() then TriggerServerEvent(E..'selectBelt',slot) end
 end,false)
 if type(RegisterKeyMapping)=='function' then pcall(RegisterKeyMapping,name,'Select toolbelt slot '..slot,'keyboard','') end
end
