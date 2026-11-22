-- Simulate a lost payment response, then verify replay completes the delivery.
local worker
local row = { id = '00000000-0000-0000-0000-000000000001', request_id = '00000000-0000-0000-0000-000000000002',
    state = 'stock', seller_id = 'seller', seller_bank = 11, item_id = 'bread', quantity = 4, price_minor = 25 }
local stock, money, attempts = 0, 0, 0
function RegisterCommand() end
function RegisterNetEvent() end
function AddEventHandler() end
function GetCurrentResourceName() return 'frontier_trade' end
function Wait() coroutine.yield() end
TradeConfig = { WorkerIntervalMs = 5000 }
FrontierLib = { Log = function() end }
exports = {
    frontier_core = {},
    frontier_inventory = { ReserveTradeDelivery = function(_, id, owner, item, quantity)
        assert(id == row.id and owner == 'seller' and item == 'bread' and quantity == 4)
        stock = stock + 1; return true
    end },
    frontier_economy = { PayTradeDelivery = function(_, request, id, owner, bank, cents)
        assert(request == row.request_id and id == row.id and owner == 'seller' and bank == 11 and cents == 100)
        attempts = attempts + 1
        if attempts == 1 then money = money + cents; return false, 'database_error' end
        return true
    end },
}
MySQL = {
    ready = function(fn) worker = coroutine.create(fn) end,
    update = { await = function(sql)
        if sql:find("SET state='payment'", 1, true) then row.state = 'payment' end
        return 1
    end },
    query = { await = function(sql, args)
        if sql:find('CALL', 1, true) then
            assert(args[1] == 'complete' and args[2] == row.id and row.state == 'payment')
            row.state = 'complete'
            return { { { code = 'ok' } } }
        end
        if sql:find('FROM frontier_trade_contracts WHERE', 1, true) then return {} end
        return row.state == 'complete' and {} or { row }
    end },
}
dofile('server/deliveries.lua')
assert(coroutine.resume(worker))
assert(row.state == 'payment' and stock == 1)
assert(coroutine.resume(worker))
assert(row.state == 'payment' and money == 100 and attempts == 1)
assert(coroutine.resume(worker))
assert(row.state == 'complete' and stock == 1 and money == 100 and attempts == 2)
assert(coroutine.resume(worker))
assert(attempts == 2)
print('Trade delivery worker replay contract passed')
