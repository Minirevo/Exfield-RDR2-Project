-- Run from frontier_inventory: lua5.4 tests/ammo_recovery.lua
dofile('weapons.lua')
InventoryConfig={Slots=2,WeightGrams=25000,QuickAmmoCapacity=30}
local function clone(x)
 if type(x)~='table' then return x end
 local c={};for k,v in pairs(x) do c[k]=clone(v) end;return c
end
-- A metadata codec stand-in: round-trip independent table copies.
local coded,serial={},0
json={encode=function(t) serial=serial+1;local k='m'..serial;coded[k]=clone(t);return k end,
 decode=function(k) if k=='{}' then return {} end;return clone(assert(coded[k],k)) end}
Inventory={items={
 weapon_cattleman={grams=1000,maxStack=1,metadata='{}'},
 weapon_lancaster={grams=3000,maxStack=1,metadata='{}'},
 ammo_revolver={grams=16,maxStack=100,metadata='{}',classification='ammo'},
 ammo_repeater={grams=22,maxStack=100,metadata='{}',classification='ammo'},
 filler={grams=1,maxStack=1,metadata='{}'}
}}
function Inventory.Int(v,max) return type(v)=='number' and v%1==0 and v>=1 and v<=max end
dofile('server/slots.lua')
local db={}
local function box(id,slots,limit,entries)
 db[id]={id=id,slot_limit=slots,weight_limit=limit,revision=0,slots=entries or {}}
end
local function stack(item,n,metadata,instance) return {item=item,quantity=n,metadata=metadata or '{}',instance=instance} end
function Inventory.Load(id) if not db[id] then return false,'not_found' end;return true,clone(db[id]) end
function Inventory.Ensure(id,kind,slots,grams) if not db[id] then box(id,slots,grams) end;return true end
function Inventory.Uuid() serial=serial+1;return 'test'..serial end
local fail=false
function Inventory.Commit(key,actor,fp,...)
 local boxes={...};assert(#boxes<=2)
 for _,b in ipairs(boxes) do if db[b.id].revision~=b.revision then return false,'conflict' end end
 for _,b in ipairs(boxes) do b.revision=b.revision+1;db[b.id]=clone(b) end
 if fail then fail=false;return false,'database_error' end
 return true,key
end
dofile('server/ammo_recovery.lua')
local id='f_test'
local e,b,p='e_'..id,'p_'..id,'r_'..id
box(e,4,10000,{[1]=stack('weapon_lancaster',1,json.encode({loaded=4}),'l'),
 [2]=stack('weapon_cattleman',1,json.encode({loaded=0,checkout={token='draw',rounds=6}}),'c'),
 [3]=stack('ammo_revolver',28),[4]=stack('ammo_repeater',30)})
box(b,2,25000,{[1]=stack('filler',1),[2]=stack('filler',1)})
-- Lost SQL reply: source and destination already committed. Retry must not double.
fail=true;local ok,why=Inventory.RecoverAmmo(id,false);assert(not ok and why=='database_error')
ok,why=Inventory.RecoverAmmo(id,false);assert(ok and why==8)
assert(db[e].slots[3].quantity==30)
assert(db[e].slots[4].quantity==30)
assert(json.decode(db[e].slots[1].metadata).loaded==0)
local m=json.decode(db[e].slots[2].metadata);assert(m.loaded==0 and m.checkout==nil)
local before=Inventory.PendingAmmoCount(db[p]);assert(before==8)
ok,why=Inventory.RecoverAmmo(id,false);assert(ok and why==before)
-- One free slot: one ammo type fits, the other remains pending.
db[b].slots[1]=nil;db[b].revision=db[b].revision+1
ok,why=Inventory.RecoverAmmo(id,true);assert(ok and why==4)
db[b].slots[2]=nil;db[b].revision=db[b].revision+1
ok,why=Inventory.RecoverAmmo(id,true);assert(ok and why==0)
local total=0;for _,row in pairs(db[b].slots) do total=total+row.quantity end
assert(total==8 and Inventory.PendingAmmoCount(db[p])==0)
print('Ammo recovery, overflow, and uncertain-commit retry tests passed')
