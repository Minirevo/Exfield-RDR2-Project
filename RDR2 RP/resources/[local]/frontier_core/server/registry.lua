Frontier = Frontier or {}

Frontier.Core = Frontier.Core or {}
Frontier.Core.Players = {}
Frontier.Core.Callbacks = {}
Frontier.Core.Ready = false

local function copyPlayerRecord(record)
    if not record then
        return nil
    end

    local copy = {}
    for key, value in pairs(record) do
        copy[key] = value
    end
    return copy
end

function Frontier.GetPlayer(source)
    source = tonumber(source)
    if not FrontierLib.IsValidSource(source) then
        return nil
    end

    return copyPlayerRecord(Frontier.Core.Players[source])
end

function Frontier.GetPlayers()
    local result = {}
    for source, record in pairs(Frontier.Core.Players) do
        result[source] = copyPlayerRecord(record)
    end
    return result
end

function Frontier.IsPlayerLoaded(source)
    source = tonumber(source)
    return FrontierLib.IsValidSource(source) and Frontier.Core.Players[source] ~= nil
end

function Frontier.Core.RegisterPlayer(data)
    if type(data) ~= 'table' or not FrontierLib.IsValidSource(tonumber(data.source)) then
        return false, 'invalid_player_data'
    end

    local source = tonumber(data.source)
    local previous = Frontier.Core.Players[source]

    local record = {
        source = source,
        identifier = data.identifier,
        license = data.license,
        characterId = data.characterId and tostring(data.characterId) or nil,
        firstname = data.firstname,
        lastname = data.lastname,
        name = data.name,
        group = data.group or 'user',
        job = data.job,
        jobGrade = data.jobGrade,
        jobLabel = data.jobLabel,
        loadedAt = previous and previous.loadedAt or os.time(),
        updatedAt = os.time(),
        framework = 'vorp',
    }

    Frontier.Core.Players[source] = record
    return true, copyPlayerRecord(record)
end

function Frontier.Core.RemovePlayer(source, reason)
    source = tonumber(source)
    if not FrontierLib.IsValidSource(source) then
        return false
    end

    local record = Frontier.Core.Players[source]
    if not record then
        return false
    end

    Frontier.Core.Players[source] = nil
    TriggerEvent('frontier:playerUnloaded', copyPlayerRecord(record), reason or 'unknown')
    return true
end

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
