-- Pure surgical timing rules; all elapsed times are measured on the server.
FrontierMedicalQTE={}
local Q=FrontierMedicalQTE
function Q.windows(def,level)
 level=math.max(1,math.min(100,math.floor(tonumber(level) or 1)))
 local t=(level-1)/99
 return math.floor(def.perfect*(1+.6*t)+.5),math.floor(def.acceptable*(1+.5*t)+.5)
end
function Q.score(elapsed,center,perfect,acceptable,duration)
 if type(elapsed)~='number' or elapsed~=elapsed or elapsed<0 or elapsed>duration then return 'failed' end
 local distance=math.abs(elapsed-center)
 if distance<=perfect then return 'perfect' end
 if distance<=acceptable then return 'acceptable' end
 -- Near misses are a paid failure; far misses cause additional injury.
 if distance<=acceptable+100 then return 'failed' end
 return 'complication'
end
function Q.complete(previous,stage)
 if stage=='acceptable' or previous=='acceptable' then return 'acceptable' end
 return 'success'
end
function Q.isSuccessful(outcome)
 return outcome=='success' or outcome=='acceptable'
end
function Q.xp(base,outcome)
 if outcome=='success' then return base end
 if outcome=='acceptable' then return math.max(1,math.floor(base/2)) end
 return 0
end
