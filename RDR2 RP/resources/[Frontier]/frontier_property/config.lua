PropertyConfig = {
    InitialRadius=100, ExpansionStep=25, MaxRadius=500, ExpansionBase=15000, ExpansionMultiplier=1.5,
    TownClearance=100, TaxBase=1000, TaxPeriod=604800, TaxGrace=604800,
    ForeclosureDeduction=30, ForeclosurePenalty=50, StreamDistance=350, InteractionDistance=5,
    PlacementDistance=30, MaxHeightOffset=5, ShopDistance=12, ShopHeightTolerance=6, TickMs=1000, StorageSlots=60, StorageGrams=100000,
    -- Ground probing is for camp props, construction markers and initial previews only.
    -- Completed structures and furniture use exact saved entity origins.
    GroundSearchTolerance=12, GroundModelOffsets={},
    -- Physical building assemblies. Preserve calibrated local-space offsets.
    Assemblies={
        bee_stable={parts={
            {model='bee_stableext',x=-0.100,y=0.100,z=0.000,heading=2.000},
            {model='bee_stableint',x=-0.660,y=-1.000,z=-0.270,heading=336.000}}},
        bee_mainhouse={parts={
            {model='bee_mainhouse_foundext',x=0.000,y=0.000,z=0.000,heading=0.000},
            {model='bee_mainhouse_wallext',x=-0.350,y=5.200,z=3.750,heading=0.000},
            {model='bee_mainhouse_int',x=-1.500,y=6.300,z=2.000,heading=0.000}}},
        bee_workerhouse={parts={
            {model='bee_workerexterior',x=0.000,y=0.000,z=0.000,heading=0.000},
            {model='bee_workerinterior',x=-0.900,y=0.425,z=0.050,heading=0.000}}},
        caligahall={parts={
            {model='caligahall_ext',x=0.000,y=0.000,z=0.000,heading=0.000},
            {model='caligahall_int',x=-0.500,y=-0.300,z=0.650,heading=0.000},
            {model='caligahall_roofext',x=0.560,y=1.080,z=9.150,heading=0.000}}},
    },
    Kit={id='settlement_kit',name='Settlement kit',grams=15000,price=25000},
    Camp={fire='p_campfiredirt01x',tent='mp001_p_mp_tent_leento03x',chest='p_chest01x',site='p_cs_woodpile01x'},
    Towns={
        {name='Valentine',x=-280,y=805,r=180},{name='Rhodes',x=1290,y=-1300,r=220},
        {name='Saint Denis',x=2690,y=-1250,r=550},{name='Blackwater',x=-875,y=-1330,r=240},
        {name='Strawberry',x=-1790,y=-390,r=170},{name='Annesburg',x=2930,y=1280,r=190},
        {name='Van Horn',x=2960,y=530,r=150},{name='Tumbleweed',x=-5515,y=-2940,r=160},
        {name='Armadillo',x=-3680,y=-2600,r=170},{name='Colter',x=-1350,y=2420,r=120},
        {name='Emerald Ranch',x=1410,y=270,r=150},{name='Lagras',x=2100,y=-620,r=120},
        {name='Wapiti',x=480,y=2220,r=140},{name='MacFarlane Ranch',x=-2380,y=-2370,r=140},
        {name='Fort Wallace',x=350,y=1480,r=140},{name='Sisika',x=3350,y=-650,r=250},
        {name='Braithwaite Manor',x=1010,y=-1730,r=150},{name='Caliga Hall',x=1740,y=-1370,r=180},
    },
    Shops={{name='Valentine General Store',x=-322.4,y=803.9,z=117.9},
        {name='Rhodes General Store',x=1328.7,y=-1293.4,z=77.0},
        {name='Blackwater General Store',x=-785.1,y=-1322.4,z=43.9}},
    Tools={property_hammer={name='Hammer',grams=1000,price=1500},property_saw={name='Saw',grams=1800,price=2200}},
    -- Crow Maps streamed house models; footprint and collision require live validation.
    -- Existing exterior keys remain stable for saved construction records.
    Exteriors={
        ranch={label='Beecher ranch house',category='Residential',model='bee_mainhouse_foundext',assembly='bee_mainhouse',indoorPart=3,radius=22,slots=60,materials={wood=45,wooden_planks=60,iron_ingot=12},seconds=600,value=75000,interior=true},
        workerhouse={label='Workers house',category='Residential',model='bee_workerexterior',assembly='bee_workerhouse',indoorPart=2,radius=16,slots=25,materials={wood=20,wooden_planks=25,iron_ingot=4},seconds=240,value=28000,interior=true},
        manor={label='Caliga Hall manor',category='Residential',model='caligahall_ext',assembly='caligahall',indoorPart=2,radius=30,slots=100,materials={wood=90,wooden_planks=120,iron_ingot=25},seconds=1200,value=160000,interior=true},
        stable={label='Stable',category='Livestock',model='bee_stableext',assembly='bee_stable',indoorPart=2,radius=18,slots=40,materials={wood=35,wooden_planks=45,iron_ingot=8},seconds=420,value=48000,interior=true},
        house3={label='Country house',category='Residential',model='free_house03',radius=15,slots=35,materials={wood=28,wooden_planks=35,iron_ingot=6},seconds=360,value=42000,interior=true},
        addhouse={label='Ranch annex',category='Residential',model='bee_addhouse',radius=10,slots=20,materials={wood=18,wooden_planks=20,iron_ingot=4},seconds=240,value=22000,interior=true},
        townhouse={label='Town house',category='Residential',model='bla_house2',radius=16,slots=40,materials={wood=35,wooden_planks=40,iron_ingot=8},seconds=420,value=50000,interior=true},
        coop={label='Chicken coop',category='Livestock',model='bee_chickencoop',radius=6,slots=0,materials={wood=10,wooden_planks=12,iron_ingot=2},seconds=120,value=9000,interior=false},
        silo={label='Silo',category='Storage',model='bee_silo',radius=9,slots=0,materials={wood=20,wooden_planks=25,iron_ingot=5},seconds=240,value=22000,interior=false},
        gazebo={label='Gazebo',category='Decoration',model='bee_gazebo',radius=8,slots=0,materials={wood=15,wooden_planks=18,iron_ingot=2},seconds=180,value=15000,interior=false},
        shack={label='Wooden cabin',category='Residential',model='free_house02',radius=10,slots=10,materials={wood=12,wooden_planks=12,iron_ingot=2},seconds=120,value=12000,interior=true},
        cabin={label='Large ranch house',category='Residential',model='free_house01',radius=14,slots=30,materials={wood=25,wooden_planks=30,iron_ingot=5},seconds=300,value=35000,interior=true},
        shelter={label='Field shelter',category='Agriculture',model='mp001_p_mp_tent_leento03x',radius=4,slots=0,materials={wood=8,wooden_planks=4},seconds=90,value=5000,interior=false},
        field={label='Field plot marker',category='Agriculture',model='p_haypile_wag01x',radius=8,slots=0,materials={wood=6},seconds=60,value=3000,interior=false},
        pen={label='Livestock pen marker',category='Livestock',model='p_haypile_wag01x',radius=6,slots=0,materials={wood=16,wooden_planks=8},seconds=120,value=8000,interior=false},
        workshop={label='Workshop shack',category='Industrial',model='free_house02',radius=10,slots=20,materials={wood=20,wooden_planks=18,iron_ingot=6},seconds=240,value=22000,interior=true},
        store={label='Trading cabin',category='Commercial',model='free_house01',radius=14,slots=30,materials={wood=25,wooden_planks=30,iron_ingot=8},seconds=300,value=35000,interior=true},
        warehouse={label='Storage cabin',category='Storage',model='bee_stableext',assembly='bee_stable',indoorPart=2,radius=18,slots=40,materials={wood=30,wooden_planks=35,iron_ingot=6},seconds=360,value=40000,interior=true},
    },
    -- Interior reference bounds are model-local, provisional until measured in-game.
    -- Multipart buildings use the calibrated interior component transform.
    IndoorBounds={
        free_house01={min={x=-6,y=-6,z=0},max={x=6,y=6,z=5}},
        free_house02={min={x=-4,y=-4,z=0},max={x=4,y=4,z=4}},
        free_house03={min={x=-5,y=-5,z=0},max={x=5,y=5,z=5}},
        bee_stableint={min={x=-7,y=-5,z=-1},max={x=7,y=5,z=5}},
        bee_mainhouse_int={min={x=-7,y=-6,z=-2},max={x=7,y=6,z=6}},
        bee_workerinterior={min={x=-5,y=-4,z=-1},max={x=5,y=4,z=4}},
        caligahall_int={min={x=-10,y=-8,z=-1},max={x=10,y=8,z=9}},
        bee_addhouse={min={x=-4,y=-4,z=0},max={x=4,y=4,z=4}},
        bla_house2={min={x=-5,y=-5,z=0},max={x=5,y=5,z=5}},
    },
    Interiors={
        watson={label='Small cabin',id=53250,x=-1817.708,y=658.421,z=131.0,slots=15,bounds=3,materials={wooden_planks=8,iron_ingot=2},seconds=90,value=8000},
        mountain={label='Mountain cabin',id=28162,x=-556.359,y=2702.787,z=317.932,slots=25,bounds=3,materials={wooden_planks=12,iron_ingot=3},seconds=120,value=12000},
        farmhouse={label='Farmhouse',id=13826,x=1371.018,y=-872.910,z=70.887,slots=40,bounds=4,materials={wooden_planks=20,iron_ingot=4},seconds=180,value=20000},
        lodge={label='Hunting lodge',id=2306,x=1700.901,y=1511.271,z=148.431,slots=50,bounds=4,materials={wooden_planks=25,iron_ingot=5},seconds=240,value=25000},
        barn={label='Barn',id=59650,x=-535,y=2670,z=319,slots=60,bounds=5,materials={wooden_planks=30,iron_ingot=6},seconds=300,value=30000},
        mansion={label='Mansion',id=25858,x=2823.755,y=274.417,z=46.380,slots=100,bounds=5,materials={wooden_planks=50,iron_ingot=12},seconds=480,value=50000},
    },
    Furniture={
        property_storage={name='Storage chest',category='Functional furniture',model='p_chest01x',grams=8000,slots=0,price=3500,value=3500},
        property_counter={name='Sales counter',category='Functional furniture',model='p_sawbucktable01x',grams=12000,slots=0,price=5000,value=5000},
        property_bed={name='Bed',category='Large furniture',model='p_bed01x',grams=10000,slots=5,price=4500,value=4500},
        property_chest={name='Decorative chest',category='Medium furniture',model='p_chest01x',grams=6000,slots=3,price=2500,value=2500},
        property_wardrobe={name='Wardrobe',category='Large furniture',model='p_armoir04x',grams=12000,slots=5,price=5500,value=5500},
        property_table={name='Workbench',category='Large furniture',model='p_sawbucktable01x',grams=10000,slots=5,price=4000,value=4000},
        property_chair={name='Chair',category='Small furniture',model='p_woodenchair01x',grams=3000,slots=2,price=1000,value=1000},
    },
    Permissions={'enter','storage','deliver','work','build','furnish','move','demolish','expand','members','finance','sell'},
    InteriorBucketBase=1500000000, InteriorBucketLimit=1999999999,
    -- Conservative catalogue only; configure extra road, water, mission and map exclusions before production.
    ExtraExclusions={}
}

