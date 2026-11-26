dofile('config.lua');dofile('rules.lua')
local R=FarmRules
local s=R.new('field',0);s.crop='carrot';s.water=21600;R.advance(s,21600,'small');assert(s.growth==1)
local d=R.new('field',0);d.crop='wheat';R.advance(d,86400,'small');assert(d.dead)
local a=R.new('chicken',0);a.species='chicken';a.female=2;a.male=1;a.water=3*21600;a.feed=3*21600;R.advance(a,21600,'small');assert(a.products==2)
print('Farming rule smoke tests passed')

local medium={kind='field',size='medium'}
local f=R.new('field',0);f.crop='corn';f.water=0
local p=assert(R.supply(f,medium,'water',4));assert(p.units==4 and p.perUnit==10800 and p.maxUnits==16)
assert(R.supply(f,medium,'water',17)==nil)
f.water=172800;assert(R.supply(f,medium,'water',1)==nil)
f.water=0;f.growth=1;assert(R.supply(f,medium,'water',1)==nil)
local y,seeds=R.harvest(f,'medium',5);assert(y==250 and seeds==110)
f.harvestRemaining=50;f.seedRemaining=25;y,seeds=R.harvest(f,'medium',5);assert(y==50 and seeds==25)
local pen={kind='chicken',size='medium'}
local a=R.new('chicken',0);a.species='chicken';a.female=20;a.male=3
local p=assert(R.supply(a,pen,'feed',46));assert(p.perUnit==43200 and p.maxUnits==92)
p=assert(R.supply(a,pen,'water',6));assert(p.units==6 and p.maxUnits==24)
assert(R.supply(a,pen,'water',1.5)==nil)
print('Variable supply and full harvest tests passed')
