GatherRules={}
local R,C=GatherRules,GatherConfig
function R.clamp(x,lo,hi)return math.max(lo,math.min(hi,x)) end
function R.quality(material,q,maker)
 local m=C.materials[material];if not m then return end
 q=math.floor(R.clamp(q,0,100));local durability,yield=1,1
 if q<20 then durability,yield=.65,.8 elseif q<40 then durability,yield=.85,.9 elseif q<60 then durability,yield=1,1 elseif q<80 then durability,yield=1.25,1.15 elseif q<95 then durability,yield=1.5,1.3 else durability,yield=1.8,1.5 end
 local uses=math.floor(m.uses*durability+.5)
 return {material=m.label,materialId=material,quality=q,maxUses=uses,uses=uses,condition=100,yield=m.yield*yield,manufacturer=maker}
end
function R.key(action,x,y,z)
 local size=(action=='clay' or action=='sand' or action=='prospecting') and 8 or C.cell
 local function cell(v)return math.floor(v/size+.5) end
 return table.concat({action,cell(x),cell(y),cell(z)},':')
end
function R.region(x,y)
 for _,r in ipairs(C.rivers) do if (x-r.x)^2+(y-r.y)^2<=r.r^2 then return r end end
end
function R.protected(x,y)
 for _,r in ipairs(C.protected) do if (x-r.x)^2+(y-r.y)^2<=r.r^2 then return true end end
 return false
end
function R.reward(action,node,score,skill,tool,roll)
 local c=C.actions[action];local scale=(.65+.7*score)*skill.yield*(tool and tool.yield or 1)
 local count=math.max(1,math.floor(c.base*scale+.5))
 if action=='logging' then return 'wood',count end
 if action=='mining' then
  local coal=node.x>2300 and node.y>500
  if roll<.025*skill.rare then return 'gather_gold_ore',1 end
  if roll<.12*skill.rare then return 'gather_copper_ore',count end
  if roll<(coal and .65 or .30) then return 'coal',count end
  if roll<.80 then return 'iron_ore',count end
  return 'gather_stone',count
 end
 if action=='prospecting' then
  local region=R.region(node.x,node.y);local bonus=R.clamp((region and region.gold or .4)*skill.rare*(tool and tool.yield or 1)*(.75+.5*score),.25,2)
  if roll<.03*bonus then return 'gather_gold_nugget',1 end
  if roll<.20*bonus then return 'gather_gold_flakes',1 end
  if roll<.55*bonus then return 'gather_gold_dust',1 end
  return nil,0
 end
 if action=='herbalism' then return node.item or 'gather_herbs',count end
 return 'gather_'..action,count
end

-- Stable definition JSON: Inventory compares registered definitions byte for byte.
function R.encodeQuality(material,q,maker)
 local m=R.quality(material,q,maker)
 return ('{"condition":100,"material":%s,"materialId":%s,"quality":%d,"maxUses":%d,"uses":%d,"yield":%.4f,"manufacturer":%s}'):format(json.encode(m.material),json.encode(m.materialId),m.quality,m.maxUses,m.uses,m.yield,json.encode(m.manufacturer))
end