-- Farming assemblies: exact medium layouts supplied by the in-game designer.
PropertyConfig.Assemblies.farm_livestock_small={parts={
{model='p_fence_cattle01x',x=-3.875,y=3.75,z=0,heading=0,terrain='slope'},
{model='p_fence_cattle01x',x=-0.125,y=3.75,z=0,heading=0,terrain='slope'},
{model='p_fence_cattle01x',x=3.875,y=3.75,z=0,heading=270,terrain='slope'},
{model='p_fence_cattle01x',x=3.875,y=-0.25,z=0,heading=270,terrain='slope'},
{model='p_fence_cattle01x',x=3.875,y=-3.75,z=0,heading=180,terrain='slope'},
{model='p_fence_cattle01x',x=0.125,y=-3.75,z=0,heading=180,terrain='slope'},
{model='p_fence_cattle01x',x=-3.625,y=-3.75,z=0,heading=90,terrain='slope'},
{model='p_fence_cattle01x',x=-3.625,y=0.25,z=0,heading=90,terrain='slope'},
{model='p_watertrough03x',x=-1.2916666666666665,y=2.5,z=0,heading=0,terrain='ground'},
{model='p_haybalestack03x',x=1.1625000000000005,y=1,z=0,heading=0,terrain='ground'}}}
PropertyConfig.Exteriors.farm_livestock_small={label='small livestock enclosure',category='Agriculture',model='p_fence_cattle01x',assembly='farm_livestock_small',radius=9,slots=0,materials={wood=8,wooden_planks=6},seconds=90,value=5000,interior=false,farm='livestock',size='small',width=7.75,length=7.5}
PropertyConfig.Assemblies.farm_livestock_medium={parts={
{model='p_fence_cattle01x',x=-7.875,y=7.75,z=0,heading=0,terrain='slope'},
{model='p_fence_cattle01x',x=-4.125,y=7.75,z=0,heading=0,terrain='slope'},
{model='p_fence_cattle01x',x=-0.125,y=7.75,z=0,heading=0,terrain='slope'},
{model='p_fence_cattle01x',x=3.875,y=7.75,z=0,heading=0,terrain='slope'},
{model='p_fence_cattle01x',x=7.875,y=7.75,z=0,heading=270,terrain='slope'},
{model='p_fence_cattle01x',x=7.875,y=3.75,z=0,heading=270,terrain='slope'},
{model='p_fence_cattle01x',x=7.875,y=-0.25,z=0,heading=270,terrain='slope'},
{model='p_fence_cattle01x',x=7.875,y=-4.25,z=0,heading=270,terrain='slope'},
{model='p_fence_cattle01x',x=7.875,y=-7.75,z=0,heading=180,terrain='slope'},
{model='p_fence_cattle01x',x=3.875,y=-7.75,z=0,heading=180,terrain='slope'},
{model='p_fence_cattle01x',x=-0.125,y=-7.75,z=0,heading=180,terrain='slope'},
{model='p_fence_cattle01x',x=-3.875,y=-7.75,z=0,heading=180,terrain='slope'},
{model='p_fence_cattle01x',x=-7.625,y=-7.75,z=0,heading=90,terrain='slope'},
{model='p_fence_cattle01x',x=-7.625,y=-3.75,z=0,heading=90,terrain='slope'},
{model='p_fence_cattle01x',x=-7.625,y=0,z=0,heading=90,terrain='slope'},
{model='p_fence_cattle01x',x=-7.625,y=3.75,z=0,heading=90,terrain='slope'},
{model='p_watertrough03x',x=-5.125,y=6.5,z=0,heading=0,terrain='ground'},
{model='p_haybalestack03x',x=1.125,y=5,z=0,heading=0,terrain='ground'}}}
PropertyConfig.Exteriors.farm_livestock_medium={label='medium livestock enclosure',category='Agriculture',model='p_fence_cattle01x',assembly='farm_livestock_medium',radius=15,slots=0,materials={wood=16,wooden_planks=12},seconds=180,value=10000,interior=false,farm='livestock',size='medium',width=15.75,length=15.5}
PropertyConfig.Assemblies.farm_livestock_large={parts={
{model='p_fence_cattle01x',x=-11.875,y=11.75,z=0,heading=0,terrain='slope'},
{model='p_fence_cattle01x',x=-7.875,y=11.75,z=0,heading=0,terrain='slope'},
{model='p_fence_cattle01x',x=-3.875,y=11.75,z=0,heading=0,terrain='slope'},
{model='p_fence_cattle01x',x=0.125,y=11.75,z=0,heading=0,terrain='slope'},
{model='p_fence_cattle01x',x=4.125,y=11.75,z=0,heading=0,terrain='slope'},
{model='p_fence_cattle01x',x=7.875,y=11.75,z=0,heading=0,terrain='slope'},
{model='p_fence_cattle01x',x=11.875,y=11.75,z=0,heading=270,terrain='slope'},
{model='p_fence_cattle01x',x=11.875,y=7.75,z=0,heading=270,terrain='slope'},
{model='p_fence_cattle01x',x=11.875,y=3.75,z=0,heading=270,terrain='slope'},
{model='p_fence_cattle01x',x=11.875,y=-0.25,z=0,heading=270,terrain='slope'},
{model='p_fence_cattle01x',x=11.875,y=-4.25,z=0,heading=270,terrain='slope'},
{model='p_fence_cattle01x',x=11.875,y=-8.25,z=0,heading=270,terrain='slope'},
{model='p_fence_cattle01x',x=11.875,y=-11.75,z=0,heading=180,terrain='slope'},
{model='p_fence_cattle01x',x=7.875,y=-11.75,z=0,heading=180,terrain='slope'},
{model='p_fence_cattle01x',x=3.875,y=-11.75,z=0,heading=180,terrain='slope'},
{model='p_fence_cattle01x',x=-0.125,y=-11.75,z=0,heading=180,terrain='slope'},
{model='p_fence_cattle01x',x=-4.125,y=-11.75,z=0,heading=180,terrain='slope'},
{model='p_fence_cattle01x',x=-7.875,y=-11.75,z=0,heading=180,terrain='slope'},
{model='p_fence_cattle01x',x=-11.625,y=-11.75,z=0,heading=90,terrain='slope'},
{model='p_fence_cattle01x',x=-11.625,y=-7.75,z=0,heading=90,terrain='slope'},
{model='p_fence_cattle01x',x=-11.625,y=-3.75,z=0,heading=90,terrain='slope'},
{model='p_fence_cattle01x',x=-11.625,y=0.25,z=0,heading=90,terrain='slope'},
{model='p_fence_cattle01x',x=-11.625,y=4.25,z=0,heading=90,terrain='slope'},
{model='p_fence_cattle01x',x=-11.625,y=8.25,z=0,heading=90,terrain='slope'},
{model='p_watertrough03x',x=-9.125,y=10.5,z=0,heading=0,terrain='ground'},
{model='p_haybalestack03x',x=-2.875,y=9,z=0,heading=0,terrain='ground'}}}
PropertyConfig.Exteriors.farm_livestock_large={label='large livestock enclosure',category='Agriculture',model='p_fence_cattle01x',assembly='farm_livestock_large',radius=20,slots=0,materials={wood=24,wooden_planks=18},seconds=270,value=15000,interior=false,farm='livestock',size='large',width=23.75,length=23.5}
PropertyConfig.Assemblies.farm_chicken_small={parts={
{model='p_chickenfence01x',x=-1.75,y=1.75,z=0,heading=0,terrain='slope'},
{model='p_chickenfence01x',x=-0.25,y=1.75,z=0,heading=0,terrain='slope'},
{model='p_chickenfence01x',x=1.75,y=1.75,z=0,heading=270,terrain='slope'},
{model='p_chickenfence01x',x=1.75,y=0,z=0,heading=270,terrain='slope'},
{model='p_chickenfence01x',x=1.75,y=-1.75,z=0,heading=180,terrain='slope'},
{model='p_chickenfence01x',x=0.25,y=-1.75,z=0,heading=180,terrain='slope'},
{model='p_chickenfence01x',x=-1.5,y=-1.75,z=0,heading=90,terrain='slope'},
{model='p_chickenfence01x',x=-1.5,y=0,z=0,heading=90,terrain='slope'},
{model='p_chickencoopcart01x',x=-0.25,y=0.75,z=-0.25,heading=180,terrain='fixed'}}}
PropertyConfig.Exteriors.farm_chicken_small={label='small chicken enclosure',category='Agriculture',model='p_chickenfence01x',assembly='farm_chicken_small',radius=6,slots=0,materials={wood=8,wooden_planks=6},seconds=90,value=5000,interior=false,farm='chicken',size='small',width=3.5,length=3.5}
PropertyConfig.Assemblies.farm_chicken_medium={parts={
{model='p_chickenfence01x',x=-3.5,y=3.5,z=0,heading=0,terrain='slope'},
{model='p_chickenfence01x',x=-1.75,y=3.5,z=0,heading=0,terrain='slope'},
{model='p_chickenfence01x',x=0,y=3.5,z=0,heading=0,terrain='slope'},
{model='p_chickenfence01x',x=1.75,y=3.5,z=0,heading=0,terrain='slope'},
{model='p_chickenfence01x',x=3.5,y=3.5,z=0,heading=270,terrain='slope'},
{model='p_chickenfence01x',x=3.5,y=1.75,z=0,heading=270,terrain='slope'},
{model='p_chickenfence01x',x=3.5,y=0,z=0,heading=270,terrain='slope'},
{model='p_chickenfence01x',x=3.5,y=-1.75,z=0,heading=270,terrain='slope'},
{model='p_chickenfence01x',x=3.5,y=-3.5,z=0,heading=180,terrain='slope'},
{model='p_chickenfence01x',x=2,y=-3.5,z=0,heading=180,terrain='slope'},
{model='p_chickenfence01x',x=0.25,y=-3.5,z=0,heading=180,terrain='slope'},
{model='p_chickenfence01x',x=-1.5,y=-3.5,z=0,heading=180,terrain='slope'},
{model='p_chickenfence01x',x=-3.25,y=-3.5,z=0,heading=90,terrain='slope'},
{model='p_chickenfence01x',x=-3.25,y=-1.75,z=0,heading=90,terrain='slope'},
{model='p_chickenfence01x',x=-3.25,y=0,z=0,heading=90,terrain='slope'},
{model='p_chickenfence01x',x=-3.25,y=1.75,z=0,heading=90,terrain='slope'},
{model='p_chickencoopcart01x',x=-0.5,y=1.5,z=-0.25,heading=180,terrain='fixed'},
{model='p_chickencoopcart01x',x=1.5,y=0,z=-0.25,heading=90,terrain='fixed'}}}
PropertyConfig.Exteriors.farm_chicken_medium={label='medium chicken enclosure',category='Agriculture',model='p_chickenfence01x',assembly='farm_chicken_medium',radius=8,slots=0,materials={wood=16,wooden_planks=12},seconds=180,value=10000,interior=false,farm='chicken',size='medium',width=7,length=7}
PropertyConfig.Assemblies.farm_chicken_large={parts={
{model='p_chickenfence01x',x=-5.25,y=5.25,z=0,heading=0,terrain='slope'},
{model='p_chickenfence01x',x=-3.5,y=5.25,z=0,heading=0,terrain='slope'},
{model='p_chickenfence01x',x=-1.75,y=5.25,z=0,heading=0,terrain='slope'},
{model='p_chickenfence01x',x=0,y=5.25,z=0,heading=0,terrain='slope'},
{model='p_chickenfence01x',x=1.75,y=5.25,z=0,heading=0,terrain='slope'},
{model='p_chickenfence01x',x=3.25,y=5.25,z=0,heading=0,terrain='slope'},
{model='p_chickenfence01x',x=5.25,y=5.25,z=0,heading=270,terrain='slope'},
{model='p_chickenfence01x',x=5.25,y=3.5,z=0,heading=270,terrain='slope'},
{model='p_chickenfence01x',x=5.25,y=1.75,z=0,heading=270,terrain='slope'},
{model='p_chickenfence01x',x=5.25,y=0,z=0,heading=270,terrain='slope'},
{model='p_chickenfence01x',x=5.25,y=-1.75,z=0,heading=270,terrain='slope'},
{model='p_chickenfence01x',x=5.25,y=-3.5,z=0,heading=270,terrain='slope'},
{model='p_chickenfence01x',x=5.25,y=-5.25,z=0,heading=180,terrain='slope'},
{model='p_chickenfence01x',x=3.5,y=-5.25,z=0,heading=180,terrain='slope'},
{model='p_chickenfence01x',x=1.75,y=-5.25,z=0,heading=180,terrain='slope'},
{model='p_chickenfence01x',x=0,y=-5.25,z=0,heading=180,terrain='slope'},
{model='p_chickenfence01x',x=-1.75,y=-5.25,z=0,heading=180,terrain='slope'},
{model='p_chickenfence01x',x=-3.25,y=-5.25,z=0,heading=180,terrain='slope'},
{model='p_chickenfence01x',x=-5,y=-5.25,z=0,heading=90,terrain='slope'},
{model='p_chickenfence01x',x=-5,y=-3.5,z=0,heading=90,terrain='slope'},
{model='p_chickenfence01x',x=-5,y=-1.75,z=0,heading=90,terrain='slope'},
{model='p_chickenfence01x',x=-5,y=0,z=0,heading=90,terrain='slope'},
{model='p_chickenfence01x',x=-5,y=1.75,z=0,heading=90,terrain='slope'},
{model='p_chickenfence01x',x=-5,y=3.5,z=0,heading=90,terrain='slope'},
{model='p_chickencoopcart01x',x=-2.25,y=3.25,z=-0.25,heading=180,terrain='fixed'},
{model='p_chickencoopcart01x',x=-0.25,y=1.75,z=-0.25,heading=90,terrain='fixed'}}}
PropertyConfig.Exteriors.farm_chicken_large={label='large chicken enclosure',category='Agriculture',model='p_chickenfence01x',assembly='farm_chicken_large',radius=11,slots=0,materials={wood=24,wooden_planks=18},seconds=270,value=15000,interior=false,farm='chicken',size='large',width=10.5,length=10.5}
PropertyConfig.Exteriors.farm_field_small={label='small crop field',category='Agriculture',model='p_handplow01x',radius=5,slots=0,materials={},seconds=60,value=0,interior=false,farm='field',size='small',width=5,length=5}
PropertyConfig.Exteriors.farm_field_medium={label='medium crop field',category='Agriculture',model='p_handplow01x',radius=9,slots=0,materials={},seconds=120,value=0,interior=false,farm='field',size='medium',width=10,length=10}
PropertyConfig.Exteriors.farm_field_large={label='large crop field',category='Agriculture',model='p_handplow01x',radius=16,slots=0,materials={},seconds=240,value=0,interior=false,farm='field',size='large',width=20,length=20}
PropertyConfig.Exteriors.farm_well={label='Farm well',category='Agriculture',model='p_well02x',radius=3,slots=0,materials={wood=12,wooden_planks=8,iron_ingot=2},seconds=120,value=4000,interior=false,farm='well',size='small',width=2,length=2}
PropertyConfig.Assemblies.farm_well={parts={{model='p_well02x',x=0,y=0,z=0,heading=0,terrain='ground'}}}
PropertyConfig.Exteriors.farm_well.assembly='farm_well'

