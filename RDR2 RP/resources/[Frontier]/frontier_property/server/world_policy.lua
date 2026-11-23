local function square(x,y,r)
    return {{x=x-r,y=y-r},{x=x+r,y=y-r},{x=x+r,y=y+r},{x=x-r,y=y+r}}
end

function ResolvePropertySurveyZone(key, points)
    if key~='world' then return PropertyConfig.SurveyZones[key] end
    local policy=PropertyConfig.WorldSurvey
    local first=type(points)=='table' and points[1]
    if not policy or not policy.enabled or type(first)~='table'
        or type(first.x)~='number' or type(first.y)~='number'
        or type(policy.interiorBuffer)~='number' or not (policy.interiorBuffer>=12 and policy.interiorBuffer<=200) then return nil end
    local exclusions={}
    local function protect(x,y,r)
        -- A planner claim is confined to 150 m across in each dimension.
        if math.abs(first.x-x)<=r+155 and math.abs(first.y-y)<=r+155 then
            exclusions[#exclusions+1]=square(x,y,r)
        end
    end
    for _, zone in ipairs(PropertyTownBuffers) do protect(zone[1],zone[2],zone[3]) end
    for _, xy in ipairs(PropertyProtectedInteriors) do protect(xy[1],xy[2],policy.interiorBuffer) end
    for _, area in ipairs(policy.extraExclusions or {}) do exclusions[#exclusions+1]=area end
    return {
        enablePurchase=true,priceCentsPerSquareMeter=policy.priceCentsPerSquareMeter,exclusions=exclusions,
        boundary={{x=-7000,y=-4200},{x=5200,y=-4200},{x=5200,y=4100},{x=-7000,y=4100}},
    }
end
