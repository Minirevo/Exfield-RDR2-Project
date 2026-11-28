dofile('config.lua');dofile('rules.lua')
local h={age=345600,health=100,gear={}}
assert(not HorseRules.ride(h));h.gear.saddle='horse_saddle';assert(HorseRules.ride(h));h.listed=100;assert(not HorseRules.ride(h));h.listed=nil
assert(HorseRules.draft(h,'a_c_horse_shire_darkbay'));assert(not HorseRules.draft(h,'a_c_horse_morgan_bay'));assert(HorseRules.id('1'));assert(not HorseRules.id('bad!'));print('Horse rules passed')
