local core = exports.frontier_core
local visits, busy, requests = {}, {}, {}
PropertyExistingRooms = {}

local function send(player,event,...)
    TriggerClientEvent('frontier_property:'..event,player,...)
end

local function tell(player,message)
    TriggerClientEvent('chat:addMessage',player,{args={'Frontier Wohnräume',message}})
end

local function nearby(player, point, radius)
    local ped=GetPlayerPed(player)
    return ped~=0 and PropertyHouseNear(GetEntityCoords(ped),point,radius) and ped or nil
end

local function allowed(actor,id)
    local result=MySQL.scalar.await([[SELECT CASE WHEN p.status<>'active' THEN 0
        WHEN perm.allow_access=0 THEN 0 WHEN h.public_access=1 OR perm.allow_access=1 THEN 1
        WHEN EXISTS(SELECT 1 FROM frontier_property_ownership o WHERE o.property_id=p.id
            AND o.party_type='character' AND o.party_id=?) THEN 1
        WHEN EXISTS(SELECT 1 FROM frontier_property_rentals r WHERE r.property_id=p.id
            AND r.tenant_id=? AND r.state='active' AND r.ends_at>UTC_TIMESTAMP()) THEN 1 ELSE 0 END
        FROM frontier_property_houses h JOIN frontier_properties p ON p.id=h.property_id
        LEFT JOIN frontier_property_permissions perm ON perm.property_id=p.id
        AND perm.character_id=? AND perm.permission_key='enter' WHERE p.id=?]],{actor,actor,actor,id})
    return result==1 or result==true or result=='1'
end

local function move(ped,point)
    SetEntityCoords(ped,point.x,point.y,point.z,false,false,false,false)
    if point.heading then SetEntityHeading(ped,point.heading) end
end

local function leave(player)
    local visit=visits[player]
    if not visit then return end
    local ped=GetPlayerPed(player)
    if ped==0 then return end
    if GetPlayerRoutingBucket(player)==visit.room.bucket then
        move(ped,visit.outside)
        SetPlayerRoutingBucket(player,0)
    end
    visits[player]=nil
    send(player,'houseLeft')
    MySQL.update('DELETE FROM frontier_property_house_returns WHERE character_id=?',{visit.actor})
end

function GetPropertyHouseVisit(player,id)
    local visit=visits[player]
    if visit and visit.id==id and GetPlayerRoutingBucket(player)==visit.room.bucket
        and core:GetPlayerCharacterId(player)==visit.actor then
        return visit
    end
end

