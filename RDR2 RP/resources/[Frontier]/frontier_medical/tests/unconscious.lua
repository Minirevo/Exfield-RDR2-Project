-- Run from frontier_medical: lua5.4 tests/unconscious.lua
-- Exercise the actual client loop with a deterministic mock of the native timer.
dofile('config.lua')
local now,ped,expires,ragCalls,resets,blocked=100,1,0,0,0,0
local mounted,vehicle,attached,dead=false,false,false,false
local handlers,threads={},{}
LocalPlayer={state={IsInSession=true}}
FrontierMedicalAdapter={update=function() end,reset=function() end}
function RegisterNetEvent(name,fn) handlers[name]=fn end
function AddEventHandler(name,fn) handlers[name]=fn end
function RegisterCommand() end
function RegisterNUICallback() end
local nui={}
function TriggerEvent() end
function SendNUIMessage(v) nui[#nui+1]=v end
function joaat(s) return s end
function CreateThread(fn) threads[#threads+1]=coroutine.create(fn) end
function Wait(ms) coroutine.yield(ms) end
function GetGameTimer() return now end
function PlayerPedId() return ped end
function PlayerId() return 1 end
function IsEntityDead() return dead end
function IsPlayerDead() return dead end
function IsPedOnMount() return mounted end
function IsPedInAnyVehicle() return vehicle end
function IsEntityAttachedToAnyPed() return attached end
function IsPedRagdoll() return now<expires end
function SetPedToRagdoll(p,min,max) assert(p==ped);ragCalls=ragCalls+1;expires=now+max end
function ResetPedRagdollTimer(p) assert(p==ped);resets=resets+1;if IsPedRagdoll() then expires=now+1000 end end
function DisableControlAction() blocked=blocked+1 end
function DisablePlayerFiring() end
source=65535
dofile('client.lua')
local feedbackLoop,loop=assert(threads[1]),assert(threads[2])
local function state(down,terminal)
 handlers['frontier_medical:state']({life=1,down=down,dead=terminal==true})
end
local function step(ms)
 now=now+(ms or 16)
 local ok,err=coroutine.resume(loop)
 assert(ok,err)
end
state(true)
for i=1,300 do step() assert(IsPedRagdoll()) end
assert(ragCalls==1 and resets==300 and blocked>0)
-- Recover naturally without clearing any unrelated tasks.
state(false)
local before=resets
step(1100);assert(not IsPedRagdoll() and resets==before)
-- Already ragdolled by combat: keep that collapse rather than restarting it.
expires=now+1000;state(true);step();assert(ragCalls==1 and resets==before+1)
-- A genuine interruption can trigger a new collapse.
expires=0;step(200);assert(ragCalls==2 and IsPedRagdoll())
-- No ragdoll maintenance while attached, mounted, in a vehicle, dead or stale.
before=resets
attached=true;step();attached=false
mounted=true;step();mounted=false
vehicle=true;step();vehicle=false
state(true,true);step()
dead=true;state(true);step();dead=false
assert(resets==before)
step(FrontierMedicalConfig.stateTimeoutMs+1);assert(resets==before)
-- Owner symptom UI and hit cue are separate from the ragdoll thread.
handlers['frontier_medical:state']({life=1,token='test',down=false,dead=false,symptoms={{kind='bleeding',level='warning',text='You are bleeding.'}}})
assert(nui[#nui].type=='symptoms')
handlers['frontier_medical:injuryFeedback']('test','You were hit.')
assert(nui[#nui].type=='injuryFeedback')
local count=#nui
handlers['frontier_medical:injuryFeedback']('test','Duplicate hit.')
assert(#nui==count)
handlers['frontier_medical:injuryFeedback']('old','Stale hit.')
assert(#nui==count)
state(true);assert(nui[#nui].type=='clearFeedback')
print('Continuous unconscious posture and owner feedback: mocked client regression passed')
