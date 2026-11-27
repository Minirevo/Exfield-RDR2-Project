LogisticsConfig={
    ModelTestAce='frontier.logistics.models',
    Models={
        crate='p_crate02x',
        recoveryCrate='p_crate02x',
        barrel='p_barrelladle1x_culture',
        sack='p_cs_sandbag01x',
        constructionBench='mp005_p_mp_tableplank04x'
        -- No dedicated timber prop; display wood as general cargo.
        -- Construction parts are inventory items with icons, not spawned entities.
    },
    Wagons={
        wagon03x={name='Small utility wagon',slots=12,grams=150000,horses=1},
        wagon02x={name='Farm wagon',slots=24,grams=350000,horses=2},
        supplywagon={name='Supply wagon',slots=40,grams=650000,horses=2},
        wagon04x={name='Heavy freight wagon',slots=60,grams=1200000,horses=4},
        logwagon={name='Timber wagon',slots=40,grams=1500000,horses=2}
    },
    -- Provisional model-specific attachment positions; calibrate in the lab.
    CargoOffsets={
        default={{x=0,y=0,z=.8},{x=-.4,y=-.6,z=.8},{x=.4,y=-.6,z=.8},{x=-.4,y=.6,z=.8},{x=.4,y=.6,z=.8}},
    },
    HorseModel='a_c_horse_shire_darkbay',
    RecoveryPercent=90,
    MaxCargoPlanLines=80,
    Loading={baseSeconds=2,secondsPerKg=.06,secondsPerUnit=.015,minSeconds=3,maxSeconds=120},
    Parts={
        logistics_frame={name='Wagon frame',grams=8000,icon='wagon_frame',inputs={wooden_planks=8,prod_nails=12},station='carpentry'},
        logistics_wheel={name='Wagon wheel',grams=3500,icon='wagon_wheel',inputs={wooden_planks=4,prod_nails=4},station='carpentry'},
        logistics_axle={name='Wagon axle',grams=6000,icon='wagon_axle',inputs={iron_ingot=4,coal=1},station='anvil'},
        logistics_fittings={name='Iron wagon fittings',grams=1500,icon='wagon_fittings',inputs={iron_ingot=2},station='anvil'},
        logistics_harness={name='Draft harness',grams=2000,icon='wagon_harness',inputs={prod_leather=4,prod_leather_strap=3},station='leatherwork'}
    }
}
