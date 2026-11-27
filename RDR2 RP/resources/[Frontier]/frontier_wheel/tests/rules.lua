dofile('rules.lua')
local r=FrontierWheelRules
assert(r.segment(0,0,8)==0)
assert(r.segment(.1,.1,8)==0)
for i=0,7 do
 local a=i*math.pi/4
 assert(r.segment(math.sin(a),-math.cos(a),8)==i+1)
end
local x,y=r.limit(3,4);assert(math.abs(x-.6)<1e-9 and math.abs(y-.8)<1e-9)
print('wheel rules passed')
