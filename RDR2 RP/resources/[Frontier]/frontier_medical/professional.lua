-- Deterministic gameplay physiology and server-timed operation scoring.
local M,C=FrontierMedicalModel,FrontierMedicalConfig
local function bounded(v,max) return math.max(0,math.min(max,math.floor(tonumber(v) or 0))) end
local function limb(r) return r:find('_arm',1,true) or r:find('_leg',1,true) end
local function trunk(r) return r=='chest' or r=='abdomen' end
local function foreign(w) return (w.projectile or 0)+(w.fragment or 0) end
function M.advancedInjury(w,r,kind,d)
 w.bone=bounded(w.bone or (w.fracture and 100 or 0),100)
 if limb(r) then
  local mult=({fall=5,blunt=3,penetrating=4,bite=2,cut=1})[kind] or 0
  w.bone=bounded(w.bone+d*mult,100)
  if w.bone>=100 then w.fracture=true;w.splinted=false;w.aligned=false end
 end
 if (kind=='penetrating' or kind=='cut' or kind=='bite') and d>=7 then w.deep=true;w.dirty=true end
 if trunk(r) and (kind=='penetrating' and d>=7 or kind=='cut' and d>=14 or kind=='fall' and d>=18 or kind=='blunt' and d>=20) then
  w.internal=bounded((w.internal or 0)+math.max(1,math.ceil(d*.24)),45)
  w.organ=bounded((w.organ or 0)+math.ceil(d*.85),100)
 end
 -- Deterministic alternating retention, not a claim about real ballistics.
 -- Batch counts are not individual bullets; one retained object per eligible batch.
 if kind=='penetrating' and d>=7 then
  w.penetrations=(w.penetrations or 0)+1
  if w.penetrations%2==1 then w.projectile=bounded((w.projectile or 0)+1,4) end
 elseif (kind=='cut' or kind=='fall') and d>=15 then
  w.fragmentHits=(w.fragmentHits or 0)+1
  if w.fragmentHits%3==1 then w.fragment=bounded((w.fragment or 0)+1,3);w.deep=true;w.dirty=true end
 end
end
function M.internalBleed(s)
 local n=0;for _,w in pairs(s.wounds) do n=n+(w.internal or 0) end;return math.min(100,n)
end
function M.canHeal(w)
 return not w.deep and not w.dirty and foreign(w)==0 and (w.internal or 0)==0 and (w.organ or 0)==0 and (not w.fracture or w.aligned==true or w.aligned==nil)
end
function M.advancedTick(s,now)
 local chest=s.wounds.chest;local organ=chest and (chest.organ or 0) or 0
 local internal=M.internalBleed(s)
 local totalOrgan=0
 for _,w in pairs(s.wounds) do
  totalOrgan=totalOrgan+(w.organ or 0)
  if foreign(w)>0 then s.pain=bounded(s.pain+2,1000) end
  if not w.fracture and (w.bone or 0)>0 and w.bleed==0 then w.bone=math.max(0,w.bone-1) end
 end
 if organ>0 then s.oxygen=math.min(s.oxygen,math.max(300,1000-organ*7)) end
 local target=bounded(math.max(0,850-s.blood)*1.25+internal*3+totalOrgan*2,1000)
 if s.shock<target then s.shock=math.min(target,s.shock+35) else s.shock=math.max(target,s.shock-25) end
