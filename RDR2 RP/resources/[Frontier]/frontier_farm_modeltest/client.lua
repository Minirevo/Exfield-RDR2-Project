local E='frontier_farm_modeltest:'
local active=false
local entity,model,kind,origin,heading,scale
local generation=0
local frozen=true
local function send(message) SendNUIMessage(message) end
local function note(message) send({type='status',message=message}) end
local function remove()
    generation=generation+1
    if entity and DoesEntityExist(entity) then
        SetEntityAsMissionEntity(entity,true,true)
        DeleteEntity(entity)
    end
    entity=nil
end
local function close()
    active=false
    remove()
    SetNuiFocus(false,false)
    send({type='close'})
end
local function apply()
    if not entity or not DoesEntityExist(entity) then return end
    SetEntityCoordsNoOffset(entity,origin.x+0.0,origin.y+0.0,origin.z+0.0,false,false,false)
    SetEntityHeading(entity,heading+0.0)
    FreezeEntityPosition(entity,frozen)
    if kind=='ped' then
        -- Native SET_PED_SCALE, RedM. Props do not have a reliable generic scale native.
        pcall(function() Citizen.InvokeNative(0x25ACFC650B65C538,entity,scale+0.0) end)
    end
    send({type='position',x=origin.x,y=origin.y,z=origin.z,heading=heading,scale=scale,frozen=frozen})
end
local function spawn(name,typ)
    if type(name)~='string' or #name>100 or not name:match('^[%w_]+$') or (typ~='ped' and typ~='prop') then return note('Invalid model name or type.') end
    remove()
    local ticket=generation
    local hash=GetHashKey(name)
    if not IsModelValid(hash) then return note('INVALID MODEL: '..name) end
    if typ=='ped' and not IsModelAPed(hash) then return note('Model is not a ped: '..name) end
    if typ=='prop' and IsModelAPed(hash) then return note('Choose animal/ped for this model.') end
    note('Loading '..name..' ...')
    RequestModel(hash)
    local deadline=GetGameTimer()+5000
    while active and generation==ticket and not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(20) end
    if not active or generation~=ticket then SetModelAsNoLongerNeeded(hash);return end
    if not HasModelLoaded(hash) then SetModelAsNoLongerNeeded(hash);return note('LOAD TIMEOUT: '..name) end
    local ped=PlayerPedId()
    local pos=GetOffsetFromEntityInWorldCoords(ped,0.0,4.0,0.0)
    origin={x=pos.x,y=pos.y,z=pos.z}
    heading=GetEntityHeading(ped);scale=1.0;frozen=true
    RequestCollisionAtCoord(pos.x,pos.y,pos.z)
    local found,z=GetGroundZFor_3dCoord(pos.x,pos.y,pos.z+5.0,false)
    if found then
        local min=GetModelDimensions(hash)
        origin.z=typ=='prop' and z-(min and min.z or 0) or z
    end
    local handle
    if typ=='ped' then
        handle=CreatePed(hash,origin.x,origin.y,origin.z,heading,false,false,false,false)
    else
        handle=CreateObject(hash,origin.x,origin.y,origin.z,false,false,false,false,false)
    end
    SetModelAsNoLongerNeeded(hash)
    if not handle or handle==0 or not DoesEntityExist(handle) then return note('SPAWN FAILED: '..name) end
    entity=handle;model=name;kind=typ
    SetEntityAsMissionEntity(entity,true,true)
    SetEntityInvincible(entity,true)
    if typ=='ped' then
        pcall(function() Citizen.InvokeNative(0x283978A15512B2FE,entity,true) end)
        SetBlockingOfNonTemporaryEvents(entity,true)
    end
    apply()
    local min,max=GetModelDimensions(hash)
    send({type='spawned',name=name,kind=typ,hash=tostring(hash),dimensions={x=max.x-min.x,y=max.y-min.y,z=max.z-min.z}})
    note('Spawned '..name..' — inspect appearance, collision and height.')
end
RegisterNetEvent(E..'open',function()
    if source~=65535 then return end
    active=true;SetNuiFocus(true,true);send({type='open'})
end)
RegisterNUICallback('close',function(_,cb) close();cb({ok=true}) end)
RegisterNUICallback('spawn',function(d,cb)
    cb({ok=active})
    if active then CreateThread(function()
        local ok,err=pcall(spawn,d.name,d.kind)
        if not ok then remove();note('Preview failed: '..tostring(err)) end
    end) end
end)
RegisterNUICallback('adjust',function(d,cb)
    if active and entity and DoesEntityExist(entity) then
        local function delta(v,limit) return type(v)=='number' and v==v and math.abs(v)<=limit and v or 0 end
        origin.x=origin.x+delta(d.x,2);origin.y=origin.y+delta(d.y,2);origin.z=origin.z+delta(d.z,2)
        heading=(heading+delta(d.heading,90))%360
        scale=math.max(0.3,math.min(2.0,scale+delta(d.scale,0.5)))
        apply()
    end
    cb({ok=true})
end)
RegisterNUICallback('delete',function(_,cb) remove();note('Preview removed.');cb({ok=true}) end)
RegisterNUICallback('ground',function(_,cb)
    if active and entity and DoesEntityExist(entity) then
        local ok,z=GetGroundZFor_3dCoord(origin.x,origin.y,origin.z+5.0,false)
        if ok then
            local min=GetModelDimensions(GetEntityModel(entity))
            origin.z=kind=='prop' and z-(min and min.z or 0) or z
            apply()
        else note('Ground not available here.') end
    end
    cb({ok=true})
end)
RegisterNUICallback('inspect',function(_,cb)
    if active then SetNuiFocus(false,false);send({type='inspect'}) end
    cb({ok=true})
end)
-- F7 brings the menu back after walking around the local preview.
CreateThread(function()
    while true do
        if active then
            Wait(0)
            if IsControlJustPressed(0,0x7F8D09B8) then SetNuiFocus(true,true);send({type='open'}) end
        else Wait(250) end
    end
end)
RegisterCommand('farmmodelclose',function() if active then close() end end,false)
AddEventHandler('onClientResourceStop',function(r) if r==GetCurrentResourceName() then close() end end)
