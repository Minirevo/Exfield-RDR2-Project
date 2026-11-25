FarmRules={}
local R,C=FarmRules,FarmConfig
function R.count(s) return (s.female or 0)+(s.male or 0)+(s.young or 0) end
function R.new(kind,t) return {kind=kind,last=t,soil=100,growth=0,water=0,feed=0,health=100,female=0,male=0,young=0,products=0,manure=0,breedClock=0,productClock=0,matureClock=0,neglect=0} end
function R.advance(s,t,size)
 local elapsed=math.min(C.maxOffline,math.max(0,t-s.last));s.last=t
 if elapsed==0 then return end
 if s.kind=='field' and s.crop then
  if s.dead then return end
  local c=C.crops[s.crop];local wet=math.min(elapsed,s.water or 0)
  s.water=math.max(0,s.water-wet);s.growth=math.min(1,s.growth+wet/(c.hours*3600)*(s.fertilized and 1.25 or 1))
  if s.growth<1 then s.neglect=wet==elapsed and 0 or ((wet>0 and 0 or s.neglect)+elapsed-wet);if s.neglect>=C.waterGrace then s.dead=true end end
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
