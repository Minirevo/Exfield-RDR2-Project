local cfg = PropertyConfig
local core, economy = exports.frontier_core, exports.frontier_economy
local resource = GetCurrentResourceName()
local busy = {}

local function db(method, sql, args)
    local ok, result = pcall(MySQL[method].await, sql, args)
    if not ok then
        FrontierLib.Log('ERROR', resource, 'Property database operation failed', { method = method })
        return false, 'database_error'
    end
    return true, result
end

local function validId(value)
    return type(value) == 'string' and #value >= 1 and #value <= 48
        and value:match('^[a-z0-9_]+$') ~= nil
end

local function character(source)
    local id = core:GetPlayerCharacterId(source)
    if type(id) == 'string' and #id == 34 and id:match('^f_[a-f0-9]+$') then return id end
end

local function notify(source, message)
    TriggerClientEvent('chat:addMessage', source, { args = { 'Frontier Immobilien', message } })
end

local function configuredSite(id)
    return validId(id) and cfg.Sites[id] or nil
end

local function seed()
    for id, site in pairs(cfg.Sites) do
        if not validId(id) or type(site) ~= 'table' or type(site.label) ~= 'string'
            or #site.label < 1 or #site.label > 96
            or type(site.type) ~= 'string' or #site.type > 32
            or not FrontierLib.IsInteger(site.priceMinor) or site.priceMinor < 0
            or not FrontierLib.IsInteger(site.rentMinor or 0) or (site.rentMinor or 0) < 0
            or type(site.x) ~= 'number' or type(site.y) ~= 'number' or type(site.z) ~= 'number'
            or not FrontierLib.IsInteger(site.bucket or 0) then
            FrontierLib.Log('ERROR', resource, 'Invalid property site configuration', { site = tostring(id) })
            return false
        end
        local ok = db('update', [[
            INSERT INTO frontier_properties
                (id,label,property_type,market_id,price_minor,rent_minor,x,y,z,bucket)
            VALUES (?,?,?,?,?,?,?,?,?,?)
            ON DUPLICATE KEY UPDATE label=VALUES(label),property_type=VALUES(property_type),
                market_id=VALUES(market_id),price_minor=VALUES(price_minor),rent_minor=VALUES(rent_minor),
                x=VALUES(x),y=VALUES(y),z=VALUES(z),bucket=VALUES(bucket)
        ]], { id, site.label, site.type, site.market, site.priceMinor, site.rentMinor or 0,
            site.x, site.y, site.z, site.bucket or 0 })
        if not ok then return false end
    end
    return true
end

local function listFor(source)
    local id = character(source)
    if not id then return false, 'character_unavailable' end
    local ok, rows = db('query', [[
        SELECT p.id,p.label,p.property_type,p.market_id,p.price_minor,p.rent_minor,p.state,
            p.owner_id,IF(p.owner_id=?,1,0) AS mine,
            IF(m.character_id IS NULL,0,1) AS member
        FROM frontier_properties p
        LEFT JOIN frontier_property_members m ON m.property_id=p.id AND m.character_id=?
        ORDER BY p.market_id,p.label,p.id
    ]], { id, id })
    if not ok then return false, rows end
    for _, row in ipairs(rows) do
        row.price_minor, row.rent_minor = tonumber(row.price_minor), tonumber(row.rent_minor)
        row.mine, row.member = tonumber(row.mine) == 1, tonumber(row.member) == 1
        row.owner_id = nil
    end
    return true, rows
end

