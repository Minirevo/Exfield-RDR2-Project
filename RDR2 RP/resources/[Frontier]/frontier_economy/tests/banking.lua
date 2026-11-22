-- Run from frontier_economy with Lua 5.4.
local events, handlers, replies, commands = {}, {}, {}, {}
local playerIds = { [1] = 'f_' .. string.rep('a', 32), [2] = 'f_' .. string.rep('b', 32) }
local accounts = {
    [1] = { cash = { id = 10, balance_minor = 1000, currency = 'USD' },
        bank = { id = 11, balance_minor = 5000 } },
    [2] = { cash = { id = 20, balance_minor = 0, currency = 'USD' },
        bank = { id = 21, balance_minor = 0 } },
}
local calls, timer, tickets = 0, 0, 0
local receiptByKey = {}
local loseReceipt, switchRecipient, cancelPending
local clientEvents = {}
local creditAttempt = false

function GetCurrentResourceName() return 'frontier_economy' end
function GetGameTimer() timer = timer + 250; return timer end
function GetInvokingResource() return 'unlisted_fixture' end
function GetConvar(_, default) return default end
function RegisterNetEvent(name, fn) events[name] = fn end
function AddEventHandler(name, fn) handlers[name] = fn end
function RegisterCommand(name, fn) commands[name] = fn end
function TriggerClientEvent(name, to, ...)
    if name == FrontierBank.Event .. 'result' then
        replies[#replies + 1] = select(3, ...)
    end
    clientEvents[#clientEvents + 1] = { name, to, ... }
end
json = { encode = function() return '{}' end }
exports = setmetatable({
    frontier_core = {
        GetPlayer = function(_, id)
            if playerIds[id] then return { source = id, frontierCharacterId = playerIds[id], name = 'Ada Holt' } end
        end,
        GetPlayerCharacterId = function(_, id) return playerIds[id] end,
        HasPermission = function() return false end,
    },
}, { __call = function(_, name, fn) exports[name] = fn end })

dofile('../frontier_lib/shared/utils.lua')
dofile('../frontier_lib/server/logger.lua')
dofile('config.lua')
dofile('shared/banking.lua')
dofile('server/database.lua')
function Economy.GetCharacterAccounts(id)
    local character = playerIds[id]
    if not character then return false, 'character_unavailable' end
    if cancelPending then
        cancelPending = false
        handlers['frontier:playerUnloaded']({ source = id })
    end
    if id == 2 and switchRecipient then
        handlers['frontier:playerUnloaded']({ source = 2 })
    end
    return true, { characterId = character, cash = accounts[id].cash, bank = accounts[id].bank }
end
function Economy.IsCurrentCharacter(id, character) return playerIds[id] == character end

function Economy.Db(method, query, params)
    if method == 'scalar' and query:find('COUNT', 1, true) then return true, 0 end
    if method == 'scalar' then
        tickets = tickets + 1
        return true, ('00000000-0000-0000-0000-%012d'):format(tickets)
    end
    if not query:find('CALL', 1, true) then
        assert(params[2] == 25 and params[1] == 11)
        return true, {
            { created_at = '2026-11-21T12:30:00.000000Z', kind = 'credit', entry_type = 'credit',
              amount_minor = 100, balance_after = 100, reason = 'license:private', actor = 'admin:command',
              metadata_json = '{"admin":"license:private"}', account_id = 11, operation_id = 'secret' },
            { created_at = '2026-11-21T12:31:00.000000Z', kind = 'transfer', entry_type = 'debit',
              amount_minor = 250, balance_after = 750, reason = 'Miete', actor = 'bank:' .. playerIds[1],
              metadata_json = '{"action":"transfer"}' },
        }
    end

    calls = calls + 1
    local _, key, kind, debit, credit, amount = table.unpack(params)
    if kind == 'credit' then creditAttempt = true end
    local receipt = receiptByKey[key]
    if receipt then
        if loseReceipt then return false, 'database_error' end
        return true, { { { code = 'ok', operation_id = receipt, replayed = 1 } } }
    end
    local all = { [10] = accounts[1].cash, [11] = accounts[1].bank,
        [20] = accounts[2].cash, [21] = accounts[2].bank }
    if all[debit].balance_minor < amount then return true, { { { code = 'insufficient_funds' } } } end
    all[debit].balance_minor = all[debit].balance_minor - amount
    all[credit].balance_minor = all[credit].balance_minor + amount
    receipt = tostring(calls)
    receiptByKey[key] = receipt
    if loseReceipt then return false, 'database_error' end
    return true, { { { code = 'ok', operation_id = receipt, replayed = 0 } } }
end

dofile('server/transactions.lua')
dofile('server/commands.lua')
dofile('server/banking.lua')

local E = FrontierBank.Event
local requestId = 1
local function open(id, view)
    source = id
    events[E .. 'open'](view or 1, 1)
    return replies[#replies]
end
local function send(ticket, action, sequence, data, view)
    source = 1
    requestId = requestId + 1
    events[E .. 'request'](view or 1, requestId, ticket, action, sequence, data)
    return replies[#replies]
end
assert(open(99).message == FrontierBank.Text.character_unavailable)
local started = open(1)
local ticket = started.ticket
assert(started.next == 1 and started.balances.cash == 1000 and started.balances.bank == 5000)
assert(send('wrong', 'deposit', 1, { amount = '1' }).message == FrontierBank.Text.stale_request)
assert(send(ticket, 'deposit', 1, { amount = '2,50' }).balances.cash == 750)
assert(send(ticket, 'deposit', 1, { amount = '2,50' }).balances.bank == 5250 and calls == 1)
assert(send(ticket, 'withdraw', 2, { amount = '1.05' }).balances.cash == 855)
assert(send(ticket, 'deposit', 3, { amount = '999' }).message == FrontierBank.Text.insufficient_cash)
assert(send(ticket, 'withdraw', 4, { amount = '999' }).message == FrontierBank.Text.insufficient_bank)
assert(send(ticket, 'transfer', 5, { amount = '9', recipient = '299' }).message == FrontierBank.Text.offline_recipient)
assert(send(ticket, 'transfer', 6, { amount = '9' }).message == FrontierBank.Text.invalid_recipient)
assert(send(ticket, 'transfer', 7, { amount = '9', recipient = '1' }).message == FrontierBank.Text.same_account)
assert(send(ticket, 'transfer', 8, { amount = '999', recipient = '2' }).message == FrontierBank.Text.insufficient_bank)
for seq, invalid in ipairs({ '0', '-1', '1.234', '1e3', '90000000001', 'NaN', 'Infinity', 0 / 0, math.huge, 1.5 }) do
    assert(send(ticket, 'deposit', seq + 8, { amount = invalid }).message == FrontierBank.Text.invalid_amount)
end
for index, extra in ipairs({ 'accountId', 'characterId', 'balance', 'source', 'actor' }) do
    assert(send(ticket, 'deposit', index + 18, { amount = '1', [extra] = 99 }).message == FrontierBank.Text.invalid_request)
end
switchRecipient = true
assert(send(ticket, 'transfer', 24, { amount = '2', recipient = '2' }).message == FrontierBank.Text.recipient_changed)
switchRecipient = false
assert(accounts[2].bank.balance_minor == 0)

loseReceipt = true
assert(send(ticket, 'transfer', 25, { amount = '2,50', recipient = '2', reason = 'Miete' }).retry)
assert(accounts[2].bank.balance_minor == 250)
loseReceipt = false
assert(send(ticket, 'transfer', 25, { amount = '90', recipient = '999' }).ok)
assert(accounts[2].bank.balance_minor == 250)
local settledCalls = calls
assert(send(ticket, 'transfer', 25, { amount = '2,50', recipient = '2' }).ok and calls == settledCalls)

local history = send(ticket, 'history', nil, 'bank').history
assert(#history == 2 and history[1].reason == nil and history[2].reason == 'Miete')
assert(history[1].actor == nil and history[1].metadata_json == nil and history[1].account_id == nil
    and history[1].operation_id == nil)
local allowed, issue = exports.CreditAccount(11, 100, { key = 'bad', reason = 'No' })
assert(not allowed and issue == 'forbidden')
commands[EconomyConfig.AdminCreditCommand](1, { '1', 'bank', '100', 'bad', 'No' })
assert(not creditAttempt and clientEvents[#clientEvents][3].args[2]:find('Berechtigung', 1, true))

cancelPending = true
send(ticket, 'deposit', 26, { amount = '1' })
assert(calls == settledCalls)
assert(clientEvents[#clientEvents][1] == E .. 'invalidated')
assert(send(ticket, 'balances').message == FrontierBank.Text.stale_request)
local reopened = open(1, 2)
assert(reopened.ticket ~= ticket and reopened.balances.bank == 4895)
assert(send(ticket, 'balances', nil, nil, 2).message == FrontierBank.Text.stale_request)
print('Frontier banking server contract passed')

-- Client lifecycle and NUI route contract, separate from the server fixture.
local callbacks, focus, output, sent, timeout = {}, {}, {}, {}, {}
function RegisterNUICallback(name, fn) callbacks[name] = fn end
function SetNuiFocus(mouse, keyboard) focus[#focus + 1] = { mouse, keyboard } end
function SetNuiFocusKeepInput(keep) assert(keep == false) end
function SendNUIMessage(payload) output[#output + 1] = payload end
function TriggerServerEvent(name, ...) sent[#sent + 1] = { name, ... } end
function SetTimeout(_, fn) timeout[#timeout + 1] = fn end
function TriggerEvent() end
local function ack(reply) assert(reply.ok) end
dofile('client/banking.lua')
commands[FrontierBank.Command]()
assert(sent[#sent][1] == E .. 'open')
source = 65535
events[E .. 'result'](1, 1, { ok = true, ticket = 'ticket', next = 1, balances = { cash = 1 } })
assert(#focus == 0)
callbacks.bankReady({}, ack)
assert(focus[#focus][1] == true and output[#output].type == 'open')
callbacks.bankRequest({ action = 'deposit', sequence = 1, uiRequest = 10, data = { amount = '1' } }, ack)
assert(sent[#sent][6] == 1)
events[E .. 'result'](1, 2, { ok = true, next = 2, balances = { cash = 0 } })
assert(output[#output].uiRequest == 10 and output[#output].next == 2)
callbacks.bankRequest({ action = 'deposit', sequence = 1, uiRequest = 11, data = { amount = '1' } }, ack)
assert(sent[#sent][6] == 1)
timeout[#timeout]()
assert(output[#output].retry and output[#output].uiRequest == 11)
callbacks.bankClose({}, ack)
assert(focus[#focus][1] == false and output[#output].type == 'close')
commands[FrontierBank.Command]()
events[E .. 'result'](2, 4, { ok = true, ticket = 'new', next = 1, balances = { cash = 2 } })
assert(focus[#focus][1] == true)
handlers.onClientResourceStop('frontier_economy')
assert(focus[#focus][1] == false and focus[#focus][2] == false)
print('Frontier banking client contract passed')
