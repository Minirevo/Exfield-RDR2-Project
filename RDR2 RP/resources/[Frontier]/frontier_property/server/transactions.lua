local _ENV=PropertyRuntime
function bank(id)
    return tonumber(MySQL.scalar.await("SELECT id FROM frontier_economy_accounts WHERE owner_type='character' AND owner_id=? AND account_type='bank' AND currency='USD'",{id}))
end
function account(src,id)
    local ok,a=eco:GetCharacterAccounts(src)
    if ok and a.characterId==id and cid(src)==id then return a.bank.id end
end
function opts(job,suffix) return {key='property:'..job.id..':'..suffix,reason='Frontier property '..job.kind,reference=job.id} end
function queue(j)
    j.id=uuid(); S.jobs[j.id]=j; save()
end
function endJob(j,outcome) j.outcome=outcome; S.history=S.history or {}; S.history[j.id]=j; S.jobs[j.id]=nil; save(); S.history[j.id]=nil end
function failJob(j,msg)
    if j.src and cid(j.src)==j.actor then notice(j.src,msg) end
    endJob(j,'failed')
end
function finishJob(j,msg)
    endJob(j,'complete')
    if j.src and cid(j.src)==j.actor then notice(j.src,msg or 'Done.'); TriggerClientEvent(E..'refresh',j.src) end
end
function definite(code) return code=='insufficient_funds' or code=='quantity' or code=='slots' or code=='weight' or code=='capacity' or code=='insufficient_stock' end
function item(j,add,key,itemId,qty)
    return inv:PropertyChangeCharacter(j.actor,itemId,qty,add,j.id..':'..key)
end
function debit(j)
    if j.paid then return true end
    local ok,err=eco:DebitAccount(j.account,j.amount,opts(j,'debit'))
    if ok then j.paid=true; save(); return true end
    if definite(err) or err=='invalid_account' or err=='invalid_amount' or err=='forbidden' then failJob(j,err)
    elseif j.lastIssue~=tostring(err) then j.lastIssue=tostring(err);save();print('[frontier_property] Payment pending '..j.id..': '..j.lastIssue) end
    return false
end
function take(j)
    local ok,err=item(j,false,'take',j.item,j.qty or 1)
    if ok then return true end
    if definite(err) then failJob(j,err) end
    return false
end
function payout(j)
    for k,p in ipairs(j.payouts or {}) do
        if p.amount>0 and not p.done then
            local ok=eco:CreditAccount(p.account,p.amount,opts(j,'credit'..k))
            if not ok then return false end
            p.done=true; save()
        end
    end
    return true
end
function shares(s,amount)
    local ids={}; for id in pairs(s.owners) do ids[#ids+1]=id end; table.sort(ids)
    local out={}; local rest=amount
    for i,id in ipairs(ids) do
        local a=bank(id); if not a then return end
        local n=i==#ids and rest or math.floor(amount/#ids)
        rest=rest-n; out[#out+1]={account=a,amount=n}
    end
    return out
end
function process(j)
    local s=settlement(j.sid)
    if j.kind=='claim' then
        local ok=inv:CreateStorage({id=chestId(j.sid),name='Settlement chest',slots=C.StorageSlots,grams=C.StorageGrams,ace=''})
        if not ok then return end
        if not take(j) then return end
        S.settlements[j.sid]=j.claim
        finishJob(j,'Settlement established!')
    elseif j.kind=='shop' then
        if not debit(j) then return end
        if not j.refund then
            local ok,err=item(j,true,'grant',j.item,1)
            if ok then finishJob(j,'Item purchased.'); return end
            -- Configuration/validation failures are terminal, while ambiguous
            -- database outcomes must replay the same grant before refunding.
            if not definite(err) and err~='invalid_item' and err~='invalid_request' and err~='forbidden' and err~='invalid_metadata' then
                if j.lastIssue~=tostring(err) then j.lastIssue=tostring(err);save();print('[frontier_property] Shop grant pending '..j.id..': '..j.lastIssue) end
                return
            end
            j.refund=true;j.refundReason=tostring(err);save()
        end
        if eco:CreditAccount(j.account,j.amount,opts(j,'refund')) then finishJob(j,'Item could not be delivered ('..(j.refundReason or 'inventory full')..'); payment refunded.') end
    elseif j.kind=='expand' then
        if not debit(j) then return end
        s.radius=j.radius; finishJob(j,'Territory expanded.')
    elseif j.kind=='tax' then
        if not debit(j) then return end
        s.debt=math.max(0,s.debt-j.amount)
        if s.debt==0 then s.overdue=nil end
        finishJob(j,'Tax paid.')
    elseif j.kind=='deliver' then
        if not take(j) then return end
        local b=s.buildings[j.bid]
        b.delivered[j.item]=(b.delivered[j.item] or 0)+j.qty
        finishJob(j,'Materials delivered.')
    elseif j.kind=='furniture' then
        if not take(j) then return end
        if j.physical then s.furniture=s.furniture or {};s.furniture[j.fid]=j.furniture
        else s.buildings[j.bid].furniture[j.fid]=j.furniture end
        finishJob(j,'Furniture placed.')
    elseif j.kind=='removeFurniture' then
        local ok,err=item(j,true,'return',j.item,1)
        if ok then if j.physical then s.furniture[j.fid]=nil else s.buildings[j.bid].furniture[j.fid]=nil end; finishJob(j,'Furniture returned to inventory.')
        elseif definite(err) then failJob(j,err) end
    elseif j.kind=='sale' then
        if not debit(j) then return end
        if not payout(j) then return end
        s.owners={[j.actor]=true}; s.primary=j.actor; s.members={}; s.listing=nil
        finishJob(j,'Settlement purchased, including chest and furniture.')
    elseif j.kind=='foreclose' then
        local farm=GetResourceState('frontier_farming')
        if farm~='missing' and (farm~='started' or not exports.frontier_farming:DrainPlot(j.sid)) then return end
        if not payout(j) then return end
        s.status='abandoned'; s.listing=nil; finishJob(j)
    end
end
