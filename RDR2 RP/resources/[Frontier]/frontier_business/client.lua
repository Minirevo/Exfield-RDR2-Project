local opened=false
local function close() opened=false;SetNuiFocus(false,false);SendNUIMessage({type='close'}) end
RegisterCommand('business',function() TriggerServerEvent('frontier_business:open') end,false)
RegisterNetEvent('frontier_business:view',function(d) if source~=65535 then return end;opened=true;SetNuiFocus(true,true);SendNUIMessage({type='view',data=d}) end)
RegisterNetEvent('frontier_business:notice',function(m) if source~=65535 then return end;TriggerEvent('chat:addMessage',{args={'Business',m}});SendNUIMessage({type='notice',message=m}) end)
RegisterNUICallback('close',function(_,cb) close();cb({ok=true}) end)
RegisterNUICallback('action',function(d,cb) if opened then TriggerServerEvent('frontier_business:action',d.action,d.data) end;cb({ok=true}) end)
RegisterNUICallback('refresh',function(_,cb) TriggerServerEvent('frontier_business:open');cb({ok=true}) end)
AddEventHandler('onClientResourceStop',function(r) if r==GetCurrentResourceName() then close() end end)
