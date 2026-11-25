PropertyConfig = {
    InitialRadius=100, ExpansionStep=25, MaxRadius=500, ExpansionBase=15000, ExpansionMultiplier=1.5,
    TownClearance=100, TaxBase=1000, TaxPeriod=604800, TaxGrace=604800,
    ForeclosureDeduction=30, ForeclosurePenalty=50, StreamDistance=350, InteractionDistance=5,
    PlacementDistance=30, MaxHeightOffset=5, TickMs=1000, StorageSlots=60, StorageGrams=100000,
    -- Ground probing is for camp props, construction markers and initial previews only.
    -- Completed structures and furniture use exact saved entity origins.
    GroundSearchTolerance=12, GroundModelOffsets={},
    -- Server-side ACE required. Disable these tools on public servers.
    AdminTesting={Enabled=true,Ace='frontier.property.test',FinishDistance=20,AssetModels={
        bee_addhouse=15,
        bee_chickencoop=7,
        bee_entrance=6,
        bee_entrancestable=6,
        bee_gazebo=8,
        bee_mainhouse_foundext=18,
        bee_mainhouse_int=18,
        bee_mainhouse_wallext=18,
        bee_silo=12,
        bee_stableext=18,
        bee_stableint=18,
        bee_workerexterior=15,
        bee_workerinterior=15,
        bla_dechouse2=16,
        bla_house2=16,
        brontewindow=4,
        caligahall_ext=22,
        caligahall_int=22,
        caligahall_roofext=22,
        cookingstation=5,
        cookingstation2=5,
        fancyfireplace=5,
        free_house01=15,
        free_house02=12,
        free_house03=15
    }},
    -- Test assemblies: first part is the ground anchor, remaining parts use its exact
    -- origin plus local-space offsets calibrated in-game; verify after respawn.
    TestAssemblies={
        bee_stable={distance=18,parts={
            {model='bee_stableext',x=-0.100,y=0.100,z=0.000,heading=2.000},
            {model='bee_stableint',x=-0.660,y=-1.000,z=-0.270,heading=336.000}}},
        bee_mainhouse={distance=20,parts={
            {model='bee_mainhouse_foundext',x=0.000,y=0.000,z=0.000,heading=0.000},
            {model='bee_mainhouse_wallext',x=-0.350,y=5.200,z=3.750,heading=0.000},
            {model='bee_mainhouse_int',x=-1.500,y=6.300,z=2.000,heading=0.000}}},
        bee_workerhouse={distance=16,parts={
            {model='bee_workerexterior',x=0.000,y=0.000,z=0.000,heading=0.000},
            {model='bee_workerinterior',x=-0.900,y=0.425,z=0.050,heading=0.000}}},
        caligahall={distance=25,parts={
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
        shack={label='Wooden cabin',category='Residential',model='free_house02',radius=10,slots=10,materials={wood=12,wooden_planks=12,iron_ingot=2},seconds=120,value=12000,interior=true},
        cabin={label='Large ranch house',category='Residential',model='free_house01',radius=14,slots=30,materials={wood=25,wooden_planks=30,iron_ingot=5},seconds=300,value=35000,interior=true},
        shelter={label='Field shelter',category='Agriculture',model='mp001_p_mp_tent_leento03x',radius=4,slots=0,materials={wood=8,wooden_planks=4},seconds=90,value=5000,interior=false},
        field={label='Field plot marker',category='Agriculture',model='p_haypile_wag01x',radius=8,slots=0,materials={wood=6},seconds=60,value=3000,interior=false},
        pen={label='Livestock pen marker',category='Livestock',model='p_haypile_wag01x',radius=6,slots=0,materials={wood=16,wooden_planks=8},seconds=120,value=8000,interior=false},
        workshop={label='Workshop shack',category='Industrial',model='free_house02',radius=10,slots=20,materials={wood=20,wooden_planks=18,iron_ingot=6},seconds=240,value=22000,interior=true},
        store={label='Trading cabin',category='Commercial',model='free_house01',radius=14,slots=30,materials={wood=25,wooden_planks=30,iron_ingot=8},seconds=300,value=35000,interior=true},
        warehouse={label='Storage cabin',category='Storage',model='wat_main_cabin',radius=9,slots=40,materials={wood=30,wooden_planks=35,iron_ingot=6},seconds=360,value=40000,interior=true},
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
