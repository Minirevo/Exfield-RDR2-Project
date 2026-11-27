dofile('rules.lua')
dofile('layout.lua')
local r,l=FrontierWheelRules,FrontierWheelLayout
for _,n in ipairs({8,9}) do
 assert(r.segment(0,0,n)==0)
 for i=0,n-1 do local a=i*math.pi*2/n;assert(r.segment(math.sin(a),-math.cos(a),n)==i+1) end
end
local main=l.main()
assert(#main==9 and main[1].kind=='disabled' and main[9].target=='character')
assert(main[6].kind=='page' and main[6].target=='medicine')
local guns={{kind='weapon',target=1},{kind='weapon',target=2}}
main=l.main(guns);assert(main[1].target==2 and main[2].target==1)
local t=l.tools({{kind='pickaxe',name='Pickaxe',quality=80}})
assert(#t==8 and t[1].target==1 and t[2].kind=='disabled' and t[8].target=='main')
local c=l.character();assert(#c==9 and c[1].target=='inventar' and c[9].target=='main')
print('Unified wheel layout tests passed')
