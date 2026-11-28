local C,R=JobsConfig,JobsRules
local E='frontier_jobs:'
local core,inv,eco,business=exports.frontier_core,exports.frontier_inventory,exports.frontier_economy,exports.frontier_business
local Q,S,U,V=MySQL.query.await,MySQL.single.await,MySQL.update.await,MySQL.scalar.await
local ready,busy=false,false
local sessions,last={},{}
local function now() return os.time() end
local function uuid() return V('SELECT LOWER(UUID())') end
local function cid(src) return core:GetPlayerCharacterId(src) end
local function name(src) local p=core:GetPlayer(src);return p and p.name or GetPlayerName(src) or 'Unknown' end
local function need(ok,msg) if not ok then error(msg,0) end return ok end
local function row(id) if R.uuid(id) then return S('SELECT * FROM frontier_jobs_contracts WHERE id=?',{id}) end end
local function position(src)
 local ok,p=inv:GetJobsPosition(src);if ok then return p end
end
local function near(src,p) return R.near(position(src),p,C.reach) end
local function company(id) if type(id)=='string' and #id==32 then return S('SELECT id,name,status FROM fb_companies WHERE id=?',{id}) end end
local function manage(who,id) return business:HasCompanyPermission(id,who,'hire') end
local function funds(who,id) return business:GetCompanyAccount(id,who,'withdraw') end
local function bank(src,who)
 local ok,a=eco:GetCharacterAccounts(src);if ok and a.characterId==who then return a.bank.id end
end
local function send(src,msg) TriggerClientEvent(E..'notice',src,tostring(msg)) end
local function owner(who,id) return tonumber(V('SELECT COUNT(*) FROM fb_shares WHERE company_id=? AND character_id=?',{id,who}))>0 end
local function transition(id,old,new)
 return U('UPDATE frontier_jobs_contracts SET state=? WHERE id=? AND state=?',{new,id,old})==1
end
local function result(src,who,msg)
 if cid(src)==who then send(src,msg) end
end
local function pendingHarvest(who)
 if GetResourceState('frontier_gathering')~='started' or exports.frontier_gathering:JobsGatheringBusy(who) then return true end
 return tonumber(V('SELECT COUNT(*) FROM frontier_gather_claims WHERE character_id=? AND phase<2',{who}))>0
end
-- Inventory checks this before starting/finishing new work with a borrowed tool.
exports('IsLoanActive',function(character,contract,item)
 if GetInvokingResource()~='frontier_inventory' or not ready then return false end
 local j=row(contract)
 return j and j.kind=='npc' and j.state=='active' and j.worker==character and j.loan==item and tonumber(j.wants_loan)==1 and tonumber(j.expires)>now() or false
end)
local function progress(j)
 -- Durable states precede external effects. Every inventory/economy key is stable.
 if j.state=='funding' then
  local ok,why=eco:FundTradeHold(j.id,j.company,tonumber(j.company_bank),tonumber(j.reward))
  if ok then transition(j.id,'funding','open')
  elseif why=='insufficient_funds' then transition(j.id,'funding','cancelled')
  else return false,why end
 elseif j.state=='loaning' then
  local ok,why=inv:JobsInventory(j.id,j.worker,'loan',j.loan,1)
  if ok then transition(j.id,'loaning','active')
  elseif why=='weight' or why=='slots' then return false,why
  else return false,why end
 elseif j.state=='delivering' then
  -- Never take a tool from an unresolved gathering claim.
  if tonumber(j.wants_loan)==1 and pendingHarvest(j.worker) then return false,'Resolve pending gathering reward first (/gatherrecover).' end
  local ok,why=inv:JobsInventory(j.id,j.worker,'deliver',j.item,tonumber(j.quantity),tonumber(j.wants_loan)==1 and j.loan or false)
  if ok then transition(j.id,'delivering','paying')
  elseif why=='insufficient_stock' then transition(j.id,'delivering','active');return false,why
  else return false,why end
 elseif j.state=='paying' then
  local ok,receipt
  if j.kind=='npc' then
   ok,receipt=eco:CreditAccount(tonumber(j.worker_bank),tonumber(j.reward),{key='jobs:'..j.id..':wage',reason='NPC work contract completed',reference=j.id})
  else
   ok,receipt=eco:PayTradeDelivery(j.id,j.id,j.worker,tonumber(j.worker_bank),tonumber(j.reward))
  end
  if not ok then return false,receipt end
  U("UPDATE frontier_jobs_contracts SET state='paid',receipt=? WHERE id=? AND state='paying'",{receipt.operationId,j.id})
 elseif j.state=='returning' then
  if tonumber(j.wants_loan)==1 then
   if pendingHarvest(j.worker) then return false,'pending harvest' end
   local ok,why=inv:JobsInventory(j.id,j.worker,'return',j.loan,1)
   if not ok then return false,why end
  end
  transition(j.id,'returning','cancelled')
 elseif j.state=='refunding' then
  local ok,why=eco:ReleaseTradeHold(j.id,j.company,tonumber(j.company_bank),tonumber(j.reward))
  if not ok then return false,why end
  transition(j.id,'refunding','cancelled')
 end
 return true
