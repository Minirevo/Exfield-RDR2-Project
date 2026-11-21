local Core = Frontier.Core

MySQL.ready(function()
    while not Core.Ready do
        local ok = pcall(MySQL.query.await, [[
            SELECT i.id FROM frontier_character_identities i
            LEFT JOIN frontier_character_data d ON d.character_id = i.id LIMIT 0
        ]])
        if ok then
            Core.Ready = true
            Core.SyncOnline(Core.Provider)
        else
            FrontierLib.Log('ERROR', GetCurrentResourceName(), 'Character schema unavailable')
            Wait(FrontierConfig.SessionRetryMs)
        end
    end
end)

exports('GetPlayer', Frontier.GetPlayer)
exports('GetPlayers', Frontier.GetPlayers)
exports('IsPlayerLoaded', Frontier.IsPlayerLoaded)
exports('GetPlayerCharacterId', Frontier.GetPlayerCharacterId)
exports('GetCharacterData', Frontier.GetCharacterData)
exports('HasPermission', Frontier.HasPermission)
exports('GetStatus', Frontier.GetStatus)
exports('RegisterCallback', Frontier.RegisterCallback)
exports('TriggerCallback', Frontier.TriggerCallback)
exports('UpdateCharacterData', function(id, expectedVersion, patch)
    local caller = GetInvokingResource()
    if not caller or FrontierConfig.CharacterWriters[caller] ~= true then
        return false, 'forbidden'
    end
    return Frontier.UpdateCharacterData(id, expectedVersion, patch)
end)
