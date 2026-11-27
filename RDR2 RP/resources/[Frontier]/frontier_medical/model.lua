-- Persistent, deterministic game physiology. Not a real medical model.
FrontierMedicalModel={}
local M,C=FrontierMedicalModel,FrontierMedicalConfig
local valid={};for _,r in ipairs(C.regions) do valid[r]=true end
local function clamp(v) return math.max(0,math.min(C.max,math.floor(tonumber(v) or 0))) end
function M.new(life)
 return {life=life or 1,blood=C.max,pain=0,trauma=0,oxygen=C.max,deprivation=0,lastDrowning=0,tonicUntil=0,down=false,dead=false,nativeSeen=false,wounds={}}
end
-- Upgrade existing persisted JSON in place, without discarding V1 injuries.
function M.normalize(s)
 s.trauma=clamp(s.trauma or 0);s.oxygen=clamp(s.oxygen==nil and C.max or s.oxygen)
 s.deprivation=clamp(s.deprivation or 0);s.lastDrowning=tonumber(s.lastDrowning) or 0
 -- V1 only set dead after observing provider death. New deaths explicitly set false.
 if s.nativeSeen==nil then s.nativeSeen=s.dead==true end
 return s
end
function M.region(r) return valid[r] and r or 'chest' end
function M.bleed(s)
 local n=0;for _,w in pairs(s.wounds) do n=n+(w.bleed or 0) end;return math.min(150,n)
end
function M.pain(s,now) return math.max(0,s.pain-((s.tonicUntil or 0)>now and C.tonicRelief or 0)) end
function M.status(s,now)
 if s.dead or s.blood<=0 then return 'dead' end
 if s.down then return 'unconscious' end
 if s.blood<550 or M.pain(s,now)>650 or (s.trauma or 0)>=450 or (s.oxygen or C.max)<650 or (s.deprivation or 0)>=500 then return 'critical' end
 if next(s.wounds) or s.blood<950 or (s.trauma or 0)>0 or (s.oxygen or C.max)<950 or (s.deprivation or 0)>0 then return 'injured' end
 return 'stable'
end
function M.updateDown(s,now)
 M.normalize(s)
 if s.dead or s.blood<=0 or s.trauma>=C.max or s.oxygen<=0 or s.deprivation>=C.max then
  s.dead=true;s.down=true;return
 end
 local p=M.pain(s,now)
 if s.blood<=C.downBlood or p>=C.downPain or s.trauma>=C.downTrauma or s.oxygen<=C.downOxygen or s.deprivation>=C.downDeprivation then s.down=true
 elseif s.down and s.blood>=C.wakeBlood and p<C.wakePain and s.trauma<=C.wakeTrauma and s.oxygen>=C.wakeOxygen and s.deprivation<=C.wakeDeprivation then s.down=false end
end
function M.injure(s,region,kind,damage,now)
 if s.dead or s.blood<=0 then return false end
 region=M.region(region)
 damage=math.max(1,math.min(C.maxDamageReport,math.floor(damage)))
 if kind~='penetrating' and kind~='fall' and kind~='cut' and kind~='burn' and kind~='bite' then kind='blunt' end
 local w=s.wounds[region] or {severity=0,bleed=0,fracture=false,splinted=false,kind=kind}
 w.kind=kind;w.severity=clamp(w.severity+damage*12)
 local bleed=kind=='penetrating' and math.ceil(damage*.8) or (kind=='cut' or kind=='bite') and math.ceil(damage*.5) or kind=='burn' and 0 or math.ceil(damage*.12)
 w.bleed=math.min(100,w.bleed+bleed)
 if (region:find('_arm',1,true) or region:find('_leg',1,true)) and (kind=='fall' and damage>=20 or damage>=45) then w.fracture=true;w.splinted=false end
 s.wounds[region]=w;s.pain=clamp(s.pain+damage*9);M.updateDown(s,now);return true
