local _ENV=PropertyRuntime
function plotAt(src,id)
    local pos=position(src)
    if not pos or pos.bucket~=0 then return end
    for _,s in pairs(S.settlements) do
        if s.status=='active' and R.distance(s,pos)<=s.radius and allowed(s,id,'furnish') then return s end
    end
end
function beginPreview(src,s,b,exterior,interior,mode,fid,itemId)
    local id=cid(src)
    previews[src]={sid=s.id,bid=b and b.id,exterior=exterior,mode=mode,fid=fid,item=itemId,actor=id,untilTime=os.time()+120}
    local isFurniture=mode=='furniture' or mode=='moveFurniture'
    local e=not isFurniture and C.Exteriors[exterior]
    local model=isFurniture and C.Furniture[itemId].model or e.model
    local origin=b and mode=='move' and {x=b.x,y=b.y,z=b.z,heading=b.heading} or nil
    if mode=='moveFurniture' then origin=s.furniture[fid] end
    local blockers={}
    if not isFurniture then for k,v in pairs(s.buildings) do if mode~='move' or k~=b.id then blockers[k]={x=v.x,y=v.y,z=v.z,radius=math.max(v.radius,(C.Exteriors[v.exterior] or {}).radius or 0)} end end end
    TriggerClientEvent(E..'preview',src,{model=model,parts=e and R.parts(e,C) or nil,mode=mode,origin=origin,claim=public(s),blockers=blockers,radius=e and e.radius or nil,furniture=isFurniture})
end
