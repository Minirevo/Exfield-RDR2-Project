local Core = Frontier.Core
local resource = GetCurrentResourceName()

local function database(method, statement, args)
    local ok, result = pcall(MySQL[method].await, statement, args)
    if not ok or (method == 'transaction' and result ~= true) then
        FrontierLib.Log('ERROR', resource, 'Character database operation failed', { method = method })
        return false, 'database_error'
    end
    return true, result
end

local function validText(value, limit)
    return type(value) == 'string' and #value <= limit and utf8.len(value) ~= nil
        and not value:find('%c') and FrontierLib.Trim(value) ~= ''
end

local function validDate(value)
    if type(value) ~= 'string' then return false end
    local year, month, day = value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    if not year or year < 1000 or month < 1 or month > 12 or day < 1 then return false end
    local days = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) then days[2] = 29 end
    return day <= days[month]
end

local function validObject(value)
    if type(value) ~= 'string' or #value > 8192 or not value:match('^%s*{')
        or not utf8.len(value) then
        return false
    end
    local ok, parsed = pcall(json.decode, value)
    return ok and type(parsed) == 'table'
end

local fields = {
    firstname = { column = 'firstname', limit = 96 },
    lastname = { column = 'lastname', limit = 96 },
    name = { column = 'full_name', limit = 193 },
    dateOfBirth = { column = 'date_of_birth', validate = validDate },
    gender = { column = 'gender', limit = 48 },
    metadataJson = { column = 'metadata_json', validate = validObject },
    attributesJson = { column = 'attributes_json', validate = validObject },
}

local function validField(field, value)
    if field.validate then return field.validate(value) end
    return validText(value, field.limit)
end

function Core.IsCharacterId(id)
    return type(id) == 'string' and #id == 34 and id:match('^f_[a-f0-9]+$') ~= nil
end

function Frontier.GetCharacterData(id)
    if not Core.IsCharacterId(id) then return false, 'invalid_character_id' end
    local ok, data = database('single', [[
        SELECT character_id AS frontierCharacterId, firstname, lastname, full_name AS name,
               DATE_FORMAT(date_of_birth, '%Y-%m-%d') AS dateOfBirth, gender,
               metadata_json AS metadataJson, attributes_json AS attributesJson, version,
               DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%s.%fZ') AS createdAt,
               DATE_FORMAT(updated_at, '%Y-%m-%dT%H:%i:%s.%fZ') AS updatedAt
        FROM frontier_character_data WHERE character_id = ?
    ]], { id })
    if not ok then return false, data end
    if not data then return false, 'character_not_found' end
    data.version = tonumber(data.version)
    return true, data
end

local function optionalProfile(data, key)
    local value = data[key]
    if validField(fields[key], value) then return value end
    return ''
end

function Core.ResolveCharacter(provider, selected)
    local external = selected.providerCharacterId
    if type(provider) ~= 'string' or #provider > 32 or not provider:match('^[a-z][a-z0-9_]*$')
        or type(external) ~= 'string' or #external > 64 or not external:match('^[A-Za-z0-9_-]+$') then
        return false, 'invalid_provider_identity'
    end

    local ok, candidate = database('scalar', "SELECT CONCAT('f_', REPLACE(UUID(), '-', ''))")
    if not ok then return false, candidate end
    if not Core.IsCharacterId(candidate) then return false, 'database_error' end

    local account = selected.identifier or selected.license
    account = validText(account, 128) and account or ''
    local saved, err = database('transaction', {
        {
            query = [[
                INSERT INTO frontier_character_identities
                    (id, provider, provider_character_id, account_identifier, created_at, updated_at)
                VALUES (?, ?, ?, NULLIF(?, ''), UTC_TIMESTAMP(6), UTC_TIMESTAMP(6))
                ON DUPLICATE KEY UPDATE id = id
            ]],
            values = { candidate, provider, external, account },
        },
        {
            query = [[
                UPDATE frontier_character_identities
                SET account_identifier = COALESCE(account_identifier, NULLIF(?, '')),
                    updated_at = UTC_TIMESTAMP(6)
                WHERE provider = ? AND provider_character_id = ?
                  AND (account_identifier IS NULL OR BINARY account_identifier = BINARY ?)
            ]],
            values = { account, provider, external, account },
        },
        {
            query = [[
                INSERT INTO frontier_character_data
                    (character_id, firstname, lastname, full_name, date_of_birth, gender,
                     metadata_json, attributes_json, created_at, updated_at)
                SELECT id, NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''),
                       '{}', '{}', UTC_TIMESTAMP(6), UTC_TIMESTAMP(6)
                FROM frontier_character_identities
                WHERE provider = ? AND provider_character_id = ?
                  AND (account_identifier IS NULL OR BINARY account_identifier = BINARY ?)
                ON DUPLICATE KEY UPDATE character_id = frontier_character_data.character_id
            ]],
            values = {
                optionalProfile(selected, 'firstname'), optionalProfile(selected, 'lastname'),
                optionalProfile(selected, 'name'), optionalProfile(selected, 'dateOfBirth'),
                optionalProfile(selected, 'gender'), provider, external, account,
            },
        },
    })
    if not saved then return false, err end
    local found, identity = database('single', [[
        SELECT id, account_identifier FROM frontier_character_identities
        WHERE provider = ? AND provider_character_id = ?
    ]], { provider, external })
    if not found then return false, identity end
    if not identity then return false, 'database_error' end
    if identity.account_identifier and identity.account_identifier ~= account then
        return false, 'provider_account_conflict'
    end
    local loaded, data = Frontier.GetCharacterData(identity.id)
    if loaded and identity.id == candidate then
        TriggerEvent('frontier:characterCreated', identity.id, Core.Copy(data))
    end
    return loaded, data
end

function Frontier.UpdateCharacterData(id, expectedVersion, patch)
    if not Core.IsCharacterId(id) then return false, 'invalid_character_id' end
    if not FrontierLib.IsInteger(expectedVersion) or expectedVersion < 1
        or expectedVersion >= 4294967295 or type(patch) ~= 'table' then
        return false, 'invalid_patch'
    end
    local updates, parameters = {}, {}
    for key, value in pairs(patch) do
        local field = fields[key]
        if not field or not validField(field, value) then
            return false, 'invalid_patch'
        end
        updates[#updates + 1] = field.column .. ' = ?'
        parameters[#parameters + 1] = value
    end
    if #updates == 0 then return false, 'invalid_patch' end
    parameters[#parameters + 1] = id
    parameters[#parameters + 1] = expectedVersion
    local ok, changed = database('update', 'UPDATE frontier_character_data SET ' ..
        table.concat(updates, ', ') .. ', version = version + 1, updated_at = UTC_TIMESTAMP(6)' ..
        ' WHERE character_id = ? AND version = ?', parameters)
    if not ok then return false, changed end
    if changed ~= 1 then return false, 'character_missing_or_version_conflict' end

    local loaded, data = Frontier.GetCharacterData(id)
    if not loaded then
        FrontierLib.Log('WARN', resource, 'Character update committed but reload failed')
        return false, 'update_committed_reload_failed'
    end
    Core.RefreshCharacter(data)
    TriggerEvent('frontier:characterUpdated', id, Core.Copy(data), expectedVersion + 1)
    return true, data
end
