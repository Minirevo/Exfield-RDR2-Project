local _ENV=PropertyRuntime
function allowed(s,id,perm)
    return s and s.status=='active' and id and (s.owners[id] or (s.members[id] and s.members[id][perm]==true))
end
function owner(s,id) return s and s.status=='active' and id and s.owners[id] end
function settlement(id) return type(id)=='string' and S.settlements[id] end
function chestId(id) return 'property_'..id end
