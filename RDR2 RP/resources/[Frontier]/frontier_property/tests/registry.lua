local actor = 'f_' .. string.rep('a', 32)
local exported = {}
exports = function(name, fn) exported[name] = fn end
local decision, calls = nil, 0
MySQL = {
    single = { await = function(sql, args)
        assert(sql:find("status = 'active'", 1, true) and args[1] == 9)
        calls = calls + 1
        return { id = 9 }
    end },
    scalar = { await = function(sql, args)
        assert(sql:find('frontier_character_identities', 1, true))
        assert(args[1] == actor and args[2] == 'enter' and args[5] == 9)
        calls = calls + 1
        return decision
    end },
    query = { await = function(sql, args)
        assert(sql:find('SELECT DISTINCT', 1, true) and args[1] == 9)
        calls = calls + 1
        return { { facility_key = 'forge' } }
    end },
}
local registryPath = ... or 'server/registry.lua'
dofile(registryPath)
assert(exported.GetProperty('9') == nil and #exported.GetPropertyFacilities(0) == 0)
assert(not exported.CanAccessProperty(actor, 9, 'unknown'))
assert(not exported.CanAccessProperty('bad', 9, 'enter') and calls == 0)
assert(exported.GetProperty(9).id == 9 and exported.GetPropertyFacilities(9)[1] == 'forge')
assert(not exported.CanAccessProperty(actor, 9, 'enter'))
decision = 0
assert(not exported.CanAccessProperty(actor, 9, 'enter'))
decision = 1
assert(exported.CanAccessProperty(actor, 9, 'enter') and calls == 5)
print('Property registry Lua contract passed')
