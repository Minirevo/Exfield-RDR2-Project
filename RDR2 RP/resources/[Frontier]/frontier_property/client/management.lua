local active=false
local requested=0

local function open()
    if IsNuiFocused() and not active then return end
    requested=GetGameTimer()+8000
    TriggerServerEvent('frontier_property:manageRequest')
end

RegisterCommand('grundstück',open,false)
RegisterCommand('grundstueck',open,false)

RegisterNetEvent('frontier_property:manageOpen',function(data)
    if source~=65535 or (not active and (GetGameTimer()>requested or IsNuiFocused())) then return end
    active=true
    SetNuiFocus(true,true)
    SendNUIMessage({action='manageOpen',data=data})
end)
RegisterNetEvent('frontier_property:manageResult',function(text)
    if source==65535 and active then SendNUIMessage({action='manageResult',data=text}) end
end)
RegisterNUICallback('manageAction',function(data,cb)
    if active then TriggerServerEvent('frontier_property:manageAction',data) end
    cb({ok=active})
end)

local function close()
    if not active then return end
    active=false
    requested=0
    SetNuiFocus(false,false)
    SendNUIMessage({action='manageClose'})
end

RegisterNUICallback('manageClose',function(_,cb) close(); cb({ok=true}) end)
AddEventHandler('onClientResourceStop',function(resource)
    if resource==GetCurrentResourceName() then close() end
end)