end
local function advance(id)
 for i=1,4 do
  local j=row(id);if not j or not ({funding=true,loaning=true,delivering=true,paying=true,returning=true,refunding=true})[j.state] then return true,j and j.state end
  local ok,why=progress(j);if not ok then return false,why end
 end
 return false,'pending'
end
local function validView(src,v)
 if not v or cid(src)~=v.who then return false end
 if v.mode=='board' then return near(src,C.boards[v.place]) end
 if v.mode=='employer' then return near(src,C.employers[v.place]) end
 if v.mode=='manage' then return manage(v.who,v.place) end
 return v.mode=='personal'
end
local function quota(who,key)
 local start=math.floor(now()/86400)*86400
 local total=tonumber(V("SELECT COUNT(*) FROM frontier_jobs_contracts WHERE kind='npc' AND template=? AND created>=?",{key,start})) or 0
 local own=tonumber(V("SELECT COUNT(*) FROM frontier_jobs_contracts WHERE kind='npc' AND worker=? AND created>=?",{who,start})) or 0
 return math.max(0,math.min(C.perJobDaily-total,C.perCharacterDaily-own))
end
local function publicPostings()
 return Q("SELECT j.id,j.kind,j.title,j.description,j.employer,j.town,j.reward,j.expires FROM frontier_jobs_contracts j JOIN fb_companies c ON c.id=j.company WHERE j.state='open' AND j.expires>? AND c.status='active' ORDER BY j.created DESC LIMIT 100",{now()})
