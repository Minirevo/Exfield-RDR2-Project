function Frontier.GetStatus()
    local count = 0
    for _ in pairs(Frontier.Core.Players) do count = count + 1 end
    local provider = Frontier.Core.Provider
    local available, issue = provider.status()
    return {
        ready = Frontier.Core.Ready,
        provider = provider.name,
        providerAvailable = available,
        providerIssue = issue,
        vorpAvailable = provider.name == 'vorp' and available,
        vorpApiIssue = provider.name == 'vorp' and issue or nil,
        registeredPlayers = count,
        resource = GetCurrentResourceName(),
        version = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or 'unbekannt',
    }
end

RegisterCommand('frontier_status', function(playerSource)
    if playerSource ~= 0 and not Frontier.HasPermission(playerSource, 'frontier.admin') then
        TriggerClientEvent('chat:addMessage', playerSource, {
            args = { 'Frontier', 'Dir fehlt die Berechtigung für diesen Befehl.' },
        })
        return
    end

    local status = Frontier.GetStatus()
    local message = ('Datenbank beim Start geprüft: %s | Anbieter %s verfügbar: %s | Aktive Sitzungen: %d | Version: %s'):format(
        status.ready and 'ja' or 'nein', status.provider, status.providerAvailable and 'ja' or 'nein',
        status.registeredPlayers, status.version
    )
    print(('[FRONTIER][STATUS] %s'):format(message))
    if playerSource ~= 0 then
        TriggerClientEvent('chat:addMessage', playerSource, { args = { 'Frontier', message } })
        local player = Frontier.GetPlayer(playerSource)
        if player then
            local detail = ('Charakter-ID: %s | Name: %s'):format(
                player.frontierCharacterId, player.name or 'unbekannt'
            )
            TriggerClientEvent('chat:addMessage', playerSource, { args = { 'Frontier', detail } })
        end
    end
end, false)