end
local kinds={penetrating=true,cut=true,fall=true,blunt=true,burn=true,bite=true}
local function integer(n,min,max) return type(n)=='number' and n%1==0 and n>=min and n<=max end
function M.validReport(hits,drowning)
 if type(hits)~='table' or type(drowning)~='boolean' or #hits>C.maxGroups then return false end
 local total,count=0,0
 for k,v in pairs(hits) do
  if not integer(k,1,#hits) or type(v)~='table' or not valid[v.region] or not kinds[v.kind] or not integer(v.raw,1,C.maxRawGroup) then return false end
  total=total+v.raw;count=count+1
  if total>C.maxRawBatch then return false end
 end
 return count==#hits and (count>0 or drowning)
end
function M.applyRaw(s,r,kind,raw,now)
 if s.dead or s.blood<=0 then return false end
 M.normalize(s)
 if not valid[r] or not kinds[kind] or not integer(raw,1,C.maxRawGroup) then return false end
 local wound=math.max(1,math.min(C.maxDamageReport,math.floor(raw/C.rawPerWound+.5)))
 -- Fixed raw scale: the artificial native buffer never determines wound severity.
 local multiplier=r=='head' and 1.5 or (r=='chest' or r=='abdomen') and 1 or .65
 s.trauma=clamp(s.trauma+math.ceil(raw*C.traumaPerRaw*multiplier))
 M.injure(s,r,kind,wound,now);M.updateDown(s,now)
 return true
end
function M.drown(s,now)
 if s.dead then return false end
 M.normalize(s);s.oxygen=clamp(s.oxygen-C.drowningPerReport);s.lastDrowning=now
 M.updateDown(s,now);return true
end
function M.deprive(s,pct,now)
 if s.dead or not integer(pct,1,5) then return false end
 M.normalize(s);s.deprivation=clamp(s.deprivation+pct*C.deprivationPerPct)
 M.updateDown(s,now);return true
end
function M.breathing(s)
 if s.dead or s.oxygen==0 then return 'Absent' end
 if (s.oxygen or C.max)<350 then return 'Very weak' end
 if (s.oxygen or C.max)<650 then return 'Laboured' end
 return 'Regular'
end
function M.tick(s,now,nourished)
 M.updateDown(s,now)
 if s.dead then return end
 local bleeding=M.bleed(s)
 if bleeding>0 then s.blood=clamp(s.blood-bleeding)
 elseif nourished then s.blood=clamp(s.blood+C.bloodRecovery) end
 s.pain=clamp(s.pain-C.painRecovery)
 if now-s.lastDrowning>=C.drowningQuietSeconds then s.oxygen=clamp(s.oxygen+C.oxygenRecovery) end
 if nourished then
  s.trauma=clamp(s.trauma-C.traumaRecovery)
  s.deprivation=clamp(s.deprivation-C.deprivationRecovery)
 end
 for r,w in pairs(s.wounds) do
  if w.bleed==0 and (not w.fracture or w.splinted) and nourished then
   w.severity=clamp(w.severity-C.woundRecovery)
   if w.severity==0 then s.wounds[r]=nil end
  end
 end
 M.updateDown(s,now)
end
function M.choose(s,item,now)
 local region,best=nil,0
 for _,r in ipairs(C.regions) do
  local w=s.wounds[r];local score=w and (item=='bandage' and w.bleed or item=='splint' and w.fracture and not w.splinted and w.severity) or 0
  if type(score)=='number' and score>best then region,best=r,score end
 end
 if item=='tonic' and s.pain>0 and (s.tonicUntil or 0)<=now then return 'head' end
 return region
end
function M.eligible(s,item,r,now)
 if s.dead or s.blood<=0 then return false end
 if item=='tonic' then return s.pain>0 and (s.tonicUntil or 0)<=now end
 if not valid[r] then return false end
 local w=s.wounds[r];if not w then return false end
 if item=='bandage' then return w.bleed>0 end
 if item=='splint' then return w.fracture and not w.splinted end
 return false
end
function M.treat(s,item,r,now)
 if not M.eligible(s,item,r,now) then return false end
 if item=='tonic' then s.tonicUntil=now+C.tonicSeconds
 elseif item=='bandage' then s.wounds[r].bleed=math.max(0,s.wounds[r].bleed-C.bandageStrength)
 elseif item=='splint' then s.wounds[r].splinted=true end
 M.updateDown(s,now);return true
end
function M.restrictions(s)
 local legs,arms=false,false
 for r,w in pairs(s.wounds) do
  if w.fracture and not w.splinted then
   if r:find('_leg',1,true) then legs=true end
   if r:find('_arm',1,true) then arms=true end
  end
 end
 return {down=s.down or s.dead or s.blood<=0,legs=legs,arms=arms}
end
function M.exam(s,r,now)
 local w=s.wounds[r]
 return w and {kind=w.kind,severity=w.severity>=700 and 'Severe' or w.severity>=300 and 'Moderate' or 'Minor',
 bleeding=w.bleed>=40 and 'Heavy' or w.bleed>0 and 'Active' or 'Controlled',
 fracture=w.fracture and (w.splinted and 'Stabilised' or 'Suspected fracture') or 'No obvious fracture'} or {kind='No visible wound'}
end
function M.pulse(s,now)
 if s.dead or s.blood<=0 then return 'Absent' end
 if s.blood<350 then return 'Very weak, rapid' end
 if s.blood<650 or M.pain(s,now)>500 then return 'Rapid' end
 return 'Regular'
end
