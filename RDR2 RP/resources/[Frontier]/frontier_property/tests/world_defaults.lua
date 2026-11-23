exports=function() end
local root=... or '.'
dofile(root..'/config.lua')
dofile(root..'/server/world_data.lua')
dofile(root..'/server/world_policy.lua')
dofile(root..'/server/survey.lua')
local function plot(x,y)
    return {{x=x,y=y,z=50},{x=x+10,y=y,z=50},{x=x+10,y=y+10,z=50},{x=x,y=y+10,z=50}}
end
local nearTown=plot(-300,790)
local world=assert(ResolvePropertySurveyZone('world',nearTown))
local area,issue=ValidatePropertySurvey(nearTown,world.boundary,world.exclusions)
assert(not area and issue=='blocked_overlap')
local outside=plot(-6990,4090)
world=assert(ResolvePropertySurveyZone('world',outside))
assert(not ValidatePropertySurvey(outside,world.boundary,world.exclusions))
local remote=plot(10,70)
world=assert(ResolvePropertySurveyZone('world',remote))
assert(ValidatePropertySurvey(remote,world.boundary,world.exclusions)==100)
assert(#PropertyProtectedInteriors==290 and PropertyGovernmentCatalogue.val_south.furnish~=false)
assert(PropertyConfig.ConstructionPlans.huette.stages[2].item=='wooden_planks')
print('Default world, exclusions and catalogues passed')
