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
