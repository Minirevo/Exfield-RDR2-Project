PropertyRules={}
local R=PropertyRules
function R.finite(n) return type(n)=='number' and n==n and math.abs(n)<100000 end
function R.point(p) return type(p)=='table' and R.finite(p.x) and R.finite(p.y) and R.finite(p.z) end
function R.distance(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
function R.near(a,b,d) return R.distance(a,b)^2+(a.z-b.z)^2<=d*d end
function R.claim(p,r,claims,ignore,c)
    if not R.point(p) or r<c.InitialRadius or r>c.MaxRadius then return false,'Invalid territory' end
    for _,group in ipairs({c.Towns,c.ExtraExclusions}) do
        for _,z in ipairs(group) do if R.distance(p,z)<=r+z.r+c.TownClearance then return false,'Protected area: '..(z.name or 'restricted') end end
    end
    for id,s in pairs(claims) do if id~=ignore and s.status~='abandoned' and R.distance(p,s)<=r+s.radius then return false,'Territory overlaps another settlement' end end
    return true
end
function R.expansion(s,c) return math.floor(c.ExpansionBase*c.ExpansionMultiplier^((s.radius-c.InitialRadius)/c.ExpansionStep)+0.5) end
function R.tax(s,c) return math.floor(c.TaxBase*(s.radius/c.InitialRadius)^2+0.5) end
function R.foreclosure(value,debt,c)
    local remainder=value-math.floor(value*c.ForeclosureDeduction/100)
    local paid=math.min(remainder,debt)
    local surplus=remainder-paid
    return surplus-math.floor(surplus*c.ForeclosurePenalty/100),paid,debt-paid
end
function R.capacity(exterior,interior) return exterior.slots+(interior and interior.slots or 0) end
function R.fits(s,p,r,ignore)
    if not R.point(p) or R.distance(s,p)+r>s.radius or R.distance(s,p)<r+6 then return false end
    for id,b in pairs(s.buildings) do if id~=ignore and R.distance(b,p)<r+b.radius+1 then return false end end
    return true
end

function R.transform(o,p)
    local a=math.rad(o.heading or 0);local x,y=p.x or 0,p.y or 0
    return {x=o.x+x*math.cos(a)-y*math.sin(a),y=o.y+x*math.sin(a)+y*math.cos(a),z=o.z+(p.z or 0),heading=((o.heading or 0)+(p.heading or 0))%360,model=p.model}
end
function R.localPoint(o,p)
    local a=math.rad(o.heading or 0);local x,y=p.x-o.x,p.y-o.y
    return {x=x*math.cos(a)+y*math.sin(a),y=-x*math.sin(a)+y*math.cos(a),z=p.z-o.z,heading=((p.heading or 0)-(o.heading or 0))%360}
end
function R.parts(e,c)
    return e.assembly and c.TestAssemblies[e.assembly].parts or {{model=e.model,x=0,y=0,z=0,heading=0}}
end
function R.indoor(b,p,c)
    local e=c.Exteriors[b.exterior]
    if not b.complete or not e or not e.interior then return false end
    local part=R.parts(e,c)[e.indoorPart or 1]
    local bounds=part and c.IndoorBounds[part.model]
    if not bounds then return false end
    local q=R.localPoint(R.transform(b,part),p)
    return q.x>=bounds.min.x and q.x<=bounds.max.x and q.y>=bounds.min.y and q.y<=bounds.max.y and q.z>=bounds.min.z and q.z<=bounds.max.z
end
function R.buildingAt(s,p,c)
    local best,dist
    for id,b in pairs(s.buildings or {}) do
        if R.indoor(b,p,c) then local d=R.distance(b,p);if not dist or d<dist or (d==dist and id<best) then best,dist=id,d end end
    end
    return best
end
