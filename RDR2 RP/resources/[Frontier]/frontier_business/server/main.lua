local C=BusinessConfig
local core,eco,inv=exports.frontier_core,exports.frontier_economy,exports.frontier_inventory
local Q,U,S=MySQL.query.await,MySQL.update.await,MySQL.single.await
local ready,busy=false,false
local sessions={}
local fixtureAction,fixtureView,retailStep,fixtureInfo,receipt,tradeReceipts,tradeAction,tradeView,liquidate,stockView
local function now() return os.time() end
local function uuid()
 -- Keep UUID() as text across oxmysql's MySQL driver; CHAR()/SPACE() in
 -- the previous SQL expression produced a binary Buffer instead of a string.
 local raw=MySQL.scalar.await('SELECT UUID()')
 if type(raw)~='string' then error('Business UUID unavailable: expected SQL text',0) end
 local id=raw:gsub('-',''):lower()
 if #id~=32 or not id:match('^[a-f0-9]+$') then error('Invalid business UUID',0) end
 return id
end
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
local function job(kind,p,extra)
 local id=uuid();local statements={{query='INSERT INTO fb_jobs(id,kind,payload,created) VALUES(?,?,?,?)',values={id,kind,encode(p),now()}}}
 if p.proposal then statements[#statements+1]={query="UPDATE fb_proposals SET status='executing' WHERE id=? AND status='open'",values={p.proposal}} end
 for _,v in ipairs(extra or {}) do statements[#statements+1]=v end
 requireThat(MySQL.transaction.await(statements),'Could not persist operation');return id
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
local function archiveStatements(id)
 return {sql("UPDATE fb_companies SET status='archived',archived_at=? WHERE id=? AND status='liquidating'",{now(),id}),sql("DELETE p FROM fb_prices p JOIN fb_fixtures f ON f.id=p.fixture_id WHERE f.owner_type='company' AND f.owner_id=?",{id}),sql("DELETE FROM fb_fixtures WHERE owner_type='company' AND owner_id=?",{id}),sql('DELETE FROM fb_locations WHERE company_id=?',{id}),sql('DELETE FROM fb_invites WHERE company_id=?',{id}),sql("UPDATE fb_proposals SET status='expired' WHERE company_id=? AND status='open'",{id})}
end
local function process(j)
 local p=decode(j.payload);local b=p.company and company(p.company)
 if j.kind=='register' then
  local ok,e=transfer(j.id,p.bank,nil,p.fee or C.registration)
  if not ok then if definite(e) then finish(j.id) end;return end
  Q("INSERT IGNORE INTO frontier_economy_accounts(owner_type,owner_id,account_type,currency) VALUES('business',?,'bank','USD')",{p.id})
  local a=tonumber(MySQL.scalar.await("SELECT id FROM frontier_economy_accounts WHERE owner_type='business' AND owner_id=? AND account_type='bank'",{p.id}))
  tx({sql("INSERT INTO fb_companies(id,name,description,account_id,status,created,next_tax,next_dividend) VALUES(?,?,?,?,'active',?,?,?)",{p.id,p.name,p.description,a,j.created,j.created+C.week,j.created+C.week}),sql('INSERT INTO fb_shares VALUES(?,?,10000)',{p.id,p.actor}),sql('DELETE FROM fb_jobs WHERE id=?',{j.id})})
 elseif j.kind=='payroll' then
  local ok,e=eco:TransferBusinessBatch(j.id,p.from,{{to=p.to,amount=p.amount}},0,true)
  if not ok and not definite(e) and e~='balance_limit' then return end
  tx({sql('INSERT INTO fb_logs(company_id,actor,action,detail,created) VALUES(?,?,?,?,?)',{p.company,p.actor,ok and 'paycheck' or 'paycheck_skipped',encode({amount=p.amount,reason=not ok and e or nil,operation=j.id}),now()}),sql('DELETE FROM fb_jobs WHERE id=?',{j.id})})
  for src,s in pairs(core:GetPlayers()) do if s.frontierCharacterId==p.actor then tell(s.source or src,ok and ('Paycheck received: '..string.format('%.2f USD',p.amount/100)) or ('Paycheck skipped: '..tostring(e))) end end
 elseif j.kind=='transfer' or j.kind=='tax' or j.kind=='license' or j.kind=='share' or j.kind=='distribution' or j.kind=='finalTax' then
  if j.kind=='distribution' then
   local ok,e=eco:TransferBusinessBatch(j.id,p.from,p.payments,p.reserve or 0,false)
   if not ok then
    if not p.closing and (definite(e) or e=='balance_limit') then
     local failed={sql('INSERT INTO fb_logs(company_id,actor,action,detail,created) VALUES(?,?,?,?,?)',{p.company,'system','distribution_failed',encode({operation=j.id,reason=e}),now()}),sql('DELETE FROM fb_jobs WHERE id=?',{j.id})}
     if p.proposal then failed[#failed+1]=sql("UPDATE fb_proposals SET status='failed' WHERE id=?",{p.proposal}) end
     tx(failed)
    end
    return
   end
  else
   local ok,e=transfer(j.id,p.from,p.to,p.amount)
   if not ok then
    if definite(e) or e=='balance_limit' then
     local failed={sql('DELETE FROM fb_jobs WHERE id=?',{j.id})}
     if p.proposal then failed[#failed+1]=sql("UPDATE fb_proposals SET status='failed' WHERE id=?",{p.proposal}) end
     if p.company then failed[#failed+1]=sql('INSERT INTO fb_logs(company_id,actor,action,detail,created) VALUES(?,?,?,?,?)',{p.company,p.actor or 'system',j.kind..'_failed',encode({operation=j.id,reason=e}),now()}) end
     tx(failed)
    end
    return
   end
  end
  local stm={}
  if j.kind=='finalTax' then
   stm[#stm+1]=sql('UPDATE fb_companies SET final_tax_settled=1,final_tax_paid=? WHERE id=?',{p.amount,p.company})
  elseif j.kind=='distribution' and p.closing then
   for _,v in ipairs(archiveStatements(p.company)) do stm[#stm+1]=v end
  elseif j.kind=='license' then
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
  if j.kind=='distribution' and p.closing then stm[#stm+1]=sql('INSERT INTO fb_logs(company_id,actor,action,detail,created) VALUES(?,?,?,?,?)',{p.company,'government','archived',encode({taxPaid=tonumber(b.final_tax_paid),uncollectedTax=math.max(0,tonumber(b.debt)+tonumber(MySQL.scalar.await("SELECT COALESCE(SUM(debt),0) FROM fb_licenses WHERE owner_type=\'company\' AND owner_id=?",{p.company}) or 0)-tonumber(b.final_tax_paid))}),now()}) end
  if p.proposal then stm[#stm+1]=sql("UPDATE fb_proposals SET status='complete' WHERE id=?",{p.proposal}) end
  if p.company then stm[#stm+1]=sql('INSERT INTO fb_logs(company_id,actor,action,detail,created) VALUES(?,?,?,?,?)',{p.company,p.actor or 'system',j.kind,encode(p),now()}) end
  stm[#stm+1]=sql('DELETE FROM fb_jobs WHERE id=?',{j.id});tx(stm)
 end
end
local function proposal(b,kind,p,actor)
 local voters={};for _,v in ipairs(shares(b.id)) do voters[v.character_id]=tonumber(v.units) end
 local id=uuid();Q('INSERT INTO fb_proposals VALUES(?,?,?,?,?,?,?,?,?)',{id,b.id,kind,encode(p),encode(voters),encode({}),'open',now(),now()+C.week});return id
end
local function totalDebt(b)
 return tonumber(b.debt)+tonumber(MySQL.scalar.await("SELECT COALESCE(SUM(debt),0) FROM fb_licenses WHERE owner_type='company' AND owner_id=?",{b.id}) or 0)
end
local function distribution(b,amount,pid,schedule,closing)
 local reserve=closing and 0 or tonumber(b.reserve_minor)
 local ok,a=eco:GetAccountBalance(account(b));requireThat(ok and integer(amount,1,9000000000000) and amount<=a.balance_minor-reserve and (closing or totalDebt(b)==0),'Insufficient distributable funds or unpaid tax')
 local list=shares(b.id);local payments={};local remaining=amount;local units=0
 for _,v in ipairs(list) do units=units+tonumber(v.units) end
 requireThat(units==10000,'Invalid share ledger')
 for i,v in ipairs(list) do
  local n=i==#list and remaining or (math.tointeger(amount)*math.tointeger(v.units))//10000;remaining=remaining-n
  if n>0 then local target=bank(v.character_id);requireThat(target,'Shareholder account unavailable');payments[#payments+1]={to=target,amount=n} end
 end
 local extra=schedule and {sql('UPDATE fb_companies SET next_dividend=? WHERE id=?',{schedule,b.id})} or nil
 job('distribution',{company=b.id,from=account(b),payments=payments,reserve=reserve,proposal=pid,actor='system',closing=closing==true},extra)
end
local function vote(b,who,id)
 local v=S("SELECT * FROM fb_proposals WHERE id=? AND company_id=? AND status='open'",{id,b.id});requireThat(v and tonumber(v.expires)>now(),'Proposal unavailable')
 local voters,approvals,p=decode(v.voters),decode(v.approvals),decode(v.payload)
 if v.kind=='share' then requireThat(who==p.target,'Only recipient can accept');requireThat(tonumber(isOwner(b.id,p.actor) or 0)>=p.units,'Shares changed')
  local from,to=bank(who),bank(p.actor);requireThat(from and to,'Bank unavailable');p.from,p.to,p.company,p.proposal,p.full=from,to,b.id,id,tonumber(isOwner(b.id,p.actor))==p.units
  job('share',p);return
 end
 requireThat(voters[who] and tonumber(isOwner(b.id,who))==voters[who],'Not an eligible voter')
 local current=shares(b.id);local count=0;for _,s in ipairs(current) do requireThat(voters[s.character_id]==tonumber(s.units),'Ownership changed');count=count+1 end
 local expected=0;for _ in pairs(voters) do expected=expected+1 end;requireThat(count==expected,'Ownership changed')
 approvals[who]=true;U('UPDATE fb_proposals SET approvals=? WHERE id=?',{encode(approvals),id})
 local units=0;for k,n in pairs(voters) do if approvals[k] then units=units+n end end
 local threshold=(v.kind=='withdraw' or v.kind=='policy' or v.kind=='dividendPolicy') and 10000 or v.kind=='close' and 7500 or 5001
 if units<threshold then return end
 if v.kind=='withdraw' then p.proposal=id;p.day=math.floor(now()/86400);job('transfer',p);return
 elseif v.kind=='dividend' then distribution(b,p.amount,id);return
 end
 local update
 if v.kind=='policy' then update=sql('UPDATE fb_companies SET withdrawal_limit=?,daily_limit=? WHERE id=?',{p.limit,p.daily,b.id})
 elseif v.kind=='dividendPolicy' then update=sql('UPDATE fb_companies SET dividend_mode=?,dividend_amount=?,reserve_minor=? WHERE id=?',{p.mode,p.amount,p.reserve,b.id})
 elseif v.kind=='close' then update=sql("UPDATE fb_companies SET status='liquidating',liquidate_until=? WHERE id=?",{now()+C.liquidation,b.id}) end
 requireThat(update,'Unknown proposal')
 tx({update,sql("UPDATE fb_proposals SET status='complete' WHERE id=?",{id})})
end
local function rights(input)
 local out={};for _,k in ipairs(C.permissions) do if type(input)=='table' and input[k]==true then out[k]=true end end;return out
end
local function propertyOwner(who,sid) return tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM fp_owners o JOIN fp_settlements s ON s.id=o.settlement_id WHERE o.character_id=? AND o.settlement_id=? AND s.status='active'",{who,sid}))==1 end
local function handle(src,a,d)
 local who=cid(src);requireThat(who,'Load a character')
 if fixtureAction and fixtureAction(src,who,a,d) then return end
 if a=='trade' then return tradeAction(src,who,d) end
 local b=company(d.company)
 if a=='register' then
  requireThat(office(src),'Visit a registry office');requireThat(str(d.name,80) and str(d.description,255),'Invalid name or description')
  requireThat(not S('SELECT id FROM fb_companies WHERE name=?',{d.name}),'Name taken')
  local ok,accounts=eco:GetCharacterAccounts(src);requireThat(ok and accounts.characterId==who,'Bank unavailable')
  job('register',{actor=who,bank=accounts.bank.id,id=uuid(),name=d.name,description=d.description,fee=C.registration});return
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
 elseif a=='hideReceipt' then if b then requireThat(allowed(b,who,'logs'),'Denied');U("UPDATE fb_receipts SET hidden=1 WHERE id=? AND owner_type='company' AND owner_id=?",{d.id,b.id}) else U("UPDATE fb_receipts SET hidden=1 WHERE id=? AND owner_type='character' AND owner_id=?",{d.id,who}) end;return
 elseif a=='grant' then
  requireThat(b and b.status=='active','Select an active company')
  requireThat(type(d.property)=='string' and #d.property==32,'Select a settlement')
  requireThat(propertyOwner(who,d.property),'You must personally own this settlement')
  local grant={};for _,k in ipairs({'stock','retail','farm','production'}) do if type(d.rights)=='table' and d.rights[k]==true then grant[k]=true end end
  requireThat(next(grant),'Select at least one usage right')
  tx({sql('INSERT INTO fb_locations(company_id,property_id,grantor,rights) VALUES(?,?,?,?) ON DUPLICATE KEY UPDATE grantor=VALUES(grantor),rights=VALUES(rights)',{b.id,d.property,who,encode(grant)}),sql('INSERT INTO fb_logs(company_id,actor,action,detail,created) VALUES(?,?,?,?,?)',{b.id,who,'plot_granted',encode({property=d.property,rights=grant}),now()})})
  return 'Property usage rights saved.'
 elseif a=='revoke' then
  requireThat(b and type(d.property)=='string' and #d.property==32,'Select a settlement and company')
  requireThat(propertyOwner(who,d.property),'You must personally own this settlement')
  local count=U('DELETE FROM fb_locations WHERE company_id=? AND property_id=?',{b.id,d.property})
  requireThat(count==1,'No existing grant for this settlement')
  log(b.id,who,'plot_revoked',{property=d.property});return 'Property usage rights revoked.'
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
  requireThat(target,'Player ID not online or no character loaded')
  requireThat(type(d.rank)=='string' and #d.rank==32,'Create and select an employee rank first')
  local r=S('SELECT * FROM fb_ranks WHERE id=? AND company_id=?',{d.rank,b.id});requireThat(r,'Selected rank does not exist in this company');requireThat(not employee(target),'Target already has an active employment')
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
 if sessions[src] and sessions[src].fixture then return fixtureView(src,sessions[src].property,sessions[src].fixture) end
 local list=Q([[SELECT DISTINCT c.* FROM fb_companies c LEFT JOIN fb_shares s ON s.company_id=c.id LEFT JOIN fb_employees e ON e.company_id=c.id WHERE s.character_id=? OR e.character_id=?]],{who,who})
 for _,b in ipairs(list) do
  b.owner=isOwner(b.id,who)~=nil;b.ranks=Q('SELECT * FROM fb_ranks WHERE company_id=?',{b.id})
  b.licenses=Q("SELECT * FROM fb_licenses WHERE owner_type='company' AND owner_id=?",{b.id});b.locations=Q('SELECT * FROM fb_locations WHERE company_id=?',{b.id});b.receipts=(b.owner or allowed(b,who,'logs')) and Q("SELECT * FROM fb_receipts WHERE owner_type='company' AND owner_id=? AND hidden=0 ORDER BY created DESC LIMIT 100",{b.id}) or {};b.shares=shares(b.id);b.employees=Q('SELECT character_id,rank_id FROM fb_employees WHERE company_id=?',{b.id})
  b.proposals=Q("SELECT * FROM fb_proposals WHERE company_id=? AND status='open'",{b.id})
  b.rights={};for _,k in ipairs(C.permissions) do b.rights[k]=allowed(b,who,k) end
  if b.owner or b.rights.trade then tradeView(b,who) end
  if b.owner or b.rights.stock then stockView(b,who) end
  if b.owner or b.rights.finance then local ok,v=eco:GetAccountBalance(account(b));if ok then b.balance=v.balance_minor end end
  if b.owner or b.rights.logs then b.logs=Q('SELECT * FROM fb_logs WHERE company_id=? ORDER BY id DESC LIMIT 100',{b.id}) end
 end
 local invites=Q('SELECT * FROM fb_invites WHERE target_id=? AND expires>?',{who,now()})
 local offers={};for _,v in ipairs(Q("SELECT * FROM fb_proposals WHERE kind='share' AND status='open' AND expires>?",{now()})) do if decode(v.payload).target==who then offers[#offers+1]=v end end
 TriggerClientEvent('frontier_business:view',src,{plots=exports.frontier_property:GetOwnedPlots(who),companies=list,invites=invites,orders=Q("SELECT * FROM fb_retail WHERE buyer=? AND state='paid'",{who}),offers=offers,office=office(src)==true,licenses=C.licenses,permissions=C.permissions,personal=Q("SELECT * FROM fb_licenses WHERE owner_type='character' AND owner_id=?",{who}),receipts=Q("SELECT * FROM fb_receipts WHERE owner_type='character' AND owner_id=? AND hidden=0 ORDER BY created DESC LIMIT 100",{who})})
end
local function run(fn,src)
 if not ready or busy then if src then tell(src,'Business busy, retry shortly.') end;return end
 busy=true;local ok,e=pcall(fn);busy=false;if not ok then print('[frontier_business] '..tostring(e));if src then tell(src,tostring(e)) end end
end
RegisterNetEvent('frontier_business:open',function() local src=source;sessions[src]=nil;run(function() view(src) end,src) end)
local function actionResult(src,request,action,ok,message)
 TriggerClientEvent('frontier_business:result',src,{request=request,action=action,ok=ok,message=message})
end
RegisterNetEvent('frontier_business:refresh',function()
 local src=source;run(function() view(src) end,src)
end)
RegisterNetEvent('frontier_business:action',function(a,d,request)
 local src=source
 if type(a)~='string' or #a>40 or type(d)~='table' or type(request)~='number' or request%1~=0 or request<1 or request>2147483647 then return end
 if not ready or busy then actionResult(src,request,a,false,'Business is busy. Please try again.');return end
 busy=true
 local ok,message=pcall(function()
  requireThat(not S('SELECT id FROM fb_jobs LIMIT 1'),'A financial transaction is pending. Try again shortly.')
  return handle(src,a,d)
 end)
 if not ok then print('[frontier_business] action='..a..' '..tostring(message)) end
 local queued=ok and ({register=true,license=true,deposit=true,withdraw=true,vote=true,payTax=true,fixtureBuy=true,trade=true})[a]
 actionResult(src,request,a,ok,ok and (type(message)=='string' and message or queued and 'Request accepted. Refresh to check the final result.' or 'Changes saved.') or tostring(message))
 if ok and a~='fixtureStock' and a~='recoverFixture' then
  local loaded,issue=pcall(view,src);if not loaded then print('[frontier_business] snapshot: '..tostring(issue));tell(src,'Action accepted, but refresh failed.') end
 end
 busy=false
end)
local function tick()
 local t=now();tradeReceipts()
 U("UPDATE fb_proposals SET status='expired' WHERE status='open' AND expires<=?",{t})
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
  if liquidate(b,t) then return end
 end
 for _,b in ipairs(Q("SELECT * FROM fb_companies WHERE status='active' AND next_dividend<=?",{t})) do
  local schedule=t+C.week
  if b.dividend_mode=='fixed' or b.dividend_mode=='percentage' then
   local ok,v=eco:GetAccountBalance(account(b));if not ok then return end
   local surplus=math.max(0,v.balance_minor-tonumber(b.reserve_minor));local n=b.dividend_mode=='fixed' and math.min(surplus,tonumber(b.dividend_amount)) or (math.tointeger(surplus)*math.tointeger(b.dividend_amount))//10000
   if n>0 and totalDebt(b)==0 then distribution(b,n,nil,schedule,false);return end
  end
  U('UPDATE fb_companies SET next_dividend=? WHERE id=?',{schedule,b.id})
 end
end
local function payroll()
 for _,p in pairs(core:GetPlayers()) do
  local who=p.frontierCharacterId;local e=employee(who)
  if e then local b=company(e.company_id);if b and b.status=='active' then
   local seconds=tonumber(e.seconds_online)+10
   if seconds>=C.payInterval then
    local wage=tonumber(e.wage);local to=bank(who)
    if wage>0 and to then local id=uuid();tx({sql('UPDATE fb_employees SET seconds_online=?,pay_seq=pay_seq+1 WHERE character_id=?',{seconds-C.payInterval,who}),sql('INSERT INTO fb_jobs(id,kind,payload,created) VALUES(?,?,?,?)',{id,'payroll',encode({company=b.id,actor=who,from=account(b),to=to,amount=wage}),now()})})
    else U('UPDATE fb_employees SET seconds_online=? WHERE character_id=?',{seconds-C.payInterval,who}) end
   else U('UPDATE fb_employees SET seconds_online=? WHERE character_id=?',{seconds,who}) end
  end end
 end
end
MySQL.ready(function()
 requireThat(S('SELECT COUNT(*) AS n FROM fb_companies'),'Apply business migration');ready=true
 CreateThread(function()
  local maintenance=0
  while true do Wait(1000);run(function()
   local j=S('SELECT * FROM fb_jobs ORDER BY created,id LIMIT 1')
   if j then process(j);return end
   local sale=S("SELECT * FROM fb_retail WHERE state IN ('reserve','payment','return') AND retry_at<=? ORDER BY retry_at,created,id LIMIT 1",{now()})
   if sale then
    local ok,e=pcall(retailStep,sale)
    U('UPDATE fb_retail SET retry_at=? WHERE id=? AND state=?',{now()+10,sale.id,sale.state})
    if not ok then print('[frontier_business] retail recovery '..sale.id..': '..tostring(e)) end
   end
   if now()>=maintenance then maintenance=now()+5;tick() end
  end) end
 end)
 CreateThread(function() while true do Wait(10000);run(payroll) end end)
end)
exports('HasCompanyPermission',function(id,who,perm) return ready and allowed(company(id),who,perm) or false end)
exports('CanUseProperty',function(id,who,sid,perm)
 if not ready or not allowed(company(id),who,perm) then return false end
 local g=S('SELECT * FROM fb_locations WHERE company_id=? AND property_id=?',{id,sid});return g and propertyOwner(g.grantor,sid) and decode(g.rights)[perm]==true or false
end)
exports('GetCompanyAccount',function(id,who,perm) local b=company(id);if ready and allowed(b,who,perm) then return account(b) end end)
exports('VerifyLicense',function(typ,id,category) local l=ready and S('SELECT * FROM fb_licenses WHERE owner_type=? AND owner_id=? AND category=?',{typ,id,category});return l and tonumber(l.active)==1 or false end)

-- Physical fixtures are ordinary Property furniture; only their stock and commercial ownership live here.
local function fixture(id) if type(id)=='string' then return S('SELECT * FROM fb_fixtures WHERE id=?',{id}) end end
local function fixturePosition(sid,id) return exports.frontier_property:GetBusinessFixture(sid,id) end
local function validFixture(f)
 if not f then return end
 local p=fixturePosition(f.property_id,f.id);if not p or not propertyOwner(f.grantor,f.property_id) then return end
 if f.owner_type=='company' then
  local b=company(f.owner_id);local g=S('SELECT * FROM fb_locations WHERE company_id=? AND property_id=?',{f.owner_id,f.property_id})
  if not b or b.status~='active' or not g or not propertyOwner(g.grantor,f.property_id) or not decode(g.rights)[f.kind=='counter' and 'retail' or 'stock'] then return end
 end
 return p
end
local function fixtureRight(f,who,perm)
 if f.owner_type=='character' then return f.owner_id==who end
 local b=company(f.owner_id)
 if b and b.status=='liquidating' then return (perm=='retrieve' or perm=='stock') and isOwner(b.id,who)~=nil end
 return allowed(b,who,perm)
end
local function stock(f)
 local ok,v=inv:GetStorageContents('business_'..f.id);requireThat(ok,'Stock unavailable')
 local items={};for _,s in pairs(v.slots or {}) do if s.item or s.itemId or s.item_id then local k=s.item or s.itemId or s.item_id;items[k]=(items[k] or 0)+tonumber(s.quantity or 0) end end
 return items
end
receipt=function(typ,id,ref,detail)
 Q('INSERT IGNORE INTO fb_receipts(id,owner_type,owner_id,reference_id,detail,created) VALUES(?,?,?,?,?,?)',{uuid(),typ,id,ref,encode(detail),now()})
end
fixtureView=function(src,sid,id)
 local who=cid(src);local p=fixturePosition(sid,id)
 requireThat(who and p and near(src,p,C.storageDistance),'Approach fixture')
 local f=fixture(id);local canSetup=propertyOwner(who,sid)
 local options={}
 if canSetup then for _,b in ipairs(Q("SELECT c.id,c.name FROM fb_companies c JOIN fb_locations l ON c.id=l.company_id WHERE l.property_id=? AND c.status='active'",{sid})) do if allowed(company(b.id),who,'locations') then options[#options+1]=b end end end
 local products={}
 if f and validFixture(f) then local quantities=stock(f);for _,r in ipairs(Q('SELECT * FROM fb_prices WHERE fixture_id=?',{id})) do products[#products+1]={item=r.item_id,price=r.price,quantity=quantities[r.item_id] or 0} end end
 TriggerClientEvent('frontier_business:view',src,{fixture={id=id,property=sid,kind=p.item=='property_counter' and 'counter' or 'storage',registered=f,setup=canSetup,companies=options,products=products,manage=f and fixtureRight(f,who,'retail') or false,access=f and fixtureRight(f,who,'stock') or false,unregister=f and canSetup or false}})
end
AddEventHandler('frontier_business:fixture',function(src,sid,id)
 if GetInvokingResource()~='frontier_property' then return end
 CreateThread(function() run(function() sessions[src]={property=sid,fixture=id};fixtureView(src,sid,id) end,src) end)
end)
exports('FixtureBound',function(id) return not ready or fixture(id)~=nil end)
local function canAccessStorage(src,id,action)
 if not ready or type(id)~='string' then return false end
 local f=fixture(id:match('^business_([a-f0-9]+)$'));local who=cid(src)
 if not f or not who then return false end
 local p=validFixture(f)
 local b=f.owner_type=='company' and company(f.owner_id)
 if b and b.status=='liquidating' and tonumber(b.liquidate_until)>now() and isOwner(b.id,who) then
  p=exports.frontier_property:GetBusinessFixtureRecovery(f.property_id,f.id);return p and near(src,p,C.storageDistance) and (action=='view' or action=='retrieve') or false
 end
 if not p then
  -- Revoked grants or foreclosed plots cannot strand stock. Only recovery, at the original physical location.
  if (f.owner_type=='character' and f.owner_id==who or b and b.status=='active' and isOwner(b.id,who)) then
   p=exports.frontier_property:GetBusinessFixtureRecovery(f.property_id,f.id)
   return p and near(src,p,C.storageDistance) and (action=='view' or action=='retrieve') or false
  end
  return false
 end
 if not near(src,p,C.storageDistance) then return false end
 if action=='view' then return fixtureRight(f,who,'stock') end
 if action=='store' then return fixtureRight(f,who,'deposit') end
 if action=='retrieve' then return fixtureRight(f,who,'retrieve') end
 if action=='storageMove' or action=='storageSplit' then return fixtureRight(f,who,'deposit') and fixtureRight(f,who,'retrieve') end
 return false
end
exports('CanAccessStorage',canAccessStorage)
fixtureAction=function(src,who,a,d)
 if a=='recoverFixture' then
  local f=fixture(d.id);requireThat(f and canAccessStorage(src,'business_'..f.id,'retrieve'),'Approach an authorized stock location')
  TriggerClientEvent('frontier_business:close',src);local ok,e=inv:OpenStorage(src,'business_'..f.id);requireThat(ok,e);return true
 end
 if a=='claimRetail' then
  local row=S("SELECT * FROM fb_retail WHERE id=? AND buyer=? AND state='paid'",{d.id,who});requireThat(row,'Purchase unavailable')
  local f=fixture(row.fixture_id);local p=f and fixturePosition(f.property_id,f.id)
  -- Already-paid customer stock is never confiscated as company property.
  requireThat(p and near(src,p,C.storageDistance) or not p and office(src),'Collect at the counter, or registry if the counter has closed')
  local ok,e=inv:BusinessMoveStock(row.fixture_id,row.id,who,row.item_id,tonumber(row.quantity),'claim');requireThat(ok,e)
  U("UPDATE fb_retail SET state='complete' WHERE id=?",{row.id});return true
 end
 if not ({fixtureSetup=true,fixtureStock=true,fixturePrice=true,fixtureBuy=true,fixtureRemove=true})[a] then return false end
 local session=sessions[src];requireThat(session and session.fixture,'Open fixture first')
 local id,sid=session.fixture,session.property;local p=fixturePosition(sid,id);requireThat(p and near(src,p,C.storageDistance),'Approach fixture')
 local f=fixture(id)
 if a=='fixtureSetup' then
  requireThat(not f and propertyOwner(who,sid) and str(d.name,60),'Invalid fixture setup')
  local typ,owner='character',who;local kind=p.item=='property_counter' and 'counter' or 'storage'
  if d.company and d.company~='' then
   local b=company(d.company);local g=S('SELECT * FROM fb_locations WHERE company_id=? AND property_id=?',{d.company,sid})
   requireThat(allowed(b,who,'locations') and g and propertyOwner(g.grantor,sid) and decode(g.rights)[kind=='counter' and 'retail' or 'stock'],'Company usage not granted')
   typ,owner='company',b.id
  end
  local ok,e=inv:CreateStorage({id='business_'..id,name='Commercial stock',slots=100,grams=1000000,ace='' });requireThat(ok,e)
  Q('INSERT INTO fb_fixtures VALUES(?,?,?,?,?,?,?)',{id,sid,typ,owner,kind,d.name,who})
 elseif a=='fixtureStock' then
  requireThat(f and (validFixture(f) or f.owner_type=='company' and company(f.owner_id).status=='liquidating') and fixtureRight(f,who,'stock'),'Denied')
  TriggerClientEvent('frontier_business:close',src);local ok,e=inv:OpenStorage(src,'business_'..id);requireThat(ok,e);return true
 elseif a=='fixtureRemove' then
  requireThat(f and propertyOwner(who,sid),'Plot owner required')
  local farm=GetResourceState('frontier_farming');requireThat(farm=='missing' or farm=='started' and not exports.frontier_farming:StorageBound('business_'..id),'Unlink farming storage and resolve orders first')
  local production=GetResourceState('frontier_production');requireThat(production=='missing' or production=='started' and not exports.frontier_production:StorageBound('business_'..id),'Unlink production storage and resolve orders first')
  local logistics=GetResourceState('frontier_logistics');requireThat(logistics~='started' or not exports.frontier_logistics:StockBound('business_'..id),'Resolve freight contracts first')
  requireThat(not exports.frontier_trade:BusinessFixtureBusy(id) and not next(stock(f)) and not S("SELECT id FROM fb_retail WHERE fixture_id=? AND state NOT IN ('complete','failed') LIMIT 1",{id}),'Empty storage and resolve purchases first')
  tx({sql('DELETE FROM fb_prices WHERE fixture_id=?',{id}),sql('DELETE FROM fb_fixtures WHERE id=?',{id})})
 elseif a=='fixturePrice' then
  requireThat(f and validFixture(f) and f.kind=='counter' and fixtureRight(f,who,'retail') and str(d.item,48) and integer(d.price,0,100000000),'Denied')
  local ok,def=inv:GetTradeItemDefinition(d.item);requireThat(ok and def.transferable,'Invalid item')
  if d.price==0 then U('DELETE FROM fb_prices WHERE fixture_id=? AND item_id=?',{id,d.item}) else Q('INSERT INTO fb_prices VALUES(?,?,?) ON DUPLICATE KEY UPDATE price=VALUES(price)',{id,d.item,d.price}) end
 elseif a=='fixtureBuy' then
  requireThat(f and validFixture(f) and f.kind=='counter' and integer(d.quantity,1,1000),'Invalid purchase')
  if type(d.item)=='string' and d.item:match('^farm_') and not d.item:match('^farm_seed_') then local l=S('SELECT active FROM fb_licenses WHERE owner_type=? AND owner_id=? AND category=?',{f.owner_type,f.owner_id,'agriculture'});requireThat(l and tonumber(l.active)==1,'Agriculture license required') end
  local r=S('SELECT * FROM fb_prices WHERE fixture_id=? AND item_id=?',{id,d.item});requireThat(r and (stock(f)[d.item] or 0)>=d.quantity,'Stock unavailable')
  local from=bank(who);local to=f.owner_type=='company' and account(company(f.owner_id)) or bank(f.owner_id)
  requireThat(from and to and from~=to,'Invalid accounts')
  local sale=uuid();local total=tonumber(r.price)*d.quantity
  local fits,issue=inv:BusinessMoveStock(id,sale,who,d.item,d.quantity,'check')
  requireThat(fits,({weight='Your inventory is too heavy',slots='Your inventory has no free slots',capacity='Your inventory is full',insufficient_stock='Stock unavailable'})[issue] or tostring(issue))
  local checked,balance=eco:GetAccountBalance(from);requireThat(checked,'Bank unavailable')
  requireThat(tonumber(balance.balance_minor)>=total,'Insufficient funds')
  Q("INSERT INTO fb_retail(id,fixture_id,buyer,buyer_bank,seller_type,seller_id,seller_bank,item_id,quantity,price,state,created) VALUES(?,?,?,?,?,?,?,?,?,?,'reserve',?)",{sale,id,who,from,f.owner_type,f.owner_id,to,d.item,d.quantity,total,now()})
 end
 return true
end
local function retailNotice(r,message)
 for _,player in pairs(core:GetPlayers()) do
  if player.frontierCharacterId==r.buyer and cid(player.source)==r.buyer then tell(player.source,message);return end
 end
end
retailStep=function(r)
 local quantity=tonumber(r.quantity)
 if r.state=='reserve' then
  local ok,e=inv:BusinessMoveStock(r.fixture_id,r.id,r.buyer,r.item_id,quantity,'reserve')
  if ok then U("UPDATE fb_retail SET state='payment' WHERE id=?",{r.id}) elseif e=='insufficient_stock' then U("UPDATE fb_retail SET state='failed' WHERE id=?",{r.id});retailNotice(r,'Purchase rejected: stock unavailable. No payment taken.') end
 elseif r.state=='payment' then
  local ok,e=transfer(r.id,tonumber(r.buyer_bank),tonumber(r.seller_bank),tonumber(r.price))
  if ok then
   local detail={item=r.item_id,quantity=quantity,total=tonumber(r.price),buyer=r.buyer,seller=r.seller_id}
   receipt('character',r.buyer,'retail:'..r.id,detail);receipt(r.seller_type,r.seller_id,'retail:'..r.id,detail)
   -- Persist paid state before attempting delivery. The existing claim receipt
   -- is shared by automatic and manual delivery, including after a restart.
   U("UPDATE fb_retail SET state='paid' WHERE id=?",{r.id})
   local delivered,issue=inv:BusinessMoveStock(r.fixture_id,r.id,r.buyer,r.item_id,quantity,'claim')
   if delivered then
    U("UPDATE fb_retail SET state='complete' WHERE id=? AND state='paid'",{r.id})
    retailNotice(r,('Purchased %d × %s. Items delivered to your inventory.'):format(quantity,r.item_id))
   else
    retailNotice(r,'Payment received, but delivery could not finish ('..tostring(issue)..'). Collect your paid items under Personal > Purchases.')
   end
  elseif definite(e) or e=='balance_limit' then U("UPDATE fb_retail SET state='return' WHERE id=?",{r.id});retailNotice(r,'Purchase rejected: '..tostring(e)..'. No payment taken.') end
 elseif r.state=='return' then
  if inv:BusinessMoveStock(r.fixture_id,r.id,r.buyer,r.item_id,quantity,'return') then U("UPDATE fb_retail SET state='failed' WHERE id=?",{r.id}) end
 end
end
AddEventHandler('frontier:playerUnloaded',function(p) sessions[p.source]=nil;TriggerClientEvent('frontier_business:close',p.source) end)
AddEventHandler('playerDropped',function() sessions[source]=nil end)

exports('AuthorizeTradeFixture',function(src,id,fid,perm,physical)
 if GetInvokingResource()~='frontier_trade' or not ready then return false end
 local who=cid(src);local f=fixture(fid);local b=company(id)
 if not who or not f or f.owner_type~='company' or f.owner_id~=id or not b then return false end
 local p
 if b.status=='liquidating' and tonumber(b.liquidate_until)>now() and isOwner(id,who) and perm=='deposit' then
  p=exports.frontier_property:GetBusinessFixtureRecovery(f.property_id,f.id)
 else
  if not allowed(b,who,'trade') or not fixtureRight(f,who,perm) then return false end
  p=validFixture(f)
 end
 return p~=nil and (not physical or near(src,p,C.storageDistance)==true)
end)
tradeAction=function(src,who,d)
 local b=company(d.company);requireThat(b,'Company unavailable')
 local recovery=d.operation=='claimDelivery' or d.operation=='claimSale'
 requireThat(allowed(b,who,'trade') or recovery and b.status=='liquidating' and tonumber(b.liquidate_until)>now() and isOwner(b.id,who),'Denied')
 local ok,e=exports.frontier_trade:BusinessAction(src,b.id,d.operation,d);requireThat(ok,e);log(b.id,who,'trade:'..d.operation,{reference=e});tell(src,tostring(e))
end
tradeView=function(b,who)
 if b.status~='active' and not (b.owner and b.status=='liquidating') then return end
 b.trade=exports.frontier_trade:BusinessSnapshot(b.id)
 b.tradeFixtures={}
 for _,f in ipairs(Q("SELECT * FROM fb_fixtures WHERE owner_type='company' AND owner_id=?",{b.id})) do
  if validFixture(f) or b.status=='liquidating' and fixturePosition(f.property_id,f.id) then
   b.tradeFixtures[#b.tradeFixtures+1]={id=f.id,name=f.name,deposit=fixtureRight(f,who,'deposit') or b.status=='liquidating' and b.owner,retrieve=fixtureRight(f,who,'retrieve')}
  end
 end
end
-- Idempotent receipt synchronization catches crashes after Trade settles a payment.
tradeReceipts=function()
 for _,side in ipairs({'buyer','seller'}) do
  local actor=side=='buyer' and 'r.buyer_id' or 'c.seller_id'
  Q(([[INSERT IGNORE INTO fb_receipts(id,owner_type,owner_id,reference_id,detail,created)
   SELECT REPLACE(UUID(),'-',''),IF(b.id IS NULL,'character','company'),%s,CONCAT('trade:delivery:',d.id),
   JSON_OBJECT('item',r.item_id,'quantity',d.quantity,'total',d.quantity*c.unit_minor,'buyer',r.buyer_id,'seller',c.seller_id),UNIX_TIMESTAMP()
   FROM frontier_trade_deliveries d JOIN frontier_trade_contracts c ON c.id=d.contract_id JOIN frontier_trade_requests r ON r.id=c.request_id
   LEFT JOIN fb_companies b ON b.id=%s
   WHERE d.state='complete' AND (b.id IS NOT NULL OR LEFT(%s,2)='f_')
   AND NOT EXISTS(SELECT 1 FROM fb_receipts x WHERE x.owner_type=IF(b.id IS NULL,'character','company') AND x.owner_id=%s AND x.reference_id=CONCAT('trade:delivery:',d.id))
   LIMIT 100]]):format(actor,actor,actor,actor))
  actor=side=='buyer' and 's.buyer_id' or 'o.seller_id'
  Q(([[INSERT IGNORE INTO fb_receipts(id,owner_type,owner_id,reference_id,detail,created)
   SELECT REPLACE(UUID(),'-',''),IF(b.id IS NULL,'character','company'),%s,CONCAT('trade:sale:',s.id),
   JSON_OBJECT('item',o.item_id,'quantity',s.quantity,'total',s.quantity*o.unit_minor,'buyer',s.buyer_id,'seller',o.seller_id),UNIX_TIMESTAMP()
   FROM frontier_trade_sales s JOIN frontier_trade_offers o ON o.id=s.offer_id LEFT JOIN fb_companies b ON b.id=%s
   WHERE s.state='complete' AND (b.id IS NOT NULL OR LEFT(%s,2)='f_')
   AND NOT EXISTS(SELECT 1 FROM fb_receipts x WHERE x.owner_type=IF(b.id IS NULL,'character','company') AND x.owner_id=%s AND x.reference_id=CONCAT('trade:sale:',s.id))
   LIMIT 100]]):format(actor,actor,actor,actor))
 end
end

-- Final liquidation is restartable at every state transition. Never delete a paid customer purchase.
liquidate=function(b,t)
 tx({sql('DELETE FROM fb_employees WHERE company_id=?',{b.id}),sql("UPDATE fb_licenses SET active=0 WHERE owner_type='company' AND owner_id=? AND active=1",{b.id}),sql('DELETE FROM fb_invites WHERE company_id=?',{b.id}),sql("UPDATE fb_proposals SET status='expired' WHERE company_id=? AND status='open'",{b.id})})
 local expired=tonumber(b.liquidate_until)<=t
 local drained=exports.frontier_trade:DrainBusiness(b.id,expired)
 if not expired or not drained then return false end
 local farm=GetResourceState('frontier_farming')
 if farm~='missing' and (farm~='started' or exports.frontier_farming:CompanyOrdersPending(b.id) or not exports.frontier_farming:DrainCompany(b.id)) then return false end
 if S("SELECT id FROM fb_retail WHERE seller_type='company' AND seller_id=? AND state IN ('reserve','payment','return') LIMIT 1",{b.id}) then return false end
 for _,f in ipairs(Q("SELECT * FROM fb_fixtures WHERE owner_type='company' AND owner_id=? ORDER BY id",{b.id})) do
  local row=S('SELECT * FROM fb_confiscations WHERE company_id=? AND fixture_id=?',{b.id,f.id})
  if not row then
   local ok,data=inv:GetStorageContents('business_'..f.id);requireThat(ok,'Cannot read stock for liquidation')
   local op=uuid();Q("INSERT INTO fb_confiscations VALUES(?,?,?,?,?,'pending',?)",{op,b.id,f.id,encode(data.slots),data.revision,t})
   row=S('SELECT * FROM fb_confiscations WHERE id=?',{op})
  end
  if row.status~='complete' then
   local ok,e=inv:ConfiscateBusinessStock(b.id,f.id,row.id,tonumber(row.revision))
   if not ok then
    if e=='conflict' then
     local read,data=inv:GetStorageContents('business_'..f.id);requireThat(read,'Cannot refresh stock')
     U('UPDATE fb_confiscations SET snapshot=?,revision=? WHERE id=? AND status=?',{encode(data.slots),data.revision,row.id,'pending'})
    end
    return false
   end
   tx({sql("UPDATE fb_confiscations SET status='complete' WHERE id=?",{row.id}),sql('INSERT INTO fb_logs(company_id,actor,action,detail,created) VALUES(?,?,?,?,?)',{b.id,'government','stock_confiscated',encode({fixture=f.id,operation=row.id,items=decode(row.snapshot)}),t})})
  end
 end
 local ok,v=eco:GetAccountBalance(account(b));requireThat(ok,'Company bank unavailable')
 if tonumber(b.final_tax_settled)==0 then
  local due=totalDebt(b);local payment=math.min(v.balance_minor,due)
  if payment>0 then job('finalTax',{company=b.id,actor='government',from=account(b),amount=payment,totalDebt=due});return true end
  U('UPDATE fb_companies SET final_tax_settled=1,final_tax_paid=0 WHERE id=?',{b.id})
  return false
 end
 if v.balance_minor>0 then distribution(b,v.balance_minor,nil,nil,true);return true end
 local stm=archiveStatements(b.id)
 stm[#stm+1]=sql('INSERT INTO fb_logs(company_id,actor,action,detail,created) VALUES(?,?,?,?,?)',{b.id,'government','archived',encode({taxPaid=tonumber(b.final_tax_paid),uncollectedTax=math.max(0,totalDebt(b)-tonumber(b.final_tax_paid))}),t})
 tx(stm);return false
end
stockView=function(b,who)
 b.stock={}
 for _,f in ipairs(Q("SELECT * FROM fb_fixtures WHERE owner_type='company' AND owner_id=? ORDER BY id",{b.id})) do
  local ok,v=inv:GetStorageContents('business_'..f.id)
  local pos=exports.frontier_property:GetBusinessFixtureRecovery(f.property_id,f.id)
  b.stock[#b.stock+1]={id=f.id,name=f.name,kind=f.kind,position=pos,items=ok and v.slots or {},available=ok}
 end
 if b.owner or b.rights.logs then
  b.storageAudit=Q([[SELECT a.*,f.name FROM fb_storage_audit a LEFT JOIN fb_fixtures f ON f.id=a.fixture_id
    JOIN frontier_inventory_receipts r ON r.request_key=a.request_id AND r.actor=a.actor AND r.completed=1
    WHERE a.company_id=? ORDER BY a.created DESC LIMIT 100]],{b.id})
  b.confiscations=Q("SELECT id,fixture_id,snapshot,status,created FROM fb_confiscations WHERE company_id=?",{b.id})
 end
end
exports('PlotHasBusinessFixtures',function(sid)
 if not ready then return true end
 return S('SELECT id FROM fb_fixtures WHERE property_id=? LIMIT 1',{sid})~=nil
end)
RegisterCommand('businessrecovery',function(src)
 if src~=0 and not core:HasPermission(src,'frontier.business.admin') then return end
 local function report(s) if src==0 then print(s) else tell(src,s) end end
 for _,j in ipairs(Q('SELECT id,kind,created FROM fb_jobs ORDER BY created,id LIMIT 50')) do report(('Pending financial job %s (%s), created %s'):format(j.id,j.kind,j.created)) end
 for _,r in ipairs(Q("SELECT id,state FROM fb_retail WHERE state IN ('reserve','payment','return') ORDER BY created LIMIT 50")) do report('Pending retail '..r.id..' '..r.state) end
 for _,r in ipairs(Q("SELECT id,fixture_id,status FROM fb_confiscations WHERE status<>'complete' LIMIT 50")) do report('Pending seizure '..r.id..' '..r.fixture_id) end
 report('Recovery is replay-only. Do not delete pending jobs or manually edit ledger balances.')
end,false)

exports('FarmStock',function(who,sid,typ,id)
 if GetInvokingResource()~='frontier_farming' or not ready then return {} end
 if typ=='character' and who~=id or typ=='company' and not allowed(company(id),who,'farm') then return {} end
 local out={}
 for _,f in ipairs(Q("SELECT * FROM fb_fixtures WHERE property_id=? AND owner_type=? AND owner_id=? AND kind='storage'",{sid,typ,id})) do
  if validFixture(f) then out[#out+1]={id='business_'..f.id,name=f.name} end
 end
 return out
end)
exports('FarmStockValid',function(sid,typ,id,storage)
 if GetInvokingResource()~='frontier_farming' or not ready or type(storage)~='string' then return false end
 local f=fixture(storage:match('^business_([a-f0-9]+)$'))
 return f and f.kind=='storage' and f.property_id==sid and f.owner_type==typ and f.owner_id==id and validFixture(f)~=nil or false
end)

-- Only a persisted farming order may debit a company account. Replay is independent of employee changes.
exports('PayFarmOrder',function(id)
 if GetInvokingResource()~='frontier_farming' or not ready then return false,'forbidden' end
 local j=S("SELECT * FROM ff_orders WHERE id=? AND owner_type='company' AND phase='payment'",{id})
 if not j then return false,'invalid_order' end
 local b=company(j.owner_id);if not b then return false,'invalid_company' end
 return eco:DebitAccount(account(b),tonumber(j.amount),{key='farm_order_'..id,reason='Agricultural supplies',reference=id})
end)

exports('PayFarmHorseSale',function(id)
 if GetInvokingResource()~='frontier_farming' or not ready then return false,'forbidden' end
 local j=S("SELECT h.*,f.owner_type AS seller_type,f.owner_id AS seller_id,t.owner_type AS buyer_type,t.owner_id AS buyer_id FROM ff_horse_sales h JOIN ff_facilities f ON f.id=h.source_id JOIN ff_facilities t ON t.id=h.dest_id WHERE h.id=? AND h.phase='payment'",{id})
 if not j then return false,'invalid_sale' end
 local from=j.buyer_type=='company' and account(company(j.buyer_id)) or bank(j.buyer_id)
 local to=j.seller_type=='company' and account(company(j.seller_id)) or bank(j.seller_id)
 if from~=tonumber(j.debit) or to~=tonumber(j.credit) then return false,'invalid_account' end
 return eco:TransferAccounts(from,to,tonumber(j.amount),{key='farm_horse_'..id,reason='Horse certificate sale',reference=id})
end)

exports('RefundFarmOrder',function(id)
 if GetInvokingResource()~='frontier_farming' or not ready then return false,'forbidden' end
 local j=S("SELECT * FROM ff_orders WHERE id=? AND owner_type='company' AND phase='paid'",{id})
 local b=j and company(j.owner_id);if not b or b.status~='liquidating' then return false,'invalid_order' end
 return eco:CreditAccount(account(b),tonumber(j.amount),{key='farm_refund_'..id,reason='Undelivered agricultural supply refund',reference=id})
end)

local function productionGrant(who,sid,id,perm)
 local b=company(id);local g=S('SELECT * FROM fb_locations WHERE company_id=? AND property_id=?',{id,sid})
 local l=S("SELECT active FROM fb_licenses WHERE owner_type='company' AND owner_id=? AND category='manufacturing'",{id})
 return allowed(b,who,perm) and g and propertyOwner(g.grantor,sid) and decode(g.rights).production==true and l and tonumber(l.active)==1 or false
end
exports('ProductionCompanies',function(who,sid)
 if GetInvokingResource()~='frontier_production' or not ready then return {} end
 local out={}
 for _,b in ipairs(Q("SELECT c.id,c.name FROM fb_companies c JOIN fb_locations l ON c.id=l.company_id WHERE l.property_id=? AND c.status='active'",{sid})) do
  if productionGrant(who,sid,b.id,'locations') and productionGrant(who,sid,b.id,'production') then out[#out+1]=b end
 end
 return out
end)
exports('ProductionAccess',function(who,sid,typ,id,manage)
 if GetInvokingResource()~='frontier_production' or not ready then return false end
 if typ=='character' then return who==id end
 return typ=='company' and productionGrant(who,sid,id,manage and 'locations' or 'production') or false
end)
exports('ProductionStocks',function(who,sid,typ,id)
 if GetInvokingResource()~='frontier_production' or not ready then return {} end
 if typ=='character' and who~=id or typ=='company' and not productionGrant(who,sid,id,'production') then return {} end
 local out={}
 for _,f in ipairs(Q("SELECT * FROM fb_fixtures WHERE property_id=? AND owner_type=? AND owner_id=? AND kind='storage'",{sid,typ,id})) do
  if validFixture(f) then out[#out+1]={id='business_'..f.id,name=f.name} end
 end
 return out
end)
exports('ProductionStockValid',function(sid,typ,id,storage)
 if GetInvokingResource()~='frontier_production' or not ready or type(storage)~='string' then return false end
 local f=fixture(storage:match('^business_([a-f0-9]+)$'))
 return f and f.kind=='storage' and f.property_id==sid and f.owner_type==typ and f.owner_id==id and validFixture(f)~=nil or false
end)

exports('LogisticsStock',function(src,all)
 if GetInvokingResource()~='frontier_logistics' or not ready then return {} end
 local who=cid(src);if not who then return {} end
 local out={}
 for _,f in ipairs(Q("SELECT * FROM fb_fixtures WHERE kind='storage'")) do
  local p=validFixture(f)
  if p and fixtureRight(f,who,'stock') and (all or near(src,p,C.storageDistance)) then
   out[#out+1]={id='business_'..f.id,name=f.name,x=p.x,y=p.y,z=p.z,ownerType=f.owner_type,ownerId=f.owner_id,deposit=fixtureRight(f,who,'deposit')==true,retrieve=fixtureRight(f,who,'retrieve')==true}
  end
 end
 return out
end)
exports('LogisticsStockPoint',function(id)
 if GetInvokingResource()~='frontier_logistics' or not ready or type(id)~='string' then return end
 local f=fixture(id:match('^business_([a-f0-9]+)$'));local p=f and f.kind=='storage' and validFixture(f)
 if p then return {id=id,name=f.name,x=p.x,y=p.y,z=p.z,ownerType=f.owner_type,ownerId=f.owner_id} end
end)
exports('LogisticsCompanies',function(who)
 if GetInvokingResource()~='frontier_logistics' or not ready then return {} end
 local out={}
 for _,b in ipairs(Q("SELECT id,name FROM fb_companies WHERE status='active'")) do
  if allowed(company(b.id),who,'trade') then
   local l=S("SELECT active FROM fb_licenses WHERE owner_type='company' AND owner_id=? AND category='transport'",{b.id})
   if l and tonumber(l.active)==1 then out[#out+1]={id=b.id,name=b.name} end
  end
 end
 return out
end)

exports('PayPublicHorseSale',function(id)
 if GetInvokingResource()~='frontier_farming' or not ready then return false,'forbidden' end
 local j=S("SELECT j.*,f.owner_type AS seller_type,f.owner_id AS seller_id FROM ff_public_horse_sales j JOIN ff_facilities f ON f.id=j.source_id WHERE j.id=? AND j.phase='payment'",{id})
 if not j then return false,'invalid_sale' end
 local from=tonumber(MySQL.scalar.await("SELECT id FROM frontier_economy_accounts WHERE owner_type='character' AND owner_id=? AND account_type='cash' AND currency='USD'",{j.buyer}))
 local seller=j.seller_type=='company' and company(j.seller_id) or nil
 local to=j.seller_type=='company' and seller and account(seller) or (j.seller_type=='character' and bank(j.seller_id))
 if not from or not to or from==to then return false,'invalid_account' end
 return eco:TransferAccounts(from,to,tonumber(j.amount),{key='public_horse_'..id,reason='Ranch horse sale',reference=id})
end)
exports('HorseCompanies',function(who)
 if GetInvokingResource()~='frontier_horses' or not ready then return {} end
 local out={}
 for _,b in ipairs(Q("SELECT * FROM fb_companies WHERE status='active'")) do
  if allowed(b,who,'trade') and allowed(b,who,'withdraw') then out[#out+1]={id=b.id,name=b.name} end
 end
 return out
end)
exports('PayStableCompanyHorse',function(id)
 if GetInvokingResource()~='frontier_horses' or not ready then return false,'forbidden' end
 local j=S("SELECT * FROM frontier_horse_orders WHERE id=? AND kind='buy' AND state='payment'",{id})
 if not j then return false,'invalid_order' end
 local p=decode(j.payload);local b=company(p.ownerId)
 if p.ownerType~='company' or not b or account(b)~=tonumber(j.account) then return false,'invalid_account' end
 return eco:DebitAccount(account(b),tonumber(j.amount),{key='horse:'..id..':pay',reason='Company horse purchase',reference=id})
end)
