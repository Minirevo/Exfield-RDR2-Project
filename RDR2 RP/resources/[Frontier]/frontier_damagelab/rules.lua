-- Diagnostic modes, not production medical rules.
FrontierDamageLab={}
local L=FrontierDamageLab
L.modes={observe={},refill={refill=true},buffer={refill=true,buffer=true},guarded={refill=true,buffer=true,flags=true},invincible={invincible=true}}
L.flags={263,340,388}
L.bufferMax=5000
L.durationMs=180000
-- Only these fixed test scenarios are permitted. No arbitrary models or targets.
L.npcs={
 melee={model='A_M_M_VALTOWNFOLK_01',distance=4.0},
 knife={model='A_M_M_VALTOWNFOLK_01',distance=4.0,weapon='WEAPON_MELEE_KNIFE'},
 revolver={model='A_M_M_VALTOWNFOLK_01',distance=8.0,weapon='WEAPON_REVOLVER_CATTLEMAN'},
 wolf={model='A_C_WOLF',distance=5.0,animal=true}
}
function L.npcAction(name)
 if type(name)~='string' then return nil end
 if name=='stop' or name=='clear' then return 'clear' end
 return L.npcs[name] and name or nil
end
-- Always return explicit values, even if a native is unavailable or throws.
-- tostring(readNative(...)) must never become tostring() with zero arguments.
function L.readNative(fn,...)
 if type(fn)~='function' then return nil,nil end
 local ok,a,b=pcall(fn,...)
 if ok then return a,b end
 return nil,nil
end
function L.validMode(mode) return type(mode)=='string' and L.modes[mode]~=nil end
function L.target(original,mode)
 if not L.validMode(mode) or type(original)~='number' or original<1 then return nil end
 return L.modes[mode].buffer and math.max(original,L.bufferMax) or original
end
-- Readback can include a native health modifier not present in the setter input.
function L.validHealth(n)
 return type(n)=='number' and n==n and n%1==0 and n>=1 and n<=1000000
end
function L.bufferAccepted(request,actual)
 return L.validHealth(request) and L.validHealth(actual) and actual>=request and actual<=request*2
end
function L.correctMax(request,actual,desired)
 if not L.validHealth(request) or not L.validHealth(actual) or not L.validHealth(desired) then return nil end
 local corrected=request+desired-actual
 if not L.validHealth(corrected) or corrected==request then return nil end
 return corrected
end
function L.loss(before,after)
 if type(before)~='number' or type(after)~='number' then return 0 end
 return math.max(0,before-after)
end
function L.newStats()
 return {lossSamples=0,rawLoss=0,aiEvents=0,networkEvents=0,incapEvents=0,gameEvents=0,refills=0,errors=0,dead=false}
end
function L.summary(s)
 return ('lossSamples=%d rawLoss=%d aiEvents=%d networkEvents=%d incapEvents=%d gameEvents=%d refills=%d errors=%d dead=%s'):format(s.lossSamples,s.rawLoss,s.aiEvents,s.networkEvents,s.incapEvents,s.gameEvents,s.refills,s.errors,tostring(s.dead))
end
