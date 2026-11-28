-- Run from frontier_inventory. Verify the Lua adapter routes only the three-box
-- job delivery to the wide routine, preserving the receipt key and actor.
local calls={}
function GetCurrentResourceName() return 'frontier_inventory' end
FrontierLib={Log=function() end}
InventoryConfig={}
json={encode=function(v) return v end}
MySQL={query={await=function(sql,args)
 calls[#calls+1]={sql=sql,args=args}
 return {{{code='ok',replayed=0}}}
end}}
dofile('server/database.lua')
local bag={id='p_f_test',revision=1,slots={}}
local belt={id='b_f_test',revision=2,slots={}}
local stock={id='jobs_test',revision=0,slots={}}
local key,actor,fp='jobs:test:deliver','resource:frontier_jobs','fingerprint'
assert(Inventory.Commit(key,actor,fp,bag,stock))
assert(calls[1].sql:find('frontier_inventory_commit_v1',1,true))
assert(Inventory.CommitJobDelivery(key,actor,fp,bag,belt,stock))
local c=calls[2]
assert(c.sql:find('frontier_inventory_logistics_commit_v1',1,true))
assert(c.args[1]==key and c.args[2]==actor and c.args[3]==fp)
assert(#c.args[4]==3 and c.args[4][1].id==belt.id and c.args[4][2].id==stock.id and c.args[4][3].id==bag.id)
assert(not Inventory.CommitJobDelivery(key,'resource:other',fp,bag,belt,stock))
assert(not Inventory.CommitJobDelivery(key,actor,fp,bag,stock))
assert(#calls==2)
print('Job delivery transaction routing passed')