RegisterNetEvent('frontier_property:houseEnter',function(key, requested)
    local player=source
    local house=type(key)=='string' and PropertyHouses[key]
    local actor=core:GetPlayerCharacterId(player)
    local time=GetGameTimer()
    if not house or not actor or visits[player] or busy[player] or (requests[player] or 0)>time
        or GetPlayerRoutingBucket(player)~=0 or not nearby(player,house.door,2.5) then return end
    requests[player]=time+1000
    busy[player]=actor
    local ok, err=pcall(function()
        local candidates=MySQL.query.await([[SELECT h.property_id,p.label FROM frontier_property_houses h
            JOIN frontier_properties p ON p.id=h.property_id WHERE h.house_key=? AND p.status='active'
            ORDER BY h.property_id]],{key})
        local matches={}
        local selected
        for _,row in ipairs(candidates) do
            local id=tonumber(row.property_id)
            if id and id<500000000 and allowed(actor,id) then
                matches[#matches+1]=('#%d %s'):format(id,row.label)
                if not requested or requested==id then selected=id end
            end
        end
        if core:GetPlayerCharacterId(player)~=actor or busy[player]~=actor then return end
        if not selected or (not requested and #matches>1) then
            return tell(player,#matches==0 and 'Kein zugängliches Haus zugewiesen.'
                or 'Mit /grundhaus ID auswählen: '..table.concat(matches,', '))
        end
        local ped=nearby(player,house.door,2.5)
        if not ped or GetPlayerRoutingBucket(player)~=0 then return end
        local pos=GetEntityCoords(ped)
        local outside={x=pos.x,y=pos.y,z=pos.z,heading=GetEntityHeading(ped)}
        MySQL.update.await([[INSERT INTO frontier_property_house_returns (character_id,x,y,z,heading)
            VALUES (?,?,?,?,?) ON DUPLICATE KEY UPDATE x=VALUES(x),y=VALUES(y),z=VALUES(z),heading=VALUES(heading)]],
            {actor,outside.x,outside.y,outside.z,outside.heading})
        if busy[player]~=actor or core:GetPlayerCharacterId(player)~=actor or GetPlayerPed(player)~=ped
            or GetPlayerRoutingBucket(player)~=0 or not nearby(player,house.door,2.5) then
            if busy[player]==actor then
                MySQL.update.await('DELETE FROM frontier_property_house_returns WHERE character_id=?',{actor})
            end
            return
        end
        local room={min=house.min,max=house.max,capacity=house.capacity,bucket=1500000000+selected}
        PropertyExistingRooms[selected]=room
        visits[player]={id=selected,room=room,actor=actor,outside=outside,key=key,loadingUntil=GetGameTimer()+12000}
        SetRoutingBucketPopulationEnabled(room.bucket,false)
        SetRoutingBucketEntityLockdownMode(room.bucket,'strict')
        SetPlayerRoutingBucket(player,room.bucket)
        move(ped,house.entry)
        send(player,'houseEntered',selected,key)
    end)
    if busy[player]==actor then busy[player]=nil end
    if not ok then
        print(('[frontier_property] Hauszugang fehlgeschlagen: %s'):format(err))
        leave(player)
    end
end)

RegisterNetEvent('frontier_property:houseExit',function()
    leave(source)
end)

RegisterCommand('grundhauszugang',function(player,args)
    if player<=0 then return end
    local actor=core:GetPlayerCharacterId(player)
    local id=tonumber(args[1])
    local mode=args[2]
    if not actor or math.type(id)~='integer' or id<1 or (mode~='privat' and mode~='öffentlich') then
        return tell(player,'Verwendung: /grundhauszugang ID privat oder öffentlich')
    end
    local count=MySQL.update.await([[UPDATE frontier_property_houses h
        JOIN frontier_properties p ON p.id=h.property_id AND p.status='active'
        JOIN frontier_property_ownership o ON o.property_id=p.id AND o.party_type='character' AND o.party_id=?
        SET h.public_access=? WHERE h.property_id=?]],{actor,mode=='öffentlich' and 1 or 0,id})
    if core:GetPlayerCharacterId(player)==actor then
        tell(player,count>0 and ('Hauszugang: '..mode) or 'Kein zugewiesenes Haus oder keine Änderung.')
    end
end,false)

RegisterNetEvent('frontier_property:houseRecover',function()
    local player=source
    local actor=core:GetPlayerCharacterId(player)
    if not actor or busy[player] or visits[player] then return end
    local ped=GetPlayerPed(player)
    if ped==0 then return end
    local bucket=GetPlayerRoutingBucket(player)
    if bucket==0 then
        local pos=GetEntityCoords(ped)
        local inside=false
        for _,house in pairs(PropertyHouses) do if PropertyHouseWithin(pos,house,0) then inside=true; break end end
        if not inside then return end
    elseif bucket<1500000000 or bucket>=2000000000 then return end
    busy[player]=actor
    local ok, err=pcall(function()
        local point=MySQL.single.await('SELECT x,y,z,heading FROM frontier_property_house_returns WHERE character_id=?',{actor})
        local ped=GetPlayerPed(player)
        if not point or busy[player]~=actor or core:GetPlayerCharacterId(player)~=actor or ped==0 then return end
        local bucket=GetPlayerRoutingBucket(player)
        if bucket>=1500000000 and bucket<2000000000 then
            move(ped,point)
            SetPlayerRoutingBucket(player,0)
            MySQL.update.await('DELETE FROM frontier_property_house_returns WHERE character_id=?',{actor})
        elseif bucket==0 then
            local pos=GetEntityCoords(ped)
            for _,house in pairs(PropertyHouses) do
                if PropertyHouseWithin(pos,house,0) then
                    move(ped,point)
                    MySQL.update.await('DELETE FROM frontier_property_house_returns WHERE character_id=?',{actor})
                    break
                end
            end
        end
    end)
    if busy[player]==actor then busy[player]=nil end
    if not ok then print(('[frontier_property] Hausrückkehr fehlgeschlagen: %s'):format(err)) end
end)

AddEventHandler('playerDropped',function()
    visits[source],busy[source],requests[source]=nil,nil,nil
end)
AddEventHandler('onResourceStop',function(name)
    if name==GetCurrentResourceName() then for player in pairs(visits) do leave(player) end end
end)
CreateThread(function()
    while true do
        Wait(3000)
        for player,visit in pairs(visits) do
            local ok, access=pcall(allowed,visit.actor,visit.id)
            local ped=GetPlayerPed(player)
            if visits[player]==visit and (not ok or not access or core:GetPlayerCharacterId(player)~=visit.actor
                or (GetGameTimer()>visit.loadingUntil and ped~=0
                    and not PropertyHouseWithin(GetEntityCoords(ped),visit.room,-0.25))) then leave(player) end
        end
    end
end)
