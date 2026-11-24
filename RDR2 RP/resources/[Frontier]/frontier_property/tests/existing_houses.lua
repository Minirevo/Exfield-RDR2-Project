-- Run from the frontier_property resource directory with Lua 5.4.
local events, commands, callbacks, positions, buckets, returns = {}, {}, {}, {}, {}, {}
local actors = {[1]='owner',[2]='guest',[3]='other',[4]='stranger'}
local clock=1000
local access={owner={[11]=true},guest={[11]=true},other={[12]=true},stranger={}}
exports={frontier_core={GetPlayerCharacterId=function(_,player) return actors[player] end}}
function RegisterNetEvent(name,fn) events[name]=fn end
function RegisterCommand(name,fn) commands[name]=fn end
function AddEventHandler(name,fn) callbacks[name]=fn end
function CreateThread() end
function GetCurrentResourceName() return 'frontier_property' end
function GetPlayerPed(player) return positions[player] and player or 0 end
function GetPlayerRoutingBucket(player) return buckets[player] or 0 end
function GetEntityCoords(ped) return positions[ped] end
function GetEntityHeading() return 90 end
function SetEntityCoords(ped,x,y,z) positions[ped]={x=x,y=y,z=z} end
function SetEntityHeading() end
function SetPlayerRoutingBucket(player,bucket) buckets[player]=bucket end
function SetRoutingBucketPopulationEnabled() end
function SetRoutingBucketEntityLockdownMode() end
function TriggerClientEvent() end
function GetGameTimer() return clock end
MySQL={
    query={await=function() return {{property_id=11,label='A'},{property_id=12,label='B'}} end},
    scalar={await=function(_,args) return access[args[1]][args[4]] and 1 or 0 end},
    single={await=function(_,args) return returns[args[1]] end},
    update=setmetatable({await=function(sql,args)
        if sql:find('INSERT INTO',1,true) then
            returns[args[1]]={x=args[2],y=args[3],z=args[4],heading=args[5]}
        elseif sql:find('DELETE FROM',1,true) then
            returns[args[1]]=nil
        end
        return 1
    end},{__call=function(self,...) return self.await(...) end}),
}

dofile('shared/houses.lua')
dofile('server/houses.lua')
local door=PropertyHouses.watson.door
local function event(player,name,...)
    source=player
    events['frontier_property:'..name](...)
end
for player=1,4 do positions[player]={x=door.x,y=door.y,z=door.z} end
event(1,'houseEnter','watson')
event(2,'houseEnter','watson',12)
assert(GetPlayerRoutingBucket(2)==0,'guest must not select a foreign house')
clock=clock+1000
event(2,'houseEnter','watson')
event(3,'houseEnter','watson')
event(4,'houseEnter','watson')
assert(GetPlayerRoutingBucket(4)==0)
assert(GetPlayerRoutingBucket(1)==GetPlayerRoutingBucket(2))
assert(GetPlayerRoutingBucket(1)~=GetPlayerRoutingBucket(3))
assert(GetPropertyHouseVisit(1,11) and not GetPropertyHouseVisit(1,12))
event(1,'houseExit')
assert(positions[1].x==door.x and GetPlayerRoutingBucket(1)==0 and not returns.owner)
assert(GetPropertyHouseVisit(2,11))
source=2
callbacks.playerDropped()
assert(returns.guest and not GetPropertyHouseVisit(2,11))
event(2,'houseRecover')
assert(positions[2].x==door.x and GetPlayerRoutingBucket(2)==0 and not returns.guest)
callbacks.onResourceStop('frontier_property')
assert(positions[3].x==door.x and GetPlayerRoutingBucket(3)==0 and not returns.other)
assert(PropertyHouseWithin(PropertyHouses.watson.entry,PropertyHouses.watson,0.55))
assert(not PropertyHouseWithin(PropertyHouses.watson.door,PropertyHouses.watson,0.55))
print('existing house: access, bucket selection, exit, reconnect and restart simulation passed')
