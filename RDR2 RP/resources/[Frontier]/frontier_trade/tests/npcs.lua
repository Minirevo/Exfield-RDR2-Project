local worker
local count,requested=0,nil
local epoch=0
local effects={}
function RegisterCommand() end
function exports() end
exports=setmetatable({
    frontier_economy={ProvisionTradeNpc=function(_,who) assert(who=='npc_fixture');return true,77 end},
    frontier_core={},
    frontier_inventory={
        GetTradeNpcStock=function() return true,count end,
        ChangeTradeNpcStock=function(_,_,_,qty,add,id)
            if not effects[id] then count=count+(add and qty or -qty);effects[id]=true end
            return true
        end,
        ClaimTradeDelivery=function() error('Nothing to claim') end,
    },
},{__call=function() end})
function Wait() coroutine.yield() end
FrontierLib={Log=function() end}
TradeConfig={NpcEnabled=true,NpcTickMinutes=15,LifetimeHours=24,Markets={valentine=true},Products={bread=true},
    NpcMerchants={npc_fixture={market='valentine',item='bread',minimum=3,target=8,maximum=10,consume=1,produce=2,price=25,chance=0}}}
MySQL={
    ready=function(fn) worker=coroutine.create(fn) end,
    scalar={await=function(q,args)
        if q:find('UNIX_TIMESTAMP',1,true) then return 900 end
        if q:find('SHA2',1,true) then return args[3] end
        return requested and q:find('frontier_trade_requests',1,true) and 1 or 0
    end},
    query={await=function(q)
        if q:find('last_epoch',1,true) and epoch>0 then return {{owner_id='npc_fixture',last_epoch=epoch}} end
        return {}
    end},
    single={await=function() end},
    update={await=function(q,args)
        if q:find('last_epoch',1,true) then epoch=args[2] end
        if q:find('INSERT INTO frontier_trade_requests',1,true) then requested=args end
        return 1
    end},
}
dofile('server/npcs.lua')
assert(coroutine.resume(worker))
assert(count==2 and requested[2]=='npc_fixture' and requested[3]==77 and requested[6]==6 and requested[8]==150)
assert(coroutine.resume(worker))
assert(count==2 and epoch==1)
print('NPC bounded production and demand cycle contract passed')
