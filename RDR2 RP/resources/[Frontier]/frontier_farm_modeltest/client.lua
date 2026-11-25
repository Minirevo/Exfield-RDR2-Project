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
    TriggerEvent('frontier_farm_modeltest:editorHide')
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

-- Independent assembly preview; does not modify the model browser or its candidates.
local pen,penGeneration={},0
local penOrigin,penHeading
local function penNote(msg) TriggerEvent('chat:addMessage',{args={'Farm pen',msg}}) end
local function clearPen()
    penGeneration=penGeneration+1
    for _,h in ipairs(pen) do if DoesEntityExist(h) then SetEntityAsMissionEntity(h,true,true);DeleteEntity(h) end end
    pen={}
end
local function layout()
    local parts={}
    local function add(model,x,y,heading,ped)
        parts[#parts+1]={model=model,x=x,y=y,heading=heading,ped=ped}
    end
    -- 12 x 16 m; verified fence length 2.01 m along local X.
    -- 4 m open entrance on the south side; no unverified gate model.
    for x=-5,5,2 do
        add('p_fence02x',x,8,0)
        if math.abs(x)>2 then add('p_fence02x',x,-8,0) end
    end
    for y=-7,7,2 do
        add('p_fence02x',-6,y,90)
        add('p_fence02x',6,y,90)
    end
    add('p_watertrough03x',3.8,5.8,0)
    add('p_haybalestack03x',-2.8,5.8,0)
    add('p_troughtable01x',-3.4,3.6,0)
    add('p_haybale03x',4.5,-5.8,0)
    add('a_c_cow',-2.5,-2,25,true)
    add('a_c_cow',2.5,0,160,true)
    add('a_c_bull_01',-1,2,90,true)
    return parts
end
local function spawnPen()
    clearPen()
    local ticket=penGeneration
    local rad=math.rad(penHeading)
    local parts=layout()
    local hashes={}
    local function releaseModels()
        for _,hash in pairs(hashes) do SetModelAsNoLongerNeeded(hash) end
    end
    -- Load each unique model once, with cancellation during every wait.
    for _,p in ipairs(parts) do
        if not hashes[p.model] then
            local hash=GetHashKey(p.model)
            if not IsModelValid(hash) then releaseModels();penNote('Invalid model: '..p.model);return end
            hashes[p.model]=hash
            RequestModel(hash)
            local deadline=GetGameTimer()+5000
            while ticket==penGeneration and not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(20) end
            if ticket~=penGeneration then releaseModels();return end
            if not HasModelLoaded(hash) then releaseModels();penNote('Load timeout: '..p.model);return end
        end
    end
    local misses=0
    for _,p in ipairs(parts) do
        if ticket~=penGeneration then releaseModels();return end
        local x=penOrigin.x+p.x*math.cos(rad)-p.y*math.sin(rad)
        local y=penOrigin.y+p.x*math.sin(rad)+p.y*math.cos(rad)
        local hash=hashes[p.model]
        RequestCollisionAtCoord(x,y,penOrigin.z)
        local ok,z=GetGroundZFor_3dCoord(x,y,penOrigin.z+8.0,false)
        if not ok or math.abs(z-penOrigin.z)>4 then
            misses=misses+1
        else
            local min=GetModelDimensions(hash)
            local h
            local angle=(penHeading+p.heading)%360
            -- Correct vertical model origin for both animals and props.
			z=z-min.z

			if p.ped then
				h=CreatePed(hash,x,y,z,angle,false,false,false,false)
			else
				h=CreateObject(hash,x,y,z,false,false,false,false,false)
			end
            if h and h~=0 and DoesEntityExist(h) then
                pen[#pen+1]=h
                SetEntityAsMissionEntity(h,true,true)
                if p.ped then
                    pcall(function() Citizen.InvokeNative(0x283978A15512B2FE,h,true) end)
                    SetBlockingOfNonTemporaryEvents(h,true)
                end
                SetEntityCoordsNoOffset(h,x,y,z,false,false,false)
                SetEntityHeading(h,angle)
                SetEntityInvincible(h,true)
                FreezeEntityPosition(h,true)
            else misses=misses+1 end
        end
    end
    releaseModels()
    penNote(('Medium cattle pen: %d/%d parts spawned. %d skipped. /farmpen rotate or /farmpen clear.'):format(#pen,#parts,misses))
end
RegisterNetEvent(E..'pen',function(action)
    if source~=65535 then return end
    if action=='clear' then clearPen();penOrigin=nil;penNote('Preview removed.');return end
    if action=='spawn' or not penOrigin then
        local ped=PlayerPedId()
        local pos=GetOffsetFromEntityInWorldCoords(ped,0.0,14.0,0.0)
        penOrigin={x=pos.x,y=pos.y,z=pos.z}
        penHeading=GetEntityHeading(ped)
    else penHeading=(penHeading+90)%360 end
    CreateThread(function()
        local ok,err=pcall(spawnPen)
        if not ok then clearPen();penNote('Assembly failed: '..tostring(err)) end
    end)
end)
AddEventHandler('onClientResourceStop',function(r)
    if r==GetCurrentResourceName() then clearPen() end
end)

AddEventHandler('frontier_farm_modeltest:editorOpen',function() if active then close() end;clearPen() end)
