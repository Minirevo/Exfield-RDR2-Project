-- VORP store coordinates copied from the bundled vorp_stores/config.lua.
ShopConfig={
 reach=5.0,stream=35.0,maxLines=20,maxQuantity=100,maxTotal=250000,
 enableExperimentalBows=false, -- bow projection still requires a live test
 sites={
  valentine={name='Valentine General Store',kind='general',x=-324.628,y=803.9818,z=116.88,npc={x=-324.628,y=803.9818,z=116.88,h=-81.17,model='U_M_M_NbxGeneralStoreOwner_01'},sprite=1475879922},
  rhodes={name='Rhodes General Store',kind='general',x=1330.227,y=-1293.41,z=76.021,npc={x=1330.227,y=-1293.41,z=76.021,h=68.88,model='S_M_M_UNIBUTCHERS_01'},sprite=1475879922},
  strawberry={name='Strawberry General Store',kind='general',x=-1789.66,y=-387.918,z=159.32,npc={x=-1789.66,y=-387.918,z=159.32,h=56.96,model='S_M_M_UNIBUTCHERS_01'},sprite=1475879922},
  blackwater={name='Blackwater General Store',kind='general',x=-784.738,y=-1321.73,z=42.884,npc={x=-784.738,y=-1321.73,z=42.884,h=179.63,model='S_M_M_UNIBUTCHERS_01'},sprite=1475879922},
  armadillo={name='Armadillo General Store',kind='general',x=-3687.34,y=-2623.53,z=-13.43,npc={x=-3687.34,y=-2623.53,z=-13.43,h=-85.32,model='S_M_M_UNIBUTCHERS_01'},sprite=1475879922},
  tumbleweed={name='Tumbleweed General Store',kind='general',x=-5485.7,y=-2938.08,z=-0.299,npc={x=-5485.7,y=-2938.08,z=-0.299,h=127.72,model='S_M_M_UNIBUTCHERS_01'},sprite=1475879922},
  stdenis={name='Saint Denis General Store',kind='general',x=2824.863,y=-1319.74,z=45.755,npc={x=2824.863,y=-1319.74,z=45.755,h=-39.61,model='U_M_M_NbxGeneralStoreOwner_01'},sprite=1475879922},
  vanhorn={name='Van Horn General Store',kind='general',x=3025.42,y=561.791,z=43.722,npc={x=3025.42,y=561.791,z=43.722,h=-99.2,model='U_M_M_NbxGeneralStoreOwner_01'},sprite=1475879922},
  blackwaterfishing={name='Blackwater Bait Shop',kind='fishing',x=-756.069,y=-1360.76,z=43.724,npc={x=-756.069,y=-1360.76,z=43.724,h=-90.8,model='U_M_M_NbxGeneralStoreOwner_01'},sprite=3442726182},
  wapiti={name='Wapiti Trading Post',kind='trading',x=449.7435,y=2216.437,z=245.3,npc={x=449.7435,y=2216.437,z=245.3,h=-73.78,model='cs_eagleflies'},sprite=1475879922},
  valentinegunstore={name='Valentine Gunsmith',kind='gunsmith',x=-280.4646,y=779.0331,z=119.254,npc={x=-280.4646,y=779.0331,z=119.254,h=2.82,model='S_M_M_UNIBUTCHERS_01'},sprite=joaat('blip_shop_gunsmith')},
  saintdgunstore={name='Saint Denis Gunsmith',kind='gunsmith',x=2716.73,y=-1285.27,z=49.63,npc={x=2717.75,y=-1286.62,z=49.64,h=44.58,model='S_M_M_UNIBUTCHERS_01'},sprite=joaat('blip_shop_gunsmith')},
  rhodesgunstore={name='Rhodes Gunsmith',kind='gunsmith',x=1323.04,y=-1321.56,z=77.889,npc={x=1322.95,y=-1323.21,z=77.89,h=350.17,model='S_M_M_UNIBUTCHERS_01'},sprite=joaat('blip_shop_gunsmith')},
  annesburggunstore={name='Annesburg Gunsmith',kind='gunsmith',x=2948.16,y=1318.79,z=44.82,npc={x=2948.16,y=1318.79,z=44.82,h=91.34,model='S_M_M_UNIBUTCHERS_01'},sprite=joaat('blip_shop_gunsmith')},
  tumbleweedgunstore={name='Tumbleweed Gunsmith',kind='gunsmith',x=-5506.42,y=-2964.27,z=-0.64,npc={x=-5505.97,y=-2963.91,z=-0.64,h=103.15,model='S_M_M_UNIBUTCHERS_01'},sprite=joaat('blip_shop_gunsmith')},
  valentinebutcher={name='Valentine Butcher',kind='butcher',x=-335.7698,y=762.8827,z=116.5357,npc={x=-335.7698,y=762.8827,z=116.5357,h=97.418,model='u_m_m_sdtrapper_01'},sprite=-1406874050},
  blackwaterbutcher={name='Blackwater Butcher',kind='butcher',x=-752.7546,y=-1288.8815,z=43.3985,npc={x=-752.7546,y=-1288.8815,z=43.3985,h=272.4592,model='u_m_m_sdtrapper_01'},sprite=-1406874050},
  saintdenisbutcher={name='Saint Denis Butcher',kind='butcher',x=2821.2917,y=-1327.5411,z=46.5656,npc={x=2821.2917,y=-1327.5411,z=46.5656,h=132.457,model='u_m_m_sdtrapper_01'},sprite=-1406874050},
 },
 types={general='General store',gunsmith='Gunsmith',butcher='Butcher',fishing='Fishing supplies',trading='Trading post'},
 catalogs={general={},gunsmith={},butcher={},fishing={},trading={}}
}
local C=ShopConfig
local function item(kind,id,name,category,buy,sell,icon)
 C.catalogs[kind][id]={id=id,name=name,category=category,buy=buy,sell=sell,icon=icon}
