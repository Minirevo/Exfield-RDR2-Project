local last={}
RegisterNetEvent('frontier_hud:balance',function(sequence)
 local src=source
 if type(sequence)~='number' or sequence%1~=0 or sequence<1 or sequence>2147483646 then return end
 local now=GetGameTimer()
 if last[src] and now-last[src]<2000 then return end
 last[src]=now
 local id=exports.frontier_core:GetPlayerCharacterId(src)
 if not id then return end
 local ok,b=exports.frontier_economy:GetCharacterBalances(src)
 if ok and exports.frontier_core:GetPlayerCharacterId(src)==id then
  TriggerClientEvent('frontier_hud:balance',src,sequence,{cash=b.cash,bank=b.bank,currency=b.currency})
 end
end)
AddEventHandler('playerDropped',function() last[source]=nil end)
