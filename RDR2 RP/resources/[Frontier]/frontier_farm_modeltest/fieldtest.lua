local preview = {}
local generation = 0

local sizes = {
    small = 5.0,
    medium = 10.0,
    large = 20.0
}

local crops = {
    corn = {
        models = {
            'crp_cornstalks_cb_sim',
            'crp_cornstalks_ca_sim',
            'crp_cornstalks_ab_sim'
        },
        rotation = 90,
        rowGap = 0.35
    },

    wheat = {
        models = {'crp_wheat_dry_aa_sim'},
        rotation = 0,
        rowGap = 0.25
    },

    potato = {
        models = {'crp_potato_aa_sim'},
        rotation = 90,
        rowGap = 0.35
    },

    carrot = {
        models = {'crp_carrots_aa_sim'},
        rotation = 0,
        rowGap = 0.35
    },

    tobacco = {
        models = {
            'crp_tobaccoplant_aa_sim',
            'crp_tobaccoplant_ab_sim',
            'crp_tobaccoplant_ac_sim'
        },
        rotation = 0,
        rowGap = 0.35
    }
}

local settings = {
    size = 'medium',
    crop = 'corn',
    stage = 3,

    fence = 'p_fence02x',

    -- Experimental vanilla ground model.
    soil = 'p_campfiredirt01x',

    soilOffset = 0.015,
    cropOffset = 0.02,
    entrance = 2.0,
    margin = 0.65,
    spacing = 1.0,
    cropRotation = nil
}

local anchor

local function note(message)
    print('[fieldtest] ' .. message)

    TriggerEvent('chat:addMessage', {
        args = {'Field Test', message}
    })
end

local function clear()
    generation = generation + 1

    for _, entity in ipairs(preview) do
        if DoesEntityExist(entity) then
            SetEntityAsMissionEntity(entity, true, true)
            DeleteEntity(entity)
        end
    end

    preview = {}
end

local function loadModel(name, ticket)
    local hash = GetHashKey(name)

    if not IsModelValid(hash) or IsModelAPed(hash) then
        note('Invalid prop: ' .. name)
        return nil
    end

    RequestModel(hash)

    local deadline = GetGameTimer() + 5000

    while not HasModelLoaded(hash)
        and GetGameTimer() < deadline
        and generation == ticket do
        Wait(20)
    end

    if generation ~= ticket or not HasModelLoaded(hash) then
        SetModelAsNoLongerNeeded(hash)
        return nil
    end

    return hash
end

local function dimensions(hash)
    local min, max = GetModelDimensions(hash)

    return {
        min = min,
        max = max,
        x = max.x - min.x,
        y = max.y - min.y,
        z = max.z - min.z
    }
end

local function world(x, y)
    local angle = math.rad(anchor.heading)

    return
        anchor.x + x * math.cos(angle) - y * math.sin(angle),
        anchor.y + x * math.sin(angle) + y * math.cos(angle)
end

local function ground(x, y)
    local ok, z = GetGroundZFor_3dCoord(
        x, y, anchor.z + 8.0, false
    )

    if not ok or math.abs(z - anchor.z) > 5.0 then
        return nil
    end

    return z
end

