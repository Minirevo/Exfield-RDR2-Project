local C,R=PropertyConfig,PropertyRules
local E='frontier_property:'
local objects,markers={},{}
local world={claims={},objects={},markers={}}
local interior,preview,inside,focused=nil,nil,nil,false
local pendingMenu,menuSequence=nil,0
local function notice(msg) TriggerEvent('chat:addMessage',{args={'Frontier Property',msg}}) end
local function close()
    pendingMenu=nil
    if focused then SetNuiFocus(false,false); focused=false end
    SendNUIMessage({type='close'})
end
local function action(a,d) TriggerServerEvent(E..'action',a,d or {}) end
local function atShop(pos,s)
    return (pos.x-s.x)^2+(pos.y-s.y)^2<=C.ShopDistance^2 and math.abs(pos.z-s.z)<=C.ShopHeightTolerance
end
local function remove(o) if o and DoesEntityExist(o) then DeleteEntity(o) end end
local function model(name)
    local h=GetHashKey(name)
    if not IsModelValid(h) then return end
    RequestModel(h)
    local deadline=GetGameTimer()+3500
    while not HasModelLoaded(h) and GetGameTimer()<deadline do Wait(10) end
    if HasModelLoaded(h) then return h end
end
-- Terrain is streamed client-side. Never freeze a camp prop at an unverified height.
local function groundAt(x,y,z)
    RequestCollisionAtCoord(x+0.0,y+0.0,z+0.0)
    local ok,height=GetGroundZFor_3dCoord(x+0.0,y+0.0,z+5.0,false)
    if ok and R.finite(height) and math.abs(height-z)<=C.GroundSearchTolerance then return height end
end
local collisionWarnings={}
local function collisionReady(h,d)
    RequestCollisionAtCoord(d.x+0.0,d.y+0.0,d.z+0.0)
    RequestCollisionForModel(h)
    local deadline=GetGameTimer()+1500
    while not HasCollisionForModelLoaded(h) and GetGameTimer()<deadline do Wait(25) end
    return HasCollisionForModelLoaded(h)
end
local function spawn(d,ghost)
    local h=model(d.model); if not h then return end
    local z=d.z;local roll=0
    if d.terrain then
        local min,max=GetModelDimensions(h)
        local g=d.terrain=='fixed' and (d.anchorZ or d.z) or groundAt(d.x,d.y,d.anchorZ or d.z)
        if not g then SetModelAsNoLongerNeeded(h);return nil,'terrain' end
        if d.terrain=='slope' then
            local a=math.rad(d.heading);local half=(max.x-min.x)/2
            local g1=groundAt(d.x-half*math.cos(a),d.y-half*math.sin(a),g)
            local g2=groundAt(d.x+half*math.cos(a),d.y+half*math.sin(a),g)
            if not g1 or not g2 then SetModelAsNoLongerNeeded(h);return nil,'terrain' end
            roll=-math.deg(math.atan(g2-g1,2*half));g=(g1+g2)/2
            if math.abs(roll)>20 then SetModelAsNoLongerNeeded(h);return nil,'terrain' end
        end
        z=g-min.z+(d.offsetZ or 0)
    elseif d.ground then
        local ground=groundAt(d.x,d.y,d.z)
        if not ground then SetModelAsNoLongerNeeded(h); return nil,'terrain' end
        local min=GetModelDimensions(h)
        z=ground-(min and min.z or 0)+(C.GroundModelOffsets[d.model] or 0)
    end
    local loaded=ghost or collisionReady(h,d)
    local o=CreateObject(h,d.x+0.0,d.y+0.0,z+0.0,false,false,false,false,false)
    SetModelAsNoLongerNeeded(h)
    if o==0 then return end
    SetEntityAsMissionEntity(o,true,true)
    -- CreateObject can apply a model-dependent Z offset. Override it before freezing,
    -- for BOTH previews and completed models; saved coordinates are entity origins.
    SetEntityCoordsNoOffset(o,d.x+0.0,d.y+0.0,z+0.0,false,false,false)
    SetEntityRotation(o,0.0,roll,(d.heading or 0)+0.0,2,false); FreezeEntityPosition(o,true)
    if ghost then
        SetEntityAlpha(o,130,false)
        SetEntityCollision(o,false,false)
    else
        SetEntityCollision(o,true,true)
        if not loaded and not collisionWarnings[d.model] then
            collisionWarnings[d.model]=true
            print(('[frontier_property] Model collision not ready: %s (%s)'):format(d.model,h))
        end
    end
    return o
