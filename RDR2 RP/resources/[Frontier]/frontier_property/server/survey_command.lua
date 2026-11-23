local sessions = {}
local core = exports.frontier_core

local function tell(source, message)
    TriggerClientEvent('chat:addMessage', source, { args = { 'Frontier Landvermessung', message } })
end

local function surveyPosition(source)
    local ped = GetPlayerPed(source)
    if ped == 0 or GetPlayerRoutingBucket(source) ~= 0 then return nil end
    local position = GetEntityCoords(ped)
    return { x = position.x, y = position.y, z = position.z }
end

RegisterCommand('grundvermessung', function(source, arguments)
    if source <= 0 then return end
    local character = core:GetPlayerCharacterId(source)
    if not character then return tell(source, 'Wähle zuerst einen Charakter.') end
    local action = arguments[1]
    if action == 'status' then
        local status = LatestPropertyLandClaim(character)
        if core:GetPlayerCharacterId(source) ~= character then return end
        local labels = { reserved = 'in Bearbeitung', owned = 'eingetragen', declined = 'abgelehnt' }
        return tell(source, status and ('Letzter Landkauf: %s.'):format(labels[status] or 'unbekannt')
            or 'Kein Kauf gefunden.')
    end
    if sessions[source] and sessions[source].character == character and sessions[source].pending then
        return tell(source, 'Dein Kauf wird gerade bearbeitet.')
    end
    if action == 'start' then
        local zoneKey = arguments[2]
        if not zoneKey or not PropertyConfig.SurveyZones[zoneKey] then
            return tell(source, 'Gib eine freigegebene Vermessungszone an.')
        end
        sessions[source] = { character = character, zoneKey = zoneKey, points = {} }
        return tell(source, 'Vermessung gestartet. Setze Eckpunkte mit /grundvermessung punkt.')
    end

    local survey = sessions[source]
    if not survey or survey.character ~= character then
        sessions[source] = nil
        return tell(source, 'Beginne mit /grundvermessung start ZONE.')
    end
    if action == 'abbrechen' then
        sessions[source] = nil
        return tell(source, 'Vermessung abgebrochen.')
    end
    if action == 'zurück' then
        survey.quote = nil
        table.remove(survey.points)
        return tell(source, ('Eckpunkte: %d'):format(#survey.points))
    end
    if action == 'punkt' then
        if #survey.points >= 64 then return tell(source, 'Höchstens 64 Eckpunkte sind erlaubt.') end
        local position = surveyPosition(source)
        if not position then return tell(source, 'Deine Position ist hier nicht verfügbar.') end
        survey.quote = nil
        survey.points[#survey.points + 1] = position
        return tell(source, ('Eckpunkt %d gesetzt.'):format(#survey.points))
    end
    if action == 'prüfen' then
        local zone = PropertyConfig.SurveyZones[survey.zoneKey]
        local area = ValidatePropertySurvey(survey.points, zone.boundary, zone.exclusions or {})
        if not area then return tell(source, 'Die vermessene Fläche liegt außerhalb der Vorgaben.') end
        local rate = zone.priceCentsPerSquareMeter
        if math.type(rate) ~= 'integer' or rate <= 0 or rate > 100000000 then
            return tell(source, 'Für diese Zone ist kein gültiger Preis eingerichtet.')
        end
        local cost = math.ceil(area * rate)
        survey.quote = cost
        local hint = zone.enablePurchase and ' Bestätige mit /grundvermessung kaufen.' or ''
        return tell(source, ('Vorschau: %.2f m² für $%.2f.'):format(area, cost / 100) .. hint)
    end
    if action == 'kaufen' then
        if not survey.quote then return tell(source, 'Prüfe die Fläche zuerst.') end
        local points, quote = survey.points, survey.quote
        local reserved = { character = character, zoneKey = survey.zoneKey, points = {}, pending = true }
        sessions[source] = reserved
        local ok, claim = pcall(ReservePropertyLand, source, character, survey.zoneKey, points, quote)
        if sessions[source] ~= reserved or core:GetPlayerCharacterId(source) ~= character then return end
        sessions[source] = nil
        if not ok then return tell(source, 'Kaufstatus unklar. Prüfe ihn mit /grundvermessung status.') end
        if not claim then return tell(source, 'Kauf nicht reserviert. Prüfe die Fläche und dein Bankkonto.') end
        return tell(source, 'Kauf vorgemerkt. Prüfe ihn mit /grundvermessung status.')
    end
    tell(source, 'Befehle: start ZONE, punkt, zurück, prüfen, kaufen, status, abbrechen.')
end, false)

AddEventHandler('playerDropped', function() sessions[source] = nil end)
