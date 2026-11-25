dofile('config.lua'); dofile('shared/rules.lua')
local C,R=PropertyConfig,PropertyRules
local s={x=0,y=0,z=0,radius=100,buildings={}}
assert(R.tax(s,C)==1000)
assert(R.expansion(s,C)==15000)
s.radius=125
assert(R.expansion(s,C)==22500)
assert(R.tax(s,C)==1563)
assert(R.capacity({slots=10},{slots=50})==60)
assert(not R.claim({x=0,y=0,z=0},100,{a=s},nil,C))
assert(R.fits(s,{x=25,y=0,z=0},5))
assert(not R.fits(s,{x=124,y=0,z=0},5))
local payout,paid,forgiven=R.foreclosure(10000,1000,C)
assert(payout==3000 and paid==1000 and forgiven==0)
print('rules passed')

local C=PropertyConfig
local b={id='stable',exterior='stable',complete=true,x=100,y=200,z=30,heading=90}
local part=PropertyRules.parts(C.Exteriors.stable,C)[2]
local origin=PropertyRules.transform(b,part)
local inside=PropertyRules.transform(origin,{x=0,y=0,z=1})
assert(PropertyRules.indoor(b,inside,C))
assert(PropertyRules.buildingAt({buildings={stable=b}},inside,C)=='stable')
assert(not PropertyRules.indoor(b,{x=100,y=250,z=30},C))
b.complete=false;assert(not PropertyRules.indoor(b,inside,C))
