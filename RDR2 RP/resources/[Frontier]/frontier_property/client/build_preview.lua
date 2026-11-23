local current, preview = nil, nil
local checkAt = 0

local function tell(text)
    TriggerEvent('chat:addMessage',{args={'Frontier Bau',text}})
end

local function remove()
    if preview and preview~=0 then DeleteEntity(preview) end
    preview=nil
end

local function stop()
    current=nil
    remove()
end

RegisterNetEvent('frontier_property:buildPreview',function(data)
    if source~=65535 then return end
    stop()
    local state={id=data.id,key=data.key,radius=data.radius,steps=0,hash=GetHashKey(data.model)}
    current=state
    checkAt=0
    tell(('Vorschau: Radius %.1f m. Geh zum Baupunkt. R dreht, E bestätigt, Esc beendet. Ein grüner Ring zeigt die freie Grundfläche.'):format(data.radius))
    CreateThread(function()
        RequestModel(state.hash,false)
        local deadline=GetGameTimer()+5000
        while current==state and not HasModelLoaded(state.hash) and GetGameTimer()<deadline do Wait(15) end
        if current~=state then SetModelAsNoLongerNeeded(state.hash); return end
        if not HasModelLoaded(state.hash) then stop(); tell('Dieses Modell konnte nicht geladen werden.'); return end
        local ped=PlayerPedId()
        local at=GetEntityCoords(ped)
        preview=CreateObjectNoOffset(state.hash,at.x,at.y,at.z,false,false,false,false)
        SetModelAsNoLongerNeeded(state.hash)
        if not preview or preview==0 then stop(); return tell('Vorschau konnte nicht erstellt werden.') end
        SetEntityCollision(preview,false,false)
        SetEntityAlpha(preview,120,false)
        FreezeEntityPosition(preview,true)
        while current==state do
            ped=PlayerPedId()
            at=GetEntityCoords(ped)
            SetEntityCoordsNoOffset(preview,at.x,at.y,at.z,false,false,false)
            SetEntityHeading(preview,(GetEntityHeading(ped)+15*state.steps)%360)
            if GetGameTimer()>=checkAt then
                checkAt=GetGameTimer()+1300
                TriggerServerEvent('frontier_property:buildPreviewCheck')
            end
            local green=state.clear==true
            Citizen.InvokeNative(0x2A32FAA57B937173,0xEC032ADD,at.x,at.y,at.z+0.08,
                0.0,0.0,0.0,0.0,0.0,0.0,state.radius*2,state.radius*2,0.15,
                green and 45 or 225,green and 205 or 115,70,160,false,false,2,false,nil,nil,false)
            if IsControlJustReleased(0,0xE30CD707) then state.steps=(state.steps+1)%24 end
            if IsControlJustReleased(0,0x156F7119) then stop() end
            if IsControlJustReleased(0,0xCEFD9220) and green then ExecuteCommand('grundbauen') end
            Wait(0)
        end
    end)
end)
RegisterNetEvent('frontier_property:buildPreviewResult',function(clear)
    if source==65535 and current then current.clear=clear==true end
end)

RegisterCommand('grunddrehen',function() if current then current.steps=(current.steps+1)%24 end end,false)
RegisterCommand('grundabbruch',stop,false)
RegisterCommand('grundbauen',function()
    local choice=current
    if not choice or not preview then return end
    stop()
    ExecuteCommand(('grundbau start %s %s %d'):format(choice.id,choice.key,choice.steps))
end,false)
AddEventHandler('onClientResourceStop',function(name)
    if name==GetCurrentResourceName() then stop() end
end)
