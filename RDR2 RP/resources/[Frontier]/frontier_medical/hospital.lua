-- Hospital service uses the same durable account/receipt APIs as the rest of Frontier.
FrontierHospital={dutyStation={}}
local H,C,R=FrontierHospital,FrontierHospitalConfig,FrontierHospitalRules
local core,eco,inv=exports.frontier_core,exports.frontier_economy,exports.frontier_inventory
local E='frontier_medical:'
local A,account
local sessions,locks,last={}, {}, {}
local ready=false
local function query(method,sql,args) return A.db(method,sql,args) end
local function name(src)
 local p=core:GetPlayer(src)
 return p and (p.name or p.characterData and p.characterData.name) or ('Character #'..src)
end
local function money(n) return ('$%.2f'):format((tonumber(n) or 0)/100) end
local function online(id)
 for _,p in pairs(core:GetPlayers()) do if p.frontierCharacterId==id then return p.source end end
end
local function notice(id,msg) local src=online(id);if src then A.notify(src,msg) end end
local function isPolice(src) return A.ace(src,C.policeAce) end
local function nearStation(src,id)
 local st=C.stations[id];if not st or GetPlayerRoutingBucket(src)~=0 then return false end
 local pos=A.position(src);return pos and (pos.x-st.x)^2+(pos.y-st.y)^2+(pos.z-st.z)^2<=C.reach^2
end
local function allowed(src,v)
 if not ready or A.legacy() or not A.capable(src) or A.cid(src)~=v.actor then return false end
 if v.mode=='station' then return A.medic(src) and nearStation(src,v.station) end
 if v.mode=='police' then return isPolice(src) end
 return v.mode=='patient'
end
function H.schema()
 local id=query('scalar',[[SELECT id FROM frontier_economy_accounts WHERE owner_type='medical_service' AND owner_id='frontier_medical' AND account_type='treasury' AND currency='USD']])
 if not id or query('query','SELECT id FROM frontier_medical_supply_orders LIMIT 0')==nil or query('query','SELECT id FROM frontier_medical_invoices LIMIT 0')==nil or query('query','SELECT request_key FROM frontier_medical_charges LIMIT 0')==nil then return false end
 account=tonumber(id);ready=account~=nil;return ready
end
function H.canBill(src,v)
 return ready and A.duty(src) and not A.testing(src) and v.actor~=v.patient
end
function H.capture(src,v,key,item,region,life)
 if not H.canBill(src,v) or not A.validView(src,v) then return end
 local fee=C.fees[item];if not fee then return end
 local station=H.dutyStation[src] or 'field'
 local patientName,doctorName=name(v.target),name(src)
 if not A.validView(src,v) then return end
 local n=query('update',[[INSERT IGNORE INTO frontier_medical_charges
 (request_key,patient,patient_name,doctor,doctor_name,life,hospital,region,treatment,label,price_minor,created_at)
 VALUES(?,?,?,?,?,?,?,?,?,?,?,?)]],{key,v.patient,patientName,v.actor,doctorName,life,station,region,item,fee.label,fee.price,os.time()})
 if n==nil then A.notify(src,'Treatment will continue, but the billing record could not be saved.') end
end
local function dueSummary(id)
 local row=query('single',[[SELECT COUNT(*) AS count,COALESCE(SUM(amount_minor),0) AS total,
 COALESCE(SUM(CASE WHEN due_at<=? THEN 1 ELSE 0 END),0) AS overdue
 FROM frontier_medical_invoices WHERE patient=? AND status IN ('pending','reported','paying')]],{os.time(),id})
 return row or {count=0,total=0,overdue=0}
