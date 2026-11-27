-- Shared catalog; server grants only these inventory-backed weapons.
FrontierWeaponRules={
 reloadDelayMs=2000,
 models={
  weapon_cattleman={model='WEAPON_REVOLVER_CATTLEMAN',ammo='ammo_revolver',nativeAmmo='AMMO_REVOLVER',capacity=6,slot=2},
  weapon_lancaster={model='WEAPON_REPEATER_WINCHESTER',ammo='ammo_repeater',nativeAmmo='AMMO_REPEATER',capacity=14,slot=1}
 }
}
local R=FrontierWeaponRules
function R.integer(v,min,max)
 return type(v)=='number' and v==v and v%1==0 and v>=min and v<=max
end
function R.remaining(issued,reported)
 if not R.integer(reported,0,issued) then return nil end
 return reported
end
function R.count(box,item,first,last)
 local n=0
 for i=first,last do local e=box.slots[i];if e and e.item==item then n=n+e.quantity end end
 return n
end
function R.plan(equipment,bag,item,remaining,capacity)
 local need=math.max(0,capacity-remaining)
 if need==0 then return nil,0 end
 local quick=R.count(equipment,item,3,4)
 if quick>0 then return 'quick',math.min(need,quick) end
 local reserve=R.count(bag,item,1,bag.slot_limit)
 if reserve>0 then return 'satchel',math.min(need,reserve) end
 return nil,0
end
function R.loaded(entry,definition)
 local ok,m=pcall(json.decode,entry.metadata)
 if not ok or type(m)~='table' then return nil end
 local n=m.loaded or 0
 if not R.integer(n,0,definition.capacity) then return nil end
 return n,m
end
