-- Pure native readback rules. The effective maximum and attainable HP are distinct.
FrontierMedicalDamageRules={}
local D=FrontierMedicalDamageRules
function D.valid(n)
 return type(n)=='number' and n%1==0 and n>=1 and n<=1000000
end
function D.acceptCap(request,actual)
 return D.valid(request) and D.valid(actual) and actual>=request and actual<=request*2
end
function D.acceptFill(minimum,cap,actual)
 return D.valid(minimum) and D.valid(cap) and D.valid(actual) and actual>=minimum and actual<=cap
end
function D.loss(previous,current)
 if not previous or not current or previous.ped~=current.ped or previous.cap~=current.cap then return 0 end
 if not D.valid(previous.hp) or not D.valid(current.hp) then return 0 end
 return math.max(0,previous.hp-current.hp)
end
