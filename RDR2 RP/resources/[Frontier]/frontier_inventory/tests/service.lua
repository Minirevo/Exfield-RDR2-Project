-- Executed by integration.py against a disposable MariaDB schema.
local A = 'f_' .. string.rep('a', 32)
local B = 'f_' .. string.rep('b', 32)
local C = 'f_' .. string.rep('c', 32)
local selected = { [1] = A, [2] = B }
local positions = { [1] = { x = 0, y = 0, z = 0 }, [2] = { x = 1, y = 0, z = 0 } }
local events, handlers, replies, commands = {}, {}, {}, {}
local trustedCaller = 'fixture'
local timer = 0

function GetCurrentResourceName() return 'frontier_inventory' end
function GetConvar(_, value) return value end
function RegisterNetEvent(name, fn) events[name] = fn end
function AddEventHandler(name, fn) handlers[name] = fn end
function RegisterCommand(name, fn) commands[name] = fn end
function TriggerClientEvent(name, target, ...) replies[#replies+1] = { name, target, ... } end
function TriggerEvent() end
function GetInvokingResource() return trustedCaller end
function GetGameTimer() timer = timer + 300; return timer end
function GetPlayerPed(source) return selected[source] and source or 0 end
function DoesEntityExist(ped) return ped > 0 end
function GetEntityCoords(ped) return positions[ped] end
function GetEntityHealth() return 100 end
local deadPeds = {}
function IsPedDeadOrDying(ped) return deadPeds[ped] == true end
function GetPlayerRoutingBucket() return 0 end
exports = setmetatable({ frontier_core = {
    GetPlayerCharacterId = function(_, source) return selected[source] end,
    GetPlayers = function() return {} end,
    HasPermission = function(_, source) return source == 1 end,
} }, { __call = function(_, name, fn) exports[name] = fn end })

dofile('../frontier_lib/shared/utils.lua')
dofile('../frontier_lib/server/logger.lua')
dofile('config.lua')
dofile('weapons.lua')
for _, name in ipairs({ 'database', 'items', 'slots', 'service', 'ammo_recovery', 'interface' }) do
    dofile('server/' .. name .. '.lua')
end
InventoryConfig.TrustedResources.fixture = true
InventoryConfig.Slots = 4
InventoryConfig.WeightGrams = 7500
assert(Inventory.BootItems())
Inventory.ready = true

-- The native death state, rather than an unreliable health value, gates access.
assert(Inventory.Session(1) == A)
deadPeds[1] = true
local deadId, deadIssue = Inventory.Session(1)
assert(deadId == nil and deadIssue == 'restricted')
deadPeds[1] = nil
assert(Inventory.Session(1) == A)

local function result(ok, value) assert(ok, value); return value end
local function failure(expected, ok, value) assert(not ok and value == expected, tostring(value)) end
local function inventory(source) return result(exports.GetInventory(source)) end
local function count(source, item) return result(exports.GetItemCount(source, item)) end
local function action(source, kind, data, key)
    return Inventory.Act({ source = source, id = selected[source], key = key, actor = 'fixture',
        fingerprint = kind .. ':' .. key, storage = 'locker' }, kind, data)
end

assert(inventory(1).available == 4 and inventory(2).available == 4)
assert(exports.AddItem(1, 'bread', 12, nil, 'seed-bread'))
assert(exports.AddItem(1, 'bread', 12, nil, 'seed-bread'))
assert(count(1, 'bread') == 12 and inventory(1).available == 2)
failure('request_conflict', exports.AddItem(1, 'bread', 11, nil, 'seed-bread'))
failure('invalid_item', exports.AddItem(1, 'unknown', 1))
failure('quantity', exports.RemoveItem(1, 'bread', 13))
failure('weight', exports.AddItem(1, 'water', 7))
failure('invalid_metadata', exports.AddItem(1, 'bread', 1, '[]'))
assert(exports.RemoveItem(1, 'bread', 3))
assert(count(1, 'bread') == 9)
assert(exports.SplitItem(1, { slot = 1, target = 3, quantity = 2 }))
assert(exports.MoveItem(1, { slot = 3, target = 2, quantity = 2 }))
assert(inventory(1).available == 2)
assert(exports.MoveItem(1, { slot = 2, target = 4, quantity = 4 }))
assert(exports.AddItem(1, 'lantern', 1))
local view = inventory(1)
local unique = view.slots[2].instance
assert(unique and view.slots[2].metadata == '{"condition":100}')
assert(exports.MoveItem(1, { slot = 2, target = 3, quantity = 1 }))
assert(inventory(1).slots[2].instance == unique)

assert(exports.AddItem(2, 'water', 10))
failure('weight', exports.GiveItem(1, { slot = 3, recipient = 2, quantity = 1 }))
assert(count(1, 'lantern') == 1 and count(2, 'lantern') == 0)
assert(exports.GiveItem(1, { slot = 1, recipient = 2, quantity = 1 }))
assert(count(1, 'bread') == 8 and count(2, 'bread') == 1)
positions[2].x = 50
failure('distance', exports.GiveItem(1, { slot = 1, recipient = 2, quantity = 1 }))
positions[2].x = 1

assert(exports.CreateStorage({ id = 'locker', name = 'Testlager', x = 0, y = 0, z = 0, slots = 2, grams = 7500 }))
failure('forbidden', Inventory.Storage(2, 'locker'))
assert(action(1, 'store', { slot = 4, quantity = 3, target = 1 }, 'put'))
assert(action(1, 'storageSplit', { slot = 1, target = 2, quantity = 1 }, 'split-locker'))
assert(action(1, 'storageMove', { slot = 2, target = 1, quantity = 1 }, 'merge-locker'))
assert(action(1, 'retrieve', { slot = 1, quantity = 3, target = 4 }, 'take'))
assert(result(exports.GetStorageContents('locker')).available == 2)

assert(exports.AddItem(1, 'bandage', 1))
local used = 0
assert(exports.RegisterUsableItem('bandage', function(source, item)
    assert(source == 1 and item.item == 'bandage' and type(item.metadata) == 'table')
    used = used + 1
    return true
end, 'consume'))
assert(exports.UseItem(1, { slot = 2 }, 'use-1'))
assert(exports.UseItem(1, { slot = 2 }, 'use-1'))
assert(used == 1 and count(1, 'bandage') == 0)

assert(exports.DropItem(1, { slot = 4, quantity = 2 }, 'drop-1'))
local drops = result(Inventory.NearbyDrops(result(true, Inventory.Position(1))))
assert(#drops == 1 and drops[1].quantity == 2)
assert(action(2, 'pickup', { drop = drops[1].id }, 'pick-2'))
failure('not_found', action(1, 'pickup', { drop = drops[1].id }, 'pick-1'))
assert(count(1, 'bread') == 6 and count(2, 'bread') == 3)

local boxA = result(Inventory.Load('p_' .. A))
local boxB = result(Inventory.Load('p_' .. A))
assert(Inventory.Place(boxA, { item = 'apple', quantity = 1, metadata = '{}' }))
assert(Inventory.Place(boxB, { item = 'apple', quantity = 1, metadata = '{}' }))
assert(Inventory.Commit('optimistic-a', 'fixture', 'a', boxA))
local replayOk, _, replay = Inventory.Commit('optimistic-a', 'fixture', 'a', boxA)
assert(replayOk and replay)
failure('conflict', Inventory.Commit('optimistic-b', 'fixture', 'b', boxB))
assert(count(1, 'apple') == 1)
failure('slots', exports.AddItem(1, 'lantern', 1))

selected[1] = C
handlers['frontier:playerUnloaded']({ source = 1 })
assert(count(1, 'bread') == 0)
selected[1] = A
Inventory.items = {}
assert(Inventory.BootItems())
assert(count(1, 'bread') == 6 and count(1, 'lantern') == 1)
assert(exports.CreateStorage({ id = 'large', name = 'Metadatenlager', slots = 12, grams = 7500 }))
for i = 1, 10 do
    local metadata = ('{"serial":%d,"padding":"%s"}'):format(i, string.rep('x', 7000))
    assert(exports.AddItemToStorage('large', 'apple', 1, metadata))
end
assert(result(exports.GetStorageContents('large')).available == 2)
trustedCaller = 'unlisted'
failure('forbidden', exports.AddItem(1, 'bread', 1))
trustedCaller = 'fixture'
source = 1
events['frontier_inventory:open'](1)
local token = replies[#replies][4]
assert(type(token) == 'string')
source = 2
local before = #replies
events['frontier_inventory:request'](token, 1, 'drop', { slot = 1, quantity = 1, characterId = A, revision = 0 })
assert(#replies == before and count(1, 'bread') == 6)
source = 1
events['frontier_inventory:request'](token, 2, 'drop', { slot = 1, quantity = -1, revision = 0 })
assert(replies[#replies][5].ok == false and count(1, 'bread') == 6)
print('Frontier Inventory service and MariaDB contracts passed')
