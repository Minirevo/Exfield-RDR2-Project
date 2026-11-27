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
print('Damage lab rules passed')