local function purchase(source, propertyId)
    local id = character(source)
    if not id then return false, 'Dein Charakter ist nicht verfügbar.' end
    if not configuredSite(propertyId) then return false, 'Diese Immobilie ist nicht konfiguriert.' end

    local ok, accounts = economy:GetCharacterAccounts(source)
    if not ok or accounts.characterId ~= id or character(source) ~= id then
        return false, 'Dein Bankkonto ist momentan nicht verfügbar.'
    end

    local generated, attempt = db('scalar', 'SELECT UUID()')
    if not generated or type(attempt) ~= 'string' then
        return false, 'Der Kauf konnte nicht vorbereitet werden.'
    end
    local requestKey = ('property:%s:%s'):format(propertyId, attempt)
    local reserved, changed = db('update', [[
        UPDATE frontier_properties SET state='purchasing',owner_id=?,purchase_bank=?,purchase_key=?
        WHERE id=? AND state='available' AND owner_id IS NULL
    ]], { id, accounts.bank.id, requestKey, propertyId })
    if not reserved then return false, 'Die Immobilie konnte nicht reserviert werden.' end

    if changed == 0 then
        local read, row = db('single', 'SELECT state,owner_id,purchase_key FROM frontier_properties WHERE id=?',
            { propertyId })
        if not read then return false, 'Der Immobilienstatus konnte nicht geprüft werden.' end
        if row and row.state == 'owned' and row.owner_id == id then
            return true, 'Diese Immobilie gehört dir bereits.'
        end
        if row and row.state == 'purchasing' and row.owner_id == id and row.purchase_key == requestKey then
            return true, 'Dein Kauf wird bereits verarbeitet.'
        end
        return false, 'Diese Immobilie ist nicht mehr verfügbar.'
    end

    if character(source) ~= id then return false, 'Dein Charakter hat sich geändert.' end
    local charged, issue = economy:DebitAccount(accounts.bank.id, tonumber(cfg.Sites[propertyId].priceMinor), {
        key = requestKey .. ':debit',
        reason = 'Immobilienkauf: ' .. cfg.Sites[propertyId].label,
        reference = propertyId,
    })
    if not charged then
        db('update', [[UPDATE frontier_properties SET state='available',owner_id=NULL,purchase_bank=NULL,
            purchase_key=NULL WHERE id=? AND state='purchasing' AND owner_id=? AND purchase_key=?]],
            { propertyId, id, requestKey })
        if issue == 'insufficient_funds' then return false, 'Dein Bankguthaben reicht für diesen Kauf nicht aus.' end
        return false, 'Der Kauf konnte nicht bestätigt werden. Bitte prüfe den Immobilienstatus.'
    end

    local committed, count = db('update', [[
        UPDATE frontier_properties SET state='owned',purchased_at=UTC_TIMESTAMP()
        WHERE id=? AND state='purchasing' AND owner_id=? AND purchase_key=?
    ]], { propertyId, id, requestKey })
    if not committed or count ~= 1 then
        FrontierLib.Log('ERROR', resource, 'Property purchase charged but ownership finalization is pending',
            { property = propertyId, character = id })
        return false, 'Zahlung bestätigt; Eigentumsübertragung wird automatisch erneut verarbeitet.'
    end
    return true, 'Immobilie erfolgreich gekauft: ' .. cfg.Sites[propertyId].label
end

local function roleFor(characterId, propertyId)
    local ok, row = db('single', [[
        SELECT p.owner_id,m.role FROM frontier_properties p
        LEFT JOIN frontier_property_members m ON m.property_id=p.id AND m.character_id=?
        WHERE p.id=? AND p.state='owned'
    ]], { characterId, propertyId })
    if not ok or not row then return false, ok and 'property_not_found' or row end
    if row.owner_id == characterId then return true, 'owner' end
    if row.role then return true, row.role end
    return false, 'forbidden'
end

local function grant(source, propertyId, targetId, role)
    local ownerId = character(source)
    if not ownerId then return false, 'Dein Charakter ist nicht verfügbar.' end
    if not validId(propertyId) or type(targetId) ~= 'string' or #targetId ~= 34
        or not targetId:match('^f_[a-f0-9]+$') or (role ~= 'manager' and role ~= 'employee') then
        return false, 'Verwendung: /immobilie_rechte <ID> <Charakter-ID> <manager|employee>'
    end
    local allowed, ownRole = roleFor(ownerId, propertyId)
    if not allowed or ownRole ~= 'owner' then return false, 'Nur der Eigentümer kann Mitarbeiterrechte vergeben.' end
    local ok, count = db('scalar', 'SELECT COUNT(*) FROM frontier_property_members WHERE property_id=?', { propertyId })
    if not ok then return false, 'Die Rechte konnten nicht geprüft werden.' end
    local exists = db('scalar', 'SELECT COUNT(*) FROM frontier_property_members WHERE property_id=? AND character_id=?',
        { propertyId, targetId })
    if not exists then return false, 'Die Rechte konnten nicht geprüft werden.' end
    if tonumber(count) >= cfg.MaxMembers and tonumber(exists) == 0 then return false, 'Die Mitarbeiterliste ist voll.' end
    local saved = db('update', [[
        INSERT INTO frontier_property_members(property_id,character_id,role,granted_by)
        VALUES(?,?,?,?) ON DUPLICATE KEY UPDATE role=VALUES(role),granted_by=VALUES(granted_by)
    ]], { propertyId, targetId, role, ownerId })
    if not saved then return false, 'Die Rechte konnten nicht gespeichert werden.' end
    return true, 'Immobilienrechte wurden vergeben.'
end

