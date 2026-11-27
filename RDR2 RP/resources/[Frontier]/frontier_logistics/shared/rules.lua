-- Pure rules shared by the lab and future server-authoritative logistics worker.
LogisticsRules={}
local R,C=LogisticsRules,LogisticsConfig
function R.integer(n,min,max)
    return type(n)=='number' and n==n and n%1==0 and n>=min and n<=max
end
function R.loadingSeconds(grams,units,level)
    assert(R.integer(grams,0,100000000) and R.integer(units,0,1000000))
    assert(R.integer(level,1,100))
    if units==0 then return 0 end
    local l=C.Loading
    local raw=l.baseSeconds+grams/1000*l.secondsPerKg+units*l.secondsPerUnit
    local multiplier=1-.4*(level-1)/99
    return math.max(l.minSeconds,math.min(l.maxSeconds,math.ceil(raw*multiplier)))
end
-- Deterministic per-stack stochastic rounding: only one random draw per stack.
-- For a unique item this becomes a 10% loss chance; aggregate expectation is 90%.
-- The persistent destruction journal must freeze all loss decisions BEFORE inventory commit.
function R.recoverQuantity(quantity,random)
    assert(R.integer(quantity,1,10000))
    local numerator=quantity*C.RecoveryPercent
    local keep=math.floor(numerator/100)
    local remainder=numerator%100
    if remainder>0 and (random or math.random)(1,100)<=remainder then keep=keep+1 end
    return keep,quantity-keep
end
function R.fillCount(grams,limit,maxProps)
    assert(R.integer(grams,0,100000000) and R.integer(limit,1,100000000) and R.integer(maxProps,1,20))
    return math.min(maxProps,math.ceil(grams/limit*maxProps))
end
function R.assemblyQuality(components)
    local weighted,total=0,0
    for _,part in ipairs(components) do
        assert(R.integer(part.quality,0,100) and R.integer(part.quantity,1,10000))
        weighted=weighted+part.quality*part.quantity
        total=total+part.quantity
    end
    assert(total>0)
    return math.floor(weighted/total+.5)
end
