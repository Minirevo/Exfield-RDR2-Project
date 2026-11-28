-- Shared catalog; server grants only these inventory-backed weapons.
FrontierWeaponRules={
 reloadDelayMs=2000,
 models={
  weapon_cattleman={model='WEAPON_REVOLVER_CATTLEMAN',ammo='ammo_revolver',nativeAmmo='AMMO_REVOLVER',capacity=6,slot=2,name='Cattleman Revolver',grams=1050,price=2500,category='Revolvers',icon='weapon_revolver_cattleman'},
  weapon_doubleaction={model='WEAPON_REVOLVER_DOUBLEACTION',ammo='ammo_revolver',nativeAmmo='AMMO_REVOLVER',capacity=6,slot=2,name='Double-action Revolver',grams=1000,price=3800,category='Revolvers',icon='weapon_revolver_doubleaction'},
  weapon_schofield={model='WEAPON_REVOLVER_SCHOFIELD',ammo='ammo_revolver',nativeAmmo='AMMO_REVOLVER',capacity=6,slot=2,name='Schofield Revolver',grams=1200,price=4500,category='Revolvers',icon='weapon_revolver_schofield'},
  weapon_navy={model='WEAPON_REVOLVER_NAVY',ammo='ammo_revolver',nativeAmmo='AMMO_REVOLVER',capacity=6,slot=2,name='Navy Revolver',grams=1200,price=5800,category='Revolvers',icon='weapon_revolver_navy'},
  weapon_lemat={model='WEAPON_REVOLVER_LEMAT',ammo='ammo_revolver',nativeAmmo='AMMO_REVOLVER',capacity=9,slot=2,name='LeMat Revolver',grams=1500,price=6500,category='Revolvers',icon='weapon_revolver_lemat'},
  weapon_volcanic={model='WEAPON_PISTOL_VOLCANIC',ammo='ammo_pistol',nativeAmmo='AMMO_PISTOL',capacity=8,slot=2,name='Volcanic Pistol',grams=1300,price=4800,category='Pistols',icon='weapon_pistol_volcanic'},
  weapon_semiauto={model='WEAPON_PISTOL_SEMIAUTO',ammo='ammo_pistol',nativeAmmo='AMMO_PISTOL',capacity=8,slot=2,name='Semi-automatic Pistol',grams=900,price=8500,category='Pistols',icon='weapon_pistol_semiauto'},
  weapon_mauser={model='WEAPON_PISTOL_MAUSER',ammo='ammo_pistol',nativeAmmo='AMMO_PISTOL',capacity=10,slot=2,name='Mauser Pistol',grams=1150,price=9500,category='Pistols',icon='weapon_pistol_mauser'},
  weapon_m1899={model='WEAPON_PISTOL_M1899',ammo='ammo_pistol',nativeAmmo='AMMO_PISTOL',capacity=8,slot=2,name='M1899 Pistol',grams=1000,price=11000,category='Pistols',icon='weapon_pistol_m1899'},
  weapon_carbine={model='WEAPON_REPEATER_CARBINE',ammo='ammo_repeater',nativeAmmo='AMMO_REPEATER',capacity=7,slot=1,name='Carbine Repeater',grams=3200,price=4800,category='Repeaters',icon='weapon_repeater_carbine'},
  weapon_lancaster={model='WEAPON_REPEATER_WINCHESTER',ammo='ammo_repeater',nativeAmmo='AMMO_REPEATER',capacity=14,slot=1,name='Lancaster Repeater',grams=3500,price=6500,category='Repeaters',icon='weapon_repeater_winchester'},
  weapon_litchfield={model='WEAPON_REPEATER_HENRY',ammo='ammo_repeater',nativeAmmo='AMMO_REPEATER',capacity=16,slot=1,name='Litchfield Repeater',grams=3900,price=7500,category='Repeaters',icon='weapon_repeater_henry'},
  weapon_evans={model='WEAPON_REPEATER_EVANS',ammo='ammo_repeater',nativeAmmo='AMMO_REPEATER',capacity=26,slot=1,name='Evans Repeater',grams=4000,price=8500,category='Repeaters',icon='weapon_repeater_evans'},
  weapon_varmint={model='WEAPON_RIFLE_VARMINT',ammo='ammo_22',nativeAmmo='AMMO_22',capacity=14,slot=1,name='Varmint Rifle',grams=2500,price=3000,category='Rifles',icon='weapon_rifle_varmint'},
  weapon_springfield={model='WEAPON_RIFLE_SPRINGFIELD',ammo='ammo_rifle',nativeAmmo='AMMO_RIFLE',capacity=1,slot=1,name='Springfield Rifle',grams=4100,price=5500,category='Rifles',icon='weapon_rifle_springfield'},
  weapon_boltaction={model='WEAPON_RIFLE_BOLTACTION',ammo='ammo_rifle',nativeAmmo='AMMO_RIFLE',capacity=5,slot=1,name='Bolt-action Rifle',grams=4200,price=7800,category='Rifles',icon='weapon_rifle_boltaction'},
  weapon_elephant={model='WEAPON_RIFLE_ELEPHANT',ammo='ammo_rifle_elephant',nativeAmmo='AMMO_RIFLE_ELEPHANT',capacity=2,slot=1,name='Elephant Rifle',grams=5000,price=10500,category='Rifles',icon='weapon_rifle_elephant'},
  weapon_rollingblock={model='WEAPON_SNIPERRIFLE_ROLLINGBLOCK',ammo='ammo_rifle',nativeAmmo='AMMO_RIFLE',capacity=1,slot=1,name='Rolling Block Rifle',grams=4400,price=9500,category='Rifles',icon='weapon_sniperrifle_rollingblock'},
  weapon_carcano={model='WEAPON_SNIPERRIFLE_CARCANO',ammo='ammo_rifle',nativeAmmo='AMMO_RIFLE',capacity=6,slot=1,name='Carcano Rifle',grams=4200,price=12000,category='Rifles',icon='weapon_sniperrifle_carcano'},
  weapon_sawedoff={model='WEAPON_SHOTGUN_SAWEDOFF',ammo='ammo_shotgun',nativeAmmo='AMMO_SHOTGUN',capacity=2,slot=2,name='Sawed-off Shotgun',grams=2200,price=3500,category='Shotguns',icon='weapon_shotgun_sawedoff'},
  weapon_doublebarrel={model='WEAPON_SHOTGUN_DOUBLEBARREL',ammo='ammo_shotgun',nativeAmmo='AMMO_SHOTGUN',capacity=2,slot=1,name='Double-barrel Shotgun',grams=3400,price=5000,category='Shotguns',icon='weapon_shotgun_doublebarrel'},
  weapon_pump={model='WEAPON_SHOTGUN_PUMP',ammo='ammo_shotgun',nativeAmmo='AMMO_SHOTGUN',capacity=5,slot=1,name='Pump-action Shotgun',grams=3800,price=7500,category='Shotguns',icon='weapon_shotgun_pump'},
  weapon_repeating_shotgun={model='WEAPON_SHOTGUN_REPEATING',ammo='ammo_shotgun',nativeAmmo='AMMO_SHOTGUN',capacity=6,slot=1,name='Repeating Shotgun',grams=3900,price=9500,category='Shotguns',icon='weapon_shotgun_repeating'},
  weapon_semiauto_shotgun={model='WEAPON_SHOTGUN_SEMIAUTO',ammo='ammo_shotgun',nativeAmmo='AMMO_SHOTGUN',capacity=5,slot=1,name='Semi-automatic Shotgun',grams=4000,price=11500,category='Shotguns',icon='weapon_shotgun_semiauto'},
  weapon_cattleman_mexican={model='WEAPON_REVOLVER_CATTLEMAN_MEXICAN',ammo='ammo_revolver',nativeAmmo='AMMO_REVOLVER',capacity=6,slot=2,name='Engraved Cattleman',grams=1050,price=4800,category='Revolvers',icon='weapon_revolver_cattleman_mexican'},
  weapon_doubleaction_gambler={model='WEAPON_REVOLVER_DOUBLEACTION_GAMBLER',ammo='ammo_revolver',nativeAmmo='AMMO_REVOLVER',capacity=6,slot=2,name='Gambler\'s Double-action',grams=1000,price=6500,category='Revolvers',icon='weapon_revolver_doubleaction_gambler'},
  weapon_navy_crossover={model='WEAPON_REVOLVER_NAVY_CROSSOVER',ammo='ammo_revolver',nativeAmmo='AMMO_REVOLVER',capacity=6,slot=2,name='Engraved Navy Revolver',grams=1200,price=8500,category='Revolvers',icon='weapon_revolver_navy_crossover'},
  weapon_doublebarrel_exotic={model='WEAPON_SHOTGUN_DOUBLEBARREL_EXOTIC',ammo='ammo_shotgun',nativeAmmo='AMMO_SHOTGUN',capacity=2,slot=1,name='Engraved Double-barrel',grams=3400,price=7800,category='Shotguns',icon='weapon_shotgun_doublebarrel_exotic'},
  weapon_bow={model='WEAPON_BOW',ammo='ammo_arrow',nativeAmmo='AMMO_ARROW',capacity=1,slot=1,name='Bow',grams=900,price=1500,category='Bows',icon='weapon_bow',experimental=true},
  weapon_bow_improved={model='WEAPON_BOW_IMPROVED',ammo='ammo_arrow',nativeAmmo='AMMO_ARROW',capacity=1,slot=1,name='Improved Bow',grams=1000,price=2800,category='Bows',icon='weapon_bow_improved',experimental=true},
 },
 ammunition={
  ammo_revolver={name='Revolver cartridges',grams=16,price=8,icon='ammo_bullet_revolver'},
  ammo_repeater={name='Repeater cartridges',grams=22,price=10,icon='ammo_bullet_repeater'},
  ammo_pistol={name='Pistol cartridges',grams=15,price=9,icon='ammo_bullet_pistol'},
  ammo_rifle={name='Rifle cartridges',grams=28,price=15,icon='ammo_bullet_rifle'},
  ammo_22={name='.22 cartridges',grams=5,price=5,icon='ammo_bullet_varmin'},
  ammo_rifle_elephant={name='Elephant rifle cartridges',grams=65,price=30,icon='ammoelephant'},
  ammo_shotgun={name='Shotgun shells',grams=40,price=15,icon='ammo_shotgun'},
  ammo_arrow={name='Arrows',grams=30,price=10,icon='ammo_arrow'},
 }
}
local R=FrontierWeaponRules
function R.integer(v,min,max)
 return type(v)=='number' and v==v and v%1==0 and v>=min and v<=max
end
function R.remaining(issued,reported)
 if not R.integer(reported,0,issued) then return nil end
 return reported
end
function R.count(box,item,first,last)
 local n=0
 for i=first,last do local e=box.slots[i];if e and e.item==item then n=n+e.quantity end end
 return n
end
function R.plan(equipment,bag,item,remaining,capacity)
 local need=math.max(0,capacity-remaining)
 if need==0 then return nil,0 end
 local quick=R.count(equipment,item,3,4)
 if quick>0 then return 'quick',math.min(need,quick) end
 local reserve=R.count(bag,item,1,bag.slot_limit)
 if reserve>0 then return 'satchel',math.min(need,reserve) end
 return nil,0
end
function R.loaded(entry,definition)
 local ok,m=pcall(json.decode,entry.metadata)
 if not ok or type(m)~='table' then return nil end
 local n=m.loaded or 0
 if not R.integer(n,0,definition.capacity) then return nil end
 return n,m
end
