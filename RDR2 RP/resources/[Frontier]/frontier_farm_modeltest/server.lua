RegisterCommand('farmmodels',function(src)
    if src<=0 then print('Use /farmmodels in game.');return end
    if not IsPlayerAceAllowed(src,'frontier.farmmodels') then
        TriggerClientEvent('chat:addMessage',src,{args={'Farm models','Permission denied (frontier.farmmodels).'}})
        return
    end
    TriggerClientEvent('frontier_farm_modeltest:open',src)
end,false)
