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

-- Known animal hash issue is not permission to accept a mismatching wagon or horse.
local horse=1066034872;local wagon=-1753201617
local ok,fallback=R.networkModel(0,horse,horse,true);assert(ok and fallback)
assert(not R.networkModel(0,wagon,wagon,false))
assert(not R.networkModel(123,horse,horse,true))
assert(not R.networkModel(0,horse,123,true))
assert(not R.networkModel(nil,horse,horse,true))
assert(R.networkModel(2541765679,wagon,wagon,false))
assert(R.networkModel(horse,horse,horse,true))
print('Network model validation rules passed')

-- Exercise the actual wagon storage and world tick code with stubbed natives/DB.
dofile('tests/wagon_runtime.lua')

dofile('tests/freight_security.lua')

dofile('tests/trade_delivery.lua')
