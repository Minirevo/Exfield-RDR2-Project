local Core = Frontier.Core

local function callable(value)
    return type(value) == 'function' or type(value) == 'table'
        and (value.__cfx_functionReference ~= nil
            or type(getmetatable(value)) == 'table' and type(getmetatable(value).__call) == 'function')
end

local function property(value)
    if not callable(value) then return value end
    local ok, result = pcall(function() return value() end)
    if ok then return result end
end

local function text(value)
    if type(value) == 'string' and value ~= '' then return value end
end

local function getCore()
    local ok, api = pcall(function() return exports.vorp_core:GetCore() end)
    if not ok or type(api) ~= 'table' or api.getUser == nil then
        return nil, 'vorp_api_unavailable'
    end
    return api
end

local provider = { name = 'vorp' }

function provider.status()
    local api, issue = getCore()
    return api ~= nil, issue
end

function provider.read(id)
    local api, issue = getCore()
    if not api then return nil, issue end
    -- Call through a closure to support Cfx function reference tables.
    local ok, user = pcall(function() return api.getUser(id) end)
    if not ok then return nil, 'vorp_get_user_failed' end
    if type(user) ~= 'table' then return nil, 'provider_user_unavailable' end

    local character = property(user.getUsedCharacter)
    if type(character) ~= 'table' then return nil, 'character_not_selected' end
    local external = character.charIdentifier or character.charidentifier or character.CharId
    if type(external) == 'number' and external > 0 and external <= 9007199254740991
        and FrontierLib.IsInteger(external) then
        external = ('%.0f'):format(external)
    end
    if type(external) ~= 'string' or external == '' then return nil, 'character_not_selected' end

    local first = text(character.firstname or character.firstName or character.FirstName)
    local last = text(character.lastname or character.lastName or character.LastName)
    return {
        providerCharacterId = external,
        identifier = text(character.identifier) or text(property(user.getIdentifier)),
        license = GetPlayerIdentifierByType(id, 'license'),
        firstname = first,
        lastname = last,
        name = first and last and (first .. ' ' .. last) or first or last,
        dateOfBirth = text(character.dateOfBirth or character.dob),
        gender = text(character.gender),
        group = text(property(user.getGroup)) or text(character.group or character.Group),
        job = text(character.job or character.Job),
        jobGrade = tonumber(character.jobgrade or character.jobGrade or character.Grade),
        jobLabel = text(character.joblabel or character.jobLabel or character.JobLabel),
    }
end

Core.Provider = provider

AddEventHandler('vorp:SelectedCharacter', function(playerSource)
    -- Only the source is a notification. Resolve all identity fields from the provider.
    Core.ScheduleSync(playerSource, provider)
end)

AddEventHandler('onResourceStart', function(name)
    if name == 'vorp_core' then Core.SyncOnline(provider) end
end)

AddEventHandler('onResourceStop', function(name)
    if name == 'vorp_core' then Core.EndProviderSessions(provider) end
end)
