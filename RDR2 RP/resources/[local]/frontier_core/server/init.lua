local resourceName = GetCurrentResourceName()

AddEventHandler('onResourceStart', function(startedResource)
    if startedResource ~= resourceName then
        return
    end

    FrontierLib.Log('INFO', resourceName, 'Starting Frontier Core', {
        version = GetResourceMetadata(resourceName, 'version', 0) or 'unknown',
        locale = FrontierConfig.Locale,
    })

    -- Resolve the VORP API during startup to report dependency readiness.
    local core = Frontier.Core.VORP and Frontier.Core.VORP.SyncPlayer
    if not core then
        FrontierLib.Log('ERROR', resourceName, 'VORP adapter did not initialize')
        return
    end

    Frontier.Core.Ready = true
    FrontierLib.Log('INFO', resourceName, 'Core API initialized')
end)

exports('GetPlayer', Frontier.GetPlayer)
exports('GetPlayers', Frontier.GetPlayers)
exports('IsPlayerLoaded', Frontier.IsPlayerLoaded)
exports('HasPermission', Frontier.HasPermission)
exports('RegisterCallback', Frontier.RegisterCallback)
exports('TriggerCallback', Frontier.TriggerCallback)

-- Server-side API is also available to resources that directly depend on core.
