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
