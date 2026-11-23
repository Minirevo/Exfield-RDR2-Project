local command, messages, character = nil, {}, 'one'
exports = { frontier_core = { GetPlayerCharacterId = function() return character end } }
RegisterCommand = function(name, fn) assert(name == 'grundvermessung'); command = fn end
AddEventHandler = function() end
TriggerClientEvent = function(_, _, body) messages[#messages + 1] = body.args[2] end
GetPlayerPed = function() return 3 end
GetPlayerRoutingBucket = function() return 0 end
GetEntityCoords = function() return { x = 2, y = 3 } end
PropertyConfig = { SurveyZones = { demo = { boundary = {}, priceCentsPerSquareMeter = 50 } } }
ValidatePropertySurvey = function(points)
    assert(points[1].x == 2 and points[1].y == 3)
    return 100
end
dofile((... or '.') .. '/server/survey_command.lua')
command(1, {'start', 'demo'})
command(1, {'punkt'})
command(1, {'prüfen'})
assert(messages[3]:find('$50.00', 1, true))
character = 'two'
command(1, {'prüfen'})
assert(messages[4]:find('Beginne', 1, true))
print('Property survey command passed')
