HorseRules={}
local R=HorseRules
function R.id(id) return type(id)=='string' and #id<=32 and #id>0 and id:match('^[a-f0-9]+$')~=nil end
function R.distance(a,b) if not a or not b then return math.huge end;return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
function R.ride(h) return h and h.health>=30 and h.age>=HorseConfig.adultAge and h.gear and h.gear.saddle and not h.listed end
function R.draft(h,model) return h and h.health>=60 and h.age>=HorseConfig.adultAge and model=='a_c_horse_shire_darkbay' and not h.listed end
function R.name(s) return type(s)=='string' and #s>=1 and #s<=48 and not s:find('[%c<>]') and utf8.len(s)~=nil end
