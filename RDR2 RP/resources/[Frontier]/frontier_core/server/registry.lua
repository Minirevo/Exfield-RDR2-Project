Frontier = Frontier or {}
Frontier.Core = { Players = {}, Callbacks = {}, Ready = false }
local Core = Frontier.Core
local slots = {}

function Core.Copy(value)
    if type(value) ~= 'table' then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = Core.Copy(item) end
    return copy
end

local function sourceId(value)
    local id = tonumber(value)
    if FrontierLib.IsValidSource(id) and id <= 2147483647 then return id end
end

local function active(value)
    local id = sourceId(value)
    return id and Core.Players[id]
end

function Frontier.GetPlayer(value)
    return Core.Copy(active(value))
end

function Frontier.GetPlayers()
    return Core.Copy(Core.Players)
end

function Frontier.IsPlayerLoaded(value)
    return active(value) ~= nil
end

function Frontier.GetPlayerCharacterId(value)
    local record = active(value)
    return record and record.frontierCharacterId
end

local function assignData(record, data)
    record.characterData = Core.Copy(data)
    record.firstname = data.firstname
    record.lastname = data.lastname
    record.name = data.name
    record.updatedAt = os.time()
end

function Core.RefreshCharacter(data)
    for _, record in pairs(Core.Players) do
        if record.frontierCharacterId == data.frontierCharacterId
            and record.characterData.version <= data.version then
            assignData(record, data)
        end
    end
end

local function endSession(id, reason)
    local previous = Core.Players[id]
    Core.Players[id] = nil
    if previous then
        previous.state = 'ending'
        TriggerEvent('frontier:playerUnloaded', Core.Copy(previous), reason)
    end
    return previous
end

local function getSlot(id)
    if not slots[id] then slots[id] = { connectedAt = os.time() } end
    return slots[id]
end

local function sync(id, slot, token, provider)
    if slots[id] ~= slot or slot.token ~= token or not GetPlayerName(id) then return end
    local selected, issue = provider.read(id)
    if slots[id] ~= slot or slot.token ~= token then return end

    local current = Core.Players[id]
    if selected and current and current.provider == provider.name
        and current.providerCharacterId == selected.providerCharacterId
        and current.identifier == selected.identifier and current.license == selected.license then
        return
    end
    if current then
        slot.previous = current
        endSession(id, selected and 'character_switch' or 'provider_unavailable')
    end

    if not selected then
        if issue ~= 'character_not_selected' and issue ~= 'provider_user_unavailable' then
            SetTimeout(FrontierConfig.SessionRetryMs, function() sync(id, slot, token, provider) end)
        end
        return
    end

    local ok, data = Core.ResolveCharacter(provider.name, selected)
    if slots[id] ~= slot or slot.token ~= token or not GetPlayerName(id) then return end
    if not ok then
        FrontierLib.Log('WARN', GetCurrentResourceName(), 'Character session could not load', { reason = data })
        if data == 'database_error' then
            SetTimeout(FrontierConfig.SessionRetryMs, function() sync(id, slot, token, provider) end)
        end
        return
    end

    local previous = slot.previous
    slot.previous = nil
    local record = {
        source = id,
        frontierCharacterId = data.frontierCharacterId,
        characterId = data.frontierCharacterId,
        provider = provider.name,
        framework = provider.name,
        providerCharacterId = selected.providerCharacterId,
        identifier = selected.identifier,
        license = selected.license,
        group = selected.group or 'user',
        job = selected.job,
        jobGrade = selected.jobGrade,
        jobLabel = selected.jobLabel,
        state = 'active',
        connectedAt = slot.connectedAt,
        loadedAt = os.time(),
    }
    assignData(record, data)
    Core.Players[id] = record
    TriggerEvent('frontier:playerLoaded', Core.Copy(record))
    if Core.Players[id] == record and previous and previous.frontierCharacterId ~= record.frontierCharacterId then
        TriggerEvent('frontier:characterSwitched', Core.Copy(previous), Core.Copy(record))
    end
end

function Core.ScheduleSync(value, provider)
    local id = sourceId(value)
    if not id then return end
    local slot = getSlot(id)
    local token = {}
    slot.token = token
    SetTimeout(0, function() sync(id, slot, token, provider) end)
end

function Core.SyncOnline(provider)
    for _, id in ipairs(GetPlayers()) do Core.ScheduleSync(id, provider) end
end

function Core.EndProviderSessions(provider)
    for id, slot in pairs(slots) do
        slot.token = nil
        slot.previous = nil
        if Core.Players[id] and Core.Players[id].provider == provider.name then
            endSession(id, 'provider_stopped')
        end
    end
end

AddEventHandler('playerJoining', function()
    local id = sourceId(source)
    if id then
        slots[id] = { connectedAt = os.time() }
        endSession(id, 'source_reused')
    end
end)

AddEventHandler('playerDropped', function()
    local id = sourceId(source)
    if id then
        slots[id] = nil
        endSession(id, 'disconnected')
    end
end)

function Frontier.RegisterCallback(name, callback)
    if type(name) ~= 'string' or name == '' or type(callback) ~= 'function' then
        return false, 'invalid_callback'
    end

    if Frontier.Core.Callbacks[name] then
        return false, 'callback_already_registered'
    end

    Frontier.Core.Callbacks[name] = callback
    return true
end

function Frontier.TriggerCallback(name, ...)
    local callback = Frontier.Core.Callbacks[name]
    if not callback then
        return false, 'callback_not_found'
    end

    local ok, result = pcall(callback, ...)
    if not ok then
        FrontierLib.Log('ERROR', 'frontier_core', ('Callback "%s" failed'):format(name), {
            error = result,
        })
        return false, 'callback_error'
    end

    return true, result
end
