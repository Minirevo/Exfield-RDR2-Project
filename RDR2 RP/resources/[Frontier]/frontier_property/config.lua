PropertyConfig = {
    -- Keyed by name. Set boundary, exclusions, and priceCentsPerSquareMeter per staging zone.
    -- Configure government rentals by property ID with agent vector3, price, seconds and furnish.
    GovernmentRentals = {},
    SaleAgent = {-393.19,739.39,115.01}, -- Public vector3 for property sales.
    PrivateRentalAgent = nil, -- Set a reviewed vector3 to enable private rental commands.
    SurveyZones = {
		test_zone = {
			boundary = {
				{ x = -439.75, y = 836.94 },
				{ x = -449.95, y = 627.79 },
				{ x = -558.61, y = 606.37 },
				{ x = -582.64, y = 695.18 },
			},

			exclusions = {},

			priceCentsPerSquareMeter = 1,

			enablePurchase = true,
		}
	},
    SurveyMinArea = 25,
    SurveyMaxArea = 2500,
    FurnishingRooms = {}, -- By property ID: min, max, bucket and capacity.
    FurnitureCatalog = {}, -- By key: model, positive price in cents and collision radius.
    FurnitureRecoveryAgent = nil,
    ConstructionPlans = {}, -- Model, radius, value in cents, and stages with item/count/tool.
    Upkeep = {
        enabled = false,
        rateBps = 100,
        intervalSeconds = 86400,
        forecloseDebtCents = 10000,
        graceSeconds = 604800,
        treasuryBank = nil,
    },
    ForeclosureDeductionBps = 3000,
    ForeclosureStatePenaltyBps = 5000,

    -- Candidates for a RedM placement smoke test. No spawning is enabled here.
    PropCandidates = {
        bed = 'p_bed01x',
        chest = 'p_chest01x',
        cupboard = 'p_armoir04x',
        furnace = 'p_mp_furnace01x',
        carpentryTable = 'p_sawbucktable01x',
    },
}
