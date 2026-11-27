dofile('config.lua');dofile('model.lua')
local M,C=FrontierNeedsModel,FrontierNeedsConfig
local function full() return {hunger=1000,thirst=1000,energy=1000,stamina=1000} end
local s=full()
for i=1,25 do s=M.step(s,'sprint',false,s.locked) end
assert(s.stamina==0 and s.locked and s.energy==1000 and s.hunger==1000 and s.thirst==1000)
for i=1,4 do s=M.step(s,'idle',false,s.locked) end
assert(s.stamina==200 and not s.locked and s.energy==948 and s.hunger==1000 and s.thirst==1000)
for i=1,16 do s=M.step(s,'idle',false,s.locked) end
assert(s.stamina==1000 and s.energy==740 and s.hunger==1000 and s.thirst==1000)
s=M.step(s,'idle',false,s.locked)
assert(s.energy==744 and s.hunger==998 and s.thirst==997)
s=M.step(full(),'sprint',true,false)
assert(s.hunger==999 and s.thirst==998 and s.energy==1000 and s.stamina==960)
s=full();s.thirst=0;s.energy=0;s.stamina=0
s=M.step(s,'idle',false,true)
assert(s.energy==0 and s.stamina==0 and s.locked and M.damage(s.hunger,s.thirst)==3)
s.hunger=0;assert(M.damage(s.hunger,s.thirst)==5)
s=full();s.energy=0;s.stamina=0
s=M.step(s,'idle',false,true);assert(s.energy==4 and s.stamina==0)
s=M.step(s,'idle',false,true);assert(s.stamina>0 and s.energy==0)
s=full();s.thirst=1;s.energy=999;s.stamina=250
s=M.step(s,'idle',false,false);assert(s.thirst>=0 and s.energy<=1000)
assert(M.capacity(1000,1000)==1000 and M.capacity(0,1000)==250)
assert(M.damage(0,1000)==2 and M.damage(1000,1000)==0)
print('Needs model: sprint, recovery fuel, basal decay, exhaustion and starvation tests passed')
