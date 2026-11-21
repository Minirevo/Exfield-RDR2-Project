-- Run from frontier_core with Lua 5.4.
local handlers, tasks, events = {}, {}, {}
local players = { [1] = true }
local identities, profiles = {}, {}
local candidates, transactions = 0, 0
local failTransaction, failUpdate, suspendTransaction

function GetCurrentResourceName() return 'frontier_core' end
function GetPlayerName(id) return players[id] and 'fixture' end
function GetPlayers() return { '1' } end
function GetConvar(_, default) return default end
function AddEventHandler(event, handler) handlers[event] = handler end
function SetTimeout(_, handler) tasks[#tasks + 1] = handler end
function TriggerEvent(event, ...)
    events[#events + 1] = { event, ... }
end
json = {
    encode = function() return '{}' end,
    decode = function(value) if value == '{}' then return {} end error('invalid fixture JSON') end,
}

MySQL = {
    scalar = { await = function()
        candidates = candidates + 1
        return ('f_%032x'):format(candidates)
    end },
    transaction = { await = function(queries)
        transactions = transactions + 1
        if failTransaction then return false end
        if suspendTransaction then coroutine.yield() end
        local id, provider, external, account = table.unpack(queries[1].values)
        local key = provider .. ':' .. external
        if not identities[key] then
            identities[key] = { id = id, account_identifier = account }
        end
        local identity = identities[key]
        if account == identity.account_identifier and not profiles[identity.id] then
            local first, last, name = table.unpack(queries[3].values)
            profiles[identity.id] = { frontierCharacterId = identity.id, firstname = first,
                lastname = last, name = name, metadataJson = '{}', attributesJson = '{}', version = 1 }
        end
        return true
    end },
    single = { await = function(statement, args)
        if statement:find('provider_character_id', 1, true) then
            return Frontier.Core.Copy(identities[args[1] .. ':' .. args[2]])
        end
        return Frontier.Core.Copy(profiles[args[1]])
    end },
    update = { await = function(_, args)
        if failUpdate then error('fixture: disconnected') end
        local row = profiles[args[#args - 1]]
        if not row or row.version ~= args[#args] then return 0 end
        row.firstname = args[1]
        row.version = row.version + 1
        return 1
    end },
}

dofile('../frontier_lib/shared/utils.lua')
dofile('../frontier_lib/server/logger.lua')
dofile('config.lua')
dofile('server/registry.lua')
dofile('server/characters.lua')
local Core = Frontier.Core

local selected = { providerCharacterId = '10', identifier = 'fixture:account', license = 'license:fixture',
    firstname = 'Anna', lastname = 'Holt', name = 'Anna Holt' }
local provider = { name = 'vorp', read = function() return selected end }

local function step()
    local task = table.remove(tasks, 1)
    assert(task, 'expected scheduled task')
    task()
end
local function expectError(expected, fn, ...)
    local ok, issue = fn(...)
    assert(not ok and issue == expected, tostring(issue))
end

Core.SyncOnline(provider)
step()
local first = assert(Frontier.GetPlayer(1))
assert(first.state == 'active' and first.characterId == first.frontierCharacterId)
assert(first.characterData.firstname == 'Anna')
assert(events[1][1] == 'frontier:characterCreated' and events[2][1] == 'frontier:playerLoaded')
first.characterData.firstname = 'mutated copy'
assert(Frontier.GetPlayer(1).characterData.firstname == 'Anna')

Core.ScheduleSync(1, provider)
step()
assert(#events == 2 and transactions == 1)
local ok, updated = Frontier.UpdateCharacterData(first.characterId, 1, { firstname = 'Ada' })
assert(ok and updated.version == 2 and Frontier.GetPlayer(1).firstname == 'Ada')
expectError('invalid_patch', Frontier.UpdateCharacterData, first.characterId, 2, { dateOfBirth = '1900-02-29' })
expectError('character_missing_or_version_conflict', Frontier.UpdateCharacterData, first.characterId, 1, { firstname = 'Old' })
failUpdate = true
expectError('database_error', Frontier.UpdateCharacterData, first.characterId, 2, { firstname = 'Lost' })
failUpdate = false

source = 1
handlers.playerDropped()
assert(not Frontier.IsPlayerLoaded(1))
assert(events[#events][1] == 'frontier:playerUnloaded' and events[#events][2].state == 'ending')
handlers.playerJoining()
Core.ScheduleSync(1, provider)
step()
assert(Frontier.GetPlayerCharacterId(1) == first.characterId and Frontier.GetPlayer(1).firstname == 'Ada')

selected.providerCharacterId = '11'
Core.ScheduleSync(1, provider)
step()
assert(Frontier.GetPlayerCharacterId(1) ~= first.characterId)
assert(events[#events][1] == 'frontier:characterSwitched')

selected.providerCharacterId = '../invalid'
expectError('invalid_provider_identity', Core.ResolveCharacter, 'vorp', selected)
selected.providerCharacterId = '12'
failTransaction = true
Core.ScheduleSync(1, provider)
step()
assert(not Frontier.IsPlayerLoaded(1))
failTransaction = false

suspendTransaction = true
local loading = coroutine.create(step)
assert(coroutine.resume(loading))
handlers.playerDropped()
assert(coroutine.resume(loading))
assert(not Frontier.IsPlayerLoaded(1))
assert(coroutine.status(loading) == 'dead')

selected.providerCharacterId = '13'
local results = {}
local function register()
    local success, data = Core.ResolveCharacter('vorp', selected)
    assert(success)
    results[#results + 1] = data.frontierCharacterId
end
local left, right = coroutine.create(register), coroutine.create(register)
assert(coroutine.resume(left))
assert(coroutine.resume(right))
assert(coroutine.resume(right))
assert(coroutine.resume(left))
assert(#results == 2 and results[1] == results[2])
local created = 0
for _, event in ipairs(events) do
    if event[1] == 'frontier:characterCreated' and event[2] == results[1] then created = created + 1 end
end
assert(created == 1)
local function proxy(handler)
    return setmetatable({ __cfx_functionReference = 'fixture' }, { __call = function(_, ...) return handler(...) end })
end
function GetPlayerIdentifierByType() return 'license:fixture' end
exports = { vorp_core = { GetCore = function()
    return {
        getUser = proxy(function(id)
            assert(id == 1)
            return {
                getUsedCharacter = {
                    charIdentifier = 19, identifier = 'owner:fixture', firstname = 'Ada',
                    lastname = 'Holt', jobgrade = 2, joblabel = 'Medic', gender = 'female',
                },
                getGroup = proxy(function() return 'admin' end),
            }
        end),
    }
end } }
dofile('server/vorp_adapter.lua')
local selection = Core.Provider.read(1)
assert(selection.providerCharacterId == '19' and selection.identifier == 'owner:fixture')
assert(selection.group == 'admin' and selection.jobGrade == 2 and selection.jobLabel == 'Medic')
assert(selection.gender == 'female' and selection.dateOfBirth == nil)
assert(handlers['vorp:SelectedCharacter'])
print('Frontier Player & Character service contract passed')
