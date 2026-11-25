
local E='frontier_farm_modeltest:'
local parts,anchor,selected={},nil,nil
local visible,busy=false,false
local title='livestock_pen'
local function finite(n,limit) return type(n)=='number' and n==n and math.abs(n)<=limit end
local function destroy(p)
    if p and p.entity and DoesEntityExist(p.entity) then DeleteEntity(p.entity) end
end
local function clear()
    for _,p in ipairs(parts) do destroy(p) end
    parts={};selected=nil
end
local function plain(p)
    return {model=p.model,x=p.x,y=p.y,z=p.z,heading=p.heading,terrain=p.terrain,role=p.role}
end
local function snapshot()
    local list={}
    for i,p in ipairs(parts) do list[i]=plain(p) end
    return {version=1,name=title,parts=list,selected=selected,anchor=anchor}
end
local function emit(msg)
    SendNUIMessage({type='buildState',state=snapshot(),message=msg})
end
local function ground(x,y,z)
    RequestCollisionAtCoord(x,y,z)
    local ok,g=GetGroundZFor_3dCoord(x,y,z+8.0,false)
    if not ok or math.abs(g-z)>6 then return nil end
    return g
end
local function getAnchor()
    local ped=PlayerPedId()
    local pos=GetOffsetFromEntityInWorldCoords(ped,0.0,5.0,0.0)
    local g=ground(pos.x,pos.y,pos.z)
    if not g then error('Ground unavailable. Try an open area.') end
    return {x=pos.x,y=pos.y,z=g,heading=GetEntityHeading(ped)}
end
local function world(p)
    local a=math.rad(anchor.heading)
    return anchor.x+p.x*math.cos(a)-p.y*math.sin(a),anchor.y+p.x*math.sin(a)+p.y*math.cos(a),(anchor.heading+p.heading)%360
end
local function transform(p)
    local x,y,h=world(p)
    local min,max=GetModelDimensions(GetEntityModel(p.entity))
    local z=anchor.z
    local pitch,roll=0,0
    if p.terrain~='fixed' then
        z=ground(x,y,anchor.z)
        if not z then error('Ground unavailable for '..p.model) end
        if p.terrain=='slope' then
            local a=math.rad(h)
            local half=(max.x-min.x)/2
            if half<0.1 then error('Slope mode needs a long X-axis prop') end
            local g1=ground(x-half*math.cos(a),y-half*math.sin(a),z)
            local g2=ground(x+half*math.cos(a),y+half*math.sin(a),z)
            if not g1 or not g2 then error('Fence endpoint ground unavailable') end
            roll=-math.deg(math.atan(g2-g1,2*half))
            if math.abs(roll)>20 then error('Slope exceeds preview limit of 20 degrees') end
            z=(g1+g2)/2
        end
    end
    SetEntityCoordsNoOffset(p.entity,x,y,z-min.z+p.z,false,false,false)
    SetEntityRotation(p.entity,pitch,roll,h,2,true)
    FreezeEntityPosition(p.entity,true)
end
local roles={fence=true,corner=true,gate=true,feed=true,water=true,shelter=true,decoration=true}
local modes={fixed=true,ground=true,slope=true}
local function validate(d)
    if type(d)~='table' or type(d.model)~='string' or #d.model>100 or not d.model:match('^[%w_]+$') then error('Invalid model') end
    if not finite(d.x,60) or not finite(d.y,60) or not finite(d.z,10) or not finite(d.heading,3600) then error('Invalid coordinates') end
    if not modes[d.terrain] or not roles[d.role] then error('Invalid terrain mode or role') end
    return {model=d.model,x=d.x,y=d.y,z=d.z,heading=d.heading%360,terrain=d.terrain,role=d.role}
end
local function spawn(d)
    local p=validate(d)
    local hash=GetHashKey(p.model)
    if not IsModelValid(hash) or IsModelAPed(hash) then error('Invalid prop: '..p.model) end
    RequestModel(hash)
    local deadline=GetGameTimer()+5000
    while not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(20) end
    if not HasModelLoaded(hash) then SetModelAsNoLongerNeeded(hash);error('Model timeout: '..p.model) end
    local x,y=world(p)
    p.entity=CreateObject(hash,x,y,anchor.z,false,false,false,false,false)
    SetModelAsNoLongerNeeded(hash)
    if not p.entity or p.entity==0 or not DoesEntityExist(p.entity) then error('Spawn failed: '..p.model) end
    SetEntityAsMissionEntity(p.entity,true,true)
    SetEntityInvincible(p.entity,true)
    local ok,err=pcall(transform,p)
    if not ok then destroy(p);error(err) end
    return p
