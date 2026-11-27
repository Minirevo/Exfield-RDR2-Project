-- Physical fulfillment of existing frontier_trade purchase contracts.
local L=LogisticsRuntime
local C=L.C
local function offers(src,w)
 if not w or w.owner_type~='company' or not L.right(src,w,'trade') or GetResourceState('frontier_trade')~='started' then return {} end
 local ok,rows=pcall(function()return exports.frontier_trade:WagonContracts(src,w.owner_id)end)
 if not ok or type(rows)~='table' then return {} end
 return rows
end
local function destination(c)
 local p=L.B:LogisticsStockPoint('business_'..c.destination_id)
 if p and p.ownerType=='company' and p.ownerId==c.buyer_id then return p end
end
local function arrived(src,w,p)
 return p and w.state=='world' and L.stationary(w) and L.near(src,L.point(w),C.InteractionDistance)
  and L.near(src,p,C.InteractionDistance) and L.dist(L.point(w),p)<=C.LoadDistance
end
local function amount(box,item)
 local n=0;for _,s in ipairs(box.slots or {}) do if s.item==item then n=n+tonumber(s.quantity) end end;return n
end
function L.tradeView(src,w)
 local out={};if not w then return out end
 local list=offers(src,w);if #list==0 then return out end
 local ok,box=L.I:LogisticsRead(L.route(w.id));if not ok then return out end
 for _,c in ipairs(list) do
  local p=destination(c)
  c.destination=p and p.name or 'Warehouse unavailable'
  c.point=p;c.onboard=amount(box,c.item_id)
  c.canDeliver=arrived(src,w,p)==true and c.onboard>0 and not L.wagonBusy(w.id)
  out[#out+1]=c
 end
 return out
end
function L.tradeDeliver(src,w,id,qty)
 L.check(w and w.owner_type=='company' and L.right(src,w,'trade') and w.state=='world'
  and L.near(src,L.point(w),C.InteractionDistance) and L.stationary(w) and not L.wagonBusy(w.id),'Approach your stationary company wagon')
 L.check(L.R.integer(qty,1,1000),'Invalid delivery quantity')
 local c;for _,row in ipairs(offers(src,w)) do if row.id==id then c=row;break end end
 L.check(c and qty<=tonumber(c.remaining),'Contract unavailable or quantity exceeds remaining order')
 L.check(arrived(src,w,destination(c)),'Bring the loaded wagon to the buyer warehouse')
 local ok,box=L.I:LogisticsRead(L.route(w.id))
 L.check(ok and amount(box,c.item_id)>=qty,'Not enough contracted goods on this wagon')
 local queued,why=exports.frontier_trade:WagonDispatch(src,w.owner_id,c.id,qty,w.id,c.destination_id)
 L.check(queued,why)
 -- Pending stock is protected by L.wagonBusy until the Trade worker reserves it.
 -- Its original receipt, payment and claim flow handle restart/retry.
 local e=L.entities[w.id];if e then e.publishPending=true;e.tradeRefresh=true end
 return 'Delivery queued in Trade: '..tostring(why)
end
