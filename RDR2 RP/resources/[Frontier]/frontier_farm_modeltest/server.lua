RegisterCommand('farmmodels',function(src)
    if src<=0 then print('Use /farmmodels in game.');return end
    if not IsPlayerAceAllowed(src,'frontier.farmmodels') then
        TriggerClientEvent('chat:addMessage',src,{args={'Farm models','Permission denied (frontier.farmmodels).'}})
        return
    end
    TriggerClientEvent('frontier_farm_modeltest:open',src)
end,false)

RegisterCommand('farmpen',function(src,args)
    if src<=0 or not IsPlayerAceAllowed(src,'frontier.farmmodels') then return end
    local action=args[1] or 'spawn'
    if action~='spawn' and action~='clear' and action~='rotate' then
        TriggerClientEvent('chat:addMessage',src,{args={'Farm pen','Usage: /farmpen [spawn|clear|rotate]'}});return
    end
    TriggerClientEvent('frontier_farm_modeltest:pen',src,action)
end,false)
