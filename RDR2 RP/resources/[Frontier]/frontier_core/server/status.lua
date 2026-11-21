function Frontier.GetStatus()
    local playerCount = 0
    for _ in pairs(Frontier.Core.Players) do
        playerCount = playerCount + 1
    end

    return {
        ready = Frontier.Core.Ready == true,
        vorpAvailable = Frontier.Core.VORP.available == true,
        registeredPlayers = playerCount,
        resource = GetCurrentResourceName(),
        version = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or 'unknown',
    }
end

RegisterCommand('frontier_status', function(source)
    if source ~= 0 and not Frontier.HasPermission(source, 'frontier.admin') then
        TriggerClientEvent('chat:addMessage', source, {
            args = { '^1Frontier', 'You do not have permission to use this command.' }
        })
        return
    end

    local status = Frontier.GetStatus()
    local message = ('Ready: %s | VORP bridge: %s | Registered players: %d | Version: %s'):format(
        status.ready and 'YES' or 'NO',
        status.vorpAvailable and 'YES' or 'NO',
        status.registeredPlayers,
        status.version
    )

    print(('[FRONTIER][STATUS] %s'):format(message))

    if source ~= 0 then
        TriggerClientEvent('chat:addMessage', source, {
            args = { '^3Frontier Status', message }
        })

        local player = Frontier.GetPlayer(source)
        if player then
            TriggerClientEvent('chat:addMessage', source, {
                args = { '^3Frontier Player', ('Character ID: %s | Name: %s'):format(player.characterId or 'n/a', player.name or 'n/a') }
            })
        end
    end
end, false)
