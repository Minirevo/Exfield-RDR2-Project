local worker
local offer={id='o',seller_id='seller',quantity=10,available=10,item_id='bread',state='stock'}
local sale={id='s',offer_id='o',buyer_id='buyer',seller_id='seller',buyer_bank=1,seller_bank=2,
    quantity=4,unit_minor=25,item_id='bread',state='stock'}
local stock,reversals,payment=0,0,0
function RegisterCommand() end
function Wait() coroutine.yield() end
TradeConfig={Batch=20,WorkerIntervalMs=1000}
FrontierLib={Log=function() end}
exports={frontier_core={},frontier_inventory={
    ReserveTradeDelivery=function() stock=stock+1;return true end,
    MoveTradeSaleStock=function(_,id,offerId,_,qty,reverse)
        assert(id=='s' and offerId=='o' and qty==4)
        if reverse then reversals=reversals+1 end
        return true
    end,
},frontier_economy={PayTradeSale=function(_,id,_,_,_,_,amount)
    assert(id=='s' and amount==100)
    payment=payment+1
    return false,payment==1 and 'database_error' or 'insufficient_funds'
end}}
MySQL={
    ready=function(fn) worker=coroutine.create(fn) end,
    update={await=function(query,args)
        if query:find('SET state=?',1,true) then
            local row=query:find('frontier_trade_offers',1,true) and offer or sale
            row.state=args[1]
        end
        return 1
    end},
    query={await=function(query,args)
        if args[1]=='reject' then sale.state='rejected';return {{{code='ok'}}} end
        if query:find("state IN ('stock','return')",1,true) then return offer.state=='stock' and {offer} or {} end
        return sale.state~='rejected' and {sale} or {}
    end},
}
dofile('server/sales.lua')
local function tick()
    local ok,err=coroutine.resume(worker)
    assert(ok,err)
end
tick()
assert(stock==1 and offer.state=='open' and sale.state=='payment')
tick()
assert(sale.state=='payment' and reversals==0)
tick()
assert(sale.state=='reverse' and reversals==0)
tick()
assert(sale.state=='rejected' and reversals==1)
print('Sale worker unknown payment and definitive rejection contract passed')
