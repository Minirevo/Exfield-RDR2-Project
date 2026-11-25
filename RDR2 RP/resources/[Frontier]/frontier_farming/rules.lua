FarmRules={}
local R,C=FarmRules,FarmConfig
function R.count(s) return (s.female or 0)+(s.male or 0)+(s.young or 0) end
function R.new(kind,t) return {kind=kind,last=t,soil=100,growth=0,water=0,feed=0,health=100,female=0,male=0,young=0,products=0,manure=0,breedClock=0,productClock=0,matureClock=0,neglect=0} end
function R.horseCounts(s)
 s.female,s.male,s.young=0,0,0
 for _,h in ipairs(s.horses or {}) do
  if h.age<C.species.horse.mature*3600 then s.young=s.young+1 else s[h.sex]=s[h.sex]+1 end
 end
end
local function clamp(v) return math.max(1,math.min(100,v)) end
function R.newHorse(id,breed,sex,juvenile,parents)
 local b=C.horseBreeds[breed];local genes={}
 for _,k in ipairs({'speed','stamina','health'}) do
  local v=parents and (parents[1].genes[k]+parents[2].genes[k])/2 or b[k]
  genes[k]=math.floor(clamp(v+math.random(-8,8)))
 end
 return {id=id,breed=breed,sex=sex,age=juvenile and 0 or C.species.horse.mature*3600,genes=genes,health=100,care=100,neglectSeconds=0,training=0,trainedAt=0,parents=parents and {parents[1].id,parents[2].id} or nil}
end
function R.horseValue(h)
 return math.floor((h.genes.speed+h.genes.stamina+h.genes.health)*60*(.25+.75*h.care/100)*(.5+.5*h.health/100)*(1+h.training/200)*(h.age>=C.species.horse.mature*3600 and 1 or .5))
end
function R.advanceHorses(s,elapsed,size,t)
 local n=#s.horses;if n==0 then return end
 local fed=math.min(elapsed,s.feed/n);local watered=math.min(elapsed,s.water/n);local cared=math.min(fed,watered)
 s.feed=math.max(0,s.feed-fed*n);s.water=math.max(0,s.water-watered*n)
 local dry=elapsed-cared;local mare,stallion
 for i=#s.horses,1,-1 do local h=s.horses[i]
  h.age=h.age+elapsed;h.neglectSeconds=h.neglectSeconds+dry;h.care=math.max(0,h.care-dry/3600*.15)
  h.health=math.max(0,math.min(100,h.health+cared/3600-dry/3600))
  if h.health<=0 and h.neglectSeconds>=C.waterGrace*2 then table.remove(s.horses,i)
  elseif h.health>=70 and h.age>=C.species.horse.mature*3600 and not h.listed then
   if h.sex=='female' then mare=h else stallion=h end
  end
 end
 if mare and stallion and #s.horses<C.species.horse.capacity[size] then
  s.breedClock=s.breedClock+cared
  if s.breedClock>=172800 then
   s.horseSerial=(s.horseSerial or 0)+1
   local id=mare.id..'-'..t..'-'..s.horseSerial
   s.horses[#s.horses+1]=R.newHorse(id,math.random(2)==1 and mare.breed or stallion.breed,math.random(2)==1 and 'female' or 'male',true,{mare,stallion})
   s.breedClock=s.breedClock%172800
  end
 else s.breedClock=0 end
 s.manure=math.min(500,s.manure+cared*n/86400)
 R.horseCounts(s)
end
function R.advance(s,t,size)
 local elapsed=math.min(C.maxOffline,math.max(0,t-s.last));s.last=t
 if elapsed==0 then return end
 if s.kind=='field' and s.crop then
  if s.dead then return end
  local c=C.crops[s.crop];local wet=math.min(elapsed,s.water or 0)
  s.water=math.max(0,s.water-wet);s.growth=math.min(1,s.growth+wet/(c.hours*3600)*(s.fertilized and 1.25 or 1))
  if s.growth<1 then s.neglect=wet==elapsed and 0 or ((wet>0 and 0 or s.neglect)+elapsed-wet);if s.neglect>=C.waterGrace then s.dead=true end end
 elseif s.species=='horse' then
  s.horses=s.horses or {};R.advanceHorses(s,elapsed,size,t)
 elseif s.species and R.count(s)>0 then
  local c=C.species[s.species];local count=R.count(s)
  local wet=math.min(elapsed,s.water/count,s.feed/count)
  s.water=math.max(0,s.water-wet*count);s.feed=math.max(0,s.feed-wet*count)
  s.health=math.max(0,math.min(100,s.health+wet/3600-(elapsed-wet)/3600))
  s.neglect=wet==elapsed and 0 or ((wet>0 and 0 or s.neglect)+elapsed-wet)
  if s.neglect>=C.waterGrace*2 then
   local deaths=math.min(count,math.floor(s.neglect/86400)-1)
   for _=1,deaths do if s.young>0 then s.young=s.young-1 elseif s.male>0 then s.male=s.male-1 else s.female=s.female-1 end end
   s.neglect=s.neglect-deaths*86400
  end
  if s.health>=50 then
   s.matureClock=s.matureClock+wet
   if s.young>0 and s.matureClock>=c.mature*3600 then
    local m=math.floor(s.young/2);s.male=s.male+m;s.female=s.female+s.young-m;s.young=0;s.matureClock=0
   end
   if s.male>0 and s.female>0 then
    s.breedClock=s.breedClock+wet
    if s.breedClock>=86400 then
     local born=math.min(math.floor(s.breedClock/86400)*s.female,c.capacity[size]-R.count(s));if born>0 then if s.young==0 then s.matureClock=0 end;s.young=s.young+born end;s.breedClock=s.breedClock%86400
    end
   end
   if c.product then s.productClock=s.productClock+wet;if s.productClock>=c.hours*3600 then s.products=math.min(500,s.products+math.floor(s.productClock/(c.hours*3600))*s.female);s.productClock=s.productClock%(c.hours*3600) end end
   s.manure=math.min(500,(s.manure or 0)+wet*count/86400)
  end
 end
end
function R.world(b,x,y)
 local a=math.rad(b.heading);return b.x+x*math.cos(a)-y*math.sin(a),b.y+x*math.sin(a)+y*math.cos(a)
end
