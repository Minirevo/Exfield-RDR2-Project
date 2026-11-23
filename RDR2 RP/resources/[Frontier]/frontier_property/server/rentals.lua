local economy = exports.frontier_economy
local core = exports.frontier_core

local function validInteger(value, max)
    return math.type(value) == 'integer' and value > 0 and value <= max
end

local function depositFor(price, deposit)
    if deposit == nil or deposit == 0 then return 0 end
    if validInteger(deposit, 9000000000000 - price) then return deposit end
end

local function tell(source, message)
    TriggerClientEvent('chat:addMessage', source, { args = { 'Frontier Vermietung', message } })
end

local function locateOffer(source, id)
    local offer = PropertyConfig.GovernmentRentals[id]
    if not offer or not validInteger(offer.price, 9000000000000)
        or depositFor(offer.price, offer.deposit) == nil
        or not validInteger(offer.seconds, 31536000)
        or GetPlayerRoutingBucket(source) ~= 0 then return nil end
    local ped = GetPlayerPed(source)
    if ped == 0 or #(GetEntityCoords(ped) - offer.agent) > 4 then return nil end
    return offer
end

RegisterCommand('grundmiete', function(source, args)
    if source <= 0 then return end
    local character = core:GetPlayerCharacterId(source)
    if not character then return tell(source, 'Wähle zuerst einen Charakter.') end
    if args[1] == 'status' then
        local row = MySQL.single.await([[
            SELECT property_id, CASE WHEN state='active' AND ends_at<=UTC_TIMESTAMP()
                THEN 'expired' ELSE state END AS state,
                DATE_FORMAT(ends_at, '%Y-%m-%d %H:%i') AS ends
            FROM frontier_property_rentals WHERE tenant_id=? ORDER BY id DESC LIMIT 1
        ]], { character })
        if core:GetPlayerCharacterId(source) ~= character then return end
        if not row then return tell(source, 'Kein Mietantrag gefunden.') end
        local states = { reserved = 'in Bearbeitung', active = 'aktiv',
            expired = 'abgelaufen', declined = 'abgelehnt' }
        local expiry = row.state == 'active' and (' bis ' .. row.ends .. ' UTC') or ''
        return tell(source, ('Mietobjekt #%s: %s%s.'):format(row.property_id, states[row.state], expiry))
    end
    local id = tonumber(args[2])
    local offer = id and locateOffer(source, id)
    if not offer then return tell(source, 'Gib ein Mietangebot am zuständigen Makler an.') end
    local deposit = depositFor(offer.price, offer.deposit)
    if args[1] == 'angebot' then
        return tell(source, ('#%d: $%.2f für %.2f Stunden, Kaution $%.2f. Möblieren: %s. Bestätigen: /grundmiete buchen %d %d %d'):format(
            id, offer.price / 100, offer.seconds / 3600, deposit / 100, offer.furnish and 'ja' or 'nein', id, offer.price, deposit
        ))
    end
    if args[1] ~= 'buchen' or tonumber(args[3]) ~= offer.price or tonumber(args[4]) ~= deposit then
        return tell(source, 'Rufe zuerst das aktuelle Angebot auf: /grundmiete angebot NUMMER.')
    end
    local ok, accounts = economy:GetCharacterAccounts(source)
    if not ok or accounts.characterId ~= character or core:GetPlayerCharacterId(source) ~= character
        or locateOffer(source, id) ~= offer then return end
    local result = MySQL.query.await('CALL frontier_property_rent_reserve_v2(?,?,?,?,?,?,?)', {
        id, character, accounts.bank.id, offer.price, offer.seconds, offer.furnish and 1 or 0, deposit,
    })
    if core:GetPlayerCharacterId(source) ~= character then return end
    local receipt = result and result[1] and result[1][1]
    if receipt and receipt.id then
        return tell(source, 'Mietantrag vorgemerkt. Prüfe ihn mit /grundmiete status.')
    end
    return tell(source, 'Dieses Mietobjekt ist nicht verfügbar.')
end, false)

local function atPrivateAgent(source)
    local agent = PropertyConfig.PrivateRentalAgent
    if not agent or GetPlayerRoutingBucket(source) ~= 0 then return false end
    local ped = GetPlayerPed(source)
    return ped ~= 0 and #(GetEntityCoords(ped) - agent) <= 4
end