end
local function clear()
    for _,o in pairs(objects) do remove(o.handle) end; objects={}
end
local function cancel(send)
    if preview then for _,h in ipairs(preview.handles or {preview.handle}) do remove(h) end; preview=nil; if send then action('cancelPreview') end end
end
RegisterNetEvent(E..'notice',function(msg) if source==65535 then notice(msg); SendNUIMessage({type='notice',message=msg}) end end)
RegisterNetEvent(E..'close',function() if source==65535 then close() end end)
RegisterNetEvent(E..'refresh',function() if source==65535 and focused then SendNUIMessage({type='refresh'}) end end)
RegisterNetEvent(E..'menu',function(data)
    if source~=65535 then return end
    menuSequence=menuSequence+1
    local token=menuSequence
    pendingMenu=token
    SendNUIMessage({type='menu',data=data,token=token})
    SetTimeout(3000,function()
        if pendingMenu==token then
            close()
            notice('Property interface did not acknowledge loading. Try again or check the F8 console.')
        end
    end)
end)
RegisterNetEvent(E..'world',function(data) if source==65535 then world=data end end)
RegisterNetEvent(E..'interior',function(data)
    if source~=65535 then return end
    close(); clear(); cancel(false); world={claims={},objects={},markers={}}; interior=data or nil
    if interior then
        local a=interior.anchor
        RequestCollisionAtCoord(a.x,a.y,a.z)
        CreateThread(function()
            local current=interior; local deadline=GetGameTimer()+10000
            while interior==current and GetGameTimer()<deadline do
                local ped=PlayerPedId()
                if HasCollisionLoadedAroundEntity(ped) and GetInteriorFromEntity(ped)==a.id then return end
                Wait(250)
            end
            if interior==current then notice('Interior did not load safely; returning outside.'); action('exit') end
        end)
    end
end)
RegisterNetEvent(E..'preview',function(d)
    if source~=65535 then return end
    close(); cancel(false)
    local ped=PlayerPedId(); local pos=GetOffsetFromEntityInWorldCoords(ped,0.0,3.0,0.0)
    local o=d.origin or {x=pos.x,y=pos.y,z=pos.z,heading=GetEntityHeading(ped)}
    local parts=d.parts or {{model=d.model,x=0,y=0,z=0,heading=0}}
    local handles={}
    for n,part in ipairs(parts) do
        local q=R.transform(o,part)
        q.ground=n==1 and not d.origin
        local handle=spawn(q,true)
        if not handle then for _,h in ipairs(handles) do remove(h) end;notice('Model unavailable: '..part.model);action('cancelPreview');return end
        handles[n]=handle
        if n==1 and q.ground and not q.terrain then local actual=GetEntityCoords(handle);o.z=actual.z-(part.z or 0) end
    end
    preview={handle=handles[1],handles=handles,parts=parts,x=o.x,y=o.y,z=o.z,heading=o.heading or 0,mode=d.mode,claim=d.claim,blockers=d.blockers,radius=d.radius,furniture=d.furniture}
    notice('Placement: arrows move, PageUp/Down height, Q/R rotate, Enter confirm, Esc cancel.')
end)
RegisterNUICallback('menuReady',function(d,cb)
    if type(d)=='table' and pendingMenu and d.token==pendingMenu then
        pendingMenu=nil
        SetNuiFocus(true,true); focused=true
        cb({ok=true})
    else cb({ok=false}) end
end)
RegisterNUICallback('menuError',function(d,cb)
    if type(d)=='table' and d.token==pendingMenu then
        close()
        notice('Property UI error: '..tostring(d.message or 'unknown'):sub(1,200))
    end
    cb({ok=true})
end)
RegisterCommand('propertyclose',function() close(); SetNuiFocus(false,false) end,false)
RegisterNUICallback('close',function(_,cb) close(); cb({ok=true}) end)
RegisterNUICallback('action',function(d,cb)
    if focused and type(d)=='table' and type(d.action)=='string' then
        if d.action=='exit' or d.action=='chest' then close() end
        action(d.action,d.data); cb({ok=true})
    else cb({ok=false}) end
end)
RegisterCommand('propertyfurniture',function() action('furnitureMenu') end,false)
RegisterCommand('propertymarket',function() action('market') end,false)
RegisterCommand('propertyshop',function() action('shop') end,false)
RegisterCommand('propertyexit',function() action('exit') end,false)
RegisterCommand('propertystop',function() action('stopWork') end,false)
local function nearest()
    local p=GetEntityCoords(PlayerPedId()); local best,dist
    for _,o in pairs(objects) do
        local d=o.data; local n= #(p-(o.actual or vector3(d.x,d.y,d.z)))
        if d.action and n<=(d.interaction or C.InteractionDistance) and (not dist or n<dist) then best,dist=d,n end
    end
    return best
