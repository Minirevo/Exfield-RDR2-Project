local core = exports.frontier_core
local pending = {}
local cutoverReady = false

local function checkCutover()
    if cutoverReady then return true end
    local ok, marker = Economy.Db('scalar', 'SELECT id FROM frontier_economy_identity_cutover WHERE id = 1')
    if not ok then return false, marker end
    if tonumber(marker) ~= 1 then return false, 'identity_migration_required' end
    cutoverReady = true
    return true
end

local function currentCharacter(playerSource)
    if not Economy.PositiveInteger(playerSource, 2147483647) then
        return nil
    end
    local id = core:GetPlayerCharacterId(playerSource)
    if type(id) == 'string' and #id == 34 and id:match('^f_[a-f0-9]+$') then
        return id
    end
end

local function normalizeAccount(row)
    row.id = tonumber(row.id)
    row.balance_minor = tonumber(row.balance_minor)
    if not Economy.PositiveInteger(row.id, Economy.MaxId) or not row.balance_minor
        or row.balance_minor < 0 or row.balance_minor > Economy.MaxMinor
        or not FrontierLib.IsInteger(row.balance_minor) then
        FrontierLib.Log('ERROR', Economy.Resource, 'Invalid economy account data')
        return false
    end
    return true
end

local function provision(characterId)
    local ready, issue = checkCutover()
    if not ready then return false, issue end
    return Economy.Db('query', 'CALL frontier_economy_provision_v1(?)', { characterId })
end

function Economy.GetCharacterAccounts(playerSource)
    local characterId = currentCharacter(playerSource)
    if not characterId then
        return false, 'character_unavailable'
    end

    local ready, issue = checkCutover()
    if not ready then return false, issue end

    local function readAccounts()
        return Economy.Db('query', [[
            SELECT CAST(id AS CHAR) AS id, account_type, balance_minor, currency
            FROM frontier_economy_accounts
            WHERE owner_type = 'character' AND owner_id = ? AND account_type IN ('cash', 'bank')
        ]], { characterId })
    end

    local ok, rows = readAccounts()
    if ok and #rows < 2 then
        ok, rows = provision(characterId)
        if ok then
            ok, rows = readAccounts()
        end
    end
    if not ok then
        return false, rows
    end
    if currentCharacter(playerSource) ~= characterId then
        return false, 'character_changed'
    end
    if #rows ~= 2 then
        return false, 'account_not_found'
    end

    local accounts = { characterId = characterId }
    for _, row in ipairs(rows) do
        if not normalizeAccount(row) then
            return false, 'database_error'
        end
        accounts[row.account_type] = row
    end
    return true, accounts
end

function Economy.IsCurrentCharacter(playerSource, characterId)
    return currentCharacter(playerSource) == characterId
end

function Economy.GetAccountBalance(accountId)
    if not Economy.PositiveInteger(accountId, Economy.MaxId) then
        return false, 'invalid_account'
    end
    local ok, row = Economy.Db('single', [[
        SELECT CAST(id AS CHAR) AS id, account_type, balance_minor, currency
        FROM frontier_economy_accounts WHERE id = ?
    ]], { accountId })
    if not ok then
        return false, row
    end
    if not row then
        return false, 'account_not_found'
    end
    if not normalizeAccount(row) then
        return false, 'database_error'
    end
    return true, row
end

local function enqueue(player)
    if type(player) == 'table' and currentCharacter(player.source) == player.frontierCharacterId
        and player.frontierCharacterId ~= nil then
        -- A fresh token prevents an older attempt from clearing a new session's work.
        pending[player.source] = { characterId = player.frontierCharacterId }
    end
end

AddEventHandler('frontier:playerLoaded', enqueue)
AddEventHandler('frontier:playerUnloaded', function(player)
    pending[player.source] = nil
end)

MySQL.ready(function()
    for _, player in pairs(core:GetPlayers()) do
        enqueue(player)
    end

    while true do
        local batch = {}
        for playerSource, entry in pairs(pending) do
            batch[playerSource] = entry
        end
        for playerSource, entry in pairs(batch) do
            if pending[playerSource] == entry then
                local done = not Economy.IsCurrentCharacter(playerSource, entry.characterId)
                    or provision(entry.characterId)
                if done and pending[playerSource] == entry then
                    pending[playerSource] = nil
                end
            end
        end
        Wait(EconomyConfig.ProvisionRetryMs)
    end
end)

Economy.Export('GetCharacterAccounts', function(_, playerSource)
    return Economy.GetCharacterAccounts(playerSource)
end)
Economy.Export('GetCharacterBalances', function(_, playerSource)
    local ok, accounts = Economy.GetCharacterAccounts(playerSource)
    if not ok then
        return false, accounts
    end
    return true, {
        cash = accounts.cash.balance_minor,
        bank = accounts.bank.balance_minor,
        currency = accounts.cash.currency,
    }
end)
Economy.Export('GetAccountBalance', function(_, id)
    return Economy.GetAccountBalance(id)
end)
