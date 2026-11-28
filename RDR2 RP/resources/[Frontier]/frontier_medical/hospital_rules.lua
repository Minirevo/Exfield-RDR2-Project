FrontierHospitalRules={}
local R,C=FrontierHospitalRules,FrontierHospitalConfig
function R.plan(kind,id,count,owned)
 local targets={}
 if kind=='kit' then local kit=C.kits[id];if not kit then return end;targets=kit.items
 elseif kind=='item' then
  local item=C.supplies[id];if not item or type(count)~='number' or count%1~=0 or count<1 or count>item.max then return end
  targets[id]=math.min(item.max,(owned[id] or 0)+count)
 else return end
 local lines,total={},0
 for item,target in pairs(targets) do
  local def=C.supplies[item]
  local qty=math.max(0,math.min(def.max,target)-(owned[item] or 0))
  if qty>0 then lines[#lines+1]={item=item,count=qty,price=def.price};total=total+qty*def.price end
 end
 table.sort(lines,function(a,b)return a.item<b.item end)
 return lines,total
end
function R.status(row,now)
 if row.status=='pending' and tonumber(row.due_at)<=now then return 'overdue' end
 return row.status
end
function R.payable(status) return status=='pending' or status=='reported' end
