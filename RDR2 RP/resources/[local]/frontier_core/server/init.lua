local resourceName = GetCurrentResourceName()

AddEventHandler('onResourceStart', function(startedResource)
    if startedResource ~= resourceName then
        return
    end

    FrontierLib.Log('INFO', resourceName, 'Starting Frontier Core', {
        version = GetResourceMetadata(resourceName, 'version', 0) or 'unknown',
        locale = FrontierConfig.Locale,
    })

    local core = Frontier.Core.VORP.GetCore()
    if not core then
        FrontierLib.Log('ERROR', resourceName, 'Could not access VORP Core API; framework bridge is unavailable')
        return
    end

    Frontier.Core.Ready = true
    FrontierLib.Log('INFO', resourceName, 'Core API initialized; VORP bridge available')
end)

exports('GetPlayer', Frontier.GetPlayer)
exports('GetPlayers', Frontier.GetPlayers)
exports('IsPlayerLoaded', Frontier.IsPlayerLoaded)
exports('HasPermission', Frontier.HasPermission)
exports('GetStatus', Frontier.GetStatus)
exports('RegisterCallback', Frontier.RegisterCallback)
exports('TriggerCallback', Frontier.TriggerCallback)

-- Server-side API is also available to resources that directly depend on core.
