-- Exercise real freight/lock handlers against a deterministic stub environment.
local C,R=LogisticsConfig,LogisticsRules
local id=string.rep('b',32);local contractId='11111111-1111-1111-1111-111111111111'
local wagon={id=id,state='world',owner_type='character',owner_id='carrier',locked=1}
local contract={id=contractId,state='pickup',customer_type='character',customer_id='customer',carrier_type='character',carrier_id='carrier',wagon_id=id,origin_id='origin',destination_id='dest',deadline=1000}
local position={x=1,y=1,z=1};local close=true;local stationary=true;local actor='carrier';local writes,consumed=0,0
local L={C=C,R=R,E='test:',entities={[id]={vehicle=20}},lockTests={},views={},I={},B={}}
LogisticsRuntime=L
function L.check(ok,msg)if not ok then error(msg,0)end;return ok end
function L.cid()return actor end
function L.right()return actor=='carrier' end
function L.near()return close end
function L.point()return position end
function L.dist()return 1 end
function L.stationary()return stationary end
function L.wagonBusy()return false end
function L.now()return 100 end
function L.wagon()return wagon end
function L.uuid()return id end
function L.bag()return 'p_test' end
function L.broadcastWagon()end
function L.S()return contract end
function L.U()writes=writes+1 end
function L.B:LogisticsStockPoint()return position end
function L.I:HasItem()return true,true end
function L.I:LogisticsConsume()consumed=consumed+1;return true end
local timer=0
function GetGameTimer()return timer end
function TriggerClientEvent()end
function exports()end
dofile('server/contracts.lua')
dofile('server/cargo.lua')
local function rejected(fn,msg)local ok,err=pcall(fn);assert(not ok and tostring(err):find(msg,1,true),tostring(err))end
close=false;rejected(function()L.contractAction(1,wagon,contractId,'pickup')end,'Approach your stationary carrier wagon');assert(writes==0)
close=true;L.contractAction(1,wagon,contractId,'pickup');assert(writes==1)
rejected(function()L.lockStart(1,wagon)end,'owner cargo controls');assert(consumed==0)
actor='thief';L.lockStart(1,wagon);assert(consumed==1)
rejected(function()L.lockStart(2,wagon)end,'Another player');assert(consumed==1)
local t=L.lockTests[1];timer=math.floor(t.target*2000);L.entities[id].vehicle=21
L.lockStrike(1,t.id);assert(writes==1 and not L.lockTests[1])
L.lockStart(1,wagon);t=L.lockTests[1];timer=t.start+math.floor(t.target*2000)
L.lockStrike(1,t.id);assert(writes==2 and consumed==2)
L.lockStart(1,wagon);close=false;L.cleanupLockTests();assert(not L.lockTests[1])
print('Freight proximity and lock attempt regressions passed')
