local preview = {}
local generation = 0

print('[fieldtest] Script loaded successfully')

RegisterCommand('fielddebug', function()
    print('[fieldtest] Command works!')
end, false)

local vegetationModifiers = {}

local sizes = {
    small = 7.5,
    medium = 15.5,
    large = 23.5
}

local fenceLayouts = {
    small = {
        {-3.875, 3.75, 0},
        {-0.125, 3.75, 0},

        {3.875, 3.75, 270},
        {3.875, -0.25, 270},

        -- Entrance on south side

        {-3.625, -3.75, 90},
        {-3.625, 0.25, 90}
    },

    medium = {
        {-7.875, 7.75, 0},
        {-4.125, 7.75, 0},
        {-0.125, 7.75, 0},
        {3.875, 7.75, 0},

        {7.875, 7.75, 270},
        {7.875, 3.75, 270},
        {7.875, -0.25, 270},
        {7.875, -4.25, 270},

        {7.875, -7.75, 180},

        -- Entrance on south side

        {-3.875, -7.75, 180},

        {-7.625, -7.75, 90},
        {-7.625, -3.75, 90},
        {-7.625, 0, 90},
        {-7.625, 3.75, 90}
    },

    large = {
        {-11.875, 11.75, 0},
        {-7.875, 11.75, 0},
        {-3.875, 11.75, 0},
        {0.125, 11.75, 0},
        {4.125, 11.75, 0},
        {7.875, 11.75, 0},

        {11.875, 11.75, 270},
        {11.875, 7.75, 270},
        {11.875, 3.75, 270},
        {11.875, -0.25, 270},
        {11.875, -4.25, 270},
        {11.875, -8.25, 270},

        {11.875, -11.75, 180},
        {7.875, -11.75, 180},

        -- Entrance on south side

        {-4.125, -11.75, 180},
        {-7.875, -11.75, 180},

        {-11.625, -11.75, 90},
        {-11.625, -7.75, 90},
        {-11.625, -3.75, 90},
        {-11.625, 0.25, 90},
        {-11.625, 4.25, 90},
        {-11.625, 8.25, 90}
    }
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

    fence = 'p_fence_cattle01x',
	soil = 'mp005_p_dirtpile_gen_buried',

	soilOffset = -0.10,
	cropOffset = 0.05,
	entrance = 8.0,
	margin = 1.0,
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
	
	for _, modifier in ipairs(vegetationModifiers) do
		Citizen.InvokeNative(
			0x9CF1836C03FB67A2,
			Citizen.PointerValueIntInitialized(modifier),
			0
		)
	end

	vegetationModifiers = {}
	
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
	
	-- Remove natural vegetation inside the field.

	local cells = math.ceil(size / 2.5)
	local step = size / cells
	local radius = step * 0.72

	local flags = 1 + 2 + 4 + 8 + 16 + 256

	for col = 1, cells do
		for row = 1, cells do
			local x = -half + (col - 0.5) * step
			local y = -half + (row - 0.5) * step

			local wx, wy = world(x, y)
			local wz = ground(wx, wy) or anchor.z

			local modifier = Citizen.InvokeNative(
				0xFA50F79257745E74,
				wx,
				wy,
				wz,
				radius,
				1,
				flags,
				0,
				Citizen.ResultAsInteger()
			)

			if modifier and modifier ~= 0 then
				vegetationModifiers[#vegetationModifiers + 1] = modifier
			end
		end
	end
	
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

        -- =====================================
    -- ORIGINAL LIVESTOCK FENCES
    -- =====================================

    local fence = getModel(settings.fence)

    if not fence then
        releaseModels()
        return
    end

    for _, part in ipairs(fenceLayouts[settings.size]) do
        add(
            fence,
            part[1],
            part[2],
            part[3],
            0.0,
            true
        )
    end

    -- =====================================
    -- DIRT BEDS AND CROPS
    -- =====================================

    local soil
    local soilDim

    if settings.soil ~= 'none' then
        soil = getModel(settings.soil)

        if soil then
            soilDim = dimensions(soil)
        end
    end

    local cropHash
    local cropDim
    local rotation = 0

    if settings.crop ~= 'empty' then
        local crop = crops[settings.crop]

        local stage = math.min(
            #crop.models,
            math.max(1, settings.stage)
        )

        cropHash = getModel(crop.models[stage])
        rotation = settings.cropRotation or crop.rotation

        if cropHash then
            cropDim = dimensions(cropHash)
        end
    end

    local bedWidth = soilDim and soilDim.x or 1.5
    local bedLength = soilDim and soilDim.y or 1.5

    -- Account for the rotated crop dimensions.

    if cropDim then
        local cw = cropDim.x
        local cl = cropDim.y

        if rotation % 180 == 90 then
            cw, cl = cl, cw
        end

        bedWidth = math.max(bedWidth, cw)
        bedLength = math.max(bedLength, cl)
    end

    local spacingX = math.max(
        0.5,
        (bedWidth + 0.35) * settings.spacing
    )

    local spacingY = math.max(
        0.5,
        (bedLength + 0.20) * settings.spacing
    )

    local area = size - settings.margin * 2

    local cols = math.max(
        1,
        math.floor(area / spacingX)
    )

    local rows = math.max(
        1,
        math.floor(area / spacingY)
    )

    -- Limit entity count for performance.

    while cols * rows > 250 do
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

            -- Place the dirt bed.

            if soil and soilDim then

    local coverWidth = bedWidth
    local coverLength = bedLength

    -- Slight overlap between dirt piles.
    local overlap = 0.80

    local tileWidth = math.max(
        0.25, soilDim.x * overlap
    )

    local tileLength = math.max(
        0.25, soilDim.y * overlap
    )

    local soilCols = math.max(
        1, math.ceil(coverWidth / tileWidth)
    )

    local soilRows = math.max(
        1, math.ceil(coverLength / tileLength)
    )

    local spanX = math.max(
        0, coverWidth - soilDim.x
    )

    local spanY = math.max(
        0, coverLength - soilDim.y
    )

    for sx = 1, soilCols do
        for sy = 1, soilRows do

            local offsetX = soilCols > 1
                and (-spanX / 2
                + (sx - 1) * spanX / (soilCols - 1))
                or 0

            local offsetY = soilRows > 1
                and (-spanY / 2
                + (sy - 1) * spanY / (soilRows - 1))
                or 0

            add(
                soil,
                x + offsetX,
                y + offsetY,
                0,
                settings.soilOffset,
                false
            )
        end
    end
end

            -- Place the crop at exactly the
            -- same coordinates as the dirt bed.

            if cropHash then
                add(
                    cropHash,
                    x,
                    y,
                    rotation,
                    settings.cropOffset,
                    false
                )
            end
        end
    end

    note(('Field layout: %d x %d planting beds'):format(
        cols, rows
    ))

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
    local min, max = GetModelDimensions(part.hash)

    local halfX = math.max(
        0.15, (max.x - min.x) / 2
    )

    local halfY = math.max(
        0.15, (max.y - min.y) / 2
    )

    local angle = math.rad(part.heading)

    local cosA = math.cos(angle)
    local sinA = math.sin(angle)

    -- Sample terrain along the local X axis.

    local left = ground(
        part.x - halfX * cosA,
        part.y - halfX * sinA
    )

    local right = ground(
        part.x + halfX * cosA,
        part.y + halfX * sinA
    )

    -- Sample terrain along the local Y axis.

    local back = ground(
        part.x + halfY * sinA,
        part.y - halfY * cosA
    )

    local front = ground(
        part.x - halfY * sinA,
        part.y + halfY * cosA
    )

    part.pitch = 0.0
    part.roll = 0.0

    if left and right then
        part.roll = -math.deg(
            math.atan(right - left, halfX * 2)
        )
    end

    if back and front then
        part.pitch = math.deg(
            math.atan(front - back, halfY * 2)
        )
    end

    -- Prevent extreme rotations.

    part.pitch = math.max(
        -25.0, math.min(25.0, part.pitch)
    )

    part.roll = math.max(
        -25.0, math.min(25.0, part.roll)
    )

    local average = z

    if left and right and front and back then
        average = (left + right + front + back) / 4
    end

    part.z = average - min.z + part.offset
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

                SetEntityRotation(
					entity,
					part.pitch or 0.0,
					part.roll or 0.0,
					part.heading,
					2,
					true
				)
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