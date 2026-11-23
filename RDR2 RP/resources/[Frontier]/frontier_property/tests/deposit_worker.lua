local worker
RegisterCommand = function() end
CreateThread = function(fn) worker=fn end
Wait = function() coroutine.yield() end
local debits, credits, active, refunded = 0, 0, false, false
local allowCredit, expired = false, false
local rental = { id=11, account_id=23, landlord_bank_id=24, price_cents=100, deposit_cents=50 }
exports = {
    frontier_core = {},
    frontier_economy = {
        DebitAccount = function(_, id, amount, options)
            assert(id==23 and amount==150 and options.key=='property:rent:11:collect')
            debits=debits+1
            return true
        end,
        CreditAccount = function(_, id, amount, options)
            credits=credits+1
            if id==24 then
                assert(amount==100 and options.key=='property:rent:11:landlord')
                return allowCredit
            end
            assert(id==23 and amount==50 and options.key=='property:rent:11:refund')
            return true
        end,
    },
}
MySQL = {
    ready = function(fn) fn() end,
    update = { await = function(sql)
        if sql:find("SET state='active'",1,true) then active=true end
        if sql:find("SET deposit_refunded=1",1,true) then refunded=true end
        return 1
    end },
    query = { await = function(sql)
        if sql:find("state='reserved'",1,true) then return active and {} or {rental} end
        return expired and not refunded and {rental} or {}
    end },
}
dofile((... or '.') .. '/server/rentals.lua')
local thread=coroutine.create(worker)
assert(coroutine.resume(thread))
assert(debits==1 and credits==1 and not active)
allowCredit=true
assert(coroutine.resume(thread))
assert(debits==2 and credits==2 and active)
expired=true
assert(coroutine.resume(thread))
assert(refunded and credits==3)
assert(coroutine.resume(thread))
assert(credits==3)
print('Rental deposit retry and refund contract passed')
