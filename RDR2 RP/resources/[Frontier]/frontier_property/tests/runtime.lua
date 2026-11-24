dofile('config.lua');dofile('shared/rules.lua')
exports={frontier_core={},frontier_inventory={},frontier_economy={}}
function GetPlayerPed() return 1 end
function DoesEntityExist() return true end
function GetEntityCoords() return {x=0,y=0,z=0} end
function GetPlayerRoutingBucket() return 0 end
function TriggerClientEvent() end
dofile('server/bootstrap.lua');dofile('server/runtime.lua');dofile('server/permissions.lua');dofile('server/construction.lua')
local P=PropertyRuntime
local s={status='active',owners={owner=true},members={worker={work=true}},buildings={}}
assert(P.allowed(s,'owner','sell'))
assert(P.allowed(s,'worker','work'))
assert(not P.allowed(s,'worker','sell'))
assert(not P.allowed(s,'visitor','enter'))
s.status='abandoned';assert(not P.allowed(s,'owner','work'))
local e=PropertyConfig.Exteriors.cabin;local i=PropertyConfig.Interiors.watson
local stages=P.buildingStages(e,i)
assert(#stages==3)
for item,n in pairs(e.materials) do assert((stages[1].materials[item] or 0)+(stages[2].materials[item] or 0)==n) end
assert(stages[3].materials.planks==i.materials.planks)
assert(PropertyRules.capacity(e,i)==45)
assert(P.close(1,{x=0,y=0,z=0},5,0))
assert(not P.close(1,{x=0,y=0,z=0},5,1500000001))
print('Runtime contract checks passed')
