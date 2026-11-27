dofile('config.lua')
dofile('shared/rules.lua')
local C,R=LogisticsConfig,LogisticsRules
assert(R.recoverQuantity(100)==90)
assert(R.recoverQuantity(1,function()return 1 end)==1)
local kept,lost=R.recoverQuantity(1,function()return 100 end)
assert(kept==0 and lost==1)
for n=1,10000 do
    local a,b=R.recoverQuantity(n,function()return 1 end)
    assert(a+b==n and a>=0 and b>=0)
end
assert(R.loadingSeconds(0,0,1)==0)
assert(R.loadingSeconds(400000,500,1)==34)
assert(R.loadingSeconds(400000,500,100)<34)
assert(R.fillCount(0,650000,5)==0)
assert(R.fillCount(650000,650000,5)==5)
assert(R.assemblyQuality({{quality=50,quantity=1},{quality=80,quantity=2}})==70)
assert(C.Models.crate==C.Models.recoveryCrate and not C.Models.timber)
for _,v in pairs(C.Wagons) do assert(v.horses>=1 and v.horses<=4 and v.grams>0 and v.slots>0) end
print('Logistics rules passed')
