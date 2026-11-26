ProductionConfig = {
    Enabled = true,
    WageMinor = 200,
    WageIntervalSeconds = 3600,
    StorageUnits = 100,
    StorageSlots = 30,
    StorageGrams = 50000,
    MaxJobs = 3,
    MaxBatches = 10,
    TickMs = 5000,
    MaxCheckpointSeconds = 15,
    Debug = false,
    Recipes = {
        bake = { name='Brot backen', description='Mehl und Wasser zu Brot verarbeiten.', seconds=300,
            inputs={flour=2,water=1}, output='bread', quantity=2, player=true,npc=true },
        cook = { name='Fleisch braten', description='Rohes Fleisch garen.', seconds=240,
            inputs={meat=1}, output='cooked_meat', quantity=1, player=true,npc=true },
        saw = { name='Holzbretter herstellen', description='Holz zu Brettern sägen.', seconds=360,
            inputs={wood=3}, output='wooden_planks', quantity=1, player=true,npc=true },
        smelt = { name='Eisen schmelzen', description='Eisenerz mit Kohle verhütten.', seconds=480,
            inputs={iron_ore=2,coal=1}, output='iron_ingot', quantity=1, player=true,npc=true },
    },
    Items = {
        flour={name='Mehl',description='Gemahlenes Getreide.',grams=300},
        meat={name='Fleisch',description='Rohes Fleisch.',grams=400},
        wood={name='Holz',description='Ein rohes Stück Holz.',grams=700},
        iron_ore={name='Eisenerz',description='Unverarbeitetes Eisenerz.',grams=800},
        coal={name='Kohle',description='Brennstoff zum Schmelzen.',grams=400},
        cooked_meat={name='Gebratenes Fleisch',description='Gegartes Fleisch.',grams=320},
        wooden_planks={name='Holzbretter',description='Gesägtes Bauholz.',grams=950},
        iron_ingot={name='Eisenbarren',description='Ein gegossener Barren.',grams=1000},
    },
}

ProductionConfig.Recipes.mill_wheat={name='Mill wheat',description='Process farm wheat into flour.',seconds=300,inputs={farm_wheat=3},output='flour',quantity=2,player=true,npc=true}
ProductionConfig.Recipes.cook_farm_meat={name='Cook farm meat',description='Cook harvested farm meat.',seconds=240,inputs={farm_meat=1},output='cooked_meat',quantity=1,player=true,npc=true}
