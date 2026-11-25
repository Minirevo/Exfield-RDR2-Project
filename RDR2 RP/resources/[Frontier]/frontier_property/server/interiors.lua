local _ENV=PropertyRuntime
function atInterior(src,s,b)
    local v=visits[src]; local i=b and C.Interiors[b.interior]
    return v and i and v.sid==s.id and v.bid==b.id and v.actor==cid(src) and close(src,i,i.bounds+2,b.bucket)
end
function findVisit(src)
    local v=visits[src]; local s=v and settlement(v.sid); local b=s and s.buildings[v.bid]
    if s and s.status=='active' and b and atInterior(src,s,b) and (not b.locked or allowed(s,cid(src),'enter')) then return s,b end
end
function exit(src)
    local v=visits[src]
    if not v then return end
    local ped=GetPlayerPed(src)
    if ped==0 or not DoesEntityExist(ped) then return end
    SetPlayerRoutingBucket(src,0); SetEntityCoords(ped,v.x,v.y,v.z,false,false,false,false)
    visits[src]=nil; S.visits[v.actor]=nil; save()
    TriggerClientEvent(E..'interior',src,false)
end
function enter() end
