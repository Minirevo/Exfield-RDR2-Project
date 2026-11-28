dofile('rules.lua')
local limits={maxLines=20,maxQuantity=100,maxTotal=250000}
local c={bread={buy=30,sell=10,maxStack=10},gun={buy=2500,maxStack=1}}
local l,t=ShopRules.basket(c,'buy',{{id='bread',quantity=3},{id='gun',quantity=1}},limits)
assert(l and t==2590 and l[1].id=='bread')
assert(not ShopRules.basket(c,'buy',{{id='gun',quantity=2}},limits))
assert(not ShopRules.basket(c,'sell',{{id='gun',quantity=1}},limits))
assert(not ShopRules.basket(c,'buy',{{id='bread',quantity=0}},limits))
assert(not ShopRules.basket(c,'buy',{{id='bread',quantity=1},{id='bread',quantity=1}},limits))
assert(not ShopRules.basket(c,'buy',{{id='fake',quantity=1}},limits))
assert(ShopRules.near({x=1,y=0,z=0,bucket=0},{x=0,y=0,z=0},5))
assert(not ShopRules.near({x=1,y=0,z=0,bucket=1},{x=0,y=0,z=0},5))
print('Shop rules passed')
