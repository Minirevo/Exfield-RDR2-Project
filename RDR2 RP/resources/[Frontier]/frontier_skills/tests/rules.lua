dofile('rules.lua')
local R=SkillsRules
assert(R.level(0)==1 and R.level(R.threshold(2))==2)
assert(R.level(R.threshold(100))==100)
assert(R.stats(0).yield==1 and R.stats(R.threshold(100)).wear==.75)
for n=2,100 do assert(R.threshold(n)>R.threshold(n-1)) end
print('skills rules passed')