RegisterCommand('privatmiete', function(source, args)
    if source <= 0 then return end
    local character = core:GetPlayerCharacterId(source)
    if not character or not atPrivateAgent(source) then
        return tell(source, 'Wähle einen Charakter und gehe zum Makler für Privatmieten.')
    end
    local id = tonumber(args[2])
    if not validInteger(id, 9007199254740991) then return tell(source, 'Gib eine gültige Objektnummer an.') end
    local action = args[1]
    if action == 'angebot' then
        local entry = MySQL.single.await([[
            SELECT price_cents,duration_seconds,allow_furnish,offer_version,deposit_cents
            FROM frontier_property_private_offers WHERE property_id=?
        ]], { id })
        if core:GetPlayerCharacterId(source) ~= character or not atPrivateAgent(source) then return end
        if not entry then return tell(source, 'Kein privates Mietangebot gefunden.') end
        return tell(source, ('#%d: $%.2f für %.2f Stunden, Kaution $%.2f. Möblieren: %s. Bestätigen: /privatmiete buchen %d %s'):format(
            id, entry.price_cents / 100, entry.duration_seconds / 3600, entry.deposit_cents / 100,
            tonumber(entry.allow_furnish) == 1 and 'ja' or 'nein', id, entry.offer_version))
    end

    local sql, parameters
    if action == 'anbieten' then
        local price, hours = tonumber(args[3]), tonumber(args[4])
        if not validInteger(price, 9000000000000) or not validInteger(hours, 8760)
            or (args[5] ~= 'ja' and args[5] ~= 'nein') then
            return tell(source, 'Verwendung: /privatmiete anbieten ID CENT STUNDEN ja|nein [KAUTION_CENT].')
        end
        local deposit = depositFor(price, args[6] and (tonumber(args[6]) or false))
        if deposit == nil then return tell(source, 'Gib eine gültige Kaution in Cent an.') end
        sql = 'CALL frontier_property_rent_offer_v2(?,?,?,?,?,?,?)'
        parameters = { id, character, false, price, hours * 3600, args[5] == 'ja' and 1 or 0, deposit }
    elseif action == 'buchen' then
        local version = args[3]
        if type(version) ~= 'string' or #version ~= 36 or not version:match('^[0-9a-f%-]+$') then
            return tell(source, 'Rufe zuerst /privatmiete angebot ID auf.')
        end
        sql = 'CALL frontier_property_private_rent_v2(?,?,?,?)'
        parameters = { id, character, false, version }
    else
        return tell(source, 'Verwendung: /privatmiete anbieten|angebot|buchen ID.')
    end

    local ok, accounts = economy:GetCharacterAccounts(source)
    if not ok or accounts.characterId ~= character or not atPrivateAgent(source)
        or core:GetPlayerCharacterId(source) ~= character then return end
    parameters[3] = accounts.bank.id
    local rows = MySQL.query.await(sql, parameters)
    if core:GetPlayerCharacterId(source) ~= character then return end
    local row = rows and rows[1] and rows[1][1]
    if row and tonumber(row.accepted) == 1 then return tell(source, 'Privates Mietangebot gespeichert.') end
    if row and row.id then return tell(source, 'Mietantrag vorgemerkt. Prüfe ihn mit /grundmiete status.') end
    tell(source, 'Das Objekt ist nicht verfügbar oder das Angebot ist nicht mehr gültig.')
end, false)

local function settle(rental)
    local options = {
        key = 'property:rent:' .. tostring(rental.id), reason = 'Grundmiete', reference = tostring(rental.id),
    }
    local paid, issue
    if rental.deposit_cents > 0 then
        options.key = options.key .. ':collect'
        paid, issue = economy:DebitAccount(rental.account_id, rental.price_cents + rental.deposit_cents, options)
        if paid and rental.landlord_bank_id then
            options.key = 'property:rent:' .. tostring(rental.id) .. ':landlord'
            local credited = economy:CreditAccount(rental.landlord_bank_id, rental.price_cents, options)
            if not credited then return end
        end
    elseif rental.landlord_bank_id then
        paid, issue = economy:TransferAccounts(rental.account_id, rental.landlord_bank_id, rental.price_cents, options)
    else
        paid, issue = economy:DebitAccount(rental.account_id, rental.price_cents, options)
    end
    if paid then
        MySQL.update.await([[
            UPDATE frontier_property_rentals
            SET state='active', ends_at=DATE_ADD(UTC_TIMESTAMP(), INTERVAL duration_seconds SECOND)
            WHERE id=? AND state='reserved'
        ]], { rental.id })
    elseif issue == 'insufficient_funds' or issue == 'balance_limit' then
        MySQL.update.await("UPDATE frontier_property_rentals SET state='declined' WHERE id=? AND state='reserved'",
            { rental.id })
    end
end

MySQL.ready(function()
    CreateThread(function()
        while true do
            local ok = pcall(function()
                MySQL.update.await([[UPDATE frontier_property_rentals SET state='expired'
                    WHERE state='active' AND ends_at <= UTC_TIMESTAMP()]])
                local rows = MySQL.query.await([[SELECT id,account_id,price_cents,landlord_bank_id,deposit_cents FROM frontier_property_rentals
                    WHERE state='reserved' AND retry_at<=NOW() ORDER BY retry_at,id LIMIT 20]])
                for _, row in ipairs(rows) do
                    local claimed = MySQL.update.await([[UPDATE frontier_property_rentals
                        SET retry_at=DATE_ADD(NOW(),INTERVAL 30 SECOND)
                        WHERE id=? AND state='reserved' AND retry_at<=NOW()]], { row.id })
                    if claimed == 1 then settle(row) end
                end
                local refunds = MySQL.query.await([[SELECT id,account_id,deposit_cents
                    FROM frontier_property_rentals WHERE state='expired'
                    AND deposit_refunded=0 AND deposit_cents>0 AND retry_at<=NOW()
                    ORDER BY retry_at,id LIMIT 20]])
                for _, row in ipairs(refunds) do
                    local claimed = MySQL.update.await([[UPDATE frontier_property_rentals
                        SET retry_at=DATE_ADD(NOW(),INTERVAL 30 SECOND)
                        WHERE id=? AND state='expired' AND deposit_refunded=0 AND retry_at<=NOW()]], { row.id })
                    if claimed == 1 then
                        local refunded = economy:CreditAccount(row.account_id, row.deposit_cents, {
                            key='property:rent:' .. tostring(row.id) .. ':refund',
                            reason='Mietkaution zurückgezahlt', reference=tostring(row.id),
                        })
                        if refunded then
                            MySQL.update.await('UPDATE frontier_property_rentals SET deposit_refunded=1 WHERE id=?',
                                { row.id })
                        end
                    end
                end
            end)
            if not ok then print('[frontier_property] Mietverarbeitung wird wiederholt.') end
            Wait(ok and 5000 or 30000)
        end
    end)
end)
