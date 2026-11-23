PropertyConfig = {
    -- Keyed by name. Set boundary, exclusions, and priceCentsPerSquareMeter per staging zone.
    -- Configure government rentals by property ID with agent vector3, price, seconds and furnish.
    GovernmentRentals = {},
    SurveyZones = {},
    SurveyMinArea = 25,
    SurveyMaxArea = 2500,
    FurnishingRooms = {}, -- By property ID: min, max, bucket and capacity.
    FurnitureCatalog = {
        bett = { model = 'p_bed01x', price = 1200, radius = 1.15 },
        truhe = { model = 'p_chest01x', price = 650, radius = 0.55 },
        schrank = { model = 'p_armoir04x', price = 1500, radius = 0.75 },
        tisch = { model = 'p_table01x', price = 800, radius = 0.95 },
        werkbank = { model = 'p_sawbucktable01x', price = 1750, radius = 1.10 },
    },
    ConstructionPlans = {}, -- Model, radius, value in cents, and stages with item/count/tool.
    Upkeep = {
        enabled = false,
        rateBps = 100,
        intervalSeconds = 86400,
        forecloseDebtCents = 10000,
        graceSeconds = 604800,
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
