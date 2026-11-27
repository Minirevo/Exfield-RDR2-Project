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
RegisterNetEvent(E..'notice',function(msg)if source==65535 then opening=nil;tell(msg);print('[frontier_logistics/server] '..tostring(msg));ui({type='notice',message=msg}) end end)
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
   
local hash=model(d.model)
assert(hash,'Wagon model unavailable')


local networkWagon=d.networkWagon==true

d.x = tonumber(d.x) + 0.0
d.y = tonumber(d.y) + 0.0
d.z = tonumber(d.z) + 0.0
d.heading = tonumber(d.heading) + 0.0

print(('[frontier_logistics/spawn] Coordinate types: %s %s %s %s'):format(
    math.type(d.x),
    math.type(d.y),
    math.type(d.z),
    math.type(d.heading)
))


local function xyz(p)
    return ('%.2f %.2f %.2f'):format(p.x,p.y,p.z)
end

local function coords(entity)
    return GetEntityCoords(entity,false,true)
end

local function distance(p,q)
    return math.sqrt(
        (p.x-q.x)^2+
        (p.y-q.y)^2+
        (p.z-q.z)^2
    )
end

print(('[frontier_logistics/spawn] Creating %s %s at saved position %s'):format(
    networkWagon and 'network-first wagon' or 'local-first wagon',
    d.model,
    xyz(d)
))

RequestCollisionAtCoord(d.x,d.y,d.z)

local v=CreateVehicle(
    hash,d.x,d.y,d.z,d.heading,
    networkWagon,networkWagon,true,false
)
   SetModelAsNoLongerNeeded(hash);assert(v and v~=0 and DoesEntityExist(v),'Vehicle spawn failed');s.vehicle=v
   
SetEntityAsMissionEntity(v,true,true)
FreezeEntityPosition(v,true)

SetEntityCoordsNoOffset(
    v,d.x,d.y,d.z,
    false,false,false
)

SetEntityHeading(v,d.heading)

Wait(500)

print('[frontier_logistics/spawn] Initial wagon position: '..xyz(coords(v)))