end
local function provisions(kind)
 item(kind,'bread','Bread','Provisions',30,nil,'consumable_bread_roll')
 item(kind,'apple','Apple','Provisions',15,nil,'apple')
 item(kind,'water','Water bottle','Provisions',20,nil,'water')
 item(kind,'bandage','Bandage','First aid',40,nil,'bandage')
 item(kind,'splint','Splint','First aid',65,nil,'splint')
 item(kind,'tonic','Health tonic','First aid',85,nil,'tonic')
 item(kind,'lantern','Lantern','Tools',250,nil,'weapon_melee_lantern')
end
provisions('general');provisions('trading')
for kind,t in pairs({axe={'Axe',1200},pickaxe={'Pickaxe',1500},shovel={'Shovel',1000},pan={'Gold pan',700},knife={'Hunting knife',900},rod={'Fishing rod',1000}}) do
 for material,m in pairs({crude={'Crude iron',.65},iron={'Iron',1},steel={'Steel',2},hardened={'Hardened steel',3.5}}) do
  local id='gather_'..kind..'_'..material
  local name=m[1]..' '..t[1]
  local icon=kind=='rod' and 'weapon_fishingrod' or kind=='knife' and 'weapon_melee_knife' or kind=='axe' and 'weapon_melee_hatchet' or nil
  -- Advanced manufactured tools remain with the existing property/production market.
  if material=='crude' or material=='iron' then
   item('general',id,name,'Tools',math.floor(t[2]*m[2]),nil,icon)
   if kind=='rod' then item('fishing',id,name,'Fishing gear',math.floor(t[2]*m[2]),nil,icon) end
   if kind=='knife' then item('trading',id,name,'Hunting gear',math.floor(t[2]*m[2]),nil,icon) end
  end
 end
end
for _,kind in ipairs({'general','fishing','trading'}) do item(kind,'gather_bait','Fishing bait','Fishing gear',5,nil,'bait') end
item('general','settlement_kit','Settlement kit','Settlement',25000,nil,nil)
item('general','property_hammer','Hammer','Settlement',1500,nil,'weapon_melee_hammer')
item('general','property_saw','Saw','Settlement',2200,nil,nil)
item('butcher','meat','Raw meat','Meat',35,12,'meat')
item('butcher','cooked_meat','Cooked meat','Meat',65,nil,'cooked_meat')
item('butcher','gather_pelt','Animal pelt','Animal goods',nil,20,'pelt')
item('butcher','gather_hide','Animal hide','Animal goods',nil,20,'pelt')
item('butcher','gather_fish','Fresh fish','Fish',35,12,'fish')
item('fishing','gather_fish','Fresh fish','Fish',nil,12,'fish')
item('trading','gather_pelt','Animal pelt','Animal goods',nil,20,'pelt')
item('trading','gather_hide','Animal hide','Animal goods',nil,20,'pelt')
item('trading','gather_herbs','Wild herbs','Foraged goods',nil,5,nil)
item('trading','gather_berries','Wild berries','Foraged goods',nil,5,nil)
for id,w in pairs(FrontierWeaponRules.models) do
 if not w.experimental or C.enableExperimentalBows then
  item('gunsmith',id,w.name,w.category,w.price,nil,w.icon)
  if w.category=='Bows' then item('trading',id,w.name,w.category,w.price,nil,w.icon) end
 end
end
for id,a in pairs(FrontierWeaponRules.ammunition) do
 if id~='ammo_arrow' or C.enableExperimentalBows then item('gunsmith',id,a.name,'Ammunition',a.price,nil,a.icon) end
end
