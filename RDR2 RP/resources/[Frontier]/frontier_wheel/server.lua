local last={}
RegisterNetEvent('frontier_wheel:gunLabRequest',function()
 local src=source
 local now=GetGameTimer()
 if last[src] and now-last[src]<1000 then return end
 last[src]=now
 if not IsPlayerAceAllowed(src,'frontier.wheel.gunlab') or not exports.frontier_core:GetPlayerCharacterId(src) then
  TriggerClientEvent('frontier_wheel:gunLabDenied',src);return
 end
 TriggerClientEvent('frontier_wheel:gunLabGrant',src)
end)
AddEventHandler('playerDropped',function() last[source]=nil end)
