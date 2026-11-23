local economy = exports.frontier_economy
local core = exports.frontier_core

local function validInteger(value, max)
    return math.type(value) == 'integer' and value > 0 and value <= max
end

local function tell(source, message)
    TriggerClientEvent('chat:addMessage', source, { args = { 'Frontier Vermietung', message } })
end

local function locateOffer(source, id)
    local offer = PropertyConfig.GovernmentRentals[id]
    if not offer or not validInteger(offer.price, 9000000000000)
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
    local id = tonumber(args[2])
    local offer = id and locateOffer(source, id)
    if not offer then return tell(source, 'Gib ein Mietangebot am zuständigen Makler an.') end
    if args[1] == 'angebot' then
        return tell(source, ('#%d: $%.2f für %.2f Stunden. Möblieren: %s. Bestätigen: /grundmiete buchen %d %d'):format(
            id, offer.price / 100, offer.seconds / 3600, offer.furnish and 'ja' or 'nein', id, offer.price
        ))
    end
    if args[1] ~= 'buchen' or tonumber(args[3]) ~= offer.price then
        return tell(source, 'Rufe zuerst das aktuelle Angebot auf: /grundmiete angebot NUMMER.')
    end
    local ok, accounts = economy:GetCharacterAccounts(source)
    if not ok or accounts.characterId ~= character or core:GetPlayerCharacterId(source) ~= character
        or locateOffer(source, id) ~= offer then return end
    local result = MySQL.query.await('CALL frontier_property_rent_reserve_v1(?,?,?,?,?,?)', {
        id, character, accounts.bank.id, offer.price, offer.seconds, offer.furnish and 1 or 0,
    })
    if core:GetPlayerCharacterId(source) ~= character then return end
    local receipt = result and result[1] and result[1][1]
    if receipt and receipt.id then
        return tell(source, 'Mietantrag vorgemerkt. Die Zahlung wird verarbeitet.')
    end
    return tell(source, 'Dieses Mietobjekt ist nicht verfügbar.')
end, false)

local function settle(rental)
    local paid, issue = economy:DebitAccount(rental.account_id, rental.price_cents, {
        key = 'property:rent:' .. tostring(rental.id), reason = 'Grundmiete', reference = tostring(rental.id),
    })
    if paid then
        MySQL.update.await([[
            UPDATE frontier_property_rentals
            SET state='active', ends_at=DATE_ADD(UTC_TIMESTAMP(), INTERVAL duration_seconds SECOND)
            WHERE id=? AND state='reserved'
        ]], { rental.id })
    elseif issue == 'insufficient_funds' then
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
                local rows = MySQL.query.await([[SELECT id,account_id,price_cents FROM frontier_property_rentals
                    WHERE state='reserved' AND retry_at<=NOW() ORDER BY retry_at,id LIMIT 20]])
                for _, row in ipairs(rows) do
                    local claimed = MySQL.update.await([[UPDATE frontier_property_rentals
                        SET retry_at=DATE_ADD(NOW(),INTERVAL 30 SECOND)
                        WHERE id=? AND state='reserved' AND retry_at<=NOW()]], { row.id })
                    if claimed == 1 then settle(row) end
                end
            end)
            if not ok then print('[frontier_property] Mietverarbeitung wird wiederholt.') end
            Wait(ok and 5000 or 30000)
        end
    end)
end)
