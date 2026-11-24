local rooms = {}
local core = exports.frontier_core
local visits = {}

function GetPropertyFurnishingRooms()
    local all={}
    for id, room in pairs(PropertyExistingRooms or {}) do all[id]=room end
    for id, room in pairs(rooms) do if not all[id] then all[id]=room end end
    for id, room in pairs(PropertyConfig.FurnishingRooms) do if not all[id] then all[id]=room end end
    return all
end

local function loadLegacyRooms()
    local entries=MySQL.query.await([[SELECT catalogue_key,property_id FROM frontier_property_catalogue
        WHERE property_id IS NOT NULL]])
    for _, row in ipairs(entries) do
        local home,id=PropertyGovernmentCatalogue[row.catalogue_key],tonumber(row.property_id)
        if home and id and id<1900000000 then
            local r=home.radius
            rooms[id]={capacity=home.capacity,bucket=100000000+id,
                min={x=home.x-r,y=home.y-r,z=home.z-.75},
                max={x=home.x+r,y=home.y+r,z=home.z+2},entry=home}
        end
    end
end

MySQL.ready(function()
    CreateThread(function()
        while not pcall(loadLegacyRooms) do
            print('[frontier_property] Vorhandene Mieträume nicht geladen. Migration 011 prüfen.')
            Wait(30000)
        end
    end)
end)

local function tell(source,text)
    TriggerClientEvent('chat:addMessage',source,{args={'Frontier Wohnräume',text}})
end
local function exit(source)
    local visit=visits[source]
    if not visit then return end
    visits[source]=nil
    if GetPlayerRoutingBucket(source)~=visit.bucket then return end
    SetPlayerRoutingBucket(source,0)
    local ped=GetPlayerPed(source)
    if ped~=0 then SetEntityCoords(ped,visit.returnPoint.x,visit.returnPoint.y,visit.returnPoint.z,false,false,false,false) end
end

RegisterCommand('grundzimmer',function(source,args)
    if source<=0 then return end
    if args[1]=='verlassen' then return exit(source) end
    local id=tonumber(args[1])
    local room=id and rooms[id]
    local actor=core:GetPlayerCharacterId(source)
    local agent=NearbyPropertyAgent(source)
    if not room or not actor or not agent then return tell(source,'Dieses Zimmer ist am Makler nicht verfügbar.') end
    if not exports.frontier_property:CanAccessProperty(actor,id,'enter') then
        return tell(source,'Du hast keinen Zutritt zu diesem Zimmer.')
    end
    if core:GetPlayerCharacterId(source)~=actor or NearbyPropertyAgent(source)~=agent then return end
    local ped=GetPlayerPed(source)
    if ped==0 then return end
    visits[source]={returnPoint=GetEntityCoords(ped),bucket=room.bucket,property=id,actor=actor}
    SetRoutingBucketPopulationEnabled(room.bucket,false)
    SetPlayerRoutingBucket(source,room.bucket)
    local to=room.entry
    SetEntityCoords(ped,to.x,to.y,to.z,false,false,false,false)
    tell(source,'Zum Verlassen: /grundzimmer verlassen.')
end,false)

AddEventHandler('playerDropped',function() visits[source]=nil end)
AddEventHandler('onResourceStop',function(name)
    if name==GetCurrentResourceName() then for source in pairs(visits) do exit(source) end end
end)
CreateThread(function()
    while true do
        Wait(10000)
        for source, visit in pairs(visits) do
            local actor=core:GetPlayerCharacterId(source)
            local ok, allowed=pcall(function()
                return actor==visit.actor and exports.frontier_property:CanAccessProperty(actor,visit.property,'enter')
            end)
            if visits[source]==visit and (not ok or not allowed) then exit(source) end
        end
    end
end)
