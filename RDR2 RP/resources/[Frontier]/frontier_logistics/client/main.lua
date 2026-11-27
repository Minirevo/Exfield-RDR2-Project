local E='frontier_logistics:'
local C=LogisticsConfig
local ticket,opening,pending,activity
local seq=0
local spawned,crates,visuals={},{},{}
local function tell(s)TriggerEvent('chat:addMessage',{args={'Logistics',tostring(s)}})end
local function ui(d)SendNUIMessage(d)end
local function delete(e)if e and e~=0 and DoesEntityExist(e) then DeleteEntity(e) end end
local function model(name,limit)
 local hash=GetHashKey(name)
 if not IsModelValid(hash) then return end
 RequestModel(hash);local untilTime=GetGameTimer()+(limit or 5000)
 while not HasModelLoaded(hash) and GetGameTimer()<untilTime do Wait(20) end
 if not HasModelLoaded(hash) then return end
 return hash
end
local function close()
 if ticket then TriggerServerEvent(E..'close',ticket);SetNuiFocus(false,false) end
 ticket,opening,pending=nil,nil,nil
 ui({type='close'})
end
local function open(mode,id,sid)
 if ticket or opening or activity or IsNuiFocused() then return end
 opening=GetGameTimer();local stamp=opening
 TriggerServerEvent(E..'open',mode,id,sid)
 SetTimeout(10000,function()if opening==stamp then opening=nil;tell('Logistics did not respond') end end)
end
RegisterNetEvent(E..'notice',function(msg)if source==65535 then opening=nil;tell(msg);ui({type='notice',message=msg}) end end)
RegisterNetEvent(E..'view',function(token,data)
 if source~=65535 or not opening then return end
 opening=nil;if IsNuiFocused() then TriggerServerEvent(E..'close',token);return end
 ticket,seq=token,0;SetNuiFocus(true,true);SetNuiFocusKeepInput(false);ui({type='open',data=data})
end)
RegisterNetEvent(E..'close',function()if source==65535 then close() end end)
RegisterNetEvent(E..'result',function(token,n,d)
 if source~=65535 or token~=ticket or not pending or n~=pending.seq then return end
 pending=nil;d.type='result';d.seq=n;ui(d)
end)
RegisterNUICallback('close',function(_,cb)close();cb({ok=true})end)
RegisterNUICallback('request',function(d,cb)
 if not ticket or pending or type(d.action)~='string' or type(d.data)~='table' then cb({ok=false});return end
 if not (d.retry and d.seq==seq) then seq=seq+1 end
 local req={seq=seq};pending=req
 TriggerServerEvent(E..'request',ticket,seq,d.action,d.data)
 SetTimeout(15000,function()if pending==req then pending=nil;ui({type='result',seq=req.seq,ok=false,retry=true,message='No confirmation. Retry same request.'}) end end)
 cb({ok=true,seq=seq})
end)
AddEventHandler(E..'bench',function(sid,fid)open('bench',fid,sid)end)
local function clearSpawn(s)
 if s.accepted then return end
 for _,h in ipairs(s.horses) do delete(h) end;delete(s.vehicle)
