local resourceName = GetCurrentResourceName()

AddEventHandler('onResourceStart', function(startedResource)
    if startedResource ~= resourceName then
        return
    end

    FrontierLib.Log('INFO', resourceName, 'Starting Frontier Core', {
        version = GetResourceMetadata(resourceName, 'version', 0) or 'unknown',
        locale = FrontierConfig.Locale,
    })

    local core, reason = Frontier.Core.VORP.GetCore()
    if not core then
        Frontier.Core.Ready = false
        FrontierLib.Log('ERROR', resourceName, 'VORP Core API validation failed; framework bridge is unavailable', {
            reason = reason,
        })
        return
    end

    Frontier.Core.Ready = true
    FrontierLib.Log('INFO', resourceName, 'Core API initialized; VORP getUser is available')
end)

exports('GetPlayer', Frontier.GetPlayer)
exports('GetPlayers', Frontier.GetPlayers)
exports('IsPlayerLoaded', Frontier.IsPlayerLoaded)
exports('HasPermission', Frontier.HasPermission)
exports('GetStatus', Frontier.GetStatus)
exports('RegisterCallback', Frontier.RegisterCallback)
exports('TriggerCallback', Frontier.TriggerCallback)

-- Server-side API is also available to resources that directly depend on core.