end
local function interact()
    if focused or preview then return end
    if interior then action('interior'); return end
    local d=nearest()
    if d then
        if d.action=='farmManage' then TriggerEvent('frontier_farming:manageSign',d.bid) elseif d.action=='production' then TriggerEvent('frontier_production:stationOpen',d.sid,d.bid) elseif d.action=='wagonBench' then TriggerEvent('frontier_logistics:bench',d.sid,d.bid) else action(d.action,{sid=d.sid,bid=d.bid}) end
        return
    end
    local p=GetEntityCoords(PlayerPedId())
    for _,s in ipairs(C.Shops) do if atShop(p,s) then action('shop'); return end end
end
RegisterCommand('propertymenu',interact,false)
local function hint(msg)
    local str=CreateVarString(10,'LITERAL_STRING',msg)
    SetTextScale(0.32,0.32); SetTextColor(255,255,255,255); SetTextCentre(true)
    DisplayText(str,0.5,0.88)
end
local retry={}
CreateThread(function()
    while true do
        Wait(500)
        local wanted={}
        for _,d in pairs(world.objects or {}) do wanted[d.key]=d end
        for key,o in pairs(objects) do
            local d=wanted[key]
            if d and DoesEntityExist(o.handle) then
                local pos=GetEntityCoords(PlayerPedId())
                if #(pos-GetEntityCoords(o.handle))<60 then
                    RequestCollisionAtCoord(d.x+0.0,d.y+0.0,d.z+0.0)
                    local hash=GetHashKey(d.model)
                    if not HasCollisionForModelLoaded(hash) then RequestCollisionForModel(hash) end
                    SetEntityCollision(o.handle,true,true)
                end
            end
            if d then o.data.action=d.action;o.data.interaction=d.interaction end
            if not d or not DoesEntityExist(o.handle) or d.model~=o.data.model or d.x~=o.data.x or d.y~=o.data.y or d.z~=o.data.z or d.heading~=o.data.heading then remove(o.handle); objects[key]=nil end
        end
        for key,d in pairs(wanted) do
            if not objects[key] and (not retry[key] or GetGameTimer()>retry[key]) then
                local h,reason=spawn(d,false)
                if h then
                    local actual=GetEntityCoords(h)
                    objects[key]={handle=h,data=d,actual=actual}
                    retry[key]=nil
                else retry[key]=GetGameTimer()+(reason=='terrain' and 1000 or 30000) end
            end
        end
        local p=GetEntityCoords(PlayerPedId()); local claim
        if not interior then for _,s in pairs(world.claims or {}) do if (p.x-s.x)^2+(p.y-s.y)^2<=s.radius^2 then claim=s; break end end end
        if (claim and claim.id or nil)~=inside then
            if claim then notice('Entering private property: '..claim.name) elseif inside then notice('Leaving private property.') end
            inside=claim and claim.id or nil
        end
        local mk={}
        for _,s in pairs(world.markers or {}) do
            mk[s.id]=true
            if not markers[s.id] then
                local blip=Citizen.InvokeNative(0x554D9D53F696D002,1664425300,s.x,s.y,s.z)
                SetBlipSprite(blip,GetHashKey('blip_ambient_home'),true)
                Citizen.InvokeNative(0x9CB1A1623062F402,blip,s.name); markers[s.id]=blip
            else Citizen.InvokeNative(0x9CB1A1623062F402,markers[s.id],s.name) end
        end
        for id,b in pairs(markers) do if not mk[id] then RemoveBlip(b); markers[id]=nil end end
    end
end)
local keys={interact=0xCEFD9220,left=0xA65EBAB4,right=0xDEB34313,up=0x6319DB71,down=0x05CA7C52,
    raise=0x446258B6,lower=0x3C3DD371,rotateL=0xDE794E3E,rotateR=0xE30CD707,confirm=0xC7B5340A,cancel=0x156F7119}
