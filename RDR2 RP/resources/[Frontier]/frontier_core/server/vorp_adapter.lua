Frontier.Core.VORP = {
    available = false,
    core = nil,
    lastError = 'not_initialized',
}

local function getVorpCore()
    -- Always ask the export for the current API object. Do not permanently cache
    -- an incomplete object: VORP may still be initializing when this resource starts.
    local ok, coreOrError = pcall(function()
        return exports.vorp_core:GetCore()
    end)

    if not ok then
        Frontier.Core.VORP.core = nil
        Frontier.Core.VORP.available = false
        Frontier.Core.VORP.lastError = 'get_core_export_failed'
        return nil, 'get_core_export_failed'
    end

    if type(coreOrError) ~= 'table' then
        Frontier.Core.VORP.core = nil
        Frontier.Core.VORP.available = false
        Frontier.Core.VORP.lastError = 'invalid_core_object'
        return nil, 'invalid_core_object'
    end

    if type(coreOrError.getUser) ~= 'function' then
        Frontier.Core.VORP.core = nil
        Frontier.Core.VORP.available = false
        Frontier.Core.VORP.lastError = 'missing_getUser'
        return nil, 'missing_getUser'
    end

    Frontier.Core.VORP.core = coreOrError
    Frontier.Core.VORP.available = true
    Frontier.Core.VORP.lastError = nil
    return coreOrError
end

Frontier.Core.VORP.GetCore = getVorpCore

local function safeCall(object, methodName)
    if type(object) ~= 'table' or type(object[methodName]) ~= 'function' then
        return nil
    end

    local ok, value = pcall(object[methodName])
    return ok and value or nil
end

local function normalizeCharacter(character)
    if type(character) ~= 'table' then
        return nil
    end

    local first = character.firstname or character.firstName or character.FirstName
    local last = character.lastname or character.lastName or character.LastName
    local charId = character.charIdentifier or character.charidentifier or character.CharId

    if charId == nil then
        return nil
    end

    return {
        characterId = charId,
        firstname = first,
        lastname = last,
        name = (first and last) and (tostring(first) .. ' ' .. tostring(last)) or nil,
        group = character.group or character.Group,
        job = character.job or character.Job,
        jobGrade = character.jobGrade or character.jobgrade or character.Grade,
        jobLabel = character.jobLabel or character.joblabel or character.JobLabel,
    }
end

function Frontier.Core.VORP.SyncPlayer(source)
    source = tonumber(source)
    if not FrontierLib.IsValidSource(source) then
        return false, 'invalid_source'
    end

    local core, coreError = getVorpCore()
    if not core then
        return false, coreError or 'vorp_core_api_unavailable'
    end

    local ok, user = pcall(core.getUser, source)
    if not ok then
        return false, 'vorp_getUser_failed'
    end

    if type(user) ~= 'table' then
        return false, 'vorp_user_unavailable'
    end

    -- VORP 3.4 exposes getUsedCharacter as a character table on the user
    -- object, not as a function. Keep function support for compatible forks.
    local character = user.getUsedCharacter
    if type(character) == 'function' then
        local success, data = pcall(character)
        character = success and data or nil
    end

    local charData = normalizeCharacter(character)
    if not charData then
        return false, 'character_not_selected'
    end

    local identifier = safeCall(user, 'getIdentifier')
    local license = GetPlayerIdentifierByType(source, 'license')
    local playerName = charData.name or GetPlayerName(source) or ('Player %s'):format(source)
    local previous = Frontier.GetPlayer(source)

    if previous and previous.characterId ~= tostring(charData.characterId) then
        TriggerEvent('frontier:playerUnloaded', previous, 'character_switch')
    end

    local registered, result = Frontier.Core.RegisterPlayer({
        source = source,
        identifier = identifier,
        license = license,
        characterId = charData.characterId,
        firstname = charData.firstname,
        lastname = charData.lastname,
        name = playerName,
        group = user.getGroup or charData.group or 'user',
        job = charData.job,
        jobGrade = charData.jobGrade,
        jobLabel = charData.jobLabel,
    })

    if registered and (not previous or previous.characterId ~= result.characterId) then
        TriggerEvent('frontier:playerLoaded', result)
        FrontierLib.Log('INFO', 'frontier_core', 'Player/character registered', {
            source = source,
            characterId = result.characterId,
            name = result.name,
        })
    end

    return registered, result
end

AddEventHandler('vorp:SelectedCharacter', function(source)
    source = tonumber(source)
    if not source then
        return
    end

    CreateThread(function()
        -- VORP updates its selected character before emitting this event.
        Wait(0)
        local ok, reason = Frontier.Core.VORP.SyncPlayer(source)
        if not ok then
            FrontierLib.Log('WARN', 'frontier_core', 'Could not sync selected character', {
                source = source,
                reason = reason,
            })
        end
    end)
end)

AddEventHandler('playerDropped', function(reason)
    Frontier.Core.RemovePlayer(source, reason or 'disconnected')
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    CreateThread(function()
        Wait(1000)
        local core, coreError = getVorpCore()
        if not core then
            FrontierLib.Log('ERROR', 'frontier_core', 'VORP API validation failed during player sync', {
                reason = coreError,
            })
            return
        end

        for _, playerSource in ipairs(GetPlayers()) do
            local ok, reason = Frontier.Core.VORP.SyncPlayer(tonumber(playerSource))
            if not ok then
                FrontierLib.Log('WARN', 'frontier_core', 'Could not sync connected player', {
                    source = tonumber(playerSource),
                    reason = reason,
                })
            end
        end
    end)
end)
