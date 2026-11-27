-- Diagnostic modes, not production medical rules.
FrontierDamageLab={}
local L=FrontierDamageLab
L.modes={observe={},refill={refill=true},buffer={refill=true,buffer=true},guarded={refill=true,buffer=true,flags=true},invincible={invincible=true}}
L.flags={263,340,388}
L.bufferMax=5000
L.durationMs=180000
function L.validMode(mode) return type(mode)=='string' and L.modes[mode]~=nil end
function L.target(original,mode)
 if not L.validMode(mode) or type(original)~='number' or original<1 then return nil end
 return L.modes[mode].buffer and math.max(original,L.bufferMax) or original
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
