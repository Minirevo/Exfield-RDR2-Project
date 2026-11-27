dofile('rules.lua')
local L=FrontierDamageLab
assert(L.validMode('guarded') and not L.validMode('god'))
assert(L.target(250,'observe')==250 and L.target(250,'refill')==250)
assert(L.target(250,'buffer')==5000 and L.target(6000,'guarded')==6000)
assert(L.target(0,'buffer')==nil and L.target(250,'invalid')==nil)
assert(L.loss(250,230)==20 and L.loss(230,250)==0 and L.loss(nil,10)==0)
local s=L.newStats()
assert(s.rawLoss==0 and not s.dead)
s.lossSamples=1;s.rawLoss=20
assert(L.summary(s):find('rawLoss=20',1,true))
-- A missing/erroring native used as the only argument to tostring must be safe.
assert(tostring(L.readNative(nil))=='nil')
assert(tostring(L.readNative(function() error('native failure') end))=='nil')
assert(tostring(L.readNative(function() end))=='nil')
local a,b=L.readNative(function(n) return false,n end,42)
assert(a==false and b==42)
for _,mode in ipairs({'melee','knife','revolver','wolf'}) do
 assert(L.npcAction(mode)==mode and type(L.npcs[mode].model)=='string')
end
assert(L.npcAction('clear')=='clear' and L.npcAction('stop')=='clear')
assert(L.npcAction('arbitrary')==nil and L.npcAction({})==nil)
assert(L.npcs.melee.weapon==nil and L.npcs.wolf.animal and L.npcs.revolver.weapon)
print('Damage lab rules, NPC whitelist and missing-native regression passed')
