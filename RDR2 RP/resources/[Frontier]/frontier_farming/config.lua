FarmConfig={
 tick=60,stream=120,reach=5,waterGrace=86400, maxOffline=604800,
 crops={
 carrot={hours=6,models={'crp_carrots_aa_sim'},spacing=2.5},
 potato={hours=12,models={'crp_potato_aa_sim'},spacing=6},
 corn={hours=18,models={'crp_cornstalks_cb_sim','crp_cornstalks_ca_sim','crp_cornstalks_ab_sim'},spacing=7},
 wheat={hours=24,models={'crp_wheat_dry_aa_sim'},spacing=1.5},
 tobacco={hours=24,models={'crp_tobaccoplant_aa_sim','crp_tobaccoplant_ab_sim','crp_tobaccoplant_ac_sim'},spacing=1.5},
 cotton={hours=24,models={'crp_cotton_ad_sim'},spacing=2},
 broccoli={hours=8,models={'crp_broccoli_aa_sim'},spacing=1.8},
 artichoke={hours=12,models={'crp_artichoke_aa_sim'},spacing=2.7}
 },
 fieldCapacity={small=25,medium=100,large=400},
 species={
 chicken={capacity={small=10,medium=30,large=60},female='a_c_chicken_01',male='a_c_rooster_01',feed='farm_wheat',product='farm_egg',hours=6,mature=24},
 pig={capacity={small=5,medium=15,large=30},female='a_c_pig_01',male='a_c_pig_01',feed='farm_corn',mature=48},
 sheep={capacity={small=8,medium=20,large=40},female='a_c_sheep_01',male='a_c_sheep_01',feed='farm_hay',product='farm_wool',hours=12,mature=48},
 cattle={capacity={small=4,medium=12,large=24},female='a_c_cow',male='a_c_bull_01',feed='farm_hay',product='farm_milk',hours=12,mature=72},
 horse={capacity={small=2,medium=6,large=12},female='a_c_horse_turkoman_darkbay',male='a_c_horse_turkoman_darkbay',feed='farm_hay',mature=96}
 },
 tools={hoe='farm_hoe',sickle='farm_sickle',water='farm_watering_can',bucket='farm_bucket',fork='farm_pitchfork',milk='farm_milking_kit',shear='farm_shears'},
 items={farm_hoe={name='Hoe',grams=1500,maxStack=1},farm_sickle={name='Sickle',grams=800,maxStack=1},farm_watering_can={name='Watering can',grams=800,maxStack=1},farm_bucket={name='Bucket',grams=800,maxStack=1},farm_pitchfork={name='Pitchfork',grams=1500,maxStack=1},farm_milking_kit={name='Milking kit',grams=1200,maxStack=1},farm_shears={name='Shears',grams=600,maxStack=1},farm_water={name='Farm water',grams=250},farm_fertilizer={name='Fertilizer',grams=100},farm_hay={name='Hay',grams=150},farm_egg={name='Egg',grams=60},farm_wool={name='Wool',grams=200},farm_milk={name='Milk',grams=250},farm_manure={name='Manure',grams=100}}
}
for k in pairs(FarmConfig.crops) do
 FarmConfig.items['farm_'..k]={name=k:gsub('^%l',string.upper),grams=100}
 FarmConfig.items['farm_seed_'..k]={name=k..' seeds',grams=5}
end
for k in pairs(FarmConfig.species) do
 if k~='horse' then
  FarmConfig.items['farm_'..k..'_female']={name=k..' female voucher',grams=10}
  FarmConfig.items['farm_'..k..'_male']={name=k..' male voucher',grams=10}
 end
end

FarmConfig.work={plant='hoe',water='water',fertilize='fork',harvest='sickle',clearCrop='hoe',feed='fork',collect='milk',manure='fork',slaughter='knife'}
FarmConfig.tools.knife='farm_knife'
FarmConfig.items.farm_knife={name='Butcher knife',grams=500,maxStack=1}
FarmConfig.items.farm_hide={name='Animal hide',grams=400}
FarmConfig.items.farm_horse_female={name='Mare voucher',grams=10}
FarmConfig.items.farm_horse_male={name='Stallion voucher',grams=10}
FarmConfig.supplyPrices={farm_hoe=1500,farm_sickle=1200,farm_watering_can=800,farm_bucket=600,farm_pitchfork=1200,farm_milking_kit=1000,farm_shears=800,farm_knife=900,farm_hay=12,farm_fertilizer=25}
for k in pairs(FarmConfig.crops) do FarmConfig.supplyPrices['farm_seed_'..k]=5 end
for k in pairs(FarmConfig.species) do
 FarmConfig.supplyPrices['farm_'..k..'_female']=({chicken=150,pig=700,sheep=900,cattle=1800,horse=12000})[k]
 FarmConfig.supplyPrices['farm_'..k..'_male']=FarmConfig.supplyPrices['farm_'..k..'_female']
end
FarmConfig.suppliers={{x=-322.4,y=803.9,z=117.9},{x=1328.7,y=-1293.4,z=77.0},{x=-785.1,y=-1322.4,z=43.9}}

FarmConfig.horseBreeds={
 turkoman={label='Turkoman',model='a_c_horse_turkoman_darkbay',speed=75,stamina=75,health=80},
 standardbred={label='American Standardbred',model='a_c_horse_americanstandardbred_black',speed=80,stamina=65,health=65},
 shire={label='Shire',model='a_c_horse_shire_darkbay',speed=45,stamina=75,health=90}
}
FarmConfig.work.trainHorse='hoe'
FarmConfig.horseTrainingInterval=3600
FarmConfig.slaughterFractions={.5,.5,.3,.3,.15,.05}

FarmConfig.waterSiteRadius=8
FarmConfig.waterFillMs=5000
FarmConfig.mountMaxSeconds=3600
