local C=LogisticsConfig
local vehicle,bench
local cargo,horses={},{}
local generation=0
local offsets={}
local function note(s)
    print('[Logistics lab] '..s)
    TriggerEvent('chat:addMessage',{args={'Logistics lab',s}})
end
local function delete(h)
    if h and h~=0 and DoesEntityExist(h) then SetEntityAsMissionEntity(h,true,true);DeleteEntity(h) end
end
local function clear()
    generation=generation+1
    for _,v in ipairs(cargo) do delete(v.handle) end
    for _,h in pairs(horses) do delete(h) end
    delete(vehicle);delete(bench)
    vehicle,bench=nil,nil;cargo,horses,offsets={},{},{}
end
local function load(model,ticket)
    local hash=GetHashKey(model)
    if not IsModelValid(hash) then error('Invalid model: '..model,0) end
    RequestModel(hash);local timeout=GetGameTimer()+5000
    while generation==ticket and not HasModelLoaded(hash) and GetGameTimer()<timeout do Wait(20) end
    if generation~=ticket or not HasModelLoaded(hash) then SetModelAsNoLongerNeeded(hash);error('Model load interrupted: '..model,0) end
    return hash
end
local function dimensions(hash)
    local min,max=GetModelDimensions(hash)
    return {x=max.x-min.x,y=max.y-min.y,z=max.z-min.z},min
end
local function point(distance)
    local ped=PlayerPedId()
    local p=GetOffsetFromEntityInWorldCoords(ped,0.0,distance,0.0)
    RequestCollisionAtCoord(p.x,p.y,p.z)
    local found,z=GetGroundZFor_3dCoord(p.x,p.y,p.z+6,false)
    return p.x,p.y,found and z or p.z,GetEntityHeading(ped)
end
local function spawnWagon(name)
    assert(C.Wagons[name],'Unknown wagon model')
    clear();local ticket=generation;local hash=load(name,ticket)
    local x,y,z,h=point(8.0)
    -- Explicitly suppress automatic draft animals for the harness test.
    local v=CreateVehicle(hash,x,y,z,h,false,false,true,false)
    SetModelAsNoLongerNeeded(hash)
    assert(v and v~=0 and DoesEntityExist(v),'Wagon spawn failed')
    if generation~=ticket then delete(v);return end
    vehicle=v
    SetEntityAsMissionEntity(v,true,true);FreezeEntityPosition(v,true)
    SetEntityInvincible(v,true)
    local d=dimensions(hash)
    note(('Wagon %s: %.2f x %.2f x %.2f m. Local preview, no inventory.'):format(name,d.x,d.y,d.z))
    note('Use /logisticsmodels cargo crate 0 0 0.8, horse 0, drive, export or clear.')
end
local function spawnProp(model,x,y,z,h,ticket)
    local hash=load(model,ticket)
    local d,min=dimensions(hash)
    local obj=CreateObject(hash,x,y,z,false,false,false,false,false)
    SetModelAsNoLongerNeeded(hash)
    assert(obj and obj~=0 and DoesEntityExist(obj),'Prop spawn failed')
    if generation~=ticket then delete(obj);error('Preview cancelled',0) end
    SetEntityAsMissionEntity(obj,true,true);SetEntityHeading(obj,h)
    return obj,d,min
