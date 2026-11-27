dofile('../frontier_gathering/config.lua')
dofile('../frontier_gathering/rules.lua')
json={encode=function(v)return string.format('%q',v) end}
dofile('stations.lua')
local R=StationRules
assert(R.npcQuality(42,function(lo,hi)assert(lo==0 and hi==42);return hi end)==42)
assert(R.npcQuality(100,function(lo,hi)return lo end)==0)
assert(R.manualQuality(100,1,75)==95)
assert(R.manualQuality(0,0,0)==0)
assert(R.score(800,.5)==1)
local m=R.materials(StationConfig.recipes.saw,3)
assert(m[1].id=='wood' and m[1].count==6)
assert(R.outputs(StationConfig.recipes.saw,3,1,'npc',0,75,'test')[1].count==9)
local count=0
for _,r in pairs(StationConfig.recipes) do assert(r.manual>0 and r.npc>=r.manual and next(r.inputs));count=count+1 end
assert(count>=40)
print('Station rules OK: '..count..' recipes')

for _,mat in ipairs({'crude','iron','steel','hardened'}) do for q=0,100 do assert(R.encodeTool(mat,q,'Test')==GatherRules.encodeQuality(mat,q,'Test')) end end
