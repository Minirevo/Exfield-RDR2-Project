local visible = {}
local epoch = 0

local function key(row)
    return ('%s:%s:%s:%s:%s:%s'):format(row.id,row.model,row.x,row.y,row.z,row.heading)
end

RegisterNetEvent('frontier_property:furnitureSnapshot', function(rows)
    if source ~= 65535 then return end
    epoch = epoch + 1
    local current = epoch
    local desired = {}
    for _, row in ipairs(rows) do desired[key(row)] = row end
    for id, entity in pairs(visible) do
        if not desired[id] then DeleteEntity(entity); visible[id] = nil end
    end
    for id, row in pairs(desired) do
        if not visible[id] then
            CreateThread(function()
                local hash = GetHashKey(row.model)
                RequestModel(hash, false)
                local deadline=GetGameTimer()+2500
                while not HasModelLoaded(hash) and GetGameTimer()<deadline and epoch==current do Wait(0) end
                if epoch==current and HasModelLoaded(hash) and not visible[id] then
                    local obj=CreateObjectNoOffset(hash,row.x,row.y,row.z,false,false,false,false)
                    if obj~=0 then
                        SetEntityHeading(obj,row.heading)
                        FreezeEntityPosition(obj,true)
                        visible[id]=obj
                    end
                end
                SetModelAsNoLongerNeeded(hash)
            end)
        end
    end
end)

CreateThread(function()
    while true do
        TriggerServerEvent('frontier_property:furnitureRefresh')
        Wait(3500)
    end
end)

AddEventHandler('onClientResourceStop', function(name)
    if name~=GetCurrentResourceName() then return end
    epoch=epoch+1
    for _, entity in pairs(visible) do DeleteEntity(entity) end
end)