-- Crop fields reuse the proven cattle fence geometry. Keep the existing exterior IDs
-- and economy; only the visual footprint and safe placement radius change.
PropertyConfig.FarmSignModel='p_sandwichboard01x'
local fieldEntranceParts={small={[5]=true,[6]=true},medium={[10]=true,[11]=true},large={[15]=true,[16]=true}}
for _,size in ipairs({'small','medium','large'}) do
    local source=PropertyConfig.Exteriors['farm_livestock_'..size]
    local field=PropertyConfig.Exteriors['farm_field_'..size]
    local parts={}
    for i,p in ipairs(PropertyConfig.Assemblies[source.assembly].parts) do
        if p.model=='p_fence_cattle01x' and not fieldEntranceParts[size][i] then
            parts[#parts+1]={model=p.model,x=p.x,y=p.y,z=p.z,heading=p.heading,terrain=p.terrain}
        end
    end
    local key='farm_field_'..size
    PropertyConfig.Assemblies[key]={parts=parts}
    field.assembly=key;field.model='p_fence_cattle01x'
    field.width=source.width;field.length=source.length;field.radius=source.radius
end
-- Put signs at the front edge, outside the entrance / enclosure.
for _,e in pairs(PropertyConfig.Exteriors) do
    if e.farm=='field' or e.farm=='livestock' or e.farm=='chicken' then
        local parts=PropertyConfig.Assemblies[e.assembly].parts
        parts[#parts+1]={model=PropertyConfig.FarmSignModel,x=e.width/2-0.8,y=-e.length/2-0.8,z=0,heading=0,terrain='ground',farmSign=true}
    end
end

-- Gathering supplies use the existing, idempotent general-store purchase flow.
local gatheringTools={axe={'Axe',1800,1200},pickaxe={'Pickaxe',2500,1500},shovel={'Shovel',1700,1000},pan={'Gold pan',500,700},knife={'Hunting knife',350,900},rod={'Fishing rod',600,1000}}
for kind,t in pairs(gatheringTools) do
 for material,m in pairs({crude={'Crude iron',.65},iron={'Iron',1},steel={'Steel',2},hardened={'Hardened steel',3.5}}) do
  PropertyConfig.Tools['gather_'..kind..'_'..material]={name=m[1]..' '..t[1],grams=t[2],price=math.floor(t[3]*m[2])}
 end
end
PropertyConfig.Tools.gather_bait={name='Fishing bait',grams=20,price=5}
