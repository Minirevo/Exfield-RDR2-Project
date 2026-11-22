RegisterNetEvent('frontier_admin:client:teleport', function(x, y, z)
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        TriggerEvent('frontier_admin:client:notify', 'Teleport fehlgeschlagen: Kein Spielercharakter gefunden.')
        return
    end

    DoScreenFadeOut(250)
    Wait(300)
    SetEntityCoords(ped, x, y, z, false, false, false, false)
    Wait(250)
    DoScreenFadeIn(250)

    TriggerEvent('frontier_admin:client:notify', ('Teleportiert zu X %.2f, Y %.2f, Z %.2f.'):format(x, y, z))
end)

RegisterNetEvent('frontier_admin:client:notify', function(message)
    -- Keep this resource independent from a particular notification framework.
    TriggerEvent('chat:addMessage', {
        color = { 220, 220, 220 },
        args = { 'Frontier', message }
    })
    print('[FRONTIER][ADMIN] ' .. tostring(message))
end)

RegisterCommand(FrontierAdminConfig.CoordinatesCommand, function()
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        print('[FRONTIER][ADMIN] Kein Spielercharakter gefunden.')
        return
    end

    local coords = GetEntityCoords(ped)
    print(('[FRONTIER][ADMIN] Deine Koordinaten: /tp %.2f %.2f %.2f'):format(
        coords.x, coords.y, coords.z
    ))
end, false)
