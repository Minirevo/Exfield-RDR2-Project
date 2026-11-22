local E='frontier_production:'
local ready,shown,ticket=false,false,nil
local opening,pending
local viewId=0
local function tell(text)
    TriggerEvent('chat:addMessage',{args={'Frontier Produktion',text}})
end
local function close()
    if ticket then TriggerServerEvent(E..'close',ticket) end
    ticket,opening,pending=nil,nil,nil
    if shown then SetNuiFocus(false,false) end
    shown=false
    SendNUIMessage({type='close'})
end
RegisterCommand('produktion',function()
    if shown then close();return end
    if not ready or opening or (type(IsNuiFocused)=='function' and IsNuiFocused()) then return end
    viewId=viewId+1
    local view=viewId
    opening=view
    TriggerServerEvent(E..'open',view)
    SetTimeout(12000,function()
        if opening==view then close();tell('Die Produktion antwortet gerade nicht.') end
    end)
end,false)
RegisterNetEvent(E..'opened',function(view,token,data)
    if source~=65535 or opening~=view then return end
    opening=nil
    ticket=token
    if type(IsNuiFocused)=='function' and IsNuiFocused() then close();return end
    shown=true
    SetNuiFocus(true,true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({type='open',snapshot=data})
end)
RegisterNetEvent(E..'response',function(token,seq,data)
    if source~=65535 then return end
    if seq==0 and token==opening then
        close();tell(data.message);return
    end
    if token~=ticket or not pending or seq~=pending.seq then return end
    pending=nil
    data.type='response'
    data.seq=seq
    SendNUIMessage(data)
end)
RegisterNetEvent(E..'closed',function()
    if source==65535 then close() end
end)
RegisterNUICallback('ready',function(_,cb) ready=true;if shown then close() end;cb({ok=true}) end)
RegisterNUICallback('close',function(_,cb) close();cb({ok=true}) end)
RegisterNUICallback('request',function(data,cb)
    if not shown or pending or type(data)~='table' or type(data.seq)~='number' then cb({ok=false});return end
    local request={seq=data.seq}
    pending=request
    TriggerServerEvent(E..'request',ticket,data.seq,data.action,data.data)
    SetTimeout(12000,function()
        if pending~=request then return end
        pending=nil
        SendNUIMessage({type='response',seq=request.seq,ok=false,retry=true,
            message='Keine Bestätigung. Wiederhole dieselbe Anfrage.'})
    end)
    cb({ok=true})
end)
AddEventHandler('onClientResourceStop',function(name)
    if name==GetCurrentResourceName() and shown then SetNuiFocus(false,false) end
end)
