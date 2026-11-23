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

RegisterNetEvent('frontier_property:blueprintOpen',function(data)
    if source~=65535 then return end
    exports.frontier_inventory:CloseForProperty()
    if IsNuiFocused() and not visible then return end
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
        and (text=='bauplan' or text:find('grundmiete ',1,true)==1 or text:find('privatmiete ',1,true)==1
            or text:find('grundverkauf ',1,true)==1 or text:find('grundzimmer ',1,true)==1
            or text:find('grundbau vorschau ',1,true)==1)
    local accepted=visible and not not allowed
    if accepted then
        if text:find('grundzimmer ',1,true)==1 or text:find('grundbau vorschau ',1,true)==1 then close() end
        ExecuteCommand(text)
    end
    cb({ok=accepted})
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

local planning, requestDeadline = false, 0
local walking=nil
RegisterCommand('grundplan',function()
    if IsNuiFocused() then return end
    walking=nil
    SendNUIMessage({action='walkSurveyEnd'})
    requestDeadline=GetGameTimer()+8000
    TriggerServerEvent('frontier_property:plannerStart')
end,false)

RegisterNetEvent('frontier_property:plannerOpen',function(data)
    if source~=65535 or IsNuiFocused() or GetGameTimer()>requestDeadline then return end
    planning=true
    SetNuiFocus(true,true)
    SendNUIMessage({action='plannerOpen',data=data})
end)

RegisterNetEvent('frontier_property:plannerResult',function(result)
    if source==65535 and planning then SendNUIMessage({action='plannerResult',data=result}) end
end)

RegisterNUICallback('plannerAction',function(data,cb)
    if planning and type(data)=='table' and type(data.zone)=='string'
        and (data.action=='quote' or data.action=='buy') then
        TriggerServerEvent('frontier_property:plannerAction',data.action,data.zone,data.points)
    end
    cb({ok=planning})
end)

RegisterNUICallback('plannerClose',function(_,cb)
    if planning then
        planning=false
        requestDeadline=0
        SetNuiFocus(false,false)
        SendNUIMessage({action='plannerClose'})
        TriggerServerEvent('frontier_property:plannerClose')
    end
    cb({ok=true})
end)

AddEventHandler('onClientResourceStop',function(resource)
    if resource==GetCurrentResourceName() and planning then SetNuiFocus(false,false) end
end)

local actions={punkt='point',zurueck='undo',neustart='restart',fertig='finish',abbrechen='cancel'}
RegisterCommand('grundgrenze',function(_,args)
    local action=actions[args[1]]
    if args[1]=='start' and not IsNuiFocused() then
        requestDeadline=GetGameTimer()+8000
        TriggerServerEvent('frontier_property:plannerStart','walk')
        TriggerEvent('chat:addMessage',{args={'Frontier Landvermessung',
            'Geh deine Grenze ab. /grundgrenze punkt, zurueck, neustart, fertig oder abbrechen.'}})
    elseif action and walking then TriggerServerEvent('frontier_property:walkSurveyAction',action) end
end,false)

RegisterNetEvent('frontier_property:walkSurvey',function(data)
    if source~=65535 or (not walking and GetGameTimer()>requestDeadline) then return end
    walking=data.markers or {}
    SendNUIMessage({action='walkSurvey',data=data})
end)
RegisterNetEvent('frontier_property:walkSurveyEnd',function()
    if source~=65535 then return end
    walking=nil
    SendNUIMessage({action='walkSurveyEnd'})
end)
RegisterNetEvent('frontier_property:walkSurveyFinish',function(data)
    if source~=65535 or not walking or IsNuiFocused() then return end
    walking=nil
    planning=true
    SetNuiFocus(true,true)
    SendNUIMessage({action='plannerOpen',data={radius=data.radius,zones={'world'},walk=true,points=data.points}})
    SendNUIMessage({action='walkSurveyEnd'})
end)

CreateThread(function()
    while true do
        if walking then
            for _, p in ipairs(walking) do
                Citizen.InvokeNative(0x2A32FAA57B937173,0x94FDAE17,p.x,p.y,p.z+0.1,
                    0.0,0.0,0.0,0.0,0.0,0.0,0.25,0.25,0.45,220,186,101,190,false,false,2,false,nil,nil,false)
            end
            Wait(0)
        else Wait(300) end
    end
end)
