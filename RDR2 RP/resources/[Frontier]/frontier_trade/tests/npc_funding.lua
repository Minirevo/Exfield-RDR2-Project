local handlers, applied = {}, {}
local balance=0
Economy={
    MaxId=10000,MaxMinor=10000,
    PositiveInteger=function(value,max) return type(value)=='number' and value>=1 and value<=max end,
    Export=function(name,fn) handlers[name]=fn end,
    Db=function(method,query,params)
        if method=='query' then return true,{} end
        if query:find('COUNT',1,true) then return true,2 end
        if query:find("owner_type = 'trade_hold'",1,true) then return true,99 end
        return true,params[1]
    end,
    Apply=function(_,kind,debit,credit,amount,options)
        if applied[options.key] then return true end
        if kind=='credit' then balance=balance+amount
        elseif debit==22 then
            if balance<amount then return false,'insufficient_funds' end
            balance=balance-amount
        else
            return false,'insufficient_funds'
        end
        applied[options.key]=true
        return true
    end,
}
dofile('../frontier_economy/server/trade_holds.lua')
local id='00000000-0000-0000-0000-000000000001'
assert(handlers.PayTradeSale('frontier_trade',id,'npc_shop',22,'player',11,50))
assert(handlers.PayTradeSale('frontier_trade',id,'npc_shop',22,'player',11,50))
assert(balance==0 and applied[id..':npc-topup'])
local other='00000000-0000-0000-0000-000000000002'
local ok,why=handlers.PayTradeSale('frontier_trade',other,'player',11,'npc_shop',22,50)
assert(not ok and why=='insufficient_funds' and not applied[other..':npc-topup'])
assert(not handlers.PayTradeSale('another_resource',id,'npc_shop',22,'player',11,50))
print('NPC-only top-up and payment replay contract passed')