end
local function view(src,v)
 if sessions[src]~=v or not validView(src,v) then sessions[src]=nil;TriggerClientEvent(E..'close',src);return end
 local data={ticket=v.ticket,mode=v.mode,place=v.place,boards=C.boards,employers=C.employers,jobs={},postings={},mine={},companyJobs={},applications={},canFund=false}
 if v.mode=='board' or v.mode=='employer' then
  for k,j in pairs(C.jobs) do if v.mode=='board' or j.employer==v.place then
   local a={id=k,title=j.title,description=j.description,employer=j.employer,item=j.item,quantity=j.quantity,reward=j.reward,onsite=j.onsite,loan=j.loan,available=quota(v.who,k)}
   data.jobs[#data.jobs+1]=a
  end end
  if v.mode=='board' then data.postings=publicPostings() end
 end
 data.mine=Q("SELECT id,kind,state,title,description,employer,template,item,quantity,loan,wants_loan,reward,town,expires,receipt FROM frontier_jobs_contracts WHERE worker=? ORDER BY created DESC LIMIT 60",{v.who})
 if v.mode=='manage' then
  local b=company(v.place);if not b then return end
  data.company=b;data.canFund=funds(v.who,b.id)~=nil
  data.companyJobs=Q("SELECT id,kind,state,title,description,town,reward,worker,worker_name,expires,receipt FROM frontier_jobs_contracts WHERE company=? ORDER BY created DESC LIMIT 100",{b.id})
  data.applications=Q("SELECT a.*,j.title FROM frontier_jobs_applications a JOIN frontier_jobs_contracts j ON j.id=a.posting WHERE j.company=? ORDER BY a.created DESC LIMIT 100",{b.id})
  local online={};for _,pl in pairs(core:GetPlayers()) do online[pl.frontierCharacterId]=pl.source end
  for _,a in ipairs(data.applications) do a.online=online[a.character_id] end
 end
 if sessions[src]==v and validView(src,v) then TriggerClientEvent(E..'view',src,data) end
end
local function run(src,fn)
 if not ready then return send(src,'Employment office is not ready.') end
 if busy then return send(src,'Employment office is busy. Retry shortly.') end
 local tick=GetGameTimer();if last[src] and tick-last[src]<300 then return end;last[src]=tick
 busy=true;local ok,err=pcall(fn);busy=false
 if not ok then print('[frontier_jobs] '..tostring(err));send(src,tostring(err)) end
end
RegisterNetEvent(E..'open',function(mode,place)
 local src=source;run(src,function()
  local who=need(cid(src),'Load a character first.')
  need(type(mode)=='string' and (mode=='personal' or type(place)=='string'),'Invalid employment location.')
  local v={mode=mode,place=place,who=who,ticket=uuid()}
  need(validView(src,v),'Visit a notice board or employer, or open a company you manage.')
  sessions[src]=v;view(src,v)
 end)
end)
RegisterNetEvent(E..'close',function(ticket) local v=sessions[source];if v and v.ticket==ticket then sessions[source]=nil end end)
AddEventHandler('playerDropped',function() sessions[source]=nil;last[source]=nil end)
local function acceptNpc(src,v,d)
 local j=C.jobs[d.id];need(j,'Unknown job.')
 need((v.mode=='board' and not j.onsite) or (v.mode=='employer' and v.place==j.employer),'Visit the employer to start this job.')
 need(quota(v.who,d.id)>0,'Daily work allocation exhausted.')
 need(V("SELECT COUNT(*) FROM frontier_jobs_contracts WHERE worker=? AND kind='npc' AND template=? AND state IN ('loaning','active','delivering','paying','returning')",{v.who,d.id})==0,'You already have this job.')
 local a=need(bank(src,v.who),'Bank unavailable.')
 local loan=d.loan==true and j.loan~=nil
 need(not loan or v.mode=='employer','Collect equipment at the employer.')
 local id=uuid();local t=now()
 need(validView(src,v),'Session changed.')
 U([[INSERT INTO frontier_jobs_contracts(id,kind,state,poster,employer,title,description,template,item,quantity,loan,wants_loan,reward,worker,worker_bank,worker_name,created,expires)
 VALUES(?,'npc',?,'npc',?,?,?,?,?,?,?,?,?,?,?,?,?,?)]],
 {id,loan and 'loaning' or 'active',j.employer,j.title,j.description,d.id,j.item,j.quantity,j.loan or '',loan and 1 or 0,j.reward,v.who,a,name(src),t,t+C.duration})
 local ok,why=advance(id);if not ok then return 'Contract saved; equipment pending: '..tostring(why) end
 return 'Job accepted. Deliver at '..C.employers[j.employer].name..'.'
end
local function post(src,v,d)
 need(v.mode=='manage','Open company employment management.')
 local b=need(company(v.place),'Company unavailable.')
 need(b.status=='active' and manage(v.who,b.id),'Company unavailable.')
 need(d.kind=='recruitment' or d.kind=='task','Invalid posting type.')
 need(R.text(d.title,80) and R.text(d.description,500) and C.boards[d.town],'Enter title, description and town.')
 need(V("SELECT COUNT(*) FROM frontier_jobs_contracts WHERE company=? AND state IN ('funding','open','active','submitted','paying','refunding')",{b.id})<C.maxCompanyOpen,'Too many open postings.')
 local amount,account=0,0
 if d.kind=='task' then
  need(R.integer(d.reward,1,C.maxReward),'Enter a valid reward.')
  amount=d.reward;account=need(funds(v.who,b.id),'Withdraw permission required to reserve task pay.')
 end
 local id=uuid();local t=now()
 need(validView(src,v),'Session changed.')
 U([[INSERT INTO frontier_jobs_contracts(id,kind,state,company,poster,employer,title,description,town,reward,company_bank,created,expires)
 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)]],{id,d.kind,d.kind=='task' and 'funding' or 'open',b.id,v.who,b.name,d.title,d.description,d.town,amount,account,t,t+C.postingDuration})
 local ok,state=advance(id)
 if not ok then return 'Posting saved; funding pending: '..tostring(state) end
 return state=='cancelled' and 'Insufficient company funds. Posting not published.' or 'Posting published on employment boards.'
