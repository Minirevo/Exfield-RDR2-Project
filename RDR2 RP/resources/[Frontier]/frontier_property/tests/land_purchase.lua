local coreId = 'f_' .. string.rep('a', 32)
local polygon = { {x=10,y=10,z=20}, {x=20,y=10,z=20}, {x=20,y=20,z=20}, {x=10,y=20,z=20} }
local accounts, reservations = 0, 0
local block, reply = {}, { { { id=4 } } }
exports = {
    frontier_core = { GetPlayerCharacterId = function() return coreId end },
    frontier_economy = { GetCharacterAccounts = function(_, source)
        assert(source == 2)
        accounts = accounts + 1
        return true, { characterId=coreId, bank={id=9} }
    end },
}
json = {
    encode = function(points) assert(points == polygon); return 'fixture' end,
    decode = function(value) assert(value == 'fixture'); return polygon end,
}
MySQL = {
    ready = function() end,
    scalar = { await = function() return 0 end },
    query = { await = function(sql, args)
        if not sql:find('CALL', 1, true) then return block end
        assert(args[1] == 0 and args[2] == coreId and args[3] == 'test'
            and args[4] == 'fixture' and args[5] == 100 and args[6] == 5000 and args[7] == 9)
        reservations = reservations + 1
        return reply
    end },
}
local path = ... or '.'
dofile(path .. '/config.lua')
PropertyConfig.SurveyZones.test = {
    enablePurchase=true, priceCentsPerSquareMeter=50,
    boundary={{x=0,y=0},{x=40,y=0},{x=40,y=40},{x=0,y=40}},
}
local fxExports = exports
exports = function() end
dofile(path .. '/server/survey.lua')
exports = fxExports
dofile(path .. '/server/land.lua')
assert(ReservePropertyLand(2, coreId, 'test', polygon, 4999) == nil)
assert(reservations == 0 and accounts == 0)
assert(ReservePropertyLand(2, coreId, 'test', polygon, 5000) == 4)
block = { { polygon_json='fixture' } }
assert(ReservePropertyLand(2, coreId, 'test', polygon, 5000) == nil)
assert(reservations == 1 and accounts == 1)
print('Property land purchase validation passed')