local function adjust(k)
    local p=preview; if not p then return end
    local h=math.rad(GetEntityHeading(PlayerPedId()))
    local step=0.12
    if k=='up' then p.x=p.x-math.sin(h)*step;p.y=p.y+math.cos(h)*step
    elseif k=='down' then p.x=p.x+math.sin(h)*step;p.y=p.y-math.cos(h)*step
    elseif k=='left' then p.x=p.x-math.cos(h)*step;p.y=p.y-math.sin(h)*step
    elseif k=='right' then p.x=p.x+math.cos(h)*step;p.y=p.y+math.sin(h)*step
    elseif k=='raise' then p.z=p.z+0.05 elseif k=='lower' then p.z=p.z-0.05
    elseif k=='rotateL' then p.heading=(p.heading-1.5)%360 elseif k=='rotateR' then p.heading=(p.heading+1.5)%360 end
    for n,h in ipairs(p.handles) do local q=R.transform(p,p.parts[n]);SetEntityCoordsNoOffset(h,q.x,q.y,q.z,false,false,false);SetEntityRotation(h,0.0,0.0,q.heading+0.0,2,false) end
end
for _,k in ipairs({'up','down','left','right','raise','lower','rotateL','rotateR'}) do
    RegisterCommand('property_'..k,function() adjust(k) end,false)
end
local function validPreview(p)
    local pos=GetEntityCoords(PlayerPedId())
    if not R.near(pos,p,C.PlacementDistance) or math.abs(pos.z-p.z)>C.MaxHeightOffset then return false end
    if p.furniture then return p.claim and R.distance(p.claim,p)<=p.claim.radius and R.distance(p.claim,pos)<=p.claim.radius end
    if p.claim and p.radius then
        local s=p.claim; s.buildings=p.blockers or {}
        return R.fits(s,p,p.radius)
    end
    return false
end
local function confirm()
    local p=preview;if not p then return end
    if not validPreview(p) then notice('Invalid placement.'); return end
    local d={x=p.x,y=p.y,z=p.z,heading=p.heading}
    cancel(false);action('place',d)
end
RegisterCommand('property_confirm',confirm,false)
RegisterCommand('property_cancel',function() cancel(true) end,false)
CreateThread(function()
    while true do
        Wait(0)
        if preview then
            for _,k in ipairs({'up','down','left','right','raise','lower','rotateL','rotateR'}) do
                DisableControlAction(0,keys[k],true)
                if IsDisabledControlPressed(0,keys[k]) then adjust(k) end
            end
            DisableControlAction(0,keys.confirm,true); DisableControlAction(0,keys.cancel,true)
            if IsDisabledControlJustPressed(0,keys.confirm) then confirm()
            elseif IsDisabledControlJustPressed(0,keys.cancel) then cancel(true) end
            if preview then hint((validPreview(preview) and 'VALID' or 'INVALID')..' | Arrows move | Enter confirm | Esc cancel') end
        elseif not focused and not IsNuiFocused() then
            local d=nearest(); local shop=false;local p=GetEntityCoords(PlayerPedId())
            if not d and not interior then for _,s in ipairs(C.Shops) do if atShop(p,s) then shop=true;break end end end
            if d or interior or shop then
                hint(interior and '[E] Interior / exit' or '[E] '..(d and (d.action=='farmManage' and 'Manage farm facility' or d.action=='production' and 'Manage production station' or d.action) or 'General store'))
                if IsControlJustPressed(0,keys.interact) then interact() end
            end
        end
    end
end)
AddEventHandler('onClientResourceStop',function(r)
    if r==GetCurrentResourceName() then close();cancel(false);clear();for _,b in pairs(markers) do RemoveBlip(b) end end
end)
