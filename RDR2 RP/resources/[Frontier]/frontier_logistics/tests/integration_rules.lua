dofile('config.lua')
dofile('shared/rules.lua')
local C,R=LogisticsConfig,LogisticsRules
assert(C.EnabledModels.supplywagon and not C.EnabledModels.wagon04x)
assert(C.CargoOffsets.supplywagon[1].y==-.99 and C.CargoOffsets.supplywagon[2].z==.2)
assert(C.ValidatedModels.supplywagon.wagonHash==-1753201617)
assert(C.Wagons.supplywagon.horses==2 and C.Wagons.supplywagon.grams==650000)
local grams=0
for k,n in pairs(C.Assembly) do assert(C.Parts[k]);grams=grams+C.Parts[k].grams*n end
assert(grams>25000 and grams<1000000)
assert(R.loadingSeconds(100000000,1000000,1)==120)
assert(R.loadingSeconds(1000,1,100)>=3)
for n=1,100 do
 local sum=0
 for sample=1,100 do
  local keep,lost=R.recoverQuantity(n,function()return sample end)
  assert(keep+lost==n);sum=sum+keep
 end
 assert(sum==n*90)
end
print('Logistics configuration and recovery invariants passed')
