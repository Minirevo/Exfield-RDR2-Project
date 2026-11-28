dofile('config.lua');dofile('qte.lua')
local C,Q=FrontierMedicalConfig,FrontierMedicalQTE
for _,d in pairs(C.procedures) do
 local p,a=Q.windows(d,1)
 local p100,a100=Q.windows(d,100)
 assert(p==d.perfect and a==d.acceptable and p<a and p100>p and a100>a and p100<a100)
 assert(d.duration<2500 and a100<d.duration/3)
 for stage=1,d.stages do
  local duration=math.max(1250,d.duration-100-(stage-1)*60)
  local margin=math.max(a100+90,math.floor(duration*.24))
  assert(margin<=duration-margin)
 end
end
assert(Q.score(800,800,65,135,1600)=='perfect')
assert(Q.score(735,800,65,135,1600)=='perfect')
assert(Q.score(734,800,65,135,1600)=='acceptable')
assert(Q.score(935,800,65,135,1600)=='acceptable')
assert(Q.score(936,800,65,135,1600)=='failed')
assert(Q.score(1036,800,65,135,1600)=='complication')
assert(Q.score(-1,800,65,135,1600)=='failed')
assert(Q.score(1601,800,65,135,1600)=='failed')
assert(Q.score(0/0,800,65,135,1600)=='failed')
assert(Q.complete('success','perfect')=='success')
assert(Q.complete('success','acceptable')=='acceptable')
assert(Q.complete('acceptable','perfect')=='acceptable')
assert(Q.isSuccessful('success') and Q.isSuccessful('acceptable') and not Q.isSuccessful('failed'))
assert(Q.xp(28,'success')==28 and Q.xp(28,'acceptable')==14 and Q.xp(28,'complication')==0)
print('Surgical timing windows, stage quality and XP tests passed')
