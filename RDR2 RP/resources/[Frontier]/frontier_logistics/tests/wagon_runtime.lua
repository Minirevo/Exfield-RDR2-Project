-- Regression tests for the live-tested spawn/storage baseline.
local C=LogisticsConfig
local yard=C.Depots[1]
assert(yard.spawn and yard.spawn.x==-351.02 and yard.spawn.heading==292.16)
assert(C.LoadDistance==20)
local id=string.rep('a',32)
local point=yard.spawn
local w={id=id,state='world',stolen=0,quality=50,x=point.x,y=point.y,z=point.z}
local cargo,freight={},{}
local writes,deletes={},{}
local currentHealth=0
local L={C=C,R=LogisticsRules,E='test:',entities={},leases={},Core={GetPlayers=function()return {} end}}
LogisticsRuntime=L
function L.check(ok,msg)if not ok then error(msg,0) end;return ok end
function L.now()return 100 end
function L.right()return true end
function L.stationary()return true end
function L.wagonBusy()return false end
function L.point()return point end
function L.dealer()return yard end
function L.dist(a,b)if not a or not b then return math.huge end;return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)end
function L.near(src,p,r)return p~=nil end
function L.route(wid)return 'lg_w_'..wid end
function L.freight()return freight end
function L.Q(sql)if sql:find('fl_wagons',1,true) then return {w} end;return {} end
function L.U(sql,params)writes[#writes+1]={sql=sql,params=params};return 1 end
L.I={LogisticsRead=function()return true,{slots=cargo} end}
function RegisterNetEvent()end
function CreateThread()end
function exports()end
function DoesEntityExist(e)return e~=nil and e~=0 end
function DeleteEntity(e)deletes[#deletes+1]=e end
function GetEntityHeading()return 292.16 end
function GetEntityHealth()if currentHealth==nil then error('native unavailable') end;return currentHealth end
function GetHashKey()return 0 end
function TriggerClientEvent()end
local function reset()
 L.entities[id]={vehicle=10,horses={11,12},seen=0,lastSave=0}
 writes,deletes={},{};cargo,freight={},{};point=yard.spawn;w.state='world';w.stolen=0
end
dofile('server/wagons.lua')
local function rejected(fn,message)local ok,err=pcall(fn);assert(not ok and tostring(err):find(message,1,true),tostring(err))end
reset()
L.store(1,w)
assert(#writes==1 and writes[1].params[1]=='stored' and writes[1].params[2]==yard.spawn.x)
assert(#deletes==3 and L.entities[id]==nil)
reset();cargo={{item='wood'}};rejected(function()L.store(1,w)end,'Unload all cargo first');assert(#writes==0 and #deletes==0)
reset();freight={{id='freight'}};rejected(function()L.store(1,w)end,'Unload all cargo first');assert(#writes==0)
reset();point={x=0,y=0,z=0};rejected(function()L.store(1,w)end,'Wagon outside yard')
reset();point=nil;rejected(function()L.store(1,w)end,'Approach stationary wagon at yard')
reset();w.stolen=1;rejected(function()L.store(1,w)end,'Resolve stolen wagon report first')
reset();L.wreck=function()error('Unexpected destruction of live wagon')end
L.worldTick();assert(L.entities[id] and #deletes==0 and #writes==1 and L.entities[id].healthWarning)
reset();currentHealth=nil;L.worldTick();assert(L.entities[id] and #deletes==0 and #writes==1)
print('Wagon storage and zero-health persistence regressions passed')