local function access(characterId, propertyId, action)
    if type(characterId) ~= 'string' or #characterId ~= 34 or not characterId:match('^f_[a-f0-9]+$')
        or not validId(propertyId) or (action ~= 'view' and action ~= 'trade' and action ~= 'production') then
        return false, 'invalid_request'
    end
    local ok, role = roleFor(characterId, propertyId)
    if not ok then return false, role end
    local permitted = role == 'owner' or role == 'manager'
        or (role == 'employee' and action ~= 'view')
    if not permitted then return false, 'forbidden' end
    local loaded, row = db('single', [[
        SELECT id,label,property_type,market_id,x,y,z,bucket
        FROM frontier_properties WHERE id=? AND state='owned' AND owner_id IS NOT NULL
    ]], { propertyId })
    if not loaded or not row then return false, 'property_not_found' end
    row.role = role
    row.id = row.id
    return true, row
end

RegisterCommand('immobilien', function(source)
    if source == 0 then return end
    local ok, rows = listFor(source)
    if not ok then notify(source, 'Die Immobilienliste ist momentan nicht verfügbar.'); return end
    if #rows == 0 then notify(source, 'Es sind noch keine Immobilienstandorte konfiguriert.'); return end
    for _, row in ipairs(rows) do
        local state = row.state == 'available' and ('Verfügbar | ' .. row.price_minor .. ' Cent')
            or (row.mine and 'Dein Eigentum' or (row.member and 'Mitarbeiterzugang' or 'Vergeben'))
        notify(source, ('%s (%s) — %s'):format(row.label, row.id, state))
    end
end, false)

RegisterCommand('immobilie_kaufen', function(source, args)
    if source == 0 or busy[source] then return end
    busy[source] = true
    local ok, message = purchase(source, args[1])
    busy[source] = nil
    if character(source) then notify(source, message) end
end, false)

RegisterCommand('immobilie_rechte', function(source, args)
    if source == 0 or busy[source] then return end
    busy[source] = true
    local ok, message = grant(source, args[1], args[2], args[3])
    busy[source] = nil
    if character(source) then notify(source, message) end
end, false)

-- Trade may use the adapter only after explicitly configuring this resource as its provider.
exports('GetTradePropertyAccess', function(characterId, propertyId, action)
    if GetInvokingResource() ~= 'frontier_trade' or GetResourceState('frontier_trade') ~= 'started' then
        return false, 'forbidden'
    end
    return access(characterId, propertyId, action == 'trade' and 'trade' or 'view')
end)

exports('GetProductionPropertyAccess', function(characterId, propertyId, action)
    if GetInvokingResource() ~= 'frontier_production' or GetResourceState('frontier_production') ~= 'started' then
        return false, 'forbidden'
    end
    return access(characterId, propertyId, action == 'production' and 'production' or 'view')
end)

exports('GetPropertyAccess', function(characterId, propertyId, action)
    local caller = GetInvokingResource()
    if caller ~= 'frontier_trade' and caller ~= 'frontier_production' and caller ~= 'frontier_property' then
        return false, 'forbidden'
    end
    return access(characterId, propertyId, action)
end)

local function reconcilePurchases()
    local ok, rows = db('query', [[
        SELECT id,owner_id,purchase_bank,purchase_key,price_minor,label
        FROM frontier_properties WHERE state='purchasing' AND owner_id IS NOT NULL
        ORDER BY updated_at,id LIMIT 20
    ]])
    if not ok then return end
    for _, row in ipairs(rows) do
        local charged, issue = economy:DebitAccount(tonumber(row.purchase_bank), tonumber(row.price_minor), {
            key = row.purchase_key .. ':debit',
            reason = 'Immobilienkauf: ' .. row.label,
            reference = row.id,
        })
        if charged then
            db('update', [[UPDATE frontier_properties SET state='owned',purchased_at=UTC_TIMESTAMP()
                WHERE id=? AND state='purchasing' AND owner_id=? AND purchase_key=?]],
                { row.id, row.owner_id, row.purchase_key })
        elseif issue == 'insufficient_funds' then
            db('update', [[UPDATE frontier_properties SET state='available',owner_id=NULL,purchase_bank=NULL,
                purchase_key=NULL WHERE id=? AND state='purchasing' AND owner_id=? AND purchase_key=?]],
                { row.id, row.owner_id, row.purchase_key })
        end
    end
end

MySQL.ready(function()
    while cfg.Enabled do
        local ok, ready = pcall(seed)
        if ok and ready then break end
        Wait(cfg.WorkerIntervalMs)
    end
    while cfg.Enabled do
        local ok = pcall(reconcilePurchases)
        if not ok then FrontierLib.Log('WARN', resource, 'Property purchase reconciliation failed') end
        Wait(cfg.WorkerIntervalMs)
    end
end)

AddEventHandler('playerDropped', function() busy[tonumber(source) or 0] = nil end)
