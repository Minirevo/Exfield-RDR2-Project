local defaults = {
    property_wagon_bench={name='Wagon construction bench',description='Placeable wagon construction bench',grams=12000,maxStack=1,category='Production stations',usable=true},
    -- Keep these kit IDs, weights and names aligned with PropertyConfig.Furniture.
    property_station_sawmill={name="Sawmill",description='Placeable production station kit',grams=12000,maxStack=1,category='Production stations',usable=true},
    property_station_carpentry={name="Carpenter's workbench",description='Placeable production station kit',grams=10000,maxStack=1,category='Production stations',usable=true},
    property_station_smeltery={name="Smelting furnace",description='Placeable production station kit',grams=18000,maxStack=1,category='Production stations',usable=true},
    property_station_forge={name="Blacksmith's forge",description='Placeable production station kit',grams=16000,maxStack=1,category='Production stations',usable=true},
    property_station_anvil={name="Anvil",description='Placeable production station kit',grams=14000,maxStack=1,category='Production stations',usable=true},
    property_station_tanning={name="Tanning rack",description='Placeable production station kit',grams=6000,maxStack=1,category='Production stations',usable=true},
    property_station_leatherwork={name="Leatherworking table",description='Placeable production station kit',grams=10000,maxStack=1,category='Production stations',usable=true},
    property_station_stove={name="Cooking stove",description='Placeable production station kit',grams=12000,maxStack=1,category='Production stations',usable=true},
    property_station_oven={name="Baking oven",description='Placeable production station kit',grams=16000,maxStack=1,category='Production stations',usable=true},
    property_station_mill={name="Grain mill",description='Placeable production station kit',grams=10000,maxStack=1,category='Production stations',usable=true},
    property_station_kiln={name="Pottery kiln",description='Placeable production station kit',grams=16000,maxStack=1,category='Production stations',usable=true},
    property_station_pottery={name="Pottery wheel",description='Placeable production station kit',grams=8000,maxStack=1,category='Production stations',usable=true},
    property_station_glass={name="Glass furnace",description='Placeable production station kit',grams=18000,maxStack=1,category='Production stations',usable=true},
    property_station_apothecary={name="Apothecary table",description='Placeable production station kit',grams=10000,maxStack=1,category='Production stations',usable=true},
    property_station_jewellery={name="Jeweller's workbench",description='Placeable production station kit',grams=10000,maxStack=1,category='Production stations',usable=true},
    settlement_kit = { name = 'Settlement kit', description = 'Settlement kit', grams = 15000, maxStack = 1, category = 'Settlement', usable = true },
    property_hammer = { name = 'Hammer', description = 'Hammer', grams = 1000, maxStack = 1, category = 'Settlement', usable = false },
    property_saw = { name = 'Saw', description = 'Saw', grams = 1800, maxStack = 1, category = 'Settlement', usable = false },
    property_storage = { name = 'Storage chest', description = 'Functional storage', grams = 8000, maxStack = 1, category = 'Functional furniture', usable = true },
    property_counter = { name = 'Sales counter', description = 'Retail counter', grams = 12000, maxStack = 1, category = 'Functional furniture', usable = true },
    property_bed = { name = 'Bed', description = 'Bed', grams = 10000, maxStack = 1, category = 'Large furniture', usable = true },
    property_chest = { name = 'Decorative chest', description = 'Decorative chest', grams = 6000, maxStack = 1, category = 'Medium furniture', usable = true },
    property_wardrobe = { name = 'Wardrobe', description = 'Wardrobe', grams = 12000, maxStack = 1, category = 'Large furniture', usable = true },
    property_table = { name = 'Workbench', description = 'Workbench', grams = 10000, maxStack = 1, category = 'Large furniture', usable = true },
    property_chair = { name = 'Chair', description = 'Chair', grams = 3000, maxStack = 1, category = 'Small furniture', usable = true },
    bread = { name = 'Brot', description = 'Ein Laib Brot.', grams = 350, maxStack = 10, category = 'Nahrung' },
    water = { name = 'Wasserflasche', description = 'Eine Flasche Trinkwasser.', grams = 550, maxStack = 10, category = 'Getränke' },
    apple = { name = 'Apfel', description = 'Ein frischer Apfel.', grams = 150, maxStack = 20, category = 'Nahrung' },
    bandage = { name = 'Verband', description = 'Ein sauberer Stoffverband.', grams = 80, maxStack = 15, category = 'Medizin', usable = true },
    tonic = { name = 'Heiltonikum', description = 'Eine Flasche mit etikettiertem Inhalt.', grams = 280,
        maxStack = 5, category = 'Medizin', usable = true, metadata = '{"charge":"standard"}' },
    lantern = { name = 'Laterne', description = 'Eine tragbare Laterne.', grams = 2200, maxStack = 1, category = 'Werkzeug', condition = true, classification = 'tool', metadata = '{"condition":100}' },
    -- Production owns its material definitions; do not seed competing defaults.

}