end
function M.professionalFindings(s,r)
 local w=s.wounds[r] or {};local out={}
 if (w.internal or 0)>0 then out[#out+1]=(w.internal>=20 and 'Marked' or 'Suspected')..' internal bleeding' end
 if (w.organ or 0)>0 then out[#out+1]=r=='chest' and 'Suspected lung injury' or 'Suspected abdominal organ injury' end
 if (w.projectile or 0)>0 then out[#out+1]='Suspected retained projectile ('..w.projectile..')' end
 if (w.fragment or 0)>0 then out[#out+1]='Suspected retained fragment ('..w.fragment..')' end
 if w.deep then out[#out+1]='Deep wound requires closure' end
 if w.dirty then out[#out+1]='Contaminated wound' end
 if w.fracture then out[#out+1]=w.aligned and 'Realigned fracture' or 'Fracture requires definitive treatment'
 elseif (w.bone or 0)>=45 then out[#out+1]='Suspected bone injury' end
 if #out==0 then out[1]='No additional finding on assessment' end
 return out
end
function M.vitals(s,now)
 if s.dead then return {pulse=0,respiration=0,temperature='—',circulation='Absent'} end
 local shock=s.shock or 0;local pain=M.pain(s,now)
 return {pulse=bounded(70+shock*.10+pain*.035,180),respiration=bounded(14+shock*.017+(1000-s.oxygen)*.025,45),
  temperature='Normal range',circulation=shock>=650 and 'Poor' or shock>=350 and 'Impaired' or 'Adequate'}
end
function M.procedureEligible(s,r,id,now)
 if s.dead or s.blood<=0 or not C.procedures[id] then return false end
 local w=s.wounds[r]
 if id=='saline' then return s.blood<850 or (s.shock or 0)>300 end
 if id=='morphine' then return s.pain>=100 and (s.tonicUntil or 0)<=now end
 if not w then return false end
 if id=='suture' then return w.deep==true and not w.dirty and foreign(w)==0 and (w.internal or 0)==0 end
 if id=='extract' then return foreign(w)>0 end
 if id=='haemostasis' then return (w.internal or 0)>0 end
 if id=='repair' then return (w.organ or 0)>0 and (w.internal or 0)==0 end
 if id=='realign' then return w.fracture==true and not w.aligned end
 if id=='disinfect' then return w.dirty==true end
 return false
end
function M.applyProcedure(s,r,id,outcome,now)
 if not M.procedureEligible(s,r,id,now) then return false end
 if outcome=='failed' then return false end
 local w=s.wounds[r]
 if outcome=='complication' then
  s.pain=bounded(s.pain+60,1000);s.trauma=bounded(s.trauma+30,1000)
  if w then w.bleed=bounded(w.bleed+8,100);w.severity=bounded(w.severity+40,1000) end
 elseif outcome=='success' then
  if id=='suture' then w.deep=false;w.bleed=0;w.severity=math.max(1,w.severity-100)
  elseif id=='extract' then
   if (w.projectile or 0)>0 then w.projectile=w.projectile-1 else w.fragment=w.fragment-1 end
  elseif id=='haemostasis' then w.internal=0
  elseif id=='repair' then w.organ=0
  elseif id=='realign' then w.aligned=true;w.splinted=true;w.bone=40
  elseif id=='disinfect' then w.dirty=false
  elseif id=='morphine' then s.tonicUntil=now+C.tonicSeconds;s.pain=math.max(0,s.pain-200);s.oxygen=math.max(100,s.oxygen-30)
  elseif id=='saline' then
   -- Temporary circulatory support, not replacement red cells.
   s.shock=math.max(0,(s.shock or 0)-200)
   s.blood=math.min(850,s.blood+40)
  end
 else return false end
 M.updateDown(s,now);return true
end
function M.scoreStage(elapsed,center,window)
 if type(elapsed)~='number' or elapsed<0 or elapsed>C.stageTimeoutMs then return 'failed' end
 local distance=math.abs(elapsed-center)
 if distance<=window then return 'success' end
 if distance<=window+450 then return 'failed' end
 return 'complication'
end
-- Admin presets are explicit, bounded, and operate on a living test character.
function M.testInjury(s,r,kind,amount,now)
 if s.dead or M.region(r)~=r then return false end
 if kind=='raw' then return M.applyRaw(s,r,'blunt',amount,now) end
 if kind=='penetrating' or kind=='blunt' or kind=='fall' or kind=='cut' or kind=='burn' or kind=='bite' then return M.applyRaw(s,r,kind,amount,now) end
 if kind=='fracture' and not limb(r) then return false end
 if (kind=='internal' or kind=='organ') and not trunk(r) then return false end
 if not ({fracture=true,internal=true,organ=true,bullet=true,splinter=true,deep=true,shock=true})[kind] then return false end
 if kind=='shock' then s.shock=650;M.updateDown(s,now);return true end
 local w=s.wounds[r] or {kind='blunt',severity=150,bleed=0,fracture=false,splinted=false}
 s.wounds[r]=w
 if kind=='fracture' then w.bone=100;w.fracture=true;w.aligned=false;w.splinted=false
 elseif kind=='internal' then w.internal=12
 elseif kind=='organ' then w.organ=55;w.internal=8
 elseif kind=='bullet' then w.kind='penetrating';w.kinds=w.kinds or {};w.kinds.penetrating=true;w.projectile=1;w.deep=true;w.dirty=true;w.bleed=12
 elseif kind=='splinter' then w.kind='cut';w.kinds=w.kinds or {};w.kinds.cut=true;w.fragment=1;w.deep=true;w.dirty=true;w.bleed=6
 elseif kind=='deep' then w.kind='cut';w.kinds=w.kinds or {};w.kinds.cut=true;w.deep=true;w.dirty=true;w.bleed=10 end
 s.pain=bounded(s.pain+100,1000);M.updateDown(s,now);return true
end