end
local function action(src,v,op,d)
 if op=='acceptNpc' then return acceptNpc(src,v,d) end
 if op=='post' then return post(src,v,d) end
 if op=='refresh' then return 'Refreshed.' end
 local j=need(row(d.id),'Posting or contract unavailable.')
 if op=='acceptTask' or op=='apply' then
  need(v.mode=='board' and R.canAccept(j,v.who,now()),'Posting unavailable.')
  local b=need(company(j.company),'Company unavailable.');need(b.status=='active','Company unavailable.')
  if op=='apply' then
   need(j.kind=='recruitment' and R.text(d.message,500),'Enter an application.')
   local n=U("INSERT IGNORE INTO frontier_jobs_applications(posting,character_id,name,message,created) VALUES(?,?,?,?,?)",{j.id,v.who,name(src),d.message,now()})
   return n==1 and 'Application sent.' or 'You already applied.'
  end
  need(j.kind=='task' and not owner(v.who,j.company) and not manage(v.who,j.company),'Cannot accept your own company task.')
  local a=need(bank(src,v.who),'Bank unavailable.')
  need(validView(src,v),'Session changed.')
  need(U("UPDATE frontier_jobs_contracts SET state='active',worker=?,worker_name=?,worker_bank=?,expires=? WHERE id=? AND state='open'",{v.who,name(src),a,now()+C.duration,j.id})==1,'Already accepted.')
  return 'Task accepted. Coordinate with the employer; payment is reserved.'
 elseif op=='deliver' then
  need(j.kind=='npc' and R.canSubmit(j,v.who,now()) and v.mode=='employer' and v.place==j.employer,'Deliver to the correct employer before expiry.')
  need(transition(j.id,'active','delivering'),'Contract changed.')
  local ok,why=advance(j.id);return ok and 'Delivery received and paid.' or 'Delivery pending: '..tostring(why)
 elseif op=='retry' then
  need(j.worker==v.who and j.state=='loaning' and v.mode=='employer' and v.place==j.employer,'Visit the employer for equipment.')
  local ok,why=advance(j.id);return ok and 'Equipment received.' or 'Equipment pending: '..tostring(why)
 elseif op=='submitTask' then
  need(j.kind=='task' and R.canSubmit(j,v.who,now()),'Task unavailable.')
  need(transition(j.id,'active','submitted'),'Contract changed.')
  return 'Completion submitted for employer review.'
 elseif op=='abandon' then
  need(j.worker==v.who and (j.state=='active' or j.state=='loaning'),'Contract unavailable.')
  local nextState=j.kind=='npc' and 'returning' or 'refunding'
  need(transition(j.id,j.state,nextState),'Contract changed.');local ok,why=advance(j.id)
  return ok and 'Contract ended.' or 'Cancellation pending: '..tostring(why)
 end
 need(v.mode=='manage' and j.company==v.place and manage(v.who,v.place),'Company permission required.')
 if op=='approve' then
  need(j.kind=='task' and R.canApprove(j,v.who),'Task is not awaiting review.')
  need(transition(j.id,'submitted','paying'),'Contract changed.')
  local ok,why=advance(j.id);return ok and 'Worker paid.' or 'Payment pending: '..tostring(why)
 elseif op=='cancel' then
  -- Employer cannot take back an accepted or submitted worker's reserved pay.
  need(j.state=='open','Only unaccepted postings may be cancelled.')
  need(transition(j.id,'open',j.kind=='task' and 'refunding' or 'cancelled'),'Posting changed.')
  local ok,why=advance(j.id);return ok and 'Posting cancelled.' or 'Refund pending: '..tostring(why)
 elseif op=='application' then
  need(j.kind=='recruitment' and type(d.character)=='string' and (d.decision=='contacted' or d.decision=='declined'),'Invalid application.')
  U("UPDATE frontier_jobs_applications SET state=? WHERE posting=? AND character_id=? AND state='pending'",{d.decision,j.id,d.character})
  return 'Application updated. Use existing Business hiring to send an employment invitation.'
 end
 error('Unknown employment action.',0)
end
RegisterNetEvent(E..'action',function(ticket,op,d)
 local src=source;run(src,function()
  local v=sessions[src];need(v and v.ticket==ticket and validView(src,v),'Employment session expired.')
  need(type(op)=='string' and type(d)=='table','Invalid action.')
  local ok,msg=pcall(action,src,v,op,d)
  result(src,v.who,ok and msg or tostring(msg))
  view(src,v)
 end)
end)
MySQL.ready(function()
 local ok,err=pcall(function()
  S('SELECT id FROM frontier_jobs_contracts LIMIT 1');S('SELECT posting FROM frontier_jobs_applications LIMIT 1')
 end)
 if not ok then print('[frontier_jobs] Apply sql/001_jobs.sql: '..tostring(err));return end
 CreateThread(function()
  for item,d in pairs(C.loans) do
   local definition={name=d.name,description='Employer-owned temporary gathering equipment',category='Tools',classification='tool',grams=d.grams,maxStack=1,condition=true,drop=false,transfer=false,store=false,metadata='{"condition":100,"material":"Crude iron","materialId":"crude","quality":30,"maxUses":60,"uses":60,"yield":0.85,"manufacturer":"Employer"}'}
   while true do local registered,why=inv:RegisterItem(item,definition);if registered then break end;print('[frontier_jobs] Loan registration: '..tostring(why));Wait(3000) end
  end
  ready=true;print('[frontier_jobs] ready')
  while true do
   Wait(5000)
   if not busy then
    busy=true;local ok,why=pcall(function()
     local t=now()
     U("UPDATE frontier_jobs_contracts SET state='returning' WHERE kind='npc' AND state IN ('active','loaning') AND expires<=?",{t})
     U("UPDATE frontier_jobs_contracts SET state='refunding' WHERE kind='task' AND state IN ('open','active') AND expires<=?",{t})
     U("UPDATE frontier_jobs_contracts SET state='cancelled' WHERE kind='recruitment' AND state='open' AND expires<=?",{t})
     for _,j in ipairs(Q("SELECT id,state FROM frontier_jobs_contracts WHERE state IN ('funding','delivering','paying','returning','refunding') ORDER BY created LIMIT 40")) do advance(j.id) end
    end);busy=false;if not ok then print('[frontier_jobs] recovery: '..tostring(why)) end
   end
  end
 end)
end)