-- Exact definitions accidentally seeded by the previous Property revision.
local legacyProductionDefaults = {
    -- Production materials
    flour = {
        name = 'Mehl',
        description = 'Fein gemahlenes Getreidemehl.',
        grams = 1000,
        maxStack = 20,
        category = 'Rohstoffe'
    },

    meat = {
        name = 'Rohes Fleisch',
        description = 'Frisches rohes Fleisch.',
        grams = 500,
        maxStack = 10,
        category = 'Nahrung'
    },

    cooked_meat = {
        name = 'Gebratenes Fleisch',
        description = 'Eine frisch zubereitete Portion Fleisch.',
        grams = 450,
        maxStack = 10,
        category = 'Nahrung'
    },

    wood = {
        name = 'Holz',
        description = 'Ein Stück unbearbeitetes Holz.',
        grams = 2000,
        maxStack = 20,
        category = 'Rohstoffe'
    },

    planks = {
        name = 'Holzbretter',
        description = 'Verarbeitete Holzbretter.',
        grams = 1500,
        maxStack = 20,
        category = 'Materialien'
    },

    iron_ore = {
        name = 'Eisenerz',
        description = 'Roherz mit einem hohen Eisenanteil.',
        grams = 2500,
        maxStack = 20,
        category = 'Rohstoffe'
    },

    coal = {
        name = 'Kohle',
        description = 'Brennstoff für Öfen und Schmelzarbeiten.',
        grams = 1000,
        maxStack = 20,
        category = 'Rohstoffe'
    },

    iron_ingot = {
        name = 'Eisenbarren',
        description = 'Ein geschmolzener und gegossener Eisenbarren.',
        grams = 2000,
        maxStack = 10,
        category = 'Materialien'
    },
}

function Inventory.Text(value, max)
    return type(value) == 'string' and #value > 0 and #value <= max and utf8.len(value) ~= nil
        and not value:find('%c') and FrontierLib.Trim(value) ~= ''
end

function Inventory.Metadata(value, condition)
    if type(value) ~= 'string' or #value > 8192 or not utf8.len(value) or not value:match('^%s*{') then
        return false
    end
    local ok, payload = pcall(json.decode, value)
    if not ok or type(payload) ~= 'table' then return false end
    local durability = payload.condition
    return not condition or durability == nil or durability == 0 or Inventory.Int(durability, 100)
end

local function normalize(id, input)
    if not Inventory.Id(id, 48) or type(input) ~= 'table' or not Inventory.Text(input.name, 100)
        or not Inventory.Text(input.description, 500) or not Inventory.Text(input.category, 60)
        or not Inventory.Int(input.grams, 1000000) or not Inventory.Int(input.maxStack, 10000) then return end
    local def = { id = id, name = input.name, description = input.description, category = input.category,
        grams = input.grams, maxStack = input.maxStack, stackable = input.maxStack > 1,
        metadata = input.metadata == nil and '{}' or input.metadata }
    if input.stackable ~= nil and input.stackable ~= def.stackable then return end
    for _, key in ipairs({ 'usable', 'condition', 'drop', 'transfer', 'store' }) do
        local value = input[key]
        if value ~= nil and type(value) ~= 'boolean' then return end
        def[key] = value == true or (value == nil and key ~= 'usable' and key ~= 'condition')
    end
    for _, key in ipairs({ 'icon', 'classification' }) do
        if input[key] ~= nil and not Inventory.Id(input[key], 48) then return end
        def[key] = input[key]
    end
    if Inventory.Metadata(def.metadata, def.condition) then return def end
