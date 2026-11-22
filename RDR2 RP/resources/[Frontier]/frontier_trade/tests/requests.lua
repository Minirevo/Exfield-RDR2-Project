-- Lua 5.4 with mocked Cfx exports and database.
local commands, messages, rows = {}, {}, {}
local worker, lost = nil, true
local funded, released = {}, {}
local request = '00000000-0000-0000-0000-000000000001'
function RegisterCommand(name, fn) commands[name] = fn end
function AddEventHandler() end
function GetCurrentResourceName() return 'frontier_trade' end
function GetGameTimer() return 5000 end
function TriggerClientEvent(_, _, message) messages[#messages+1] = message.args[2] end
function Wait() coroutine.yield() end
FrontierLib = { IsInteger = function(n) return n == math.floor(n) end, Log = function() end }
exports = {
    frontier_core = { GetPlayerCharacterId = function(_, source) return 'character' .. source end },
    frontier_inventory = { GetTradeItemDefinition = function() return true, { transferable = true } end },
    frontier_economy = {
        GetCharacterAccounts = function(_, source) return true, { characterId = 'character' .. source, bank = { id = source } } end,
        FundTradeHold = function(_, id, buyer, bank, amount)
            assert(buyer == 'character1' and bank == 1 and amount == 250)
            funded[id] = funded[id] or amount
            if lost then lost = false; return false, 'database_error' end
            return true
        end,
        ReleaseTradeHold = function(_, id, _, _, amount)
            assert(funded[id] == amount)
            released[id] = released[id] or amount
            return true
        end,
    },
}
MySQL = {
    ready = function(fn) worker = coroutine.create(fn) end,
    scalar = { await = function() return request end },
    single = { await = function(_, p)
        local row = rows[p[1]]
        if p[2] and row and row.buyer_id ~= p[2] then return end
        return row
    end },
    query = { await = function(q)
        local result = {}
        for _, row in pairs(rows) do
            if (q:find('retry_at', 1, true) and (row.state == 'funding' or row.state == 'refund'))
                or (not q:find('retry_at', 1, true) and row.state == 'open') then result[#result+1] = row end
        end
        return result
    end },
    update = { await = function(q, p)
        if q:find('INSERT', 1, true) then
            local id, buyer, bank, market, item, quantity, price, budget = table.unpack(p)
            rows[id] = rows[id] or { id = id, buyer_id = buyer, bank_id = bank, market_id = market,
                item_id = item, quantity = quantity, price_minor = price, budget_minor = budget, state = 'funding', attempts = 0 }
        elseif q:find('SET state = ?', 1, true) then
            rows[p[2]].state = p[1]
        elseif q:find('buyer_id = ?', 1, true) then
            local row = rows[p[1]]
            if not row or row.buyer_id ~= p[2] or row.state ~= 'open' then return 0 end
            row.state = 'refund'
        elseif q:find('SET attempts = ?', 1, true) then
            rows[p[4]].attempts = p[1]
        end
        return 1
    end },
}
dofile('config.lua')
dofile('server/requests.lua')
commands.handelsgesuch(1, { 'valentine', 'bread', '10', '25' })
assert(rows[request].state == 'funding')
commands.handelsmarkt(1, {})
assert(messages[#messages]:find('keine offenen'))
assert(coroutine.resume(worker))
assert(rows[request].state == 'funding' and rows[request].attempts == 1)
assert(coroutine.resume(worker))
assert(rows[request].state == 'open')
commands.handelsmarkt(1, {})
assert(messages[#messages]:find(request, 1, true))
commands.handelsstorno(2, {request})
assert(rows[request].state == 'open')
commands.handelsstorno(1, {request})
assert(rows[request].state == 'refund')
assert(coroutine.resume(worker))
assert(rows[request].state == 'closed' and released[request] == 250)
print('Frontier Trade request contract passed')
