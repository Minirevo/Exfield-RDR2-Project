local E='frontier_production:station:'
local ticket,shown,opening,pending,work
local seq=0
local function tell(s)TriggerEvent('chat:addMessage',{args={'Production',tostring(s)}})end
local function ui(d)SendNUIMessage(d)end
local function close()
 if ticket then TriggerServerEvent(E..'close',ticket) end
 if shown then SetNuiFocus(false,false) end
 ticket,shown,opening,pending=nil,nil,nil,nil
 if not work then ui({type='stationClose'}) end
end
AddEventHandler('frontier_production:stationOpen',function(sid,fid)
 if shown or opening or work or IsNuiFocused() then return end
 opening=GetGameTimer();local stamp=opening
 TriggerServerEvent(E..'open',sid,fid)
 SetTimeout(10000,function()if opening==stamp then opening=nil;tell('Station did not respond. Check server console.') end end)
end)
RegisterNetEvent(E..'notice',function(msg)
 if source~=65535 then return end
 if opening then opening=nil end
 tell(msg);ui({type='stationNotice',message=msg})
end)
RegisterNetEvent(E..'view',function(token,data)
 if source~=65535 or not opening then return end
 opening=nil
 if IsNuiFocused() then TriggerServerEvent(E..'close',token);return end
 ticket,shown,seq=token,true,0
 SetNuiFocus(true,true);SetNuiFocusKeepInput(false);ui({type='stationOpen',snapshot=data})
end)
RegisterNetEvent(E..'response',function(token,n,d)
 if source~=65535 or token~=ticket or not pending or pending.seq~=n then return end
 pending=nil;d.type='stationResult';d.seq=n;ui(d)
end)
RegisterNetEvent(E..'close',function()if source==65535 then close() end end)
RegisterNUICallback('stationClose',function(_,cb)close();cb({ok=true})end)
RegisterNUICallback('stationRequest',function(d,cb)
 if not shown or pending or type(d)~='table' or type(d.action)~='string' or type(d.data)~='table' then cb({ok=false});return end
 if d.retry and type(d.seq)=='number' and d.seq==seq then else seq=seq+1 end
 local request={seq=seq};pending=request
 TriggerServerEvent(E..'request',ticket,seq,d.action,d.data)
 SetTimeout(12000,function()if pending==request then pending=nil;ui({type='stationResult',seq=request.seq,ok=false,retry=true,message='No confirmation. Retry the same request.'}) end end)
 cb({ok=true,seq=seq})
end)
local scenarios={sawmill='WORLD_HUMAN_HAMMER',carpentry='WORLD_HUMAN_HAMMER',smeltery='WORLD_HUMAN_HAMMER',forge='WORLD_HUMAN_HAMMER',anvil='WORLD_HUMAN_HAMMER',tanning='WORLD_HUMAN_CROUCH_INSPECT',leatherwork='WORLD_HUMAN_CROUCH_INSPECT',stove='WORLD_HUMAN_CROUCH_INSPECT',oven='WORLD_HUMAN_CROUCH_INSPECT',mill='WORLD_HUMAN_HAMMER',kiln='WORLD_HUMAN_HAMMER',pottery='WORLD_HUMAN_CROUCH_INSPECT',glass='WORLD_HUMAN_HAMMER',apothecary='WORLD_HUMAN_CROUCH_INSPECT',jewellery='WORLD_HUMAN_CROUCH_INSPECT'}
local function clear()
 if work then ClearPedTasksImmediately(PlayerPedId()) end
 work=nil;ui({type='stationEnd'})
end
RegisterNetEvent(E..'work',function(d)
 if source~=65535 or work then return end
 close()
 if IsNuiFocused() or IsPedDeadOrDying(PlayerPedId(),true) or IsPedOnMount(PlayerPedId()) or IsPedInAnyVehicle(PlayerPedId(),false) then TriggerServerEvent(E..'cancel',d.id);return end
 work=d;d.started=GetGameTimer()
 ui({type='stationWork',label=d.label,ms=d.ms,target=d.target,width=.11})
 pcall(TaskStartScenarioInPlace,PlayerPedId(),GetHashKey(scenarios[d.kind] or 'WORLD_HUMAN_HAMMER'),d.ms,true,false,false,false)
 CreateThread(function()
  local lastSend=0
  while work==d do
   local elapsed=GetGameTimer()-d.started
   if IsPedDeadOrDying(PlayerPedId(),true) or IsControlJustPressed(0,0x156F7119) then TriggerServerEvent(E..'cancel',d.id);clear();return end
   DisableControlAction(0,0xD9D0E1C0,true)
   if not d.hit and elapsed<d.ms and IsDisabledControlJustPressed(0,0xD9D0E1C0) then d.hit=true;TriggerServerEvent(E..'strike',d.id);ui({type='stationStrike'}) end
   if elapsed>=d.ms+200 and elapsed-lastSend>=1000 then
    lastSend=elapsed;TriggerServerEvent(E..'finish',d.id)
   end
   if elapsed>d.ms+12000 then tell('Work confirmation timed out; the worker will recover the reserved materials.');clear();return end
   Wait(0)
  end
 end)
end)
RegisterNetEvent(E..'end',function(msg)if source==65535 then clear();if msg~='' then tell(msg) end end end)
AddEventHandler('onClientResourceStop',function(r)if r==GetCurrentResourceName() then close();clear() end end)