local function build()
    if not anchor then return end

    clear()

    local ticket = generation
    local loaded = {}
    local parts = {}
    local size = sizes[settings.size]
    local half = size / 2

    local function getModel(name)
        if loaded[name] then
            return loaded[name]
        end

        local hash = loadModel(name, ticket)

        if hash then
            loaded[name] = hash
        end

        return hash
    end

    local function releaseModels()
        for _, hash in pairs(loaded) do
            SetModelAsNoLongerNeeded(hash)
        end
    end

    local function add(hash, x, y, rotation, offset, collision)
        if #parts >= 650 then return end

        local wx, wy = world(x, y)

        parts[#parts + 1] = {
            hash = hash,
            x = wx,
            y = wy,
            heading = (anchor.heading + rotation) % 360,
            offset = offset or 0,
            collision = collision
        }
    end

    -- =====================================
    -- FENCE LAYOUT
    -- =====================================

    local fence = getModel(settings.fence)

    if not fence then
        releaseModels()
        return
    end

    local fenceDim = dimensions(fence)
    local segment = math.max(0.5, fenceDim.x)

    local count = math.ceil(size / segment)
    local step = size / count

    for i = 1, count do
        local pos = -half + (i - 0.5) * step

        -- Back fence
        add(fence, pos, half, 0, 0, true)

        -- Front fence with entrance
        if math.abs(pos) - segment / 2
            >= settings.entrance / 2 then

            add(fence, pos, -half, 0, 0, true)
        end

        -- Left and right fences
        add(fence, -half, pos, 90, 0, true)
        add(fence, half, pos, 90, 0, true)
    end

    -- =====================================
    -- SOIL LAYOUT
    -- =====================================

    if settings.soil ~= 'none' then
        local soil = getModel(settings.soil)

        if soil then
            local d = dimensions(soil)

            local sx = math.max(0.5, d.x)
            local sy = math.max(0.5, d.y)

            local area = size - settings.margin * 2

            local cols = math.max(1, math.ceil(area / sx))
            local rows = math.max(1, math.ceil(area / sy))

            if cols * rows <= 250 then
                for col = 1, cols do
                    for row = 1, rows do
                        local x = -area / 2
                            + (col - 0.5) * area / cols

                        local y = -area / 2
                            + (row - 0.5) * area / rows

                        add(
                            soil, x, y, 0,
                            settings.soilOffset, false
                        )
                    end
                end
            else
                note('Soil model too small to tile efficiently.')
            end

            note(('Soil dimensions: %.2f x %.2f x %.2f'):format(
                d.x, d.y, d.z
            ))
        else
            note('Soil unavailable. Continuing without soil.')
        end
    end

    -- =====================================
    -- CROP LAYOUT
    -- =====================================

    if settings.crop ~= 'empty' then
        local crop = crops[settings.crop]

        local stage = math.min(
            #crop.models,
            math.max(1, settings.stage)
        )

        local name = crop.models[stage]
        local hash = getModel(name)

        if hash then
            local d = dimensions(hash)

            local rotation =
                settings.cropRotation or crop.rotation

            local width = d.x
            local length = d.y

            if rotation % 180 == 90 then
                width, length = length, width
            end

            local spacingX = math.max(
                0.35,
                (width + crop.rowGap) * settings.spacing
            )

            local spacingY = math.max(
                0.35,
                (length + 0.1) * settings.spacing
            )

            local area = size - settings.margin * 2

            local cols = math.max(
                1, math.floor(area / spacingX)
            )

            local rows = math.max(
                1, math.floor(area / spacingY)
            )

            while cols * rows > 300 do
                if rows > cols then
                    rows = rows - 1
                else
                    cols = cols - 1
                end
            end

            for col = 1, cols do
                for row = 1, rows do
                    local x = -area / 2
                        + (col - 0.5) * area / cols

                    local y = -area / 2
                        + (row - 0.5) * area / rows

                    add(
                        hash, x, y, rotation,
                        settings.cropOffset, false
                    )
                end
            end

            note(('Crop: %s | %d columns x %d rows'):format(
                name, cols, rows
            ))
        end
    end

    -- =====================================
    -- SPAWN PREVIEW
    -- =====================================

    -- Sample terrain before spawning objects so soil
    -- props cannot interfere with ground detection.

    for i, part in ipairs(parts) do
        if generation ~= ticket then
            releaseModels()
            return
        end

        RequestCollisionAtCoord(
            part.x, part.y, anchor.z
        )

        local z = ground(part.x, part.y)

        if z then
            local min = GetModelDimensions(part.hash)
            part.z = z - min.z + part.offset
        end

        if i % 10 == 0 then Wait(0) end
    end

    local skipped = 0

    for i, part in ipairs(parts) do
        if generation ~= ticket then
            releaseModels()
            return
        end

        if part.z then
            local entity = CreateObject(
                part.hash,
                part.x,
                part.y,
                part.z,
                false,
                false,
                false,
                false,
                false
            )

            if entity and entity ~= 0
                and DoesEntityExist(entity) then

                preview[#preview + 1] = entity

                SetEntityAsMissionEntity(entity, true, true)

                SetEntityCoordsNoOffset(
                    entity,
                    part.x,
                    part.y,
                    part.z,
                    false, false, false
                )

                SetEntityHeading(entity, part.heading)
                SetEntityInvincible(entity, true)

                SetEntityCollision(
                    entity,
                    part.collision == true,
                    false
                )

                FreezeEntityPosition(entity, true)
            else
                skipped = skipped + 1
            end
        else
            skipped = skipped + 1
        end

        if i % 10 == 0 then Wait(0) end
    end

    releaseModels()

    note(('Field spawned: %d props | %d skipped'):format(
        #preview, skipped
    ))
end

local function rebuild()
    if not anchor then
        note('Create a field first.')
        return
    end

    CreateThread(function()
        local ok, err = pcall(build)

        if not ok then
            clear()
            note('Preview error: ' .. tostring(err))
        end
    end)
end

RegisterCommand('fieldtest', function(_, args)
    local action = args[1] or 'medium'

    if action == 'clear' then
        clear()
        anchor = nil
        note('Field removed.')
        return
    end

    if action == 'help' then
        note('/fieldtest small|medium|large corn|wheat|potato|carrot|tobacco|empty')
        note('/fieldtest soil MODEL')
        note('/fieldtest soil none')
        note('/fieldtest stage 1|2|3')
        note('/fieldtest rotate')
        note('/fieldtest cropangle 0|90')
        note('/fieldtest density 0.5-2.0')
        note('/fieldtest soilz VALUE')
        note('/fieldtest cropz VALUE')
        note('/fieldtest clear')
        return
    end

    if action == 'rotate' then
        if anchor then
            anchor.heading = (anchor.heading + 90) % 360
            rebuild()
        end
        return
    end

    if action == 'soil' then
        if args[2] then
            settings.soil = args[2]
            rebuild()
        end
        return
    end

    if action == 'stage' then
        settings.stage = math.max(
            1, math.min(3, tonumber(args[2]) or 3)
        )
        rebuild()
        return
    end

    if action == 'density' then
        settings.spacing = math.max(
            0.5, math.min(2.0, tonumber(args[2]) or 1.0)
        )
        rebuild()
        return
    end

    if action == 'cropangle' then
        settings.cropRotation =
            tonumber(args[2]) == 90 and 90 or 0

        rebuild()
        return
    end

    if action == 'soilz' or action == 'cropz' then
        local value = tonumber(args[2])

        if value and math.abs(value) <= 2 then
            if action == 'soilz' then
                settings.soilOffset = value
            else
                settings.cropOffset = value
            end

            rebuild()
        end
        return
    end

    if not sizes[action] then
        note('Unknown command. Use /fieldtest help')
        return
    end

    local crop = args[2] or 'corn'

    if crop ~= 'empty' and not crops[crop] then
        note('Unknown crop: ' .. crop)
        return
    end

    settings.size = action
    settings.crop = crop
    settings.cropRotation = nil

    local ped = PlayerPedId()

    local pos = GetOffsetFromEntityInWorldCoords(
        ped,
        0.0,
        sizes[action] / 2 + 5.0,
        0.0
    )

    anchor = {
        x = pos.x,
        y = pos.y,
        z = pos.z,
        heading = GetEntityHeading(ped)
    }

    rebuild()
end, false)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        clear()
    end
end)