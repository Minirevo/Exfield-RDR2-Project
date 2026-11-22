local worker, sql, handlers
local elapsed, wageAttempts, charged, outputs = 0,0,0,0
local connected = false
local player = {id='player',owner_id='f_player',mode='player',state='running',remaining_seconds=10}
local npc = {id='npc',owner_id='f_npc',mode='npc',state='reserve',materials='[]',bank_id=2,wage_minor=17,output_item='bread',output_units=2}
local production = {player=player,npc=npc}
handlers={}
function RegisterNetEvent() end
function AddEventHandler(name,fn) handlers[name]=fn end
function TriggerClientEvent() end
function Wait() coroutine.yield() end
function GetCurrentResourceName() return 'frontier_production' end
FrontierLib={Log=function() end}
json={decode=function() return {} end}
dofile('config.lua')
exports={
    frontier_core={GetPlayers=function() return {} end,GetPlayerCharacterId=function(_,source)
        if connected and source==1 then return 'f_player' end
    end},
    frontier_inventory={RegisterItem=function() return true end,
        ApplyProductionInventory=function(_,action,id,key)
            assert(id=='f_npc')
            if action=='reserve' then assert(key=='npc:reserve');return true end
            assert(action=='finish' and key=='npc:output')
            outputs=outputs+1
            return true
        end},
    frontier_economy={DebitAccount=function(_,bank,cents,options)
        assert(bank==2 and cents==17 and options.key=='npc:wage')
        wageAttempts=wageAttempts+1
        if wageAttempts==1 then charged=charged+cents;return false,'database_error' end
        return true
    end},
}
MySQL={
    ready=function(fn) worker=coroutine.create(fn) end,
    query={await=function(query)
        if query:find('SELECT DISTINCT',1,true) then return {{owner_id='f_player'}} end
        if npc.state=='reserve' or npc.state=='wage' or npc.state=='output' then return {npc} end
        return {}
    end},
    update={await=function(query,args)
        if query:find('remaining_seconds=GREATEST',1,true) then
            elapsed=elapsed+1
            assert(connected)
        elseif query:find("SET state='running'",1,true) then
            npc.state='running'
        elseif query:find("mode='npc' AND completes_at",1,true) and npc.state=='running' then
            npc.state='output'
        elseif query:find('SET state=?,retry_at=',1,true) then
            production[args[2]].state=args[1]
        end
        return 1
    end},
}
dofile('server/production.lua')
local function tick()
    local ok,why=coroutine.resume(worker)
    assert(ok,why)
end
tick()
tick()
assert(npc.state=='wage' and elapsed==0)
tick()
assert(npc.state=='wage' and charged==17 and elapsed==0)
tick()
assert(npc.state=='running' and wageAttempts==2 and charged==17)
tick()
assert(npc.state=='complete' and outputs==1 and elapsed==0)
connected=true
handlers['frontier:playerLoaded']({source=1,frontierCharacterId='f_player'})
tick()
assert(elapsed==1)
connected=false
handlers['frontier:playerUnloaded']({source=1,frontierCharacterId='f_player'})
tick()
assert(elapsed==1 and outputs==1)
print('Production worker offline NPC, paused player and wage replay passed')
