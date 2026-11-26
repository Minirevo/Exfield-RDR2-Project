local open=false
RegisterCommand('skills',function()if not IsNuiFocused() then TriggerServerEvent('frontier_skills:open') end end,false)
RegisterNetEvent('frontier_skills:view',function(rows)
 if source~=65535 or IsNuiFocused() then return end
 open=true;SetNuiFocus(true,true);SendNUIMessage({type='open',rows=rows})
end)
local function close()if open then open=false;SetNuiFocus(false,false);SendNUIMessage({type='close'}) end end
RegisterNUICallback('close',function(_,cb)close();cb({ok=true})end)
AddEventHandler('onResourceStop',function(name)if name==GetCurrentResourceName() then close() end end)
