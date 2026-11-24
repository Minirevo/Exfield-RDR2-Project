local _ENV=PropertyRuntime
function world(src)
    local p=position(src); if not p or not cid(src) then return end
    local data={claims={},objects={},markers={}}; local v=visits[src]
    local function obj(key,model,x,y,z,h,action,sid,bid)
        data.objects[#data.objects+1]={key=key,model=model,x=x,y=y,z=z,heading=h or 0,action=action,sid=sid,bid=bid}
    end
    if p.bucket==0 then
        for sid,s in pairs(S.settlements) do if s.status=='active' then
            if s.map then data.markers[#data.markers+1]=public(s) end
            if R.distance(p,s)<=s.radius+C.StreamDistance then
                data.claims[#data.claims+1]=public(s)
                if R.distance(p,s)<=C.StreamDistance then
                    obj(sid..'fire',C.Camp.fire,s.x,s.y,s.z,0,'camp',sid)
                    obj(sid..'tent',C.Camp.tent,s.x-3,s.y,s.z,0,nil,sid)
                    obj(sid..'chest',C.Camp.chest,s.x+2,s.y,s.z,0,'chest',sid)
                end
                for bid,b in pairs(s.buildings) do if R.distance(p,b)<=C.StreamDistance then
                    obj(bid,b.complete and C.Exteriors[b.exterior].model or C.Camp.site,b.x,b.y,b.z,b.heading,b.complete and b.interior and 'enter' or not b.complete and 'site' or nil,sid,bid)
                    data.objects[#data.objects].interaction=b.complete and b.radius+C.InteractionDistance or C.InteractionDistance
                end end
            end
        end end
    elseif v and v.actor==cid(src) then
        local s,b=findVisit(src)
        if b then for fid,f in pairs(b.furniture) do obj(fid,C.Furniture[f.item].model,f.x,f.y,f.z,f.heading,nil,s.id,b.id) end end
    end
    TriggerClientEvent(E..'world',src,data)
end