end
function H.chart(src,v,action)
 if not H.canBill(src,v) or not A.validView(src,v) then return A.notify(src,'Billing requires an on-duty medic treating another character.') end
 if action~='billing' then
  if A.working[src] or not v.life then return end
  local result=query('query','CALL frontier_medical_issue_invoice_v1(?,?,?,?,?,?)',{v.patient,v.actor,v.life,action=='issueBill' and 'pending' or 'waived',os.time(),os.time()+C.invoiceDueSeconds})
  local row=result and result[1] and result[1][1]
  if row and row.code=='ok' then
   A.notify(src,('Invoice MED-%s · %s · %s'):format(row.invoice_id,money(row.amount_minor),action=='issueBill' and 'issued' or 'waived'))
   if action=='issueBill' then notice(v.patient,('Medical invoice MED-%s for %s received. Open /medicalbills to review or pay.'):format(row.invoice_id,money(row.amount_minor))) end
  else A.notify(src,row and row.code=='no_charges' and 'No unbilled successful treatments.' or 'Invoice could not be confirmed. Refresh billing.') end
 end
 local lines=query('query',[[SELECT label,region,price_minor,created_at FROM frontier_medical_charges
 WHERE patient=? AND doctor=? AND life=? AND eligible=TRUE AND invoice_id IS NULL ORDER BY created_at,request_key]],{v.patient,v.actor,v.life}) or {}
 local debt=dueSummary(v.patient)
 if A.validView(src,v) and H.canBill(src,v) then TriggerClientEvent(E..'billingView',src,v.ticket,{lines=lines,debt=debt}) end
end
local function debitOrder(o)
 if o.status~='pending' then return o.status end
 local ok,receipt=eco:DebitAccount(account,tonumber(o.amount_minor),{key='med-supply:'..o.id,reason='Medical supplies',reference=o.id,
 metadataJson=json.encode({doctor=o.doctor,station=o.hospital})})
 if ok then
  query('update',"UPDATE frontier_medical_supply_orders SET status='paid',debit_receipt=? WHERE id=? AND status='pending'",{receipt.operationId,o.id})
  return 'paid'
 end
 if receipt=='insufficient_funds' then
  query('update',"UPDATE frontier_medical_supply_orders SET status='declined' WHERE id=? AND status='pending'",{o.id})
  notice(o.doctor,'Department has insufficient funds for this supply order.');return 'declined'
 end
 return 'pending'
end
local function deliverOrder(o)
 local ok,lines=pcall(json.decode,o.items_json)
 if not ok or type(lines)~='table' then return false,'invalid_record' end
 local result,why=inv:DeliverMedicalSupplies(o.doctor,'medsup:'..o.id,lines)
 if result then
  query('update',"UPDATE frontier_medical_supply_orders SET status='delivered' WHERE id=? AND status='paid'",{o.id})
  return true
 end
 return false,why
end
local function order(src,v,kind,id,count)
 if not A.duty(src) or not allowed(src,v) then return A.notify(src,'Enter service at the hospital before collecting supplies.') end
 local prior=query('single',"SELECT id FROM frontier_medical_supply_orders WHERE doctor=? AND status IN ('pending','paid') LIMIT 1",{v.actor})
 if prior then return A.notify(src,'An earlier supply order is pending. Use Collect pending order.') end
 local hour=math.floor(os.time()/3600)
 local n=query('scalar',"SELECT COUNT(*) FROM frontier_medical_supply_orders WHERE doctor=? AND funding_hour=? AND status<>'declined'",{v.actor,hour})
 if n==nil or tonumber(n)>=C.maxIssuePerHour then return A.notify(src,'Hourly supply issue limit reached.') end
 local owned={}
 for item in pairs(C.supplies) do
  local ok,qty=inv:GetItemCount(src,item)
  if not ok then return A.notify(src,'Inventory unavailable.') end
  owned[item]=tonumber(qty) or 0
 end
 local lines,amount=R.plan(kind,id,count,owned)
 if not lines or #lines==0 or amount<=0 then return A.notify(src,'Invalid selection or already sufficiently equipped.') end
 local uid=query('scalar',"SELECT REPLACE(UUID(),'-','')")
 if not uid or not allowed(src,v) or not A.duty(src) then return end
 local o={id=uid,doctor=v.actor,hospital=v.station,amount_minor=amount,items_json=json.encode(lines),status='pending'}
 local inserted=query('update',[[INSERT INTO frontier_medical_supply_orders(id,doctor,doctor_name,hospital,items_json,amount_minor,funding_hour,created_at,status)
 VALUES(?,?,?,?,?,?,?,?,'pending')]],{uid,v.actor,name(src),v.station,o.items_json,amount,hour,os.time()})
 if inserted~=1 then return A.notify(src,'Order could not be recorded.') end
 local state=debitOrder(o)
 if state=='paid' then
  local ok,why=deliverOrder(o)
  if ok then A.notify(src,'Supplies issued. Department paid '..money(amount)..'.')
  else A.notify(src,'Order paid, awaiting pickup: '..tostring(why)..'. Free inventory space and collect again.') end
 elseif state=='pending' then A.notify(src,'Payment pending; order recorded. Do not place another order.') end
