local core = exports.frontier_core
local sessions = {}
local limits = {}
local radius = 75

local function position(player)
    local ped = GetPlayerPed(player)
    if ped == 0 or GetPlayerRoutingBucket(player) ~= 0 then return nil end
    return GetEntityCoords(ped)
end

local function rateLimit(player)
    local now = GetGameTimer()
    if (limits[player] or 0) > now then return true end
    limits[player] = now + 750
    return false
end

RegisterNetEvent('frontier_property:plannerStart', function()
    local player = source
    if rateLimit(player) then return end
    local actor, origin = core:GetPlayerCharacterId(player), position(player)
    if not actor or not origin then return end
    local zones = {}
    for key, zone in pairs(PropertyConfig.SurveyZones) do
        if zone.enablePurchase == true then zones[#zones + 1] = key end
    end
    table.sort(zones)
    sessions[player] = { actor=actor, origin=origin, expires=os.time()+600 }
    TriggerClientEvent('frontier_property:plannerOpen',player,{radius=radius,zones=zones})
end)

local function respond(player, result)
    TriggerClientEvent('frontier_property:plannerResult',player,result)
end

local function validate(session, input)
    if type(input)~='table' or #input<3 or #input>64 then return nil end
    local points = {}
    for i=1,#input do
        local point=input[i]
        if type(point)~='table' or type(point.x)~='number' or type(point.y)~='number'
            or not (math.abs(point.x)<=radius and math.abs(point.y)<=radius) then return nil end
        points[i]={x=session.origin.x+point.x,y=session.origin.y+point.y,z=session.origin.z}
    end
    return points
end

RegisterNetEvent('frontier_property:plannerAction',function(action,zone,input)
    local player=source
    if rateLimit(player) then return respond(player,{message='Bitte kurz warten und erneut prüfen.'}) end
    local session,current=sessions[player],position(player)
    if not session or session.busy or session.expires<os.time() or not current
        or core:GetPlayerCharacterId(player)~=session.actor or #(current-session.origin)>5 then
        return respond(player,{message='Vermessung beendet. Öffne den Plan erneut.'})
    end
    if action~='quote' and action~='buy' then return end
    if type(zone)~='string' or #zone>64 then return end
    local points=action=='quote' and validate(session,input)
    if action=='quote' and not points then
        session.quote=nil
        return respond(player,{message='Setze 3 bis 64 gültige Eckpunkte.'})
    end
    if action=='buy' and (not session.quote or session.quote.zone~=zone) then
        return respond(player,{message='Bestätige zuerst eine gültige Preisvorschau.'})
    end
    session.busy=true
    if action=='quote' then
        session.quote=nil
        local ok, quote=pcall(QuotePropertyLand,zone,points)
        if sessions[player]~=session or core:GetPlayerCharacterId(player)~=session.actor then return end
        session.busy=false
        if not ok or not quote then return respond(player,{message='Fläche nicht verfügbar oder außerhalb der Kaufzone.'}) end
        session.quote={zone=zone,points=points,price=quote.price}
        return respond(player,{area=quote.area,price=quote.price})
    end
    local quote=session.quote
    session.quote=nil
    local ok,id=pcall(ReservePropertyLand,player,session.actor,zone,quote.points,quote.price)
    if sessions[player]~=session or core:GetPlayerCharacterId(player)~=session.actor then return end
    session.busy=false
    if not ok then return respond(player,{message='Kaufstatus unklar. Nutze /grundvermessung status.'}) end
    respond(player,{message=id and 'Kauf vorgemerkt. Status: /grundvermessung status.'
        or 'Fläche oder Preis hat sich geändert. Bitte erneut prüfen.'})
end)

RegisterNetEvent('frontier_property:plannerClose',function()
    local player=source
    if sessions[player] and not sessions[player].busy then sessions[player]=nil end
end)
AddEventHandler('playerDropped',function() sessions[source],limits[source]=nil,nil end)
