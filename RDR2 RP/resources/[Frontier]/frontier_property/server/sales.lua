local economy = exports.frontier_economy
local core = exports.frontier_core

local function tell(player, message)
    TriggerClientEvent('chat:addMessage',player,{args={'Frontier Immobilienverkauf',message}})
end

local function integer(value, ceiling)
    return math.type(value)=='integer' and value>0 and value<=ceiling
end

local function nearAgent(player)
    return NearbyPropertyAgent(player) ~= nil
end

RegisterCommand('grundverkauf',function(player,args)
    if player<=0 then return end
    local actor=core:GetPlayerCharacterId(player)
    if not actor or not nearAgent(player) then return tell(player,'Gehe zum Makler für Immobilienverkäufe.') end
    local id=tonumber(args[2])
    if not integer(id,9007199254740991) then return tell(player,'Gib eine gültige Nummer an.') end
    if args[1]=='anbieten' then
        local target, price=tonumber(args[3]),tonumber(args[4])
        if not integer(target,65535) or not integer(price,9000000000000) then
            return tell(player,'Verwendung: /grundverkauf anbieten OBJEKT SPIELER CENT.')
        end
        local buyer=core:GetPlayerCharacterId(target)
        if not buyer or buyer==actor then return tell(player,'Der Käufer ist nicht verfügbar.') end
        local result=MySQL.query.await('CALL frontier_sale_offer_v1(?,?,?,?)',{id,actor,buyer,price})
        local row=result and result[1] and result[1][1]
        if core:GetPlayerCharacterId(player)~=actor then return end
        return tell(player,row and row.id and ('Angebot #%s erstellt. Alle Eigentümer müssen zustimmen.'):format(row.id)
            or 'Dieses Objekt kann gerade nicht verkauft werden.')
    end

    local sale=MySQL.single.await([[SELECT s.id,s.property_id,s.buyer_id,s.price_cents,s.assumed_lease_id,s.state,
        (SELECT COUNT(*) FROM frontier_property_sale_approvals a WHERE a.sale_id=s.id AND a.owner_id=?) AS is_owner
        FROM frontier_property_sales s WHERE s.id=?]],{actor,id})
    if core:GetPlayerCharacterId(player)~=actor or not nearAgent(player) then return end
    if not sale or (sale.buyer_id~=actor and tonumber(sale.is_owner)~=1) then
        return tell(player,'Angebot nicht verfügbar.')
    end
    if args[1]=='info' then
        return tell(player,('Angebot #%s: Objekt #%s, $%.2f, Mietvertrag: %s.'):format(
            id,sale.property_id,sale.price_cents/100,sale.assumed_lease_id and ('#'..sale.assumed_lease_id) or 'keiner'))
    end
    if sale.state~='offered' then return tell(player,'Das Angebot kann nicht mehr geändert werden.') end
    local ok, accounts=economy:GetCharacterAccounts(player)
    if not ok or accounts.characterId~=actor or core:GetPlayerCharacterId(player)~=actor or not nearAgent(player) then return end
    if args[1]=='zustimmen' and tonumber(sale.is_owner)==1 then
        local changed=MySQL.update.await([[UPDATE frontier_property_sale_approvals a JOIN frontier_property_sales s
            ON s.id=a.sale_id SET a.bank_id=? WHERE a.sale_id=? AND a.owner_id=? AND s.state='offered']],
            {accounts.bank.id,id,actor})
        if core:GetPlayerCharacterId(player)==actor then
            tell(player,changed>0 and 'Zustimmung gespeichert.' or 'Angebot nicht verfügbar.')
        end
    elseif args[1]=='kaufen' and sale.buyer_id==actor and tonumber(args[3])==sale.price_cents then
        local result=MySQL.query.await('CALL frontier_sale_reserve_v1(?,?,?,?)',
            {id,actor,accounts.bank.id,args[4]=='miete-ja' and 1 or 0})
        local row=result and result[1] and result[1][1]
        if core:GetPlayerCharacterId(player)==actor then
            tell(player,row and tonumber(row.accepted)==1 and 'Kauf vorgemerkt.' or 'Kaufbedingungen nicht erfüllt.')
        end
    else
        tell(player,'Befehle: info ANGEBOT, zustimmen ANGEBOT, kaufen ANGEBOT CENT [miete-ja].')
    end
end,false)

local function settle(sale)
    local prefix='property:sale:'..sale.id
    local ok, issue=economy:DebitAccount(sale.buyer_bank_id,sale.price_cents,
        {key=prefix..':buyer',reason='Immobilienkauf',reference=tostring(sale.id)})
    if not ok then
        if issue=='insufficient_funds' then
            MySQL.update.await("UPDATE frontier_property_sales SET state='declined' WHERE id=? AND state='reserved'",{sale.id})
        end
        return
    end
    local owners=MySQL.query.await([[SELECT owner_id,bank_id,share_bps,paid FROM frontier_property_sale_approvals
        WHERE sale_id=? ORDER BY owner_id]],{sale.id})
    local cumulative=0
    for _, owner in ipairs(owners) do
        local previous=cumulative
        cumulative=cumulative+owner.share_bps
        local amount=sale.price_cents*cumulative//10000-sale.price_cents*previous//10000
        if tonumber(owner.paid)~=1 then
            local paid=amount==0 or economy:CreditAccount(owner.bank_id,amount,
                {key=prefix..':'..owner.owner_id,reason='Immobilienverkauf',reference=tostring(sale.id)})
            if not paid then return end
            MySQL.update.await('UPDATE frontier_property_sale_approvals SET paid=1 WHERE sale_id=? AND owner_id=?',
                {sale.id,owner.owner_id})
        end
    end
    MySQL.query.await('CALL frontier_sale_finish_v1(?)',{sale.id})
end

MySQL.ready(function()
    CreateThread(function()
        while true do
            local ok=pcall(function()
                local sales=MySQL.query.await([[SELECT id,buyer_bank_id,price_cents FROM frontier_property_sales
                    WHERE state='reserved' AND retry_at<=NOW() ORDER BY retry_at,id LIMIT 20]])
                for _, sale in ipairs(sales) do
                    MySQL.update.await('UPDATE frontier_property_sales SET retry_at=DATE_ADD(NOW(),INTERVAL 30 SECOND) WHERE id=?',{sale.id})
                    settle(sale)
                end
            end)
            if not ok then print('[frontier_property] Verkaufswarteschlange wird wiederholt.') end
            Wait(ok and 5000 or 30000)
        end
    end)
end)