assert(
    distance(coords(v),d)<=15,
    'Initial wagon position incorrect'
)

   local function getHarness(slot)
    return Citizen.InvokeNative(0xA8BA0BAE0173457B,v,slot,Citizen.ResultAsInteger())
   end
   local slots={}
   for i,h in ipairs(d.horses) do
    local slot=tonumber(h.slot_no)
    assert(slot and slot>=0 and slot<=3 and slot%1==0,'Invalid harness slot')
    local hh=model(h.model);assert(hh,'Horse model unavailable: '..tostring(h.model))
    local p=GetOffsetFromEntityInWorldCoords(v,slot%2==0 and -1.0 or 1.0,3.0+math.floor(slot/2)*2,0.0)
    local ped=CreatePed(hh,p.x,p.y,p.z,d.heading,false,false,false,false)
    SetModelAsNoLongerNeeded(hh);assert(ped and ped~=0 and DoesEntityExist(ped),'Horse spawn failed')
    s.horses[#s.horses+1]=ped;slots[i]=slot
    SetEntityAsMissionEntity(ped,true,true)
    pcall(Citizen.InvokeNative,0x283978A15512B2FE,ped,true)
    Wait(250)
    local accepted
    for attempt=1,4 do
     accepted=Citizen.InvokeNative(0x316CDB5B6E8F4110,ped,v,slot,Citizen.ResultAsInteger())
     if accepted==true or accepted==1 or getHarness(slot)==ped then break end
     Wait(300)
    end
    assert(accepted==true or accepted==1 or getHarness(slot)==ped,('Local horse harness rejected: slot=%s result=%s'):format(slot,tostring(accepted)))
    Wait(150)
    assert(getHarness(slot)==ped,('Local harness slot %d does not contain assigned horse'):format(slot))
    print(('[frontier_logistics/spawn] Local horse slot %d attached'):format(slot))
   end
   -- Register the wagon and team only AFTER the local harness links exist.
   -- Do not send local handles to the server or accept a substitute horse.
   local function register(entity,label)
    if not NetworkGetEntityIsNetworked(entity) then
     Citizen.InvokeNative(0x06FAACD625D80CAA,entity)
    end
    local deadline=GetGameTimer()+5000
    repeat
     if DoesEntityExist(entity) and NetworkGetEntityIsNetworked(entity) then
      local id=NetworkGetNetworkIdFromEntity(entity)
      if id and id~=0 then
       if type(SetNetworkIdCanMigrate)=='function' then pcall(SetNetworkIdCanMigrate,id,true) end
       print(('[frontier_logistics/spawn] %s network ID=%d'):format(label,id))
       return id
      end
     end
     Wait(100)
    until GetGameTimer()>=deadline
    error(label..' could not become networked',0)
   end
   local net=register(v,'Wagon')
   local nets={}
   for i,ped in ipairs(s.horses) do nets[i]=register(ped,'Horse slot '..slots[i]) end
   Wait(500)
   for i,ped in ipairs(s.horses) do
    assert(getHarness(slots[i])==ped,('Harness slot %d detached during network registration'):format(slots[i]))
   end
   print('[frontier_logistics/spawn] Both assigned horses retained after networking')
   

print('[frontier_logistics/spawn] Client wagon before position sync: '..xyz(coords(v)))

local controlDeadline=GetGameTimer()+3000

while not NetworkHasControlOfEntity(v)
    and GetGameTimer()<controlDeadline do

    NetworkRequestControlOfEntity(v)
    Wait(100)
end

assert(
    NetworkHasControlOfEntity(v),
    'Unable to obtain wagon network control'
)

FreezeEntityPosition(v,false)

SetEntityCoordsNoOffset(
    v,d.x,d.y,d.z,
    false,false,false
)

SetEntityHeading(v,d.heading)

Wait(1000)

print('[frontier_logistics/spawn] Client wagon after position sync: '..xyz(coords(v)))

assert(
    distance(coords(v),d)<=15,
    'Wagon position incorrect after synchronization'
)

for i,ped in ipairs(s.horses) do
    assert(
        getHarness(slots[i])==ped,
        ('Harness slot %d detached after position refresh'):format(slots[i])
    )

    print(('[frontier_logistics/spawn] Horse slot %d position: %s'):format(
        slots[i],
        xyz(coords(ped))
    ))
end


   print('[frontier_logistics/spawn] Wagon net='..net..'; waiting for server registration')
   Wait(500)
   local models={GetEntityModel(v)}
   assert((models[1]&0xffffffff)==(GetHashKey(d.model)&0xffffffff),'Wagon model changed during networking')
   for i,ped in ipairs(s.horses) do
    models[i+1]=GetEntityModel(ped)
    assert((models[i+1]&0xffffffff)==(GetHashKey(d.horses[i].model)&0xffffffff),'Horse model changed during networking')
   end
   local timeout=GetGameTimer()+35000
   while not s.accepted and GetGameTimer()<timeout do
   
	local driver=GetPedInVehicleSeat(v,-1)

	if driver and driver~=0 and driver==PlayerPedId() then
		TaskLeaveVehicle(driver,v,0)
	end

    TriggerServerEvent(E..'spawnAck',d.id,d.token,net,nets,models)
    Wait(800)
   end
   -- If ack was lost but state bag proves authoritative registration, retain the vehicle.
   if not s.accepted and Entity(v).state.frontierWagonId==d.id then s.accepted=true end
   assert(s.accepted,'Server did not register network entities')
   FreezeEntityPosition(v,false)
   print('[frontier_logistics/spawn] Server registration accepted; wagon ready')
  end)
  if not ok then print('[frontier_logistics/spawn] '..tostring(err));clearSpawn(s);TriggerServerEvent(E..'spawnFailed',d.id,d.token,tostring(err)) end
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


RegisterCommand('clearghostwagon', function()
    local player = PlayerPedId()
    local pos = GetEntityCoords(player)
    local nearest
    local distance = 5.0

    for _, v in ipairs(GetGamePool('CVehicle')) do
        if GetEntityModel(v) == GetHashKey('supplywagon') then
            local dist = #(GetEntityCoords(v) - pos)

            if dist < distance then
                nearest = v
                distance = dist
            end
        end
    end

    if not nearest then
        print('No supply wagon nearby')
        return
    end

    local state = Entity(nearest).state

    if state.frontierWagonId or state.frontierWagon then
        print('Refused: wagon has a logistics registration')
        return
    end

    local function removeEntity(entity)
        local deadline = GetGameTimer() + 3000

        while NetworkGetEntityIsNetworked(entity)
            and not NetworkHasControlOfEntity(entity)
            and GetGameTimer() < deadline do

            NetworkRequestControlOfEntity(entity)
            Wait(100)
        end

        if NetworkGetEntityIsNetworked(entity)
            and not NetworkHasControlOfEntity(entity) then

            print('Unable to obtain entity control')
            return false
        end

        SetEntityAsMissionEntity(entity,true,true)
        DeleteEntity(entity)

        return not DoesEntityExist(entity)
    end

    -- Remove unregistered attached draft horses.
    for slot = 0, 3 do
        local horse = Citizen.InvokeNative(
            0xA8BA0BAE0173457B,
            nearest,
            slot,
            Citizen.ResultAsInteger()
        )

        if horse and horse ~= 0
            and DoesEntityExist(horse)
            and not Entity(horse).state.frontierDraftHorse then

            removeEntity(horse)
        end
    end

    if removeEntity(nearest) then
        print('Ghost wagon removed successfully')
    else
        print('Ghost wagon could not be removed')
    end
end,false)

