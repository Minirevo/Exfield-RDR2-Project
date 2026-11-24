local _ENV=PropertyRuntime
function restore(src,id)
    if cid(src)~=id then return end
    local v=S.visits[id]
    if v then
        visits[src]=v; exit(src)
    end
end
AddEventHandler('frontier:playerLoaded',function(player) CreateThread(function()
    if ready then run(player.source,function() restore(player.source,player.frontierCharacterId) end,true) end
end) end)
AddEventHandler('frontier:playerUnloaded',function(player)
    workers[player.source]=nil; previews[player.source]=nil
    local v=visits[player.source]; visits[player.source]=nil
    if v and v.actor==player.frontierCharacterId then
        local ped=GetPlayerPed(player.source)
        if ped~=0 and DoesEntityExist(ped) then SetPlayerRoutingBucket(player.source,0);SetEntityCoords(ped,v.x,v.y,v.z,false,false,false,false) end
    end
end)
AddEventHandler('playerDropped',function() local src=tonumber(source); workers[src]=nil; previews[src]=nil; visits[src]=nil; rate[src]=nil end)
AddEventHandler('onResourceStop',function(name)
    if name~=GetCurrentResourceName() then return end
    for src,v in pairs(visits) do local ped=GetPlayerPed(src); if ped~=0 then SetPlayerRoutingBucket(src,0); SetEntityCoords(ped,v.x,v.y,v.z,false,false,false,false) end end
end)
MySQL.ready(function()
    load()
    local function register(key,d,usable)
        if usable then return inv:RegisterUsableItem(key,function() return true end,'keep') end
        return true
    end
    while true do
        local ok=register(C.Kit.id,C.Kit,true)
        for key,d in pairs(C.Tools) do ok=register(key,d,false) and ok end
        for key,d in pairs(C.Furniture) do ok=register(key,d,true) and ok end
        if ok then break end
        Wait(5000)
    end
    ready=true
    for _,p in pairs(core:GetPlayers()) do run(p.source,function() restore(p.source,p.frontierCharacterId) end,true) end
    while true do
        Wait(C.TickMs)
        if ready then
            run(nil,function()
                for src,p in pairs(previews) do if p.untilTime<os.time() then previews[src]=nil end end
                local _,j=next(S.jobs)
                if j then process(j) else tick() end
                for _,p in pairs(core:GetPlayers()) do
                    if visits[p.source] and not findVisit(p.source) then exit(p.source) elseif not visits[p.source] and S.visits[p.frontierCharacterId] then restore(p.source,p.frontierCharacterId) end
                    world(p.source)
                end
            end,true)
        else
            local loaded=pcall(load); if loaded then ready=true end
        end
    end
end)
