Frontier.Core.VORP = {
    available = false,
    core = nil,
}

local function getVorpCore()
    if Frontier.Core.VORP.core then
        return Frontier.Core.VORP.core
    end

    local ok, core = pcall(function()
        return exports.vorp_core:GetCore()
    end)

    if ok and type(core) == 'table' then
        Frontier.Core.VORP.core = core
        Frontier.Core.VORP.available = true
        return core
    end

    return nil
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

    local core = getVorpCore()
    if not core or type(core.getUser) ~= 'function' then
        return false, 'vorp_core_api_unavailable'
    end

    local ok, user = pcall(core.getUser, source)
    if not ok or type(user) ~= 'table' then
        return false, 'vorp_user_unavailable'
    end

    local character = user.getUsedCharacter
    if type(character) == 'function' then
        local success, data = pcall(character)
        character = success and data or nil
    end

    local charData = normalizeCharacter(character)
    if not charData or not charData.characterId then
        return false, 'character_not_selected'
    end

    local identifier = safeCall(user, 'getIdentifier')
    local license = GetPlayerIdentifierByType(source, 'license')

    local registered, result = Frontier.Core.RegisterPlayer({
        source = source,
        identifier = identifier,
        license = license,
        characterId = charData.characterId,
        firstname = charData.firstname,
        lastname = charData.lastname,
        name = charData.name,
        group = charData.group or safeCall(user, 'getGroup') or 'user',
        job = charData.job,
        jobGrade = charData.jobGrade,
        jobLabel = charData.jobLabel,
    })

    if registered then
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

    -- VORP fires this event when the character is selected. Wait one tick so
    -- the core's selected-character state is fully established before querying.
    CreateThread(function()
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
        for _, playerSource in ipairs(GetPlayers()) do
            Frontier.Core.VORP.SyncPlayer(tonumber(playerSource))
        end
    end)
end)
