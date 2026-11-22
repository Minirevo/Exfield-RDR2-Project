local function notify(source, message)
    TriggerClientEvent('frontier_admin:client:notify', source, message)
end

local function parseCoordinate(value)
    if type(value) ~= 'string' or value == '' then
        return nil
    end

    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return nil
    end

    return number
end

RegisterCommand(FrontierAdminConfig.TeleportCommand, function(source, args)
    if source == 0 then
        print('[FRONTIER][ADMIN] /frontier_tp kann nur von einem Spieler verwendet werden.')
        return
    end

    if not IsPlayerAceAllowed(source, FrontierAdminConfig.TeleportAce) then
        notify(source, 'Dafür hast du keine Berechtigung.')
        return
    end

    if #args ~= 3 then
        notify(source, 'Verwendung: /frontier_tp X Y Z')
        return
    end

    local x = parseCoordinate(args[1])
    local y = parseCoordinate(args[2])
    local z = parseCoordinate(args[3])
    local limits = FrontierAdminConfig.CoordinateLimits

    if not x or not y or not z
        or math.abs(x) > limits.x
        or math.abs(y) > limits.y
        or z < limits.zMin
        or z > limits.zMax then
        notify(source, 'Ungültige Koordinaten. Bitte prüfe X, Y und Z.')
        return
    end

    print(('[FRONTIER][ADMIN] Teleport-Anfrage von %s: X %.3f, Y %.3f, Z %.3f.'):format(
        GetPlayerName(source) or ('Spieler ' .. source), x, y, z
    ))
    TriggerClientEvent('frontier_admin:client:teleport', source, x, y, z)
end, false)
