-- Gun Lab is retired. Keep only a deployment check; no temporary firearm grants.
local retired={'vorp_inventory','vorp_weaponsv2'}
local function check(name)
 local state=GetResourceState(name)
 if state=='started' or state=='starting' then
  print(('[frontier_wheel] ERROR: %s is still active. Stop legacy inventory resources before using Frontier firearms.'):format(name))
 end
end
AddEventHandler('onResourceStart',function(name)
 if name==GetCurrentResourceName() then
  for _,r in ipairs(retired) do check(r) end
 else
  for _,r in ipairs(retired) do if name==r then check(r) end end
 end
end)
