local C=LogisticsConfig
RegisterCommand('logisticsmodels',function(src,args)
    if src<=0 then print('Run /logisticsmodels in game.') return end
    if not IsPlayerAceAllowed(src,C.ModelTestAce) then
        TriggerClientEvent('chat:addMessage',src,{args={'Logistics lab','Permission required: '..C.ModelTestAce}});return
    end
    TriggerClientEvent('frontier_logistics:lab',src,args)
end,false)
