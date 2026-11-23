local core, economy = exports.frontier_core, exports.frontier_economy

local function tell(player, message)
    TriggerClientEvent('chat:addMessage',player,{args={'Frontier Grundsteuer',message}})
end

RegisterCommand('grundsteuer',function(player,args)
    if player<=0 then return end
    local actor=core:GetPlayerCharacterId(player)
    local estate=tonumber(args[2])
    if not actor or math.type(estate)~='integer' or estate<=0 or estate>9007199254740991 then
        return tell(player,'Verwendung: /grundsteuer info|zahlen OBJEKT [CENT].')
    end
    local row=MySQL.single.await([[SELECT COALESCE(f.debt_cents,0) AS debt,
        DATE_FORMAT(f.next_due,'%Y-%m-%d %H:%i') AS due FROM frontier_properties p
        JOIN frontier_property_ownership o ON o.property_id=p.id AND o.party_type='character' AND o.party_id=?
        LEFT JOIN frontier_property_finance f ON f.property_id=p.id WHERE p.id=? AND p.status='active']],{actor,estate})
    if core:GetPlayerCharacterId(player)~=actor then return end
    if not row then return tell(player,'Kein eigenes aktives Objekt gefunden.') end
    if args[1]=='info' then return tell(player,('Offen $%.2f. Nächste Fälligkeit: %s. Zahlung: /grundsteuer zahlen %d %d'):format(
        row.debt/100,row.due and (row.due..' UTC') or 'nicht geplant',estate,row.debt)) end
    if args[1]~='zahlen' or row.debt<=0 or tonumber(args[3])~=row.debt then
        return tell(player,'Rufe zuerst die aktuelle Abrechnung mit /grundsteuer info OBJEKT auf.')
    end
    local ok, accounts=economy:GetCharacterAccounts(player)
    if not ok or accounts.characterId~=actor or core:GetPlayerCharacterId(player)~=actor then return end
    local res=MySQL.query.await('CALL frontier_upkeep_reserve_v1(?,?,?,?)',{estate,actor,accounts.bank.id,row.debt})
    local receipt=res and res[1] and res[1][1]
    if core:GetPlayerCharacterId(player)==actor then
        tell(player,receipt and receipt.id and 'Zahlung zur Verarbeitung vorgemerkt.' or 'Betrag geändert oder Zahlung bereits offen.')
    end
end,false)

local function options(kind,id,suffix,reason)
    return {key='property:'..kind..':'..id..suffix, reason=reason, reference=tostring(id)}
end

local function settlePayout(row)
    -- The deduction, debt share and state penalty are ledger allocations, not bank credits.
    local owners=MySQL.query.await([[SELECT p.owner_id,p.share_bps,p.paid,p.bank_id,a.id AS current_bank_id
        FROM frontier_property_foreclosure_payees p LEFT JOIN frontier_economy_accounts a
          ON a.owner_type='character' AND a.owner_id=p.owner_id AND a.account_type='bank'
        WHERE p.foreclosure_id=? ORDER BY p.owner_id]],{row.id})
    local cumulative=0
    for _, owner in ipairs(owners) do
        local previous=cumulative
        cumulative=cumulative+owner.share_bps
        if tonumber(owner.paid)~=1 then
            local amount=row.owner_payout_cents*cumulative//10000-row.owner_payout_cents*previous//10000
            if amount>0 and not owner.bank_id and owner.current_bank_id then
                MySQL.update.await([[UPDATE frontier_property_foreclosure_payees SET bank_id=?
                    WHERE foreclosure_id=? AND owner_id=? AND bank_id IS NULL]],
                    {owner.current_bank_id,row.id,owner.owner_id})
                owner.bank_id=owner.current_bank_id
            end
            local paid=amount==0 or (owner.bank_id and economy:CreditAccount(owner.bank_id,amount,
                options('foreclosure',row.id,':'..owner.owner_id,'Auszahlung aus Zwangsverwertung')))
            if not paid then return end
            MySQL.update.await('UPDATE frontier_property_foreclosure_payees SET paid=1 WHERE foreclosure_id=? AND owner_id=?',
                {row.id,owner.owner_id})
        end
    end
    MySQL.query.await('CALL frontier_foreclosure_finish_v2(?)',{row.id})
