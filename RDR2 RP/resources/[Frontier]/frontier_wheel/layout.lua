FrontierWheelLayout={}
local function entry(name,kind,target,resource)
 return {name=name,kind=kind,target=target,resource=resource}
end
function FrontierWheelLayout.main(guns)
 return {
  guns and guns[2] or entry('Primary','disabled'),
  guns and guns[1] or entry('Sidearm','disabled'),
  entry('Tools','page','tools'),entry('Food','disabled'),
  entry('Drinks','disabled'),entry('Medicine','disabled'),
  entry('Utility','disabled'),entry('Unarmed','holster'),
  entry('Character','page','character')
 }
end
function FrontierWheelLayout.character()
 return {
  entry('Inventory','menu','inventar','frontier_inventory'),
  entry('Documents','documents'),
  entry('Skills','menu','skills','frontier_skills'),
  entry('Business','menu','business','frontier_business'),
  entry('Property','menu','propertymenu','frontier_property'),
  entry('Finances','menu','frontier_bank','frontier_economy'),
  entry('Trade','menu','handel','frontier_trade'),
  entry('Character','profile'),
  entry('Back','page','main')
 }
end
function FrontierWheelLayout.tools(belt)
 local slots={}
 for i=1,6 do
  local row=belt and belt[i]
  if row and row.kind then
   slots[i]={name=row.name,kind='tool',quality=row.quality,uses=row.uses,maxUses=row.maxUses,equipped=row.equipped,target=i}
  else slots[i]=entry(row and row.name or 'Empty','disabled') end
 end
 slots[7]=entry('Put away','toolHolster')
 slots[8]=entry('Back','page','main')
 return slots
end