end
local function addCargo(kind,x,y,z,heading)
    assert(vehicle and DoesEntityExist(vehicle),'Spawn a wagon first')
    assert(kind=='crate' or kind=='barrel' or kind=='sack','Cargo kind must be crate, barrel or sack')
    assert(#cargo<20,'Maximum 20 preview props')
    local function valid(v)return type(v)=='number' and v==v and math.abs(v)<=5 end
    assert(valid(x) and valid(y) and valid(z),'Offset must be between -5 and 5')
    assert(type(heading)=='number' and math.abs(heading)<=360,'Invalid heading')
    local p=GetEntityCoords(vehicle);local ticket=generation
    local obj,d=spawnProp(C.Models[kind],p.x,p.y,p.z,0,ticket)
    local ok,err=pcall(AttachEntityToEntity,obj,vehicle,0,x,y,z,0.0,0.0,heading,false,false,false,false,2,true)
    if not ok then delete(obj);error(err,0) end
    cargo[#cargo+1]={handle=obj,kind=kind,x=x,y=y,z=z,heading=heading,dimensions=d}
    note(('Cargo #%d: %s %.2f x %.2f x %.2f m'):format(#cargo,kind,d.x,d.y,d.z))
end
local function horse(slot,model)
    assert(vehicle and DoesEntityExist(vehicle),'Spawn a wagon first')
    assert(LogisticsRules.integer(slot,0,3),'Harness slot must be 0–3')
    assert(not horses[slot],'Slot already occupied; clear and respawn to retest')
    model=model or C.HorseModel
    assert(type(model)=='string' and model:match('^a_c_horse_[%w_]+$'),'Use a horse model')
    local ticket=generation;local hash=load(model,ticket)
    assert(IsModelAPed(hash),'Not a ped model')
    local p=GetOffsetFromEntityInWorldCoords(vehicle,slot%2==0 and -1.0 or 1.0,3.0+math.floor(slot/2)*2,0.0)
    local ped=CreatePed(hash,p.x,p.y,p.z,GetEntityHeading(vehicle),false,false,false,false)
    SetModelAsNoLongerNeeded(hash)
    assert(ped and ped~=0 and DoesEntityExist(ped),'Horse creation failed')
    if generation~=ticket then delete(ped);return end
    SetEntityAsMissionEntity(ped,true,true);SetEntityInvincible(ped,true)
    pcall(Citizen.InvokeNative,0x283978A15512B2FE,ped,true)
    local ok,result=pcall(function()
        return Citizen.InvokeNative(0x316CDB5B6E8F4110,ped,vehicle,slot,Citizen.ResultAsInteger())
    end)
    if not ok or (result~=true and result~=1) then
        delete(ped);note('Harness slot '..slot..' rejected: '..tostring(result));return
    end
    horses[slot]=ped;note('Harness slot '..slot..' accepted; visually confirm attachment and driving.')
end
local function spawnBench()
    clear();local ticket=generation
    local x,y,z,h=point(4.0)
    local obj,d,min=spawnProp(C.Models.constructionBench,x,y,z,h,ticket)
    SetEntityCoordsNoOffset(obj,x,y,z-min.z,false,false,false)
    FreezeEntityPosition(obj,true);bench=obj
    note(('Construction bench: %.2f x %.2f x %.2f m'):format(d.x,d.y,d.z))
end
local function export()
    local out={cargo={},harnesses={}}
    if vehicle and DoesEntityExist(vehicle) then out.wagonHash=GetEntityModel(vehicle) end
    for _,v in ipairs(cargo) do out.cargo[#out.cargo+1]={kind=v.kind,x=v.x,y=v.y,z=v.z,heading=v.heading,dimensions=v.dimensions} end
    for slot,ped in pairs(horses) do out.harnesses[#out.harnesses+1]={slot=slot,horseHash=GetEntityModel(ped)} end
    note('Copy the following JSON from F8: '..json.encode(out))
end
local busy=false
RegisterNetEvent('frontier_logistics:lab',function(args)
    if source~=65535 or type(args)~='table' then return end
    if args[1]=='clear' then clear();note('Preview cleared.');return end
    if busy then return note('Preview is busy.') end
    busy=true
    CreateThread(function()
        local ok,err=pcall(function()
            local a=args[1]
            if a=='wagon' then spawnWagon(args[2])
            elseif a=='cargo' then addCargo(args[2],tonumber(args[3]),tonumber(args[4]),tonumber(args[5]),tonumber(args[6]) or 0)
            elseif a=='remove' then
                local n=tonumber(args[2]);assert(n and cargo[n],'Unknown cargo index');delete(cargo[n].handle);table.remove(cargo,n)
            elseif a=='horse' then horse(tonumber(args[2]),args[3])
            elseif a=='bench' then spawnBench()
            elseif a=='drive' then assert(vehicle and DoesEntityExist(vehicle),'Spawn wagon first');FreezeEntityPosition(vehicle,false);note('Local driving test enabled.')
            elseif a=='freeze' then assert(vehicle and DoesEntityExist(vehicle),'Spawn wagon first');FreezeEntityPosition(vehicle,true)
            elseif a=='export' then export()
            else
                note('/logisticsmodels wagon <wagon03x|wagon02x|supplywagon|wagon04x|logwagon>')
                note('/logisticsmodels cargo <crate|barrel|sack> <x> <y> <z> [heading]')
                note('/logisticsmodels horse <0-3> [horse model] | bench | remove <index> | drive | freeze | export | clear')
            end
        end)
        busy=false;if not ok then note(tostring(err)) end
    end)
end)
AddEventHandler('onClientResourceStop',function(r)if r==GetCurrentResourceName() then clear() end end)
