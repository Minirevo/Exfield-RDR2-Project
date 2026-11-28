local opened=false
local function close() opened=false;SetNuiFocus(false,false);SendNUIMessage({type='close'}) end
RegisterCommand('business',function() TriggerServerEvent('frontier_business:open') end,false)
RegisterNetEvent('frontier_business:view',function(d) if source~=65535 then return end;opened=true;SetNuiFocus(true,true);SendNUIMessage({type='view',data=d}) end)
RegisterNetEvent('frontier_business:close',function() if source==65535 then close() end end)
RegisterNetEvent('frontier_business:notice',function(m) if source~=65535 then return end;TriggerEvent('chat:addMessage',{args={'Business',m}});SendNUIMessage({type='notice',message=m}) end)
RegisterNUICallback('close',function(_,cb) close();cb({ok=true}) end)
RegisterNetEvent('frontier_business:result',function(d) if source==65535 then SendNUIMessage({type='result',data=d}) end end)
RegisterNUICallback('action',function(d,cb) if not opened then cb({ok=false});return end;TriggerServerEvent('frontier_business:action',d.action,d.data,d.request);cb({ok=true}) end)
RegisterNUICallback('refresh',function(_,cb) if opened then TriggerServerEvent('frontier_business:refresh') end;cb({ok=opened}) end)
RegisterNUICallback('management',function(_,cb) if opened then TriggerServerEvent('frontier_business:open') end;cb({ok=opened}) end)
AddEventHandler('onClientResourceStop',function(r) if r==GetCurrentResourceName() then close() end end)

RegisterNUICallback('jobs',function(d,cb)
 if not opened or type(d)~='table' or type(d.company)~='string' then cb({ok=false,message='Select a company first.'});return end
 if GetResourceState('frontier_jobs')~='started' then cb({ok=false,message='frontier_jobs is not started on the client.'});return end
 close();TriggerEvent('frontier_jobs:manage',d.company);cb({ok=true})
end)
