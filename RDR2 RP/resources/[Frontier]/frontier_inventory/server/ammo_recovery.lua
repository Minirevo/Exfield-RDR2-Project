-- All ammunition refunds are ordinary revision-checked inventory transactions.
-- A weapon's checkout lives on the weapon item and is written together with
-- the ammo debit. No client-supplied refund quantity or separate cash-like credit.
local R=FrontierWeaponRules
Inventory.AmmoRecovered={}
Inventory.AmmoRecoveryBusy={}
Inventory.AmmoWrites={}
local function load(id,prefix,kind,slots,grams)
 local ok,box=Inventory.Load(prefix..id)
 if not ok and box=='not_found' then
  ok,box=Inventory.Ensure(prefix..id,kind,slots,grams)
  if ok then ok,box=Inventory.Load(prefix..id) end
 end
 return ok,box
end
function Inventory.PendingAmmo(id)
 return load(id,'r_','storage',200,100000000)
end
local function boxes(id)
 local c=InventoryConfig
 local ok,e=load(id,'e_','storage',4,10000);if not ok then return nil,e end
 local got,b=load(id,'p_','player',c.Slots,c.WeightGrams);if not got then return nil,b end
 local found,p=Inventory.PendingAmmo(id);if not found then return nil,p end
 return e,b,p
end
function Inventory.Checkout(row,s)
 local def=R.models[row.item]
 if not def then return nil end
 local loaded,m=R.loaded(row,def)
 local c=m and m.checkout
 if loaded~=0 or type(c)~='table' or c.token~=s.token or not R.integer(c.rounds,0,def.capacity) then return nil end
 return c,m
end
local function candidate(box,item,limit,first,last,quantity)
 local def=Inventory.items[item]
 local grams=math.floor((box.weight_limit-Inventory.Weight(box))/def.grams)
 if grams<1 then return nil end
 for pass=1,2 do
  for i=first,last do
   local row=box.slots[i]
   if (pass==1 and row and row.item==item and row.metadata==def.metadata and not row.instance) or (pass==2 and not row) then
    local n=math.min(quantity,grams,limit-(row and row.quantity or 0))
    if n>0 then return i,n end
   end
  end
 end
end
local function destination(e,b,p,item,quantity,allowPending)
 local def=Inventory.items[item]
 local slot,n=candidate(e,item,math.min(def.maxStack,InventoryConfig.QuickAmmoCapacity or 30),3,4,quantity)
 if slot then return e,slot,n end
 slot,n=candidate(b,item,def.maxStack,1,b.slot_limit,quantity)
 if slot then return b,slot,n end
 if allowPending then
  slot,n=candidate(p,item,def.maxStack,1,p.slot_limit,quantity)
  if slot then return p,slot,n end
 end
end
local function commit(id,from,to,kind)
 local key=Inventory.Uuid()
 if not key then return false,'database_error' end
 if not to or to==from then return Inventory.Commit(key,'player:'..id,kind,from) end
 return Inventory.Commit(key,'player:'..id,kind,from,to)
end
local function put(to,item,slot,n)
 return Inventory.Place(to,{item=item,metadata=Inventory.items[item].metadata,quantity=n},slot)
end
function Inventory.PendingAmmoCount(box)
 local n=0;for _,row in pairs(box.slots) do n=n+row.quantity end;return n
end
function Inventory.RecoverAmmo(id,pendingOnly)
 -- Reload on each step. Atomic source reduction + destination addition means
 -- retrying after any uncertain commit cannot create another copy.
 for attempt=1,1000 do
  local e,b,p=boxes(id);if not e then return false,b end
  local from,row,def,m,quantity
  if not pendingOnly then
   for _,box in ipairs({e,b}) do
    for i=1,box.slot_limit do
     local entry=box.slots[i];local model=entry and R.models[entry.item]
     if model then
      local loaded,meta=R.loaded(entry,model)
      if loaded==nil then return false,'invalid_metadata' end
      local c=meta.checkout
      if c~=nil and (loaded~=0 or type(c)~='table' or type(c.token)~='string' or not R.integer(c.rounds,0,model.capacity)) then return false,'invalid_metadata' end
      if loaded>0 or c then from,row,def,m,quantity=box,entry,model,meta,c and c.rounds or loaded;break end
     end
    end
    if row then break end
   end
  end
  if row then
   local to,slot,n
   if quantity>0 then
    to,slot,n=destination(e,b,p,def.ammo,quantity,true)
    if not to then return false,'slots' end
    local placed,issue=put(to,def.ammo,slot,n);if not placed then return false,issue end
    quantity=quantity-n
   end
   m.checkout=nil;m.loaded=quantity
   row.metadata=json.encode(m)
   local ok,issue=commit(id,from,to,'sessionAmmoRefund')
   if not ok and issue~='conflict' then return false,issue end
  else
   local moved=false
   for i=1,p.slot_limit do
    local entry=p.slots[i]
    if entry then
     if not Inventory.items[entry.item] or Inventory.items[entry.item].classification~='ammo' then return false,'invalid_item' end
     local to,slot,n=destination(e,b,p,entry.item,entry.quantity,false)
     if to then
      local ok,issue=put(to,entry.item,slot,n);if not ok then return false,issue end
      local taken,why=Inventory.Take(p,i,n);if not taken then return false,why end
      local saved,err=commit(id,p,to,'pendingAmmoRefund')
      if not saved and err~='conflict' then return false,err end
      moved=true;break
     end
    end
   end
   if not moved then return true,Inventory.PendingAmmoCount(p) end
  end
 end
 return false,'busy'
end
