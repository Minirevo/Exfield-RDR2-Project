local _ENV=PropertyRuntime
function allowed(s,id,perm)
    return s and s.status=='active' and id and (s.owners[id] or (s.members[id] and s.members[id][perm]==true))
end
function owner(s,id) return s and s.status=='active' and id and s.owners[id] end
function settlement(id) return type(id)=='string' and S.settlements[id] end
function chestId(id) return 'property_'..id end

-- Physical workshop authorization for the gathering smith. No client-provided workshop identity.
exports('GatheringWorkshop',function(src)
 if GetInvokingResource()~='frontier_gathering' or not ready then return nil end
 local id=cid(src);if not id then return nil end
 for _,s in pairs(S.settlements) do
  if allowed(s,id,'work') and not (s.listing and s.listing.active) then
   for _,b in pairs(s.buildings) do
    if b.complete and b.exterior=='workshop' and close(src,b,6) then return {id=b.id,name=s.name or 'Workshop',equipment=75} end
   end
  end
 end
end)

-- Read-only station discovery for the next production integration. No job or storage authority is granted here.
exports('GetProductionStations',function(src)
 if GetInvokingResource()~='frontier_production' or not ready then return {} end
 local id=cid(src);local pos=position(src);if not id or not pos or pos.bucket~=0 then return {} end
 local out={}
 for _,s in pairs(S.settlements) do
  if allowed(s,id,'work') and not (s.listing and s.listing.active) and R.distance(pos,s)<=s.radius+C.StreamDistance then
   for fid,f in pairs(s.furniture or {}) do
    local def=C.Furniture[f.item]
    if def and def.station and close(src,f,C.InteractionDistance) then
     out[#out+1]={id=fid,plot=s.id,kind=def.station,skill=def.skill,name=def.name,x=f.x,y=f.y,z=f.z,heading=f.heading}
    end
   end
  end
 end
 table.sort(out,function(a,b)return a.id<b.id end);return out
end)