end
local function collect(src,v)
 if not A.duty(src) or not allowed(src,v) then return end
 local o=query('single',"SELECT * FROM frontier_medical_supply_orders WHERE doctor=? AND status IN ('pending','paid') ORDER BY created_at LIMIT 1",{v.actor})
 if not o then return A.notify(src,'No pending supply order.') end
 local status=debitOrder(o)
 if status=='paid' and allowed(src,v) and A.duty(src) then
  local ok,why=deliverOrder(o);A.notify(src,ok and 'Supplies collected.' or 'Pickup pending: '..tostring(why))
 else A.notify(src,'Order status: '..status) end
end
local function payInvoice(row)
 local ok,receipt=eco:TransferAccounts(tonumber(row.payer_account),account,tonumber(row.amount_minor),
 {key='med-bill:'..tostring(row.id),reason='Medical invoice paid',reference='MED-'..tostring(row.id)})
 if ok then
  local n=query('update',[[UPDATE frontier_medical_invoices SET status='paid',paid_at=?,payment_receipt=? WHERE id=? AND status='paying']],{os.time(),receipt.operationId,row.id})
  if n==1 then notice(row.patient,'Medical invoice MED-'..row.id..' paid.');notice(row.doctor,'Medical invoice MED-'..row.id..' paid into the department account.') end
 elseif receipt=='insufficient_funds' then
  local n=query('update',[[UPDATE frontier_medical_invoices SET status=previous_status,payer_account=NULL,previous_status=NULL WHERE id=? AND status='paying']],{row.id})
  if n==1 then notice(row.patient,'Insufficient bank funds. Invoice remains unpaid.') end
 end
end
local function getInvoice(id)
 if type(id)~='string' or #id>16 or not id:match('^[1-9]%d*$') then return end
 return query('single','SELECT * FROM frontier_medical_invoices WHERE id=?',{id})
end
local function invoiceAction(src,v,action,id)
 local row=getInvoice(id);if not row or not allowed(src,v) then return A.notify(src,'Invoice unavailable.') end
 if action=='pay' then
  if row.patient~=v.actor or not R.payable(row.status) then return A.notify(src,'This invoice cannot be paid.') end
  local ok,accounts=eco:GetCharacterAccounts(src)
  if not ok or accounts.characterId~=v.actor or not allowed(src,v) then return A.notify(src,'Bank account unavailable.') end
  local n=query('update',[[UPDATE frontier_medical_invoices SET previous_status=status,status='paying',payer_account=? WHERE id=? AND patient=? AND status IN ('pending','reported')]],{accounts.bank.id,id,v.actor})
  if n==1 then row.payer_account=accounts.bank.id;payInvoice(row) else A.notify(src,'Invoice status changed. Refresh.') end
 elseif action=='waive' or action=='cancel' or action=='report' then
  if v.mode~='station' or not A.duty(src) or row.doctor~=v.actor then return A.notify(src,'Only the issuing medic can resolve this invoice while on duty.') end
  if action=='report' then
   local n=query('update',[[UPDATE frontier_medical_invoices SET status='reported',reported_by=?,reported_at=? WHERE id=? AND doctor=? AND status='pending' AND due_at<=?]],{v.actor,os.time(),id,v.actor,os.time()})
   if n~=1 then return A.notify(src,'Only overdue, unreported invoices can be referred.') end
   notice(row.patient,'Overdue invoice MED-'..id..' has been referred to the police.')
   for _,p in pairs(core:GetPlayers()) do if isPolice(p.source) then A.notify(p.source,'Medical debt report MED-'..id..'. Use /medicalreports.') end end
  else
   local n=query('update',[[UPDATE frontier_medical_invoices SET status=?,resolved_by=?,resolved_at=? WHERE id=? AND doctor=? AND status IN ('pending','reported')]],{action=='waive' and 'waived' or 'cancelled',v.actor,os.time(),id,v.actor})
   if n~=1 then return A.notify(src,'Invoice is not open.') end
   notice(row.patient,'Invoice MED-'..id..' '..(action=='waive' and 'waived.' or 'cancelled.'))
  end
 end
