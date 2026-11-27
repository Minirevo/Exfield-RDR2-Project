-- Regression tests for the physical gate; no live SQL or natives required.
local C,R=LogisticsConfig,LogisticsRules
local w={id=string.rep('a',32),state='world',owner_type='company',owner_id='seller'}
local c={id='11111111-1111-1111-1111-111111111111',buyer_id='buyer',destination_id='warehouse',item_id='wood',remaining=20}
local point={x=0,y=0,z=0};local dest={x=1,y=0,z=0,ownerType='company',ownerId='buyer',name='Buyer warehouse'}
local close,stationary,owner,busy,onboard=true,true,true,false,12
local calls=0
local L={C=C,R=R,entities={[w.id]={}},B={},I={}}
LogisticsRuntime=L
function L.check(ok,msg)if not ok then error(msg,0)end;return ok end
function L.right()return owner end
function L.point()return point end
function L.near()return close end
function L.stationary()return stationary end
function L.dist(a,b)return math.abs(a.x-b.x)end
function L.wagonBusy()return busy end
function L.route(id)return 'lg_w_'..id end
function L.B:LogisticsStockPoint()return dest end
function L.I:LogisticsRead()return true,{slots={{item='wood',quantity=onboard},{item='stone',quantity=100}}} end
function GetResourceState()return 'started' end
exports={frontier_trade={
 WagonContracts=function(_,src,company)assert(company=='seller');return {c}end,
 WagonDispatch=function(_,src,company,ref,qty,wagon,warehouse)
  assert(company=='seller' and ref==c.id and qty==10 and wagon==w.id and warehouse=='warehouse');calls=calls+1;return true,'delivery-id'
 end}}
dofile('server/trade.lua')
local function reject(fn,msg)local ok,err=pcall(fn);assert(not ok and tostring(err):find(msg,1,true),tostring(err));assert(calls==0)end
assert(L.tradeView(1,w)[1].canDeliver)
owner=false;reject(function()L.tradeDeliver(1,w,c.id,10)end,'Approach your stationary company wagon');owner=true
close=false;reject(function()L.tradeDeliver(1,w,c.id,10)end,'Approach your stationary company wagon');close=true
busy=true;reject(function()L.tradeDeliver(1,w,c.id,10)end,'Approach your stationary company wagon');busy=false
dest.x=100;reject(function()L.tradeDeliver(1,w,c.id,10)end,'Bring the loaded wagon');dest.x=1
dest.ownerId='wrong';reject(function()L.tradeDeliver(1,w,c.id,10)end,'Bring the loaded wagon');dest.ownerId='buyer'
onboard=9;reject(function()L.tradeDeliver(1,w,c.id,10)end,'Not enough contracted goods');onboard=12
reject(function()L.tradeDeliver(1,w,c.id,21)end,'Contract unavailable')
assert(L.tradeDeliver(1,w,c.id,10):find('delivery-id',1,true));assert(calls==1 and L.entities[w.id].tradeRefresh)
print('Physical trade delivery gate regressions passed')
