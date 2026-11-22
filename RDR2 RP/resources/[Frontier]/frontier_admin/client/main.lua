RegisterNetEvent('frontier_admin:client:teleport', function(x, y, z)
    local ped = PlayerPedId()
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        TriggerEvent('frontier_admin:client:notify', 'Teleport fehlgeschlagen: Kein Spielercharakter gefunden.')
        return
    end

    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not x or not y or not z then
        TriggerEvent('frontier_admin:client:notify', 'Teleport fehlgeschlagen: Ungültige Koordinaten vom Server erhalten.')
        return
    end

    print(('[FRONTIER][ADMIN] Client erhielt Zielkoordinaten: X %.3f, Y %.3f, Z %.3f.'):format(x, y, z))

    DoScreenFadeOut(250)
    Wait(300)

    -- Request destination collision before moving, then use the no-offset native
    -- so the supplied world coordinates are applied directly.
    RequestCollisionAtCoord(x, y, z)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)

    local deadline = GetGameTimer() + 5000
    while GetGameTimer() < deadline do
        RequestCollisionAtCoord(x, y, z)
        if HasCollisionLoadedAroundEntity(ped) then
            break
        end
        Wait(100)
    end

    Wait(250)
    local actual = GetEntityCoords(ped)
    DoScreenFadeIn(250)

    print(('[FRONTIER][ADMIN] Teleport-Ergebnis: X %.3f, Y %.3f, Z %.3f.'):format(
        actual.x, actual.y, actual.z
    ))
    TriggerEvent('frontier_admin:client:notify', ('Ziel: %.1f / %.1f / %.1f | Position: %.1f / %.1f / %.1f'):format(
        x, y, z, actual.x, actual.y, actual.z
    ))
end)

RegisterNetEvent('frontier_admin:client:notify', function(message)
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
    print(('[FRONTIER][ADMIN] Deine Koordinaten: /frontier_tp %.2f %.2f %.2f'):format(
        coords.x, coords.y, coords.z
    ))
end, false)
