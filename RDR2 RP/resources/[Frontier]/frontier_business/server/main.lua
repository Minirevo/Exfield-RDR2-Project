local C=BusinessConfig
local core,eco,inv=exports.frontier_core,exports.frontier_economy,exports.frontier_inventory
local Q,U,S=MySQL.query.await,MySQL.update.await,MySQL.single.await
local ready,busy=false,false
local sessions={}
local function now() return os.time() end
local function uuid() return MySQL.scalar.await('SELECT REPLACE(UUID(),CHAR(45),SPACE(0))') end
local function encode(v) return json.encode(v) end
local function decode(v) return json.decode(v) end
local function cid(src) return core:GetPlayerCharacterId(src) end
local function integer(n,lo,hi) return type(n)=='number' and n==n and n%1==0 and n>=lo and n<=hi end
local function str(v,n) return type(v)=='string' and #v>0 and #v<=n and utf8.len(v) and not v:find('%c') end
local function company(id) if type(id)=='string' then return S('SELECT * FROM fb_companies WHERE id=?',{id}) end end
local function shares(id) return Q('SELECT character_id,units FROM fb_shares WHERE company_id=? ORDER BY character_id',{id}) end
local function isOwner(id,who) return MySQL.scalar.await('SELECT units FROM fb_shares WHERE company_id=? AND character_id=?',{id,who}) end
local function employee(who) return S('SELECT e.*,r.level_no,r.wage,r.rights,r.name AS rank_name FROM fb_employees e JOIN fb_ranks r ON r.id=e.rank_id WHERE e.character_id=?',{who}) end
local function allowed(b,who,perm)
 if not b or b.status~='active' or not who then return false end
 if isOwner(b.id,who) then return true end
 local e=employee(who);return e and e.company_id==b.id and decode(e.rights)[perm]==true or false
end
local function log(id,who,a,d) Q('INSERT INTO fb_logs(company_id,actor,action,detail,created) VALUES(?,?,?,?,?)',{id,who,a,encode(d),now()}) end
local function tell(src,msg) TriggerClientEvent('frontier_business:notice',src,msg) end
local function requireThat(ok,msg) if not ok then error(msg or 'Denied',0) end end
local function bank(who) return tonumber(MySQL.scalar.await("SELECT id FROM frontier_economy_accounts WHERE owner_type='character' AND owner_id=? AND account_type='bank' AND currency='USD'",{who})) end
local function account(b) return tonumber(b.account_id) end
local function position(src) local p=GetPlayerPed(src);if p==0 or GetPlayerRoutingBucket(src)~=0 then return end;return GetEntityCoords(p) end
local function near(src,p,r) local v=position(src);return v and (v.x-p.x)^2+(v.y-p.y)^2+(v.z-p.z)^2<=r*r end
local function office(src) for _,p in ipairs(C.offices) do if near(src,p,C.officeDistance) then return true end end end
local function job(kind,p)
 local id=uuid();Q('INSERT INTO fb_jobs VALUES(?,?,?,?)',{id,kind,encode(p),now()});return id
end
local function transfer(j,from,to,amount,suffix)
 local opts={key='business:'..j..':'..(suffix or 'pay'),reason='Frontier business',reference=j}
 if to then return eco:TransferAccounts(from,to,amount,opts) end
 return eco:DebitAccount(from,amount,opts)
