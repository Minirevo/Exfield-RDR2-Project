dofile('weapons.lua')
local R=FrontierWeaponRules
local e={slots={[3]={item='ammo_revolver',quantity=2},[4]={item='ammo_repeater',quantity=5}},slot_limit=4}
local b={slots={[1]={item='ammo_revolver',quantity=20},[2]={item='ammo_repeater',quantity=5}},slot_limit=30}
local src,n=R.plan(e,b,'ammo_revolver',0,6);assert(src=='quick' and n==2)
e.slots[3]=nil;src,n=R.plan(e,b,'ammo_revolver',2,6);assert(src=='satchel' and n==4)
src,n=R.plan(e,b,'ammo_repeater',14,14);assert(src==nil and n==0)
src,n=R.plan(e,b,'unknown',0,6);assert(src==nil and n==0)
assert(R.remaining(6,2)==2 and R.remaining(2,3)==nil and R.remaining(2,-1)==nil)
assert(R.remaining(2,0)==0 and R.remaining(2,1.5)==nil)
assert(R.models.weapon_lancaster.slot==1 and R.models.weapon_cattleman.slot==2)
print('Weapon rules passed')
