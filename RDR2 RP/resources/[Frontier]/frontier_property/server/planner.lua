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

RegisterNetEvent('frontier_property:plannerStart', function(mode)
    local player = source
    if rateLimit(player) or (sessions[player] and sessions[player].busy) then return end
    local actor, origin = core:GetPlayerCharacterId(player), position(player)
    if not actor or not origin then return end
    local zones = {}
    for key, zone in pairs(PropertyConfig.SurveyZones) do
        if zone.enablePurchase == true then zones[#zones + 1] = key end
    end
    table.sort(zones)
    if PropertyConfig.WorldSurvey and PropertyConfig.WorldSurvey.enabled then table.insert(zones,1,'world') end
    sessions[player] = { actor=actor, origin=origin, expires=os.time()+600, walk=mode=='walk', points={} }
    if mode=='walk' then
        TriggerClientEvent('frontier_property:walkSurvey',player,{radius=radius,points={}})
    else
        TriggerClientEvent('frontier_property:plannerOpen',player,{radius=radius,zones=zones})
    end
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
        or core:GetPlayerCharacterId(player)~=session.actor or #(current-session.origin)>(session.walk and radius or 5) then
        return respond(player,{message='Vermessung beendet. Öffne den Plan erneut.'})
    end
    if action~='quote' and action~='buy' then return end
    if type(zone)~='string' or #zone>64 then return end
    local points=action=='quote' and (session.walk and session.points or validate(session,input))
    if action=='quote' and (not points or #points<3 or (session.walk and zone~='world')) then
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

RegisterNetEvent('frontier_property:walkSurveyAction',function(action)
    local player=source
    if rateLimit(player) then return end
    local session,current=sessions[player],position(player)
    if not session or not session.walk or session.busy or not current
        or session.expires<os.time() or core:GetPlayerCharacterId(player)~=session.actor then return end
    if action=='cancel' then
        sessions[player]=nil
        return TriggerClientEvent('frontier_property:walkSurveyEnd',player)
    end
    if #(current-session.origin)>radius then
        return TriggerClientEvent('chat:addMessage',player,{args={'Frontier Landvermessung','Du bist zu weit vom Startpunkt entfernt.'}})
    end
    session.quote=nil
    if action=='restart' then session.points={}
    elseif action=='undo' then table.remove(session.points)
    elseif action=='point' then
        if #session.points>=64 then return end
        session.points[#session.points+1]={x=current.x,y=current.y,z=current.z}
    elseif action~='finish' then return end

    local relative={}
    for _, point in ipairs(session.points) do
        relative[#relative+1]={x=point.x-session.origin.x,y=point.y-session.origin.y}
    end
    local info={radius=radius,points=relative,markers=session.points}
    if #relative>=3 then
        session.busy=true
        local ok,quote=pcall(QuotePropertyLand,'world',session.points)
        if sessions[player]~=session or core:GetPlayerCharacterId(player)~=session.actor then return end
        session.busy=false
        info.valid=ok and quote~=nil
        if info.valid then info.area,info.price=quote.area,quote.price end
    end
    if action=='finish' and #relative>=3 then
        TriggerClientEvent('frontier_property:walkSurveyFinish',player,info)
    else
        TriggerClientEvent('frontier_property:walkSurvey',player,info)
    end
end)