end
RegisterNetEvent(E..'spawn',function(d)
 if source~=65535 or type(d)~='table' or spawned[d.token] then return end
 local s={horses={},accepted=false};spawned[d.token]=s
 CreateThread(function()
  local ok,err=pcall(function()
   local hash=model(d.model);assert(hash,'Wagon model unavailable')
   RequestCollisionAtCoord(d.x,d.y,d.z)
   local v=CreateVehicle(hash,d.x,d.y,d.z,d.heading,true,true,true,false)
   SetModelAsNoLongerNeeded(hash);assert(v~=0 and DoesEntityExist(v),'Vehicle spawn failed');s.vehicle=v
   SetEntityAsMissionEntity(v,true,true);FreezeEntityPosition(v,true)
   local nets={}
   for i,h in ipairs(d.horses) do
    local hh=model(h.model);assert(hh,'Horse model unavailable')
    local p=GetOffsetFromEntityInWorldCoords(v,i%2==1 and -1.0 or 1.0,3.0+math.floor((i-1)/2)*2,0.0)
    local ped=CreatePed(hh,p.x,p.y,p.z,d.heading,true,true,false,false)
    SetModelAsNoLongerNeeded(hh);assert(ped~=0 and DoesEntityExist(ped),'Horse spawn failed')
    s.horses[#s.horses+1]=ped
    SetEntityAsMissionEntity(ped,true,true)
    pcall(Citizen.InvokeNative,0x283978A15512B2FE,ped,true)
    local accepted=Citizen.InvokeNative(0x316CDB5B6E8F4110,ped,v,tonumber(h.slot_no),Citizen.ResultAsInteger())
    assert(accepted==true or accepted==1,'Horse harness rejected')
    local net=NetworkGetNetworkIdFromEntity(ped);assert(net~=0,'Horse not networked');nets[#nets+1]=net
    SetNetworkIdCanMigrate(net,true)
   end
   local net=NetworkGetNetworkIdFromEntity(v);assert(net~=0,'Wagon not networked')
   SetNetworkIdCanMigrate(net,true)
   Wait(500)
   TriggerServerEvent(E..'spawnAck',d.id,d.token,net,nets)
   local timeout=GetGameTimer()+10000
   while not s.accepted and GetGameTimer()<timeout do Wait(100) end
   -- If ack was lost but state bag proves authoritative registration, retain the vehicle.
   if not s.accepted and Entity(v).state.frontierWagonId==d.id then s.accepted=true end
   assert(s.accepted,'Server did not register network entities')
   FreezeEntityPosition(v,false)
  end)
  if not ok then clearSpawn(s);TriggerServerEvent(E..'spawnFailed',d.id,d.token,tostring(err)) end
  spawned[d.token]=nil
 end)
end)
RegisterNetEvent(E..'spawnAccepted',function(token)if source==65535 and spawned[token] then spawned[token].accepted=true end end)
RegisterNetEvent(E..'dismissAssigned',function()if source==65535 then TriggerEvent('frontier_logistics:dismissStableHorse') end end)
RegisterNetEvent(E..'crates',function(list)
 if source~=65535 then return end
 local visible={};for _,c in ipairs(list or {}) do visible[c.id]=c end
 for id,c in pairs(crates) do if not visible[id] then delete(c.handle);crates[id]=nil end end
 for id,c in pairs(visible) do
  if not crates[id] then
   crates[id]={data=c,loading=true};local record=crates[id]
   CreateThread(function()
    local hash=model(C.Models.recoveryCrate)
    if hash and crates[id]==record then
     local min=GetModelDimensions(hash)
     local e=CreateObject(hash,c.x,c.y,c.z-min.z,false,false,false,false,false)
     if e~=0 then FreezeEntityPosition(e,true);SetEntityAsMissionEntity(e,true,true);record.handle=e end
    end
    if hash then SetModelAsNoLongerNeeded(hash) end
    record.loading=false
   end)
  end
 end
end)
local function updateVisual(v,info)
 local count=info.model=='supplywagon' and LogisticsRules.fillCount(info.weight,info.limit,2) or 0
 local old=visuals[v]
 if old and old.id==info.id and old.count==count then return end
 if old then for _,e in ipairs(old.props) do delete(e) end end
 local entry={id=info.id,count=count,props={}};visuals[v]=entry
 if count<=0 then return end
 CreateThread(function()
  local hash=model(C.Models.crate);if not hash then return end
  for i=1,count do
   if visuals[v]~=entry or not DoesEntityExist(v) then break end
   local offset=C.CargoOffsets.supplywagon[i]
   if offset then
    local p=GetEntityCoords(v);local obj=CreateObject(hash,p.x,p.y,p.z,false,false,false,false,false)
    if obj~=0 then
     SetEntityAsMissionEntity(obj,true,true);SetEntityCollision(obj,false,false)
     AttachEntityToEntity(obj,v,0,offset.x,offset.y,offset.z,0.,0.,0.,false,false,false,false,2,true)
     entry.props[#entry.props+1]=obj
    end
   end
  end
  SetModelAsNoLongerNeeded(hash)
 end)
end
local nearest
CreateThread(function()
 while true do
  Wait(700)
  local p=GetEntityCoords(PlayerPedId());nearest=nil;local distance=C.InteractionDistance
  local seen={}
  for _,v in ipairs(GetGamePool('CVehicle')) do
   local info=Entity(v).state.frontierWagon
   if type(info)=='table' and info.id then
    seen[v]=true;updateVisual(v,info)
    local dist=#(GetEntityCoords(v)-p)
    if dist<distance then nearest={mode='wagon',id=info.id,name=info.name};distance=dist end
   end
  end
  for v,entry in pairs(visuals) do if not seen[v] then for _,e in ipairs(entry.props) do delete(e) end;visuals[v]=nil end end
  for id,c in pairs(crates) do local d=c.data;local dist=#(vector3(d.x,d.y,d.z)-p)
   if dist<distance then nearest={mode='crate',id=id,name='Recovery crate'};distance=dist end
  end
 end
end)
RegisterCommand('freight',function()open('registry')end,false)
RegisterCommand('logistics',function()
 if ticket then close();return end
 if nearest then open(nearest.mode,nearest.id) else open('registry') end
end,false)
CreateThread(function()
 while true do
  if nearest and not ticket and not activity and not IsNuiFocused() then
   local str=CreateVarString(10,'LITERAL_STRING','[G] '..nearest.name..' - cargo')
   SetTextScale(.32,.32);SetTextColor(255,255,255,255);SetTextCentre(true);DisplayText(str,.5,.84)
   if IsControlJustPressed(0,0x760A9C6F) then open(nearest.mode,nearest.id) end
   Wait(0)
  else Wait(150) end
 end
end)
local function endActivity(message)
 if activity then ClearPedTasksImmediately(PlayerPedId()) end
 activity=nil;ui({type='activityEnd'})
 if message and message~='' then tell(message) end
end
RegisterNetEvent(E..'loading',function(d)
 if source~=65535 then return end
 close();activity={id=d.id,kind='load',start=GetGameTimer(),ms=d.seconds*1000}
 ui({type='activity',label=d.label,ms=activity.ms})
 pcall(TaskStartScenarioInPlace,PlayerPedId(),GetHashKey('WORLD_HUMAN_CROUCH_INSPECT'),activity.ms,true,false,false,false)
end)
RegisterNetEvent(E..'lockpick',function(d)
 if source~=65535 then return end
 close();activity={id=d.id,kind='pick',start=GetGameTimer(),ms=d.ms}
 ui({type='lockpick',ms=d.ms,target=d.target})
end)
RegisterNetEvent(E..'loadingEnd',function(msg)if source==65535 then endActivity(msg) end end)
CreateThread(function()
 while true do
  if activity then
   local a=activity;local elapsed=GetGameTimer()-a.start
   if a.kind=='load' and (IsControlJustPressed(0,0x156F7119) or IsPedDeadOrDying(PlayerPedId(),true)) then
    TriggerServerEvent(E..'cancelLoad',a.id);endActivity('Cancelling')
   elseif a.kind=='pick' then
    DisableControlAction(0,0xD9D0E1C0,true)
    if not a.hit and IsDisabledControlJustPressed(0,0xD9D0E1C0) then a.hit=true;TriggerServerEvent(E..'lockStrike',a.id) end
   end
   if elapsed>a.ms+20000 then endActivity('Confirmation timed out; check cargo or diagnostics') end
   Wait(0)
  else Wait(200) end
 end
end)
AddEventHandler('onClientResourceStop',function(name)
 if name~=GetCurrentResourceName() then return end
 close();endActivity()
 for _,v in pairs(visuals) do for _,e in ipairs(v.props) do delete(e) end end
 for _,c in pairs(crates) do delete(c.handle) end
 for _,s in pairs(spawned) do clearSpawn(s) end
end)
