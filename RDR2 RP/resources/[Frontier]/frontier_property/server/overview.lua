local function tell(player, message)
    TriggerClientEvent('chat:addMessage', player, { args = { 'Frontier Grundbesitz', message } })
end

RegisterCommand('grundbesitz', function(player)
    if player <= 0 then return end
    local core = exports.frontier_core
    local character = core:GetPlayerCharacterId(player)
    if not character then
        tell(player, 'Wähle zuerst einen Charakter.')
        return
    end

    local rows = MySQL.query.await([[
        SELECT p.id, p.label, p.property_type, o.share_bps
        FROM frontier_property_ownership o
        JOIN frontier_properties p ON p.id = o.property_id
        WHERE o.party_type = 'character' AND o.party_id = ? AND p.status = 'active'
        ORDER BY p.id LIMIT 11
    ]], { character })

    -- The source may have changed characters while the query was running.
    if core:GetPlayerCharacterId(player) ~= character then return end
    if #rows == 0 then
        tell(player, 'Du hast keinen eingetragenen Grundbesitz.')
        return
    end

    local labels = { building = 'Gebäude', land = 'Grundstück', constructed = 'Bauwerk' }
    for index = 1, math.min(#rows, 10) do
        local row = rows[index]
        tell(player, ('#%s %s (%s) · Anteil %.2f %%'):format(
            row.id, row.label, labels[row.property_type] or 'Grundbesitz', row.share_bps / 100
        ))
    end
    if #rows > 10 then tell(player, 'Die Übersicht zeigt die ersten zehn Einträge.') end
end, false)
