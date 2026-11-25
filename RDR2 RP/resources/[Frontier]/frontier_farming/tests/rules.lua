dofile('config.lua');dofile('rules.lua')
local R=FarmRules
local s=R.new('field',0);s.crop='carrot';s.water=21600;R.advance(s,21600,'small');assert(s.growth==1)
local d=R.new('field',0);d.crop='wheat';R.advance(d,86400,'small');assert(d.dead)
local a=R.new('chicken',0);a.species='chicken';a.female=2;a.male=1;a.water=3*21600;a.feed=3*21600;R.advance(a,21600,'small');assert(a.products==2)
print('Farming rule smoke tests passed')
