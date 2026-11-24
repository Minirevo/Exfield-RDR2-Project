local preview

function IsPropertyFurniturePreviewActive()
    return preview~=nil
end

function CancelPropertyFurniturePreview()
    if preview and preview.entity then DeleteEntity(preview.entity) end
    preview=nil
end

RegisterNetEvent('frontier_property:furniturePreview',function(token,model,radius,transform)
    if source~=65535 or not GetActivePropertyHouse() then return end
    CancelPropertyFurniturePreview()
    local room=GetActivePropertyHouse()
    local edit={}
    preview=edit
    local hash=GetHashKey(model)
    RequestModel(hash,false)
    local deadline=GetGameTimer()+3000
    while preview==edit and not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(0) end
    if preview~=edit or not HasModelLoaded(hash) then
        if preview==edit then CancelPropertyFurniturePreview() end
        SetModelAsNoLongerNeeded(hash)
        return
    end
    local pos=GetEntityCoords(PlayerPedId())
    local angle=GetEntityHeading(PlayerPedId())
    local x,y,z=pos.x,pos.y,pos.z
    if transform then x,y,z,angle=transform.x,transform.y,transform.z,transform.heading end
    local obj=CreateObjectNoOffset(hash,x,y,z,false,false,false,false)
    SetModelAsNoLongerNeeded(hash)
    if obj==0 then return CancelPropertyFurniturePreview() end
    edit.entity=obj
    FreezeEntityPosition(obj,true)
    SetEntityCollision(obj,false,false)
    SetEntityAlpha(obj,165,false)
    while preview==edit do
        local step=math.min(GetFrameTime(),0.05)
        local function held(control)
            DisableControlAction(0,control,true)
            return IsDisabledControlPressed(0,control) and 1 or 0
        end
        x=x+(held(0xDEB34313)-held(0xA65EBAB4))*step
        y=y+(held(0x6319DB71)-held(0x05CA7C52))*step
        z=z+(held(0xD9D0E1C0)-held(0xDB096B85))*step*0.6
        angle=(angle+held(0xE30CD707)*step*85)%360
        x=math.max(room.min.x+radius,math.min(room.max.x-radius,x))
        y=math.max(room.min.y+radius,math.min(room.max.y-radius,y))
        z=math.max(room.min.z,math.min(room.max.z,z))
        SetEntityCoordsNoOffset(obj,x,y,z,false,false,false)
        SetEntityHeading(obj,angle)
        local valid=PropertyHouseWithin({x=x,y=y,z=z},room,radius) and GetInteriorAtCoords(x,y,z)==room.interior
        PropertyHouseHint(valid and 'Pfeile: Position | Leertaste/Strg: Höhe | R: Drehen | E: Speichern | Esc: Abbrechen'
            or 'Pfeile: Position | Leertaste/Strg: Höhe | R: Drehen | Esc: Abbrechen | Position ungültig')
        DisableControlAction(0,0x156F7119,true)
        if IsDisabledControlJustPressed(0,0x156F7119) then
            CancelPropertyFurniturePreview()
        elseif valid and IsControlJustPressed(0,0xCEFD9220) then
            TriggerServerEvent('frontier_property:furnitureConfirm',token,x,y,z,angle)
            CancelPropertyFurniturePreview()
        end
        Wait(0)
    end
end)

AddEventHandler('onClientResourceStop',function(name)
    if name==GetCurrentResourceName() then CancelPropertyFurniturePreview() end
end)
