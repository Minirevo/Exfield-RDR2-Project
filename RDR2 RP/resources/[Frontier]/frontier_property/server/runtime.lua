local _ENV=PropertyRuntime
function notice(src,msg) TriggerClientEvent(E..'notice',src,tostring(msg)) end
function cid(src) return core:GetPlayerCharacterId(src) end
function position(src)
    local ped=GetPlayerPed(src)
    if ped==0 or not DoesEntityExist(ped) then return end
    local v=GetEntityCoords(ped)
    return {x=v.x,y=v.y,z=v.z,bucket=GetPlayerRoutingBucket(src)}
end
function close(src,p,d,bucket)
    local v=position(src)
    return v and v.bucket==(bucket or 0) and R.near(v,p,d or C.InteractionDistance)
end
function uuid() return MySQL.scalar.await('SELECT UUID()'):gsub('-','') end
function load() S,revision=PropertyDB.load() end
function save() revision=PropertyDB.save(S,revision) end
function run(src,fn,allowPending)
    if not ready or busy or (not allowPending and next(S.jobs)) then if src then notice(src,'Property busy; try again shortly.') end; return end
    busy=true
    local ok,err=pcall(fn)
    if not ok then
        print('[frontier_property] '..tostring(err))
        local loaded=pcall(load)
        if not loaded then ready=false end
        if src then notice(src,'Request outcome uncertain. Refresh before retrying.') end
    end
    busy=false
end
