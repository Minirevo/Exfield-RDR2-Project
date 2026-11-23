local command, character, notices = nil, 'f_test', {}
RegisterCommand = function(name, handler) assert(name == 'grundbesitz'); command = handler end
TriggerClientEvent = function(event, source, body)
    assert(event == 'chat:addMessage' and source == 10)
    notices[#notices + 1] = body.args[2]
end
exports = { frontier_core = { GetPlayerCharacterId = function(_, source)
    assert(source == 10)
    return character
end } }
local rows, switch = {}, false
MySQL = { query = { await = function(sql, args)
    assert(sql:find('o.party_id = ?', 1, true) and args[1] == 'f_test')
    if switch then character = 'f_replacement' end
    return rows
end } }
dofile((... or '.') .. '/server/overview.lua')
command(0)
assert(#notices == 0)
command(10)
assert(notices[1]:find('keinen', 1, true))
rows[1] = { id = 1, label = 'Test', property_type = 'land', share_bps = 5000 }
command(10)
assert(notices[2]:find('50.00', 1, true))
switch = true
command(10)
assert(#notices == 2)
print('Property overview passed')
