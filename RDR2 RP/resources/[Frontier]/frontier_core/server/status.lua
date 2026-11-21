function Frontier.GetStatus()
    local playerCount = 0
    for _ in pairs(Frontier.Core.Players) do
        playerCount = playerCount + 1
    end

    return {
        ready = Frontier.Core.Ready == true,
        vorpAvailable = Frontier.Core.VORP.available == true,
        vorpApiIssue = Frontier.Core.VORP.lastError,
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

    -- Refresh the API check so the command reports the live export state,
    -- rather than only the state observed during resource startup.
    local _, apiIssue = Frontier.Core.VORP.GetCore()
    local status = Frontier.GetStatus()
    local apiState = status.vorpAvailable and 'YES' or ('NO (%s)'):format(apiIssue or status.vorpApiIssue or 'unknown')
    local message = ('Ready: %s | VORP API: %s | Registered players: %d | Version: %s'):format(
        status.ready and 'YES' or 'NO',
        apiState,
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
