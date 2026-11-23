local economy = exports.frontier_economy
local core = exports.frontier_core

local function boundaries()
    -- Read the revision first. Any subsequent change invalidates the reservation CAS.
    local revision = MySQL.scalar.await('SELECT revision FROM frontier_land_revision WHERE id=1')
    local rows = MySQL.query.await("SELECT polygon_json FROM frontier_land_claims WHERE state IN ('reserved','owned')")
    local blocked = {}
    for _, row in ipairs(rows) do
        local points = json.decode(row.polygon_json)
        if type(points) ~= 'table' then error('Invalid registered land polygon') end
        blocked[#blocked + 1] = points
    end
    return revision, blocked
end

function ReservePropertyLand(source, character, zoneKey, points, expectedCost)
    local zone = PropertyConfig.SurveyZones[zoneKey]
    if not zone or zone.enablePurchase ~= true or #zoneKey > 64
        or not zoneKey:match('^[a-z0-9_-]+$') then return nil, 'disabled' end
    local rate = zone.priceCentsPerSquareMeter
    if math.type(rate) ~= 'integer' or rate <= 0 or rate > 100000000 then return nil, 'invalid_price' end
    if not points[1] or type(points[1].z) ~= 'number' or points[1].z ~= points[1].z
        or math.abs(points[1].z) > 1000000 then return nil, 'invalid_position' end
    local revision, blocked = boundaries()
    for _, exclusion in ipairs(zone.exclusions or {}) do blocked[#blocked + 1] = exclusion end
    local area = ValidatePropertySurvey(points, zone.boundary, blocked)
    if not area then return nil, 'unavailable' end
    local price = math.ceil(area * rate)
    if price > 9000000000000 then return nil, 'invalid_price' end
    if price ~= expectedCost then return nil, 'price_changed' end
    local ok, accounts = economy:GetCharacterAccounts(source)
    if not ok or accounts.characterId ~= character or core:GetPlayerCharacterId(source) ~= character then
        return nil, 'no_account'
    end
    local result = MySQL.query.await('CALL frontier_land_reserve_v1(?,?,?,?,?,?,?)', {
        revision, character, zoneKey, json.encode(points), area, price, accounts.bank.id,
    })
    local first = result and result[1]
    local row = first and (first[1] or first)
    return row and row.id, 'unavailable'
end

function LatestPropertyLandClaim(character)
    return MySQL.scalar.await('SELECT state FROM frontier_land_claims WHERE character_id=? ORDER BY id DESC LIMIT 1', { character })
end

local function settle(claim)
    local ok, errorCode = economy:DebitAccount(claim.account_id, claim.price_cents, {
        key = 'land:purchase:' .. tostring(claim.id), reason = 'Grundstückskauf',
        reference = tostring(claim.id),
    })
    if ok or errorCode == 'insufficient_funds' then
        MySQL.query.await('CALL frontier_land_finish_v1(?,?)', { claim.id, ok and 1 or 0 })
    end
end

-- A single RedM worker per schema dispatches payments. SQL and Economy make retries replayable.
MySQL.ready(function()
    CreateThread(function()
        while true do
            local ok = pcall(function()
                local claims = MySQL.query.await([[
                    SELECT id,account_id,price_cents FROM frontier_land_claims
                    WHERE state='reserved' AND retry_at <= NOW()
                    ORDER BY retry_at,id LIMIT 20
                ]])
                for _, claim in ipairs(claims) do
                    local claimed = MySQL.update.await('UPDATE frontier_land_claims SET retry_at=DATE_ADD(NOW(),INTERVAL 30 SECOND) WHERE id=? AND retry_at <= NOW() AND state=\'reserved\'', { claim.id })
                    if claimed == 1 then
                        local settled = pcall(settle, claim)
                        if not settled then print('[frontier_property] Wiederholung für Landkauf ' .. claim.id) end
                    end
                end
            end)
            if not ok then print('[frontier_property] Landkauf-Warteschlange vorübergehend nicht verfügbar.') end
            Wait(ok and 2000 or 30000)
        end
    end)
end)