end

local function sameDefinition(a,b)
    if type(a)~='table' or type(b)~='table' then return false end
    for k,v in pairs(a) do if b[k]~=v then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end

function Inventory.Register(owner, id, input)
    local def = normalize(id, input)
    if not def or not Inventory.Text(owner, 96) then
        Inventory.Log('WARN', 'Rejected inventory item definition')
        return false, 'invalid_item'
    end
    local ok, err = Inventory.Db('update', [[
        INSERT INTO frontier_inventory_items (id, owner_resource, definition, grams, max_stack)
        VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE id = id
    ]], { id, owner, json.encode(def), def.grams, def.maxStack })
    if not ok then return false, err end
    local loaded, row = Inventory.Db('single', [[
        SELECT owner_resource, definition FROM frontier_inventory_items WHERE id = ?
    ]], { id })
    if not loaded then return false, row end
    if row and owner==Inventory.resource and row.owner_resource=='frontier_property' and
        (id=='settlement_kit' or id:match('^property_')) then
        -- Previous prototype registered these same definitions dynamically. Adopt only exact matches.
        local old=json.decode(row.definition)
        for key,value in pairs(def) do if old[key]~=value then return false,'definition_conflict' end end
        for key in pairs(old) do if def[key]==nil then return false,'definition_conflict' end end
        local moved=Inventory.Db('update','UPDATE frontier_inventory_items SET owner_resource=? WHERE id=? AND owner_resource=?',{owner,id,'frontier_property'})
        if not moved then return false,'database_error' end
        row.owner_resource=owner
    end
    -- Repair only known accidental definitions, when the actual Production resource requests them.
    -- Never delete inventory slots or transfer unrelated item ownership.
    if row and owner=='frontier_production' and row.owner_resource==Inventory.resource
        and id~='planks' and legacyProductionDefaults[id] then
        local legacy=normalize(id,legacyProductionDefaults[id])
        local prior=json.decode(row.definition)
        if sameDefinition(prior,legacy) then
            -- The canonical Production values are lighter and allow at least the old stack size.
            if def.grams>legacy.grams or def.maxStack<legacy.maxStack then return false,'definition_conflict' end
            local migrated,count=Inventory.Db('update', [[
                UPDATE frontier_inventory_items SET owner_resource=?,definition=?,grams=?,max_stack=?
                WHERE id=? AND owner_resource=? AND definition=?
            ]], {owner,json.encode(def),def.grams,def.maxStack,id,Inventory.resource,row.definition})
            if not migrated or count~=1 then return false,'definition_conflict' end
            row.owner_resource=owner;row.definition=json.encode(def)
            Inventory.Log('INFO','Repaired legacy production item definition',{item=id})
        end
    end
    if not row or row.owner_resource ~= owner then return false, 'forbidden' end
    local saved = json.decode(row.definition)
    for key, value in pairs(def) do
        if saved[key] ~= value then return false, 'definition_conflict' end
    end
    for key in pairs(saved) do
        if def[key] == nil then return false, 'definition_conflict' end
    end
    saved.owner = owner
    Inventory.items[id] = saved
    return true, id
end

function Inventory.BootItems()
    local ok, rows = Inventory.Db('query', 'SELECT id, owner_resource, definition FROM frontier_inventory_items')
    if not ok then return false end
    for _, row in ipairs(rows) do
        local def = normalize(row.id, json.decode(row.definition))
        if not def then return false end
        def.owner = row.owner_resource
        Inventory.items[row.id] = def
    end
    for id, def in pairs(defaults) do
        local registered,reason=Inventory.Register(Inventory.resource,id,def)
        if not registered then
            Inventory.Log('ERROR','Default item registration failed',{item=id,reason=reason})
            return false
        end
    end
    Inventory.handlers.bandage = { owner = Inventory.resource, consume = true, callback = function() return true end }
    Inventory.handlers.tonic = { owner = Inventory.resource, consume = true, callback = function() return true end }
    return true
end
