local active
local loading = 0

local function nearDoor()
    local ped=PlayerPedId()
    local pos=GetEntityCoords(ped)
    local origin=GetGameplayCamCoord()
    local rotation=GetGameplayCamRot(2)
    local pitch,yaw=math.rad(rotation.x),math.rad(rotation.z)
    local dx,dy,dz=-math.sin(yaw)*math.cos(pitch),math.cos(yaw)*math.cos(pitch),math.sin(pitch)
    for key,house in pairs(PropertyHouses) do
        if PropertyHouseNear(pos,house.door,2.5) then
            local x,y,z=house.door.x-origin.x,house.door.y-origin.y,house.door.z+0.95-origin.z
            local length=math.sqrt(x*x+y*y+z*z)
            if length<0.1 or (x*dx+y*dy+z*dz)/length>0.78 then return key end
        end
    end
end

function PropertyHouseHint(label)
    SetTextScale(0.35,0.35)
    SetTextCentre(true)
    DisplayText(CreateVarString(10,'LITERAL_STRING',label),0.5,0.88)
end

RegisterCommand('grundhaus',function(_,args)
    if active then
        if args[1]=='verlassen' then TriggerServerEvent('frontier_property:houseExit') end
        return
    end
    local key=nearDoor()
    if key then TriggerServerEvent('frontier_property:houseEnter',key,tonumber(args[1])) end
end,false)

RegisterNetEvent('frontier_property:houseEntered',function(id,key)
    if source~=65535 then return end
    ClearPropertyFurniture()
    active=PropertyHouses[key]
    if not active then return end
    TriggerEvent('chat:addMessage',{args={'Frontier Wohnräume',('Haus #%d. Möbelbefehle: /grundmoebel'):format(id)}})
    loading=loading+1
    local ticket=loading
    local room=active
    local ped=PlayerPedId()
    FreezeEntityPosition(ped,true)
    local deadline=GetGameTimer()+8000
    repeat
        RequestCollisionAtCoord(room.entry.x,room.entry.y,room.entry.z)
        Wait(50)
        if loading~=ticket then return end
    until (GetInteriorFromEntity(ped)==room.interior and IsInteriorReady(room.interior) and HasCollisionLoadedAroundEntity(ped))
        or GetGameTimer()>=deadline
    FreezeEntityPosition(ped,false)
    if GetInteriorFromEntity(ped)~=room.interior or not IsInteriorReady(room.interior)
        or not HasCollisionLoadedAroundEntity(ped) then
        TriggerEvent('chat:addMessage',{args={'Frontier Wohnräume','Der Innenraum konnte nicht geladen werden.'}})
        TriggerServerEvent('frontier_property:houseExit')
    end
end)

RegisterNetEvent('frontier_property:houseLeft',function()
    if source~=65535 then return end
    ClearPropertyFurniture()
    active=nil
    loading=loading+1
    FreezeEntityPosition(PlayerPedId(),false)
    if CancelPropertyFurniturePreview then CancelPropertyFurniturePreview() end
end)

function GetActivePropertyHouse()
    return active
end

CreateThread(function()
    while true do
        local room=active
        local key=not room and nearDoor()
        if room and not IsPropertyFurniturePreviewActive() and PropertyHouseNear(GetEntityCoords(PlayerPedId()),room.entry,1.55) then
            PropertyHouseHint('[E] Haus verlassen')
            if IsControlJustPressed(0,0xCEFD9220) then TriggerServerEvent('frontier_property:houseExit') end
            Wait(0)
        elseif key then
            PropertyHouseHint('[E] Haus betreten')
            if IsControlJustPressed(0,0xCEFD9220) then TriggerServerEvent('frontier_property:houseEnter',key) end
            Wait(0)
        else
            Wait(200)
        end
    end
end)

CreateThread(function()
    -- A reconnect can finish selecting and spawning its character after this resource starts.
    while true do
        if not active and not IsScreenFadedOut() then TriggerServerEvent('frontier_property:houseRecover') end
        Wait(5000)
    end
end)

AddEventHandler('onClientResourceStop',function(name)
    if name==GetCurrentResourceName() and active then FreezeEntityPosition(PlayerPedId(),false) end
end)
