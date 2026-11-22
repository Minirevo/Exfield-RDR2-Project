local hooks,boxes,receipts={}, {}, {}
InventoryConfig={Slots=4,WeightGrams=10000}
local function copy(value)
    if type(value)~='table' then return value end
    local out={}
    for k,v in pairs(value) do out[k]=copy(v) end
    return out
end
Inventory={items={flour={stackable=true,metadata='{}'},water={stackable=true,metadata='{}'},
    bread={stackable=true,metadata='{}'}}}
function Inventory.Int(n,max) return type(n)=='number' and n>0 and n<=max and n==math.floor(n) end
function Inventory.Id(s,max) return type(s)=='string' and #s<=max end
function Inventory.Ensure(id,kind,slots,grams)
    boxes[id]=boxes[id] or {id=id,slot_limit=slots,slots={}}
    return true
end
function Inventory.Load(id)
    if not boxes[id] then return false,'not_found' end
    return true,copy(boxes[id])
end
function Inventory.Replay(key,_,digest)
    if receipts[key] and receipts[key]~=digest then return false,'conflict' end
    return true,receipts[key]~=nil
end
function Inventory.Commit(key,_,digest,...)
    for _,box in ipairs({...}) do boxes[box.id]=copy(box) end
    receipts[key]=digest
    return true,key
end
function Inventory.Take(box,slot,count)
    local entry=box.slots[slot]
    local moved=copy(entry)
    moved.quantity=count
    entry.quantity=entry.quantity-count
    if entry.quantity==0 then box.slots[slot]=nil end
    return true,moved
end
function Inventory.Place(box,entry)
    for slot=1,box.slot_limit do
        if not box.slots[slot] then box.slots[slot]=copy(entry);return true end
    end
    return false,'slots'
end
function trusted(name,fn) hooks[name]=fn end
function requestKey(key) return key end
local file=assert(io.open('../frontier_inventory/server/interface.lua','r'))
local code=file:read('*a');file:close()
local start=assert(code:find('local function productionMove',1,true))
assert(load(code:sub(start)))()
local mutate=hooks.ApplyProductionInventory
local job='00000000-0000-0000-0000-000000000001'
local owner='f_fixture'
Inventory.Ensure('p_'..owner,'player',4,10000)
boxes['p_'..owner].slots[1]={item='flour',quantity=3,metadata='{}'}
local opts={job=job,slots=3,grams=10000,units=2,items={{id='flour',count=2},{id='water',count=1}}}
local ok,why=mutate('frontier_production','reserve',owner,'reserve',opts)
assert(not ok and why=='insufficient_stock' and boxes['p_'..owner].slots[1].quantity==3)
boxes['p_'..owner].slots[2]={item='water',quantity=1,metadata='{}'}
assert(mutate('frontier_production','reserve',owner,'reserve',opts))
assert(mutate('frontier_production','reserve',owner,'reserve',opts))
assert(boxes['p_'..owner].slots[1].quantity==1)
opts.items={{id='bread',count=3}}
ok,why=mutate('frontier_production','finish',owner,'output',opts)
assert(not ok and why=='storage_full' and boxes['prjob_'..job].slots[1])
opts.items[1].count=2
assert(mutate('frontier_production','finish',owner,'output',opts))
assert(mutate('frontier_production','finish',owner,'output',opts))
assert(next(boxes['prjob_'..job].slots)==nil and boxes['prod_'..owner].slots[1].quantity==2)
opts.job=nil;opts.items=nil
assert(mutate('frontier_production','collect',owner,'collect',opts))
assert(mutate('frontier_production','collect',owner,'collect',opts))
assert(next(boxes['prod_'..owner].slots)==nil and boxes['p_'..owner].slots[2].quantity==2)
assert(not mutate('untrusted','collect',owner,'another',opts))
print('Production inventory reserve, output and collection contracts passed')
