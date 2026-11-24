local _ENV=PropertyRuntime
function beginPreview(src,s,b,exterior,interior,mode,fid,itemId)
    local id=cid(src)
    previews[src]={sid=s.id,bid=b and b.id,exterior=exterior,interior=interior,mode=mode,fid=fid,item=itemId,actor=id,untilTime=os.time()+120}
    local isFurniture=mode=='furniture' or mode=='moveFurniture'
    local model=isFurniture and C.Furniture[itemId].model or C.Exteriors[exterior].model
    local origin=b and mode=='move' and {x=b.x,y=b.y,z=b.z,heading=b.heading} or nil
    if mode=='moveFurniture' then origin=b.furniture[fid] end
    local blockers={}
    if not isFurniture then for k,v in pairs(s.buildings) do if mode~='move' or k~=b.id then blockers[#blockers+1]={x=v.x,y=v.y,z=v.z,radius=v.radius} end end end
    TriggerClientEvent(E..'preview',src,{model=model,mode=mode,origin=origin,claim=public(s),blockers=blockers,radius=not isFurniture and C.Exteriors[exterior].radius or nil,room=isFurniture and C.Interiors[b.interior] or nil})
end
