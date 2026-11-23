PropertyConfig = {
    MinPropertyName = 3,
    MaxPropertyName = 64,
    -- Keyed by name. Set boundary, exclusions, and priceCentsPerSquareMeter per staging zone.
    -- Configure government rentals by property ID with agent vector3, price, seconds and furnish.
    SurveyZones = {},
    WorldSurvey = { enabled=true, priceCentsPerSquareMeter=35, interiorBuffer=34, extraExclusions={} },
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
    ConstructionPlans = {
        huette = {label='Einfache Hütte',model='sba_shack_b_a',interiorName='Keine passende Raumzuordnung verifiziert',radius=4.5,value=9600,public=true,
            stages={{item='wood',count=5,workSeconds=10},{item='wooden_planks',count=6,workSeconds=16}}},
        blockhaus = {label='Blockhaus',model='wat_main_cabin',interiorName='wat_cabin_int (nur Weltanker belegt)',radius=7,value=19500,public=true,
            stages={{item='wood',count=9,workSeconds=15},{item='wooden_planks',count=12,workSeconds=22},
                {item='iron_ingot',count=2,workSeconds=10}}},
        unterstand = {label='Kleiner Unterstand',model='mp001_p_mp_tent_leento03x',interiorName='Kein bewohnbarer Innenraum',radius=3,value=4600,public=true,
            stages={{item='wood',count=3,workSeconds=8},{item='wooden_planks',count=3,workSeconds=10}}},
    },
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
