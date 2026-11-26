TradeConfig = {
    Markets = { valentine = 'Valentine', saint_denis = 'Saint Denis', rhodes = 'Rhodes',
        strawberry = 'Strawberry', blackwater = 'Blackwater', tumbleweed = 'Tumbleweed', annesburg = 'Annesburg' },
    Products = { flour='Mehl', meat='Fleisch', wood='Holz', iron_ore='Eisenerz', coal='Kohle', cooked_meat='Gebratenes Fleisch', wooden_planks='Holzbretter', iron_ingot='Eisenbarren',  bread = 'Brot', apple = 'Apfel', water = 'Wasserflasche' },
    MaxQuantity = 1000,
    MaxUnitMinor = 10000,
    LifetimeHours = 24,
    WorkerIntervalMs = 5000,
    Batch = 20,
    EscalationHours = 6,
    EscalationPercent = 20,
    RegionalPricePercent = { valentine=100, saint_denis=110 },
    PropertyProvider = nil, -- Future resource exporting GetTradePropertyAccess(character,site,action).
    NpcTickMinutes = 15,
    NpcEnabled = false, -- Enable after testing supply and simulated treasury issuance.
    NpcMerchants = {
        npc_valentine_baker = { market='valentine',item='bread',target=12,minimum=6,maximum=24,produce=2,consume=1,price=25,chance=30 },
        npc_valentine_store = { market='valentine',item='bread',target=18,minimum=10,maximum=28,produce=0,consume=2,price=30,chance=40 },
    },
}

TradeConfig.Agricultural={}
TradeConfig.Products.farm_carrot='Carrots';TradeConfig.Agricultural.farm_carrot=true
TradeConfig.Products.farm_potato='Potatoes';TradeConfig.Agricultural.farm_potato=true
TradeConfig.Products.farm_corn='Corn';TradeConfig.Agricultural.farm_corn=true
TradeConfig.Products.farm_wheat='Wheat';TradeConfig.Agricultural.farm_wheat=true
TradeConfig.Products.farm_tobacco='Tobacco';TradeConfig.Agricultural.farm_tobacco=true
TradeConfig.Products.farm_cotton='Cotton';TradeConfig.Agricultural.farm_cotton=true
TradeConfig.Products.farm_broccoli='Broccoli';TradeConfig.Agricultural.farm_broccoli=true
TradeConfig.Products.farm_artichoke='Artichokes';TradeConfig.Agricultural.farm_artichoke=true
TradeConfig.Products.farm_hay='Hay';TradeConfig.Agricultural.farm_hay=true
TradeConfig.Products.farm_egg='Eggs';TradeConfig.Agricultural.farm_egg=true
TradeConfig.Products.farm_milk='Milk';TradeConfig.Agricultural.farm_milk=true
TradeConfig.Products.farm_wool='Wool';TradeConfig.Agricultural.farm_wool=true
TradeConfig.Products.farm_manure='Manure';TradeConfig.Agricultural.farm_manure=true
TradeConfig.Products.farm_fertilizer='Fertilizer';TradeConfig.Agricultural.farm_fertilizer=true
TradeConfig.Products.farm_hide='Hide';TradeConfig.Agricultural.farm_hide=true
TradeConfig.Products.farm_meat='Farm meat';TradeConfig.Agricultural.farm_meat=true
TradeConfig.Products.farm_seed_carrot='carrot seeds';TradeConfig.Agricultural.farm_seed_carrot=true
TradeConfig.Products.farm_seed_potato='potato seeds';TradeConfig.Agricultural.farm_seed_potato=true
TradeConfig.Products.farm_seed_corn='corn seeds';TradeConfig.Agricultural.farm_seed_corn=true
TradeConfig.Products.farm_seed_wheat='wheat seeds';TradeConfig.Agricultural.farm_seed_wheat=true
TradeConfig.Products.farm_seed_tobacco='tobacco seeds';TradeConfig.Agricultural.farm_seed_tobacco=true
TradeConfig.Products.farm_seed_cotton='cotton seeds';TradeConfig.Agricultural.farm_seed_cotton=true
TradeConfig.Products.farm_seed_broccoli='broccoli seeds';TradeConfig.Agricultural.farm_seed_broccoli=true
TradeConfig.Products.farm_seed_artichoke='artichoke seeds';TradeConfig.Agricultural.farm_seed_artichoke=true