end

local function inRange(value, minimum, maximum)
    return math.type(value)=='integer' and value>=minimum and value<=maximum
end

local function doUpkeep()
    local conf=PropertyConfig.Upkeep
    if not conf.enabled or not inRange(conf.rateBps,1,10000)
        or not inRange(conf.intervalSeconds,60,31536000) then return end
    local rows=MySQL.query.await([[SELECT p.id FROM frontier_properties p LEFT JOIN frontier_property_finance f
        ON f.property_id=p.id WHERE p.status='active' AND (f.next_due IS NULL OR f.next_due<=UTC_TIMESTAMP())
        AND EXISTS (SELECT 1 FROM frontier_property_ownership o WHERE o.property_id=p.id AND o.party_type='character')
        AND NOT EXISTS (SELECT 1 FROM frontier_property_sales s WHERE s.property_id=p.id AND s.state='reserved')
        ORDER BY f.next_due,p.id LIMIT 50]])
    for _, row in ipairs(rows) do
        MySQL.query.await('CALL frontier_upkeep_accrue_v1(?,?,?)',{row.id,conf.rateBps,conf.intervalSeconds})
    end
    if not inRange(conf.forecloseDebtCents,1,9000000000000)
        or not inRange(conf.graceSeconds,0,31536000)
        or not inRange(PropertyConfig.ForeclosureDeductionBps,0,10000)
        or not inRange(PropertyConfig.ForeclosureStatePenaltyBps,0,10000) then return end
    local eligible=MySQL.query.await([[SELECT f.property_id FROM frontier_property_finance f JOIN frontier_properties p
        ON p.id=f.property_id WHERE p.status='active' AND f.debt_cents>=?
        AND TIMESTAMPDIFF(SECOND,f.debt_since,UTC_TIMESTAMP())>=? ORDER BY f.property_id LIMIT 50]],
        {conf.forecloseDebtCents,conf.graceSeconds})
    for _, row in ipairs(eligible) do
        MySQL.query.await('CALL frontier_foreclosure_open_v2(?,?,?,?,?)',{row.property_id,
            conf.forecloseDebtCents,conf.graceSeconds,PropertyConfig.ForeclosureDeductionBps,
            PropertyConfig.ForeclosureStatePenaltyBps})
    end
end

MySQL.ready(function()
    CreateThread(function()
        local nextBilling=0
        while true do
            local ok=pcall(function()
                local bills=MySQL.query.await([[SELECT id,account_id,amount_cents FROM frontier_property_upkeep_payments
                    WHERE state='pending' AND retry_at<=NOW() ORDER BY retry_at,id LIMIT 20]])
                for _, row in ipairs(bills) do
                    MySQL.update.await([[UPDATE frontier_property_upkeep_payments
                        SET retry_at=DATE_ADD(NOW(),INTERVAL 30 SECOND) WHERE id=?]],{row.id})
                    local paid, issue=economy:DebitAccount(row.account_id,row.amount_cents,
                        options('upkeep',row.id,'','Grundsteuer'))
                    if paid or issue=='insufficient_funds' then
                        MySQL.query.await('CALL frontier_upkeep_finish_v1(?,?)',{row.id,paid and 1 or 0})
                    end
                end
                local foreclosures=MySQL.query.await([[SELECT * FROM frontier_property_foreclosures
                    WHERE state='pending' AND retry_at<=NOW() ORDER BY retry_at,id LIMIT 20]])
                for _, row in ipairs(foreclosures) do
                    MySQL.update.await([[UPDATE frontier_property_foreclosures
                        SET retry_at=DATE_ADD(NOW(),INTERVAL 30 SECOND) WHERE id=?]],{row.id})
                    settlePayout(row)
                end
                if os.time()>=nextBilling then
                    nextBilling=os.time()+60
                    doUpkeep()
                end
            end)
            if not ok then print('[frontier_property] Steuer- und Verwertungswarteschlange wird wiederholt.') end
            Wait(ok and 5000 or 30000)
        end
    end)
end)
