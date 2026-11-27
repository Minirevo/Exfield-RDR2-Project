-- Pure integer simulation; values use the existing 0..1000 scale.
FrontierNeedsModel={}
local M,C=FrontierNeedsModel,FrontierNeedsConfig
local function clamp(v) return math.max(0,math.min(C.maximum,math.floor(v))) end
function M.capacity(energy,thirst)
 local reserve=math.min(energy,thirst,C.low)
 return C.minimumCapacity+math.floor((C.maximum-C.minimumCapacity)*reserve/C.low)
end
function M.step(old,activity,basal,locked)
 local h,t,e,s=clamp(old.hunger),clamp(old.thirst),clamp(old.energy),clamp(old.stamina)
 if basal then h=clamp(h-C.basalHunger);t=clamp(t-C.basalThirst) end
 -- A lowered capacity limits new recovery; it must not drain stored stamina while idle.
 local drain=activity=='sprint' and C.sprintDrain or activity=='jog' and C.jogDrain or activity=='swim' and C.swimDrain or 0
 local restored=0
 if drain>0 then
  s=math.max(0,s-drain)
 elseif activity=='idle' or activity=='walk' or activity=='mounted' then
  local rate=activity=='walk' and C.walkStamina or C.idleStamina
  restored=math.max(0,math.min(rate,M.capacity(e,t)-s,e*C.staminaPerEnergy))
  -- A recovery step cannot spend energy and replenish it simultaneously.
  if restored>0 then
   e=e-math.ceil(restored/C.staminaPerEnergy)
   s=math.max(s,math.min(s+restored,M.capacity(e,t)))
  else
   local rate=activity=='walk' and C.walkEnergyRecovery or C.energyRecovery
   -- Energy can only be rebuilt from available food AND water.
   if h>0 and t>0 and e<C.maximum then
    local gain=math.min(rate,C.maximum-e,math.floor(h*C.costScale/C.foodCost),math.floor(t*C.costScale/C.waterCost))
    if gain>0 then
     h=h-math.ceil(gain*C.foodCost/C.costScale)
     t=t-math.ceil(gain*C.waterCost/C.costScale)
     e=e+gain
    end
   end
  end
 end
 local cap=M.capacity(e,t)
 if s<=0 then locked=true elseif locked and s>=C.resumeSprint then locked=false end
 return {hunger=h,thirst=t,energy=e,stamina=s,capacity=cap,locked=locked==true}
end
function M.damage(hunger,thirst)
 return (hunger==0 and C.starvePct or 0)+(thirst==0 and C.dehydratePct or 0)
end
