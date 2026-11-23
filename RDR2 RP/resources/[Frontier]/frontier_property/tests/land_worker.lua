local worker, finished, payments
local debtResult, debitIssue = false, 'database_error'
exports = {
    frontier_core = {},
    frontier_economy = { DebitAccount = function(_, account, price, options)
        assert(account == 23 and price == 18000 and options.key == 'land:purchase:7')
        payments = (payments or 0) + 1
        return debtResult, debitIssue
    end },
}
CreateThread = function(fn) worker = fn end
Wait = function() coroutine.yield() end
MySQL = {
    ready = function(fn) fn() end,
    update = { await = function() return 1 end },
    query = { await = function(sql, args)
        if sql:find('frontier_land_finish_v1', 1, true) then
            assert(args[1] == 7)
            finished = args[2]
        else
            return { { id = 7, account_id = 23, price_cents = 18000 } }
        end
    end },
}
dofile((... or '.') .. '/server/land.lua')
local thread = coroutine.create(worker)
assert(coroutine.resume(thread))
assert(payments == 1 and finished == nil)
debtResult = true
assert(coroutine.resume(thread))
assert(payments == 2 and finished == 1)
debtResult, debitIssue = false, 'insufficient_funds'
assert(coroutine.resume(thread))
assert(payments == 3 and finished == 0)
print('Property land settlement retries passed')