end
local function invoiceRows(v,search,before)
 search=type(search)=='string' and search:sub(1,80) or ''
 before=type(before)=='string' and #before<=16 and before:match('^[1-9]%d*$') and before or '9007199254740991'
 -- Search literally; escape wildcard characters in bound values.
 local term='%'..search:gsub('!','!!'):gsub('%%','!%%'):gsub('_','!_')..'%'
 local where,args
 if v.mode=='patient' then where='patient=?';args={v.actor}
 elseif v.mode=='police' then where='reported_at IS NOT NULL';args={}
 else where='1=1';args={} end
 args[#args+1]=before;args[#args+1]=term;args[#args+1]=term;args[#args+1]=term
 local rows=query('query',[[SELECT CAST(id AS CHAR) AS id,patient_name,doctor_name,hospital,amount_minor,status,created_at,due_at,paid_at,payment_receipt,reported_at
 FROM frontier_medical_invoices WHERE ]]..where..[[ AND id<? AND
 (patient_name LIKE ? ESCAPE '!' OR doctor_name LIKE ? ESCAPE '!' OR CONCAT('MED-',id) LIKE ? ESCAPE '!')
 ORDER BY id DESC LIMIT 41]],args)
 if not rows then return {},false end
 local more=#rows>40;if more then rows[41]=nil end
 for _,row in ipairs(rows) do row.status=R.status(row,os.time()) end
 return rows,more
end
local function invoiceDetail(src,v,id)
 local row=getInvoice(id)
 if not row or (v.mode=='patient' and row.patient~=v.actor) or (v.mode=='police' and not row.reported_at) or not allowed(src,v) then return end
 local lines=query('query','SELECT label,region,price_minor,created_at FROM frontier_medical_charges WHERE invoice_id=? ORDER BY created_at,request_key',{id}) or {}
 if not allowed(src,v) then return end
 TriggerClientEvent(E..'hospitalDetail',src,v.ticket,{id=id,patient_name=row.patient_name,doctor_name=row.doctor_name,hospital=row.hospital,amount_minor=row.amount_minor,status=R.status(row,os.time()),created_at=row.created_at,due_at=row.due_at,paid_at=row.paid_at,payment_receipt=row.payment_receipt,reported_at=row.reported_at,lines=lines,
  canPay=row.patient==v.actor and R.payable(row.status),canResolve=v.mode=='station' and A.duty(src) and row.doctor==v.actor and R.payable(row.status),canReport=v.mode=='station' and A.duty(src) and row.doctor==v.actor and row.status=='pending' and tonumber(row.due_at)<=os.time()})
end
local function view(src,v,search,before)
 if sessions[src]~=v or not allowed(src,v) then return end
 local rows,more=invoiceRows(v,search,before)
 local payload={ticket=v.ticket,mode=v.mode,station=v.station,name=v.mode=='station' and C.stations[v.station].name or v.mode=='police' and 'Medical debt reports' or 'My medical invoices',invoices=rows,more=more}
 if v.mode=='station' then
  payload.duty=A.duty(src)==true;payload.supplies=C.supplies;payload.kits=C.kits;payload.owned={}
  for item in pairs(C.supplies) do local ok,n=inv:GetItemCount(src,item);if ok then payload.owned[item]=n end end
  local ok,balance=eco:GetAccountBalance(account);if ok then payload.balance=balance.balance_minor end
  local ok2,history=eco:GetAccountTransactions(account,30);if ok2 then payload.ledger=history end
  payload.orders=query('query',[[SELECT id,doctor_name,hospital,amount_minor,status,created_at,items_json,debit_receipt FROM frontier_medical_supply_orders ORDER BY created_at DESC,id DESC LIMIT 40]]) or {}
  payload.pending=query('scalar',"SELECT COUNT(*) FROM frontier_medical_supply_orders WHERE doctor=? AND status IN ('pending','paid')",{v.actor})
  payload.calls={}
  for _,call in pairs(A.board.calls) do if call.bucket==GetPlayerRoutingBucket(src) then payload.calls[#payload.calls+1]={number=call.number,patient=call.source,assigned=call.responder~=nil,mine=call.responder==src} end end
 end
 if sessions[src]==v and allowed(src,v) then TriggerClientEvent(E..'hospitalView',src,payload) end
end
local function run(src,fn)
 if locks[src] then return end
 local t=GetGameTimer();if last[src] and t-last[src]<400 then return end;last[src]=t
 local lock={};locks[src]=lock
 local ok,err=pcall(fn)
 if locks[src]==lock then locks[src]=nil end
 if not ok then print('[frontier_medical] Hospital request failed: '..tostring(err));A.notify(src,'Hospital request could not be confirmed. Refresh before retrying.') end
end
function H.clear(src) sessions[src]=nil;locks[src]=nil;last[src]=nil;H.dutyStation[src]=nil end
function H.init(context)
 A=context
 RegisterNetEvent(E..'hospitalOpen',function(mode,station)
  local src=source
  if mode~='station' and mode~='patient' and mode~='police' then return end
  run(src,function()
   local v={actor=A.cid(src),mode=mode,station=type(station)=='string' and station or nil}
   if not v.actor or not allowed(src,v) or A.views[src] or A.working[src] then return A.notify(src,'Hospital access unavailable.') end
   v.ticket=query('scalar','SELECT UUID()')
   if not v.ticket or not allowed(src,v) then return end
   sessions[src]=v;view(src,v)
  end)
 end)
 RegisterNetEvent(E..'hospitalClose',function(ticket)
  local v=sessions[source];if v and v.ticket==ticket then sessions[source]=nil end
 end)
 RegisterNetEvent(E..'hospitalAction',function(ticket,action,id,count,search,before)
  local src=source;local v=sessions[src]
  if not v or v.ticket~=ticket or not allowed(src,v) then return end
  run(src,function()
   if sessions[src]~=v or not allowed(src,v) then return end
   if action=='detail' then return invoiceDetail(src,v,id)
   elseif action=='duty' and v.mode=='station' then A.setDuty(src,A.duty(src) and 'off' or 'on',v.station)
   elseif (action=='kit' or action=='item') and v.mode=='station' then order(src,v,action,type(id)=='string' and id or '',count)
   elseif action=='collect' and v.mode=='station' then collect(src,v)
   elseif action=='pay' or action=='waive' or action=='cancel' or action=='report' then invoiceAction(src,v,action,id)
   elseif action~='refresh' then return end
   view(src,v,search,before)
  end)
 end)
 CreateThread(function()
  while true do
   if ready and not A.legacy() then
    local ok,err=pcall(function()
     eco:CreditAccount(account,C.initialFunding,{key='med-state:initial',reason='Initial medical department funding'})
     local hour=math.floor(os.time()/C.fundingInterval)
     eco:CreditAccount(account,C.hourlyFunding,{key='med-state:'..hour,reason='Hourly state medical funding',reference=tostring(hour)})
     for _,o in ipairs(query('query',"SELECT * FROM frontier_medical_supply_orders WHERE status='pending' ORDER BY created_at LIMIT 30") or {}) do
      -- Do not race the interactive request; retry durable debits only when its character has no request in progress.
      local src=online(o.doctor);if not src or not locks[src] then debitOrder(o) end
     end
     for _,row in ipairs(query('query',"SELECT * FROM frontier_medical_invoices WHERE status='paying' ORDER BY id LIMIT 30") or {}) do
      local src=online(row.patient);if not src or not locks[src] then payInvoice(row) end
     end
    end)
    if not ok then print('[frontier_medical] Hospital worker: '..tostring(err)) end
   end
   for src,v in pairs(sessions) do
    if not allowed(src,v) then sessions[src]=nil;TriggerClientEvent(E..'hospitalCloseView',src,v.ticket) end
   end
   Wait(10000)
  end
 end)
end
