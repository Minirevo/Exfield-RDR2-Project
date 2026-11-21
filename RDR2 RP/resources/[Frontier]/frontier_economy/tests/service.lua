-- Run from the resource directory with Lua 5.4. No server or database required.
local handlers = {}
local registered = {}
local invokingResource = 'economy_test'
local statements = {}
local alpha = 'f_' .. string.rep('a', 32)
local beta = 'f_' .. string.rep('b', 32)
local gamma = 'f_' .. string.rep('c', 32)
local players = { [1] = { source = 1, frontierCharacterId = alpha }, [2] = { source = 2, frontierCharacterId = beta } }
local replaceSenderDuringLookup = false
local nextReceipt
local disconnectDatabase = false
local cutoverMarker
json = { encode = function() return '{}' end }

function GetCurrentResourceName() return 'frontier_economy' end
function GetInvokingResource() return invokingResource end
function GetConvar(_, default) return default end
function AddEventHandler(name, fn) handlers[name] = fn end

exports = setmetatable({
    frontier_core = {
        GetPlayerCharacterId = function(_, playerSource) local player = players[playerSource]; return player and player.frontierCharacterId end,
    },
}, {
    __call = function(_, name, fn) registered[name] = fn end,
})

MySQL = {
    ready = function() end,
    scalar = { await = function() return cutoverMarker end },
    query = {
        await = function(statement, parameters)
            statements[#statements + 1] = { statement, parameters }
            if disconnectDatabase then
                error('fixture: disconnected')
            end
            if statement:find('CALL frontier_economy_apply_v1', 1, true) then
                local receipt = nextReceipt or { code = 'ok', operation_id = '123', replayed = 0 }
                nextReceipt = nil
                return { { receipt }, {} }
            end
            local id = parameters[1] == alpha and 10 or 20
            if id == 20 and replaceSenderDuringLookup then
                players[1] = { source = 1, frontierCharacterId = gamma }
            end
            return {
                { id = tostring(id), account_type = 'cash', balance_minor = '42', currency = 'USD' },
                { id = tostring(id + 1), account_type = 'bank', balance_minor = '7', currency = 'USD' },
            }
        end,
    },
}

-- Load the same shared utility if the full resource tree is present.
dofile('../frontier_lib/shared/utils.lua')
dofile('../frontier_lib/server/logger.lua')
dofile('config.lua')
dofile('server/database.lua')
dofile('server/accounts.lua')
dofile('server/transactions.lua')
EconomyConfig.TrustedResources.economy_test = true

local function expectError(expected, fn, ...)
    local ok, result = fn(...)
    assert(ok == false and result == expected, ('Expected %s, got %s'):format(expected, tostring(result)))
end

local options = { key = 'test:1', reason = 'Fixture' }
invokingResource = 'unknown'
expectError('forbidden', registered.CreditAccount, 10, 1, options)
assert(#statements == 0)
invokingResource = 'economy_test'

for _, invalid in ipairs({ 0, -1, '100', 0.5, math.huge, -math.huge, 0 / 0, Economy.MaxMinor + 1 }) do
    expectError('invalid_amount', registered.CreditAccount, 10, invalid, options)
end
expectError('invalid_account', registered.CreditAccount, 0, 1, options)
expectError('same_account', registered.TransferAccounts, 10, 10, 1, options)
expectError('invalid_key', registered.DebitAccount, 10, 1, { key = 'bad key', reason = 'Test' })
expectError('invalid_metadata', registered.CreditAccount, 10, 1, {
    key = 'test:meta', reason = 'Test', metadataJson = string.rep('x', 4097),
})
assert(#statements == 0)

expectError('identity_migration_required', registered.GetCharacterBalances, 1)
cutoverMarker = 1
local ok, balances = registered.GetCharacterBalances(1)
assert(ok and balances.cash == 42 and balances.bank == 7)
local credited, receipt = registered.CreditAccount(10, 12, options)
assert(credited and receipt.operationId == '123' and not receipt.replayed)
assert(table.concat(statements[#statements][2], '|') == 'resource:economy_test|test:1|credit|0|10|12|Fixture||{}|USD')

nextReceipt = { code = 'ok', operation_id = '123', replayed = 1 }
local replayed, replay = registered.CreditAccount(10, 12, options)
assert(replayed and replay.replayed and replay.operationId == receipt.operationId)

nextReceipt = { code = 'insufficient_funds' }
expectError('insufficient_funds', registered.DebitAccount, 10, 100, options)
expectError('same_account', registered.TransferCharacters, 1, 1, 1, options)
assert(registered.TransferCharacters(1, 2, 1, options))
local transfer = statements[#statements][2]
assert(transfer[3] == 'transfer' and transfer[4] == 11 and transfer[5] == 21)
replaceSenderDuringLookup = true
expectError('character_changed', registered.TransferCharacters, 1, 2, 1, options)
assert(not statements[#statements][1]:find('CALL frontier_economy_apply_v1', 1, true))
replaceSenderDuringLookup = false

disconnectDatabase = true
expectError('database_error', registered.CreditAccount, 10, 12, options)
print('Frontier Economy service contract passed')
