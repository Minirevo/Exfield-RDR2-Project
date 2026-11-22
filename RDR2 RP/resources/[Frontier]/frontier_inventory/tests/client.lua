local callbacks, handlers, events, commands, raw = {}, {}, {}, {}, {}
local sent, focus, messages = {}, {}, {}
local persisted
function RegisterCommand(name, fn) commands[name] = fn end
function RegisterRawKeymap(name, _, up) raw[name] = up end
function GetResourceKvpString() return persisted end
function SetResourceKvp(_, value) persisted = value end
function RegisterNetEvent(name, fn) events[name] = fn end
function RegisterNUICallback(name, fn) callbacks[name] = fn end
function AddEventHandler(name, fn) handlers[name] = fn end
function TriggerServerEvent(name, ...) sent[#sent+1] = { name, ... } end
function TriggerEvent() end
function SetTimeout() end
function CreateThread() end
function IsPauseMenuActive() return false end
function SetNuiFocus(mouse, keyboard) focus[#focus+1] = { mouse, keyboard } end
function SetNuiFocusKeepInput(value) assert(value == false) end
function SendNUIMessage(message) messages[#messages+1] = message end
function GetCurrentResourceName() return 'frontier_inventory' end
local function acknowledge(reply) assert(reply.ok) end

dofile('config.lua')
dofile('client/inventory.lua')
local E = 'frontier_inventory:'
raw.frontier_inventory_F6()
assert(sent[#sent][1] == E .. 'open')
source = 65535
events[E .. 'open'](1, 'ticket', {})
assert(#focus == 0)
callbacks.ready({}, acknowledge)
assert(focus[#focus][1] and messages[#messages].type == 'open')
callbacks.action({ sequence = 1, action = 'refresh', data = {} }, acknowledge)
assert(sent[#sent][1] == E .. 'request' and sent[#sent][2] == 'ticket')
events[E .. 'result'](99, 1, { ok = true })
assert(messages[#messages].type == 'open')
events[E .. 'result'](1, 1, { ok = true })
assert(messages[#messages].sequence == 1)
callbacks.close({}, acknowledge)
assert(focus[#focus][1] == false and messages[#messages].type == 'close')
commands.inventartaste(nil, { 'F8' })
assert(persisted == 'F8')
raw.frontier_inventory_F8()
assert(sent[#sent][1] == E .. 'open' and sent[#sent][2] == 2)
events[E .. 'open'](2, 'ticket-2', {})
assert(focus[#focus][1])
handlers.onClientResourceStop('frontier_inventory')
assert(focus[#focus][1] == false and focus[#focus][2] == false)
print('Frontier Inventory client contract passed')