end
local function add(d)
    if #parts>=160 then error('160 part limit') end
    parts[#parts+1]=spawn(d);selected=#parts
end
local function current()
    if not selected or not parts[selected] then error('Select a prop first') end
    return parts[selected]
end
local function rebuild(list,newAnchor)
    local old,oldAnchor,oldSelected=parts,anchor,selected
    parts={};anchor=newAnchor
    local ok,err=pcall(function() for _,p in ipairs(list) do add(p) end end)
    if not ok then clear();parts=old;anchor=oldAnchor;selected=oldSelected;error(err) end
    for _,p in ipairs(old) do destroy(p) end
end
RegisterNetEvent(E..'build',function()
    if source~=65535 or busy then return end
    TriggerEvent(E..'editorOpen')
    local ok,err=pcall(function() if not anchor then anchor=getAnchor() end end)
    if not ok then TriggerEvent('chat:addMessage',{args={'Farm builder',tostring(err)}});return end
    visible=true;SetNuiFocus(true,true);SendNUIMessage({type='buildOpen'});emit()
end)
AddEventHandler(E..'editorHide',function()
    visible=false;SendNUIMessage({type='buildHide'})
end)
RegisterNUICallback('farmBuildAction',function(d,cb)
    if not visible or busy then cb({ok=false,message='Editor closed or busy'});return end
    busy=true
    CreateThread(function()
        local ok,err=pcall(function()
            local action=d.action
            if action=='hide' then visible=false;SetNuiFocus(false,false);SendNUIMessage({type='buildHide'})
            elseif action=='new' then
                local a=getAnchor();clear();anchor=a;title='livestock_pen'
            elseif action=='clear' then clear()
            elseif action=='select' then
                if not finite(d.index,160) or not parts[d.index] then error('Invalid selection') end
                selected=d.index
            elseif action=='add' then add(d.part)
            elseif action=='duplicate' then
                local p=plain(current());p.x=p.x+0.5;add(p)
            elseif action=='delete' then
                destroy(current());table.remove(parts,selected);selected=#parts>0 and math.min(selected,#parts) or nil
            elseif action=='update' then
                local old=current();local p=validate(d.part)
                if p.model~=old.model then error('Model cannot change; add another prop') end
                p.entity=old.entity
                local success,why=pcall(transform,p)
                if not success then pcall(transform,old);error(why) end
                parts[selected]=p
            elseif action=='relocate' then
                rebuild(snapshot().parts,getAnchor())
            elseif action=='name' then
                if type(d.name)~='string' or #d.name>64 or not d.name:match('^[%w_%-]+$') then error('Use letters, digits, underscores or hyphens') end
                title=d.name
            elseif action=='import' then
                if type(d.data)~='string' or #d.data>100000 then error('Invalid import') end
                local v=json.decode(d.data)
                if type(v)~='table' or v.version~=1 or type(v.parts)~='table' or #v.parts>160 or type(v.name)~='string' or #v.name>64 or not v.name:match('^[%w_%-]+$') then error('Invalid assembly JSON') end
                local list={}
                for i,p in ipairs(v.parts) do list[i]=validate(p) end
                rebuild(list,anchor);title=v.name
            else error('Unknown action') end
        end)
        busy=false
        emit(ok and 'Ready' or tostring(err));cb({ok=ok,message=ok and 'Ready' or tostring(err)})
    end)
end)
-- Mark the selected prop in the world, including while inspecting.
CreateThread(function()
    while true do
        local p=selected and parts[selected]
        if visible and p and p.entity and DoesEntityExist(p.entity) then
            Wait(0)
            local c=GetEntityCoords(p.entity)
            -- RedM marker native; visual selection is optional if native unavailable.
            pcall(function() Citizen.InvokeNative(0x2A32FAA57B937173,GetHashKey('vfx_ring'),c.x,c.y,c.z+0.1,0.0,0.0,0.0,0.0,0.0,0.0,0.5,0.5,0.5,255,210,80,150,false,false,2,false,nil,nil,false) end)
        else Wait(250) end
    end
end)
AddEventHandler('onClientResourceStop',function(r) if r==GetCurrentResourceName() then clear();if visible then SetNuiFocus(false,false) end end end)
