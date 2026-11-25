local _ENV=PropertyRuntime
function world(src)
    local p=position(src); if not p or not cid(src) then return end
    local data={claims={},objects={},markers={}}; local v=visits[src]
    local function obj(key,model,x,y,z,h,action,sid,bid,ground)
        data.objects[#data.objects+1]={key=key,model=model,x=x,y=y,z=z,heading=h or 0,action=action,sid=sid,bid=bid,ground=ground==true}
    end
    if p.bucket==0 then
        for sid,s in pairs(S.settlements) do if s.status=='active' then
            if s.map then data.markers[#data.markers+1]=public(s) end
            if R.distance(p,s)<=s.radius+C.StreamDistance then
                data.claims[#data.claims+1]=public(s)
                if R.distance(p,s)<=C.StreamDistance then
                    obj(sid..'fire',C.Camp.fire,s.x,s.y,s.z,0,'camp',sid,nil,true)
                    obj(sid..'tent',C.Camp.tent,s.x-3,s.y,s.z,0,nil,sid,nil,true)
                    obj(sid..'chest',C.Camp.chest,s.x+2,s.y,s.z,0,'chest',sid,nil,true)
                end
                for bid,b in pairs(s.buildings) do if R.distance(p,b)<=C.StreamDistance then
                    if b.complete then
                        local e=C.Exteriors[b.exterior]
                        if e then for n,part in ipairs(R.parts(e,C)) do
                            local q=R.transform(b,part)
                            obj(bid..':'..n,q.model,q.x,q.y,q.z,q.heading,nil,sid,bid,false)
                        end end
                    else obj(bid,C.Camp.site,b.x,b.y,b.z,b.heading,'site',sid,bid,true) end
                end end
                for fid,f in pairs(s.furniture or {}) do if R.distance(p,f)<=C.StreamDistance then obj(fid,C.Furniture[f.item].model,f.x,f.y,f.z,f.heading,nil,sid,nil,false) end end
            end
        end end
    elseif v and v.actor==cid(src) then
        local s,b=findVisit(src)
        if b then for fid,f in pairs(b.furniture) do obj(fid,C.Furniture[f.item].model,f.x,f.y,f.z,f.heading,nil,s.id,b.id) end end
    end
    TriggerClientEvent(E..'world',src,data)
end
