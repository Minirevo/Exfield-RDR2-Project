dofile('config.lua');dofile('rules.lua')
local R=GatherRules
local m=R.quality('steel',97,'Smith')
assert(m.maxUses==396 and math.abs(m.yield-1.8)<.0001 and m.condition==100)
assert(R.quality('iron',10,'Smith').maxUses==78)
local skill={yield=1,rare=1,wear=1,window=1}
local item,poor=R.reward('logging',{x=0,y=0},0,skill,nil,.5)
local _,great=R.reward('logging',{x=0,y=0},1,skill,nil,.5)
assert(item=='wood' and great>poor)
assert(R.key('logging',12,12,12)==R.key('logging',12.2,12.2,12.2))
assert(R.key('logging',12,12,12)~=R.key('mining',12,12,12))
print('gathering rules passed')

local p={x=0,y=0,z=0}
assert(R.inReach('logging',p,{x=4,y=0,z=0}))
assert(not R.inReach('logging',p,{x=5,y=0,z=0}))
assert(R.inReach('mining',p,{x=7,y=0,z=-5}))
assert(not R.inReach('mining',p,{x=9,y=0,z=0}))
assert(not R.inReach('mining',p,{x=0,y=0,z=-8}))
