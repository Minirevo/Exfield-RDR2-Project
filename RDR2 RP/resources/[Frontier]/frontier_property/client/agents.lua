local peds, visible, requested = {}, false, 0
local function close()
    visible=false
    SetNuiFocus(false,false)
    SendNUIMessage({action='close'})
end

RegisterNetEvent('frontier_property:agentOpen',function(data)
    if source~=65535 or GetGameTimer()>requested or (not visible and IsNuiFocused()) then return end
    visible=true
    SetNuiFocus(true,true)
    SendNUIMessage({action='open',data=data})
end)

RegisterNUICallback('close',function(_,cb) close(); cb({ok=true}) end)
RegisterNUICallback('refresh',function(_,cb)
    if visible then requested=GetGameTimer()+8000; TriggerServerEvent('frontier_property:agentRequest') end
    cb({ok=visible})
end)
RegisterNUICallback('command',function(payload,cb)
    -- Existing server handlers independently validate role, position, quote and ownership.
    local text=payload and payload.command
    local allowed=type(text)=='string' and #text<=120 and text:match('^[%w _%-]+$')
        and (text:find('grundmiete ',1,true)==1 or text:find('privatmiete ',1,true)==1
            or text:find('grundverkauf ',1,true)==1)
    if visible and allowed then ExecuteCommand(text) end
    cb({ok=visible and not not allowed})
end)

CreateThread(function()
    local hint=false
    local hash=GetHashKey('A_M_M_ValTownfolk_01')
    while true do
        local delay,near=500,false
        local pos=GetEntityCoords(PlayerPedId())
        for i, agent in ipairs(PropertyAgents) do
            local distance=(pos.x-agent.x)^2+(pos.y-agent.y)^2+(pos.z-agent.z)^2
            if distance < 120^2 and not peds[i] then
                RequestModel(hash,false)
                if HasModelLoaded(hash) then
                    local ped=CreatePed(hash,agent.x,agent.y,agent.z,agent.heading,false,false,false,false)
                    if ped~=0 then
                        SetEntityInvincible(ped,true)
                        FreezeEntityPosition(ped,true)
                        SetBlockingOfNonTemporaryEvents(ped,true)
                        peds[i]=ped
                    end
                    SetModelAsNoLongerNeeded(hash)
                end
            elseif peds[i] and distance>150^2 then
                DeleteEntity(peds[i]);peds[i]=nil
            end
            if distance<9 and peds[i] and not visible then
                delay,near=0,true
                if IsControlJustReleased(0,0xCEFD9220) then
                    requested=GetGameTimer()+8000
                    TriggerServerEvent('frontier_property:agentRequest')
                end
            end
        end
        if near~=hint then
            hint=near
            SendNUIMessage({action='hint',show=near})
        end
        Wait(delay)
    end
end)
AddEventHandler('onClientResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    if visible then close() end
    for _, ped in pairs(peds) do DeleteEntity(ped) end
end)
