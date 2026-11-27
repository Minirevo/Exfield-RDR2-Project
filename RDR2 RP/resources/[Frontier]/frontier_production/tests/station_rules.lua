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

assert(StationConfig.recipes.nails.rounds==1)
assert(StationConfig.recipes.tool_pickaxe_crude.rounds==2)
assert(StationConfig.recipes.tool_pickaxe_iron.rounds==3)
assert(StationConfig.recipes.tool_pickaxe_steel.rounds==4)
assert(StationConfig.recipes.tool_pickaxe_hardened.rounds==5)
for _,r in pairs(StationConfig.recipes) do assert(r.rounds>=1 and r.rounds<=5 and r.manual==r.rounds*StationConfig.roundMs/1000) end
assert(R.roundScore(1200,1,3000,2400,.5)==1)
assert(R.roundScore(4200,2,3000,2400,.5)==1)
assert(R.roundScore(1200,2,3000,2400,.5)==nil)
assert(R.roundScore(2700,1,3000,2400,.5)==nil)
assert(R.batchScore({[1]=1,[3]=.5,[4]=1},1,2)==.5)
assert(R.batchScore({[1]=1,[3]=.5,[4]=1},2,2)==.75)
local results=R.outputs(StationConfig.recipes.tool_pickaxe_iron,2,100,'manual',{0,1},75,'Test')
assert(#results==2 and results[1].metadata==R.encodeTool('iron',55,'Test') and results[2].metadata==R.encodeTool('iron',95,'Test'))
assert(R.materials(StationConfig.recipes.nails,10)[1].count==10)
print('Manual batch and round rules passed')
