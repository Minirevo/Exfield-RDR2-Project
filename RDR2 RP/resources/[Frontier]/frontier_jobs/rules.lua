JobsRules={}
local R=JobsRules
function R.text(v,max) return type(v)=='string' and #v>0 and #v<=max and utf8.len(v)~=nil and not v:find('%c') and v:match('%S')~=nil end
function R.integer(v,min,max) return type(v)=='number' and v==v and v%1==0 and v>=min and v<=max end
function R.uuid(v) return type(v)=='string' and #v==36 and v:match('^[a-f0-9]+%-[a-f0-9]+%-[a-f0-9]+%-[a-f0-9]+%-[a-f0-9]+$')~=nil end
function R.near(a,b,r) return a and b and a.bucket==0 and (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2<=r*r or false end
function R.canAccept(j,who,t) return j and j.state=='open' and j.poster~=who and tonumber(j.expires)>t end
function R.canSubmit(j,who,t) return j and j.state=='active' and j.worker==who and tonumber(j.expires)>t end
function R.canApprove(j,who) return j and j.state=='submitted' and j.worker~=who end
function R.canAbandon(j,who) return j and (j.state=='active' or j.state=='loaning') and j.worker==who and (j.kind=='npc' or j.kind=='task') end