end
local function finish(j) U('DELETE FROM fb_jobs WHERE id=?',{j}) end
local function definite(e) return e=='insufficient_funds' end
local function tx(statements) requireThat(MySQL.transaction.await(statements),'Database transaction failed') end
local function sql(q,v) return {query=q,values=v} end
local function process(j)
 local p=decode(j.payload);local b=p.company and company(p.company)
 if j.kind=='register' then
  local ok,e=transfer(j.id,p.bank,nil,C.registration)
  if not ok then if definite(e) then finish(j.id) end;return end
  Q("INSERT IGNORE INTO frontier_economy_accounts(owner_type,owner_id,account_type,currency) VALUES('business',?,'bank','USD')",{p.id})
  local a=tonumber(MySQL.scalar.await("SELECT id FROM frontier_economy_accounts WHERE owner_type='business' AND owner_id=? AND account_type='bank'",{p.id}))
  tx({sql("INSERT IGNORE INTO fb_companies(id,name,description,account_id,status,created,next_tax,next_dividend) VALUES(?,?,?,?,'active',?,?,?)",{p.id,p.name,p.description,a,j.created,j.created+C.week,j.created+C.week}),sql('INSERT IGNORE INTO fb_shares VALUES(?,?,10000)',{p.id,p.actor}),sql('DELETE FROM fb_jobs WHERE id=?',{j.id})})
 elseif j.kind=='payroll' then
  local ok,e=transfer(j.id,p.from,p.to,p.amount)
  if not ok and not definite(e) then return end
  tx({sql('INSERT INTO fb_logs(company_id,actor,action,detail,created) VALUES(?,?,?,?,?)',{p.company,p.actor,ok and 'paycheck' or 'paycheck_skipped',encode({amount=p.amount}),now()}),sql('DELETE FROM fb_jobs WHERE id=?',{j.id})})
  for src,s in pairs(core:GetPlayers()) do if s.frontierCharacterId==p.actor then tell(src,ok and ('Paycheck received: $'..p.amount/100) or 'Paycheck skipped: insufficient company funds.') end end
 elseif j.kind=='transfer' or j.kind=='tax' or j.kind=='license' or j.kind=='share' or j.kind=='distribution' then
  if j.kind=='distribution' then
   for i,v in ipairs(p.payments) do
    if v.amount>0 then local ok,e=transfer(j.id,p.from,v.to,v.amount,tostring(i));if not ok then return end end
   end
  else
   local ok,e=transfer(j.id,p.from,p.to,p.amount)
   if not ok then
    if definite(e) then
     if p.proposal then U("UPDATE fb_proposals SET status='failed' WHERE id=?",{p.proposal}) end
     finish(j.id)
    end
    return
   end
  end
  local stm={}
  if j.kind=='license' then
   stm[#stm+1]=sql('INSERT INTO fb_licenses(owner_type,owner_id,category,active,next_tax) VALUES(?,?,?,1,?) ON DUPLICATE KEY UPDATE active=1,next_tax=VALUES(next_tax)',{p.ownerType,p.owner,p.category,now()+C.week})
  elseif j.kind=='tax' then
   if p.category then stm[#stm+1]=sql('UPDATE fb_licenses SET debt=0,overdue=NULL WHERE owner_type=? AND owner_id=? AND category=?',{p.ownerType,p.owner,p.category})
   else stm[#stm+1]=sql('UPDATE fb_companies SET debt=0,overdue=NULL WHERE id=?',{p.company}) end
  elseif j.kind=='share' then
   stm[#stm+1]=sql('UPDATE fb_shares SET units=units-? WHERE company_id=? AND character_id=? AND units>?',{p.units,p.company,p.actor,p.units})
   -- Full transfers delete the original row instead of writing zero against CHECK.
   stm[#stm+1]=sql('DELETE FROM fb_shares WHERE company_id=? AND character_id=? AND units=? AND ?=1',{p.company,p.actor,p.units,p.full and 1 or 0})
   stm[#stm+1]=sql('INSERT INTO fb_shares VALUES(?,?,?) ON DUPLICATE KEY UPDATE units=units+VALUES(units)',{p.company,p.target,p.units})
  end
  if p.withdrawal then stm[#stm+1]=sql('INSERT IGNORE INTO fb_withdrawals VALUES(?,?,?,?)',{j.id,p.company,p.day,p.amount}) end
  if p.proposal then stm[#stm+1]=sql("UPDATE fb_proposals SET status='complete' WHERE id=?",{p.proposal}) end
  if p.company then stm[#stm+1]=sql('INSERT INTO fb_logs(company_id,actor,action,detail,created) VALUES(?,?,?,?,?)',{p.company,p.actor or 'system',j.kind,encode(p),now()}) end
  stm[#stm+1]=sql('DELETE FROM fb_jobs WHERE id=?',{j.id});tx(stm)
 end
end
local function proposal(b,kind,p,actor)
 local voters={};for _,v in ipairs(shares(b.id)) do voters[v.character_id]=tonumber(v.units) end
 local id=uuid();Q('INSERT INTO fb_proposals VALUES(?,?,?,?,?,?,?,?,?)',{id,b.id,kind,encode(p),encode(voters),encode({}),'open',now(),now()+C.week});return id
end
local function distribution(b,amount,pid)
 local ok,a=eco:GetAccountBalance(account(b));requireThat(ok and amount<=a.balance_minor-tonumber(b.reserve_minor) and tonumber(b.debt)==0,'Insufficient distributable funds')
 local list=shares(b.id);local payments={};local remaining=amount
 for i,v in ipairs(list) do local n=i==#list and remaining or math.floor(amount*tonumber(v.units)/10000);remaining=remaining-n;local target=bank(v.character_id);requireThat(target,'Shareholder account unavailable');payments[#payments+1]={to=target,amount=n} end
 job('distribution',{company=b.id,from=account(b),payments=payments,proposal=pid,actor='system'})
end
local function vote(b,who,id)
 local v=S("SELECT * FROM fb_proposals WHERE id=? AND company_id=? AND status='open'",{id,b.id});requireThat(v and tonumber(v.expires)>now(),'Proposal unavailable')
 local voters,approvals,p=decode(v.voters),decode(v.approvals),decode(v.payload)
 if v.kind=='share' then requireThat(who==p.target,'Only recipient can accept');requireThat(tonumber(isOwner(b.id,p.actor) or 0)>=p.units,'Shares changed')
  local from,to=bank(who),bank(p.actor);requireThat(from and to,'Bank unavailable');p.from,p.to,p.company,p.proposal,p.full=from,to,b.id,id,tonumber(isOwner(b.id,p.actor))==p.units
  job('share',p);U("UPDATE fb_proposals SET status='executing' WHERE id=?",{id});return
 end
 requireThat(voters[who] and tonumber(isOwner(b.id,who))==voters[who],'Not an eligible voter')
 local current=shares(b.id);local count=0;for _,s in ipairs(current) do requireThat(voters[s.character_id]==tonumber(s.units),'Ownership changed');count=count+1 end
 local expected=0;for _ in pairs(voters) do expected=expected+1 end;requireThat(count==expected,'Ownership changed')
 approvals[who]=true;U('UPDATE fb_proposals SET approvals=? WHERE id=?',{encode(approvals),id})
 local units=0;for k,n in pairs(voters) do if approvals[k] then units=units+n end end
 local threshold=(v.kind=='withdraw' or v.kind=='policy' or v.kind=='dividendPolicy') and 10000 or v.kind=='close' and 7500 or 5001
 if units<threshold then return end
 if v.kind=='withdraw' then p.proposal=id;job('transfer',p)
 elseif v.kind=='dividend' then distribution(b,p.amount,id)
 elseif v.kind=='policy' then U('UPDATE fb_companies SET withdrawal_limit=?,daily_limit=? WHERE id=?',{p.limit,p.daily,b.id})
 elseif v.kind=='dividendPolicy' then U('UPDATE fb_companies SET dividend_mode=?,dividend_amount=?,reserve_minor=? WHERE id=?',{p.mode,p.amount,p.reserve,b.id})
 elseif v.kind=='close' then U("UPDATE fb_companies SET status='liquidating',liquidate_until=? WHERE id=?",{now()+C.liquidation,b.id})
 end
 U('UPDATE fb_proposals SET status=? WHERE id=?',{(v.kind=='withdraw' or v.kind=='dividend') and 'executing' or 'complete',id})
end
local function rights(input)
 local out={};for _,k in ipairs(C.permissions) do if type(input)=='table' and input[k]==true then out[k]=true end end;return out
end
local function propertyOwner(who,sid) return MySQL.scalar.await("SELECT COUNT(*) FROM fp_owners o JOIN fp_settlements s ON s.id=o.settlement_id WHERE o.character_id=? AND o.settlement_id=? AND s.status='active'",{who,sid})==1 end
local function handle(src,a,d)
 local who=cid(src);requireThat(who,'Load a character')
 local b=company(d.company)
 if a=='register' then
  requireThat(office(src),'Visit a registry office');requireThat(str(d.name,80) and str(d.description,255),'Invalid name or description')
  requireThat(not S('SELECT id FROM fb_companies WHERE name=?',{d.name}),'Name taken')
  local ok,accounts=eco:GetCharacterAccounts(src);requireThat(ok and accounts.characterId==who,'Bank unavailable')
  job('register',{actor=who,bank=accounts.bank.id,id=uuid(),name=d.name,description=d.description});return
 elseif a=='accept' then
  local v=S('SELECT * FROM fb_invites WHERE id=? AND target_id=? AND expires>?',{d.id,who,now()});requireThat(v and not employee(who),'Invitation unavailable or already employed')
  local r=S('SELECT * FROM fb_ranks WHERE id=? AND company_id=?',{v.rank_id,v.company_id});local employer=company(v.company_id)
  requireThat(r and employer and employer.status=='active' and tonumber(r.wage)==tonumber(v.wage),'Terms changed')
  tx({sql('INSERT INTO fb_employees(character_id,company_id,rank_id) VALUES(?,?,?)',{who,v.company_id,r.id}),sql('DELETE FROM fb_invites WHERE target_id=?',{who})});log(v.company_id,who,'hired',{rank=r.id});return
 elseif a=='resign' then local e=employee(who);if e then U('DELETE FROM fb_employees WHERE character_id=?',{who});log(e.company_id,who,'resigned',{}) end;return
 elseif a=='license' then
  requireThat(office(src),'Visit a registry office');local l=C.licenses[d.category];requireThat(l,'Invalid license')
  if b then requireThat(allowed(b,who,'licenses'),'Denied') end
  local typ,id,from=b and 'company' or 'character',b and b.id or who,b and account(b) or bank(who)
  requireThat(from,'Bank unavailable');local old=S('SELECT * FROM fb_licenses WHERE owner_type=? AND owner_id=? AND category=?',{typ,id,d.category});requireThat(not old or (tonumber(old.active)==0 and tonumber(old.debt)==0),'Already licensed or outstanding tax')
  job('license',{company=b and b.id,actor=who,ownerType=typ,owner=id,category=d.category,from=from,amount=l.fee});return
 elseif a=='hideReceipt' then U("UPDATE fb_receipts SET hidden=1 WHERE id=? AND owner_type='character' AND owner_id=?",{d.id,who});return
 elseif a=='grant' then
  requireThat(b and b.status=='active' and propertyOwner(who,d.property),'Property owner required')
  Q('INSERT INTO fb_locations VALUES(?,?,?,?) ON DUPLICATE KEY UPDATE grantor=VALUES(grantor),rights=VALUES(rights)',{b.id,d.property,who,encode(rights(d.rights))});return
 elseif a=='revoke' then requireThat(propertyOwner(who,d.property),'Property owner required');U('DELETE FROM fb_locations WHERE company_id=? AND property_id=?',{d.company,d.property});return
 end
 requireThat(b and b.status=='active','Company unavailable')
 if a=='vote' then vote(b,who,d.id);return end
 if a=='deposit' then
  requireThat(isOwner(b.id,who) and integer(d.amount,1,100000000),'Invalid deposit')
  local from=bank(who);requireThat(from,'Bank unavailable');job('transfer',{company=b.id,actor=who,from=from,to=account(b),amount=d.amount})
 elseif a=='withdraw' then
  requireThat(allowed(b,who,'withdraw') and integer(d.amount,1,100000000),'Denied')
  local to=bank(who);requireThat(to,'Bank unavailable');local day=math.floor(now()/86400)
  local p={company=b.id,actor=who,from=account(b),to=to,amount=d.amount,withdrawal=true,day=day}
  local count=tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM fb_withdrawals WHERE company_id=? AND day_no=?',{b.id,day}))
  if d.amount>tonumber(b.withdrawal_limit) or count>=tonumber(b.daily_limit) then proposal(b,'withdraw',p,who) else job('transfer',p) end
 elseif a=='policy' then
  requireThat(isOwner(b.id,who) and integer(d.limit,0,100000000) and integer(d.daily,0,100),'Invalid policy');proposal(b,'policy',{limit=d.limit,daily=d.daily},who)
 elseif a=='dividendPolicy' then
  requireThat(isOwner(b.id,who) and ({manual=true,fixed=true,percentage=true,disabled=true})[d.mode] and integer(d.amount,0,d.mode=='percentage' and 10000 or 100000000) and integer(d.reserve,0,100000000),'Invalid policy');proposal(b,'dividendPolicy',{mode=d.mode,amount=d.amount,reserve=d.reserve},who)
 elseif a=='dividend' then requireThat(isOwner(b.id,who) and integer(d.amount,1,100000000),'Denied');proposal(b,'dividend',{amount=d.amount},who)
 elseif a=='close' then requireThat(isOwner(b.id,who),'Denied');proposal(b,'close',{},who)
 elseif a=='share' then
  local n=tonumber(isOwner(b.id,who) or 0);requireThat(integer(d.units,1,n) and integer(d.amount,1,100000000),'Invalid share offer')
  local target=cid(tonumber(d.target) or 0);requireThat(target and target~=who,'Target unavailable');proposal(b,'share',{actor=who,target=target,units=d.units,amount=d.amount},who)
 elseif a=='rank' then
  requireThat(allowed(b,who,'ranks') and str(d.name,60) and integer(d.level,1,1000) and integer(d.wage,0,100000),'Invalid rank')
  local r=rights(d.rights);if not isOwner(b.id,who) then local e=employee(who);requireThat(e and tonumber(e.level_no)>d.level,'Rank too high');for k in pairs(r) do requireThat(allowed(b,who,k),'Cannot grant permission') end end
  Q('INSERT INTO fb_ranks VALUES(?,?,?,?,?,?)',{uuid(),b.id,d.name,d.level,d.wage,encode(r)})
 elseif a=='hire' then
  requireThat(allowed(b,who,'hire'),'Denied');local target=cid(tonumber(d.target) or 0)
  local r=S('SELECT * FROM fb_ranks WHERE id=? AND company_id=?',{d.rank,b.id});requireThat(target and r and not employee(target),'Unavailable')
  if not isOwner(b.id,who) then local e=employee(who);requireThat(tonumber(e.level_no)>tonumber(r.level_no),'Rank too high') end
  Q('INSERT INTO fb_invites VALUES(?,?,?,?,?,?)',{uuid(),b.id,target,r.id,r.wage,now()+86400})
 elseif a=='fire' then
  requireThat(allowed(b,who,'hire'),'Denied');local e=employee(d.target);requireThat(e and e.company_id==b.id,'Employee missing')
  if not isOwner(b.id,who) then requireThat(tonumber(employee(who).level_no)>tonumber(e.level_no),'Rank too high') end
  U('DELETE FROM fb_employees WHERE character_id=?',{d.target});log(b.id,who,'dismissed',{target=d.target})
 elseif a=='payTax' then requireThat(allowed(b,who,'finance') and tonumber(b.debt)>0,'No tax due');job('tax',{company=b.id,actor=who,from=account(b),amount=tonumber(b.debt)})
 else error('Unknown action',0) end
end
local function view(src)
 local who=cid(src);if not who then return end
 local list=Q([[SELECT DISTINCT c.* FROM fb_companies c LEFT JOIN fb_shares s ON s.company_id=c.id LEFT JOIN fb_employees e ON e.company_id=c.id WHERE s.character_id=? OR e.character_id=?]],{who,who})
 for _,b in ipairs(list) do
  b.owner=isOwner(b.id,who)~=nil;b.ranks=Q('SELECT * FROM fb_ranks WHERE company_id=?',{b.id})
  b.shares=shares(b.id);b.employees=Q('SELECT character_id,rank_id FROM fb_employees WHERE company_id=?',{b.id})
  b.proposals=Q("SELECT * FROM fb_proposals WHERE company_id=? AND status='open'",{b.id})
  b.rights={};for _,k in ipairs(C.permissions) do b.rights[k]=allowed(b,who,k) end
  if b.owner or b.rights.finance then local ok,v=eco:GetAccountBalance(account(b));if ok then b.balance=v.balance_minor end end
  if b.owner or b.rights.logs then b.logs=Q('SELECT * FROM fb_logs WHERE company_id=? ORDER BY id DESC LIMIT 100',{b.id}) end
 end
 local invites=Q('SELECT * FROM fb_invites WHERE target_id=? AND expires>?',{who,now()})
 local offers={};for _,v in ipairs(Q("SELECT * FROM fb_proposals WHERE kind='share' AND status='open' AND expires>?",{now()})) do if decode(v.payload).target==who then offers[#offers+1]=v end end
 TriggerClientEvent('frontier_business:view',src,{companies=list,invites=invites,offers=offers,office=office(src)==true,licenses=C.licenses,permissions=C.permissions,personal=Q("SELECT * FROM fb_licenses WHERE owner_type='character' AND owner_id=?",{who}),receipts=Q("SELECT * FROM fb_receipts WHERE owner_type='character' AND owner_id=? AND hidden=0 ORDER BY created DESC LIMIT 100",{who})})
end
local function run(fn,src)
 if not ready or busy then if src then tell(src,'Business busy, retry shortly.') end;return end
 busy=true;local ok,e=pcall(fn);busy=false;if not ok then print('[frontier_business] '..tostring(e));if src then tell(src,tostring(e)) end end
end
RegisterNetEvent('frontier_business:open',function() local src=source;run(function() view(src) end,src) end)
RegisterNetEvent('frontier_business:action',function(a,d) local src=source;if type(a)~='string' or type(d)~='table' then return end;run(function() requireThat(not S('SELECT id FROM fb_jobs LIMIT 1'),'A transaction is pending');handle(src,a,d);tell(src,'Request accepted.');view(src) end,src) end)
local function tick()
 local t=now()
 for _,b in ipairs(Q("SELECT * FROM fb_companies WHERE status='active' AND next_tax<=?",{t})) do
  local periods=math.floor((t-tonumber(b.next_tax))/C.week)+1;U('UPDATE fb_companies SET debt=debt+?,overdue=COALESCE(overdue,?),next_tax=next_tax+? WHERE id=?',{C.baseTax*periods,b.next_tax,periods*C.week,b.id})
 end
 for _,l in ipairs(Q('SELECT * FROM fb_licenses WHERE active=1 AND next_tax<=?',{t})) do
  local periods=math.floor((t-tonumber(l.next_tax))/C.week)+1;local fee=C.licenses[l.category].tax
  U('UPDATE fb_licenses SET debt=debt+?,overdue=COALESCE(overdue,?),next_tax=next_tax+? WHERE owner_type=? AND owner_id=? AND category=?',{fee*periods,l.next_tax,periods*C.week,l.owner_type,l.owner_id,l.category})
 end
 for _,b in ipairs(Q("SELECT * FROM fb_companies WHERE status='active' AND debt>0")) do
  local ok,v=eco:GetAccountBalance(account(b));if ok and v.balance_minor>=tonumber(b.debt) then job('tax',{company=b.id,from=account(b),amount=tonumber(b.debt)});return
  elseif tonumber(b.overdue)+C.grace<=t then U("UPDATE fb_companies SET status='liquidating',liquidate_until=? WHERE id=?",{t+C.liquidation,b.id}) end
 end
 for _,l in ipairs(Q('SELECT * FROM fb_licenses WHERE active=1 AND debt>0')) do
  local b=l.owner_type=='company' and company(l.owner_id);local from=b and account(b) or l.owner_type=='character' and bank(l.owner_id)
  if from and (not b or b.status=='active') then local ok,v=eco:GetAccountBalance(from);if ok and v.balance_minor>=tonumber(l.debt) then job('tax',{company=b and b.id,ownerType=l.owner_type,owner=l.owner_id,category=l.category,from=from,amount=tonumber(l.debt)});return end end
  if tonumber(l.overdue)+C.grace<=t then U('UPDATE fb_licenses SET active=0 WHERE owner_type=? AND owner_id=? AND category=?',{l.owner_type,l.owner_id,l.category});if b and b.status=='active' then U("UPDATE fb_companies SET status='liquidating',liquidate_until=? WHERE id=?",{t+C.liquidation,b.id}) end end
 end
 for _,b in ipairs(Q("SELECT * FROM fb_companies WHERE status='liquidating'")) do
  U('DELETE FROM fb_employees WHERE company_id=?',{b.id});U('UPDATE fb_licenses SET active=0 WHERE owner_type=? AND owner_id=?',{'company',b.id})
  -- Do not erase assets until storage liquidation and final accounting are implemented.
 end
 for _,b in ipairs(Q("SELECT * FROM fb_companies WHERE status='active' AND next_dividend<=?",{t})) do
  U('UPDATE fb_companies SET next_dividend=? WHERE id=?',{t+C.week,b.id})
  if b.dividend_mode=='fixed' or b.dividend_mode=='percentage' then local ok,v=eco:GetAccountBalance(account(b));if ok then local surplus=math.max(0,v.balance_minor-tonumber(b.reserve_minor));local n=b.dividend_mode=='fixed' and math.min(surplus,tonumber(b.dividend_amount)) or math.floor(surplus*tonumber(b.dividend_amount)/10000);if n>0 and tonumber(b.debt)==0 then distribution(b,n);return end end end
 end
end
local function payroll()
 for _,p in pairs(core:GetPlayers()) do
  local who=p.frontierCharacterId;local e=employee(who)
  if e then local b=company(e.company_id);if b and b.status=='active' then
   local seconds=tonumber(e.seconds_online)+10
   if seconds>=C.payInterval then
    local wage=tonumber(e.wage);local to=bank(who)
    if wage>0 and to then local id=uuid();tx({sql('UPDATE fb_employees SET seconds_online=?,pay_seq=pay_seq+1 WHERE character_id=?',{seconds-C.payInterval,who}),sql('INSERT INTO fb_jobs VALUES(?,?,?,?)',{id,'payroll',encode({company=b.id,actor=who,from=account(b),to=to,amount=wage}),now()})})
    else U('UPDATE fb_employees SET seconds_online=? WHERE character_id=?',{seconds-C.payInterval,who}) end
   else U('UPDATE fb_employees SET seconds_online=? WHERE character_id=?',{seconds,who}) end
  end end
 end
end
MySQL.ready(function()
 requireThat(S('SELECT COUNT(*) AS n FROM fb_companies'),'Apply business migration');ready=true
 CreateThread(function() while true do Wait(1000);run(function() local j=S('SELECT * FROM fb_jobs ORDER BY created,id LIMIT 1');if j then process(j) else tick() end end) end end)
 CreateThread(function() while true do Wait(10000);run(payroll) end end)
end)
exports('HasCompanyPermission',function(id,who,perm) return ready and allowed(company(id),who,perm) or false end)
exports('CanUseProperty',function(id,who,sid,perm)
 if not ready or not allowed(company(id),who,perm) then return false end
 local g=S('SELECT * FROM fb_locations WHERE company_id=? AND property_id=?',{id,sid});return g and propertyOwner(g.grantor,sid) and decode(g.rights)[perm]==true or false
end)
exports('GetCompanyAccount',function(id,who,perm) local b=company(id);if ready and allowed(b,who,perm) then return account(b) end end)
exports('VerifyLicense',function(typ,id,category) local l=ready and S('SELECT * FROM fb_licenses WHERE owner_type=? AND owner_id=? AND category=?',{typ,id,category});return l and tonumber(l.active)==1 or false end)
