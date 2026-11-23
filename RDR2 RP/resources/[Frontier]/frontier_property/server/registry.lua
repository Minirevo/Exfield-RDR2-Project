local permissions = {
    enter = true, furnish = true, use_facility = true, construct = true, manage_access = true,
}

local function validId(id)
    return type(id) == 'number' and math.type(id) == 'integer' and id > 0
        and id <= 9007199254740991
end

local function validCharacter(id)
    return type(id) == 'string' and #id == 34 and id:match('^f_[0-9a-f]+$') ~= nil
end

local function getProperty(id)
    if not validId(id) then return nil end
    return MySQL.single.await([[
        SELECT id, property_type, label, exterior_x, exterior_y, exterior_z,
               interior_key, estimated_value_cents
        FROM frontier_properties WHERE id = ? AND status = 'active'
    ]], { id })
end

local function canAccess(character, id, permission)
    if not validCharacter(character) or not validId(id) or not permissions[permission] then return false end
    local result = MySQL.scalar.await([[
        SELECT CASE WHEN grant_row.allow_access = 0 THEN 0
            WHEN lease.id IS NOT NULL AND ? = 'furnish' THEN lease.allow_furnish
            WHEN owner_row.party_id IS NOT NULL OR grant_row.allow_access = 1 THEN 1
            WHEN lease.id IS NOT NULL AND ? = 'enter' THEN 1
            ELSE 0 END
        FROM frontier_properties p
        LEFT JOIN frontier_property_permissions grant_row
          ON grant_row.property_id = p.id AND grant_row.character_id = ? AND grant_row.permission_key = ?
        LEFT JOIN frontier_property_ownership owner_row
          ON owner_row.property_id = p.id AND owner_row.party_type = 'character' AND owner_row.party_id = ?
        LEFT JOIN frontier_property_rentals lease
          ON lease.property_id = p.id AND lease.tenant_id = ? AND lease.state = 'active'
          AND lease.ends_at > UTC_TIMESTAMP()
        JOIN frontier_character_identities identity_row ON identity_row.id = ?
        WHERE p.id = ? AND p.status = 'active'
    ]], { permission, permission, character, permission, character, character, character, id })
    return result == 1 or result == true or result == '1'
end

local function getFacilities(id)
    if not validId(id) then return {} end
    local rows = MySQL.query.await([[
        SELECT DISTINCT f.facility_key FROM frontier_property_facilities f
        JOIN frontier_properties p ON p.id = f.property_id
        WHERE p.id = ? AND p.status = 'active' ORDER BY f.facility_key
    ]], { id })
    local facilities = {}
    for _, row in ipairs(rows) do
        facilities[#facilities + 1] = row.facility_key
    end
    return facilities
end

exports('GetProperty', getProperty)
exports('CanAccessProperty', canAccess)
exports('GetPropertyFacilities', getFacilities)
