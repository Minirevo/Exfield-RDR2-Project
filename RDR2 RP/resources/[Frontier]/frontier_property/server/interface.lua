local _ENV=PropertyRuntime
function public(s)
    return {id=s.id,name=s.name,x=s.x,y=s.y,z=s.z,radius=s.radius,map=s.map==true}
end
function occupied(sid)
    for _,v in pairs(visits) do if v.sid==sid then return true end end
    return false
end
function view(src,kind,s,b)
    local id=cid(src)
    if not id then return end
    local data={kind=kind,catalogue=C.Exteriors,interiors=C.Interiors,permissions=C.Permissions,shop={C.Kit},market={}}
    for key,t in pairs(C.Tools) do data.shop[#data.shop+1]={id=key,name=t.name,grams=t.grams,price=t.price} end
    for key,t in pairs(C.Furniture) do data.shop[#data.shop+1]={id=key,name=t.name,grams=t.grams,price=t.price} end
    if s then
        data.settlement=public(s); data.settlement.debt=s.debt; data.settlement.tax=R.tax(s,C)
        data.settlement.expansion=R.expansion(s,C); data.settlement.owner=owner(s,id)==true
        data.settlement.rights={}; for _,perm in ipairs(C.Permissions) do data.settlement.rights[perm]=allowed(s,id,perm)==true end
        if allowed(s,id,'members') then data.settlement.members=s.members; data.settlement.owners=s.owners end
        data.settlement.listing=s.listing
        data.buildings={}; for _,x in pairs(s.buildings) do
            local info=buildingInfo(x); info.furniture=nil; data.buildings[#data.buildings+1]=info
        end
        if b then data.building=buildingInfo(b); if kind~='interior' then data.building.furniture=nil end end
    end
    if kind=='market' then
        for _,x in pairs(S.settlements) do if x.status=='active' and x.listing and x.listing.active then
            data.market[#data.market+1]={id=x.id,name=x.name,radius=x.radius,price=x.listing.price,buildings=(function() local n=0; for _ in pairs(x.buildings) do n=n+1 end; return n end)()}
        end end
    end
    TriggerClientEvent(E..'menu',src,data)
end
function nearCamp(src,s) return s and s.status=='active' and close(src,s) end
function nearShop(src)
    for _,p in ipairs(C.Shops) do if close(src,p,5) then return true end end
end
