HorseConfig={
 reach=5.0,storeReach=18.0,spawnSeconds=20,adultAge=345600,
 sites={
 valentine={name='Valentine Stable',x=-365.87,y=789.51,z=116.17,npc={-365.15,792.68,115.18,178.47},preview={-366.07,781.81,115.14,5.97},camera={-367.9267,783.0237,117.7778,-36.42624,0,-100.9786}},
 rhodes={name='Rhodes Stable',x=1432.97,y=-1295.39,z=76.82,npc={1434.64,-1294.89,76.82,105.08},preview={1431.56,-1288.21,76.82,87.28},camera={1431.58,-1292.27,79,-16,0,6}},
 wapiti={name='Wapiti Stable',x=482.06,y=2215.17,z=247.16,npc={480.43,2213.17,245.90,-44.71},preview={485.49,2209,245.7,-27.54},camera={483.39,2211.93,248,-19.14523,0,225}},
 saintdenis={name='Saint Denis Stable',x=2510.58,y=-1456.83,z=46.31,npc={2512.35,-1456.89,45.2,91.68},preview={2508.59,-1449.96,45.5,90.09},camera={2506.807,-1452.29,48.61699,-34.77003,0,-35.20742}},
 strawberry={name='Strawberry Stable',x=-1816.81,y=-561.99,z=156.07,npc={-1818.45,-564.83,155.06,347.22},preview={-1820.26,-555.84,155.16,163.01},camera={-1819.512,-558.6999,157.6765,-23.95241,0,28.46066}},
 blackwater={name='Blackwater Stable',x=-876.57,y=-1365.1,z=43.53,npc={-878.35,-1364.81,42.53,266.28},preview={-864.25,-1361.8,42.7,177.48},camera={-862.6163,-1362.927,45.58158,-40.96593,0,71.8129}},
 tumbleweed={name='Tumbleweed Stable',x=-5514.24,y=-3041.81,z=-2.39,npc={-5515.07,-3039.51,-3.39,179.88},preview={-5519.47,-3039.32,-3.31,181.62},camera={-5517.651,-3041.113,-0.50949,-33.14523,0,55.47822}}
 },
 breeds={
 morgan={name='Morgan',model='a_c_horse_morgan_bay',price=3000,genes={speed=45,stamina=50,health=55}},
 kentucky={name='Kentucky Saddler',model='a_c_horse_kentuckysaddle_black',price=3800,genes={speed=50,stamina=52,health=60}},
 shire={name='Dark Bay Shire',model='a_c_horse_shire_darkbay',price=6500,genes={speed=40,stamina=65,health=75}}
 },
 equipment={
 horse_saddle={name='Trail saddle',price=1200,grams=4000,slot='saddle',component=0x106961A8},
 horse_saddlebags={name='Standard saddlebags',price=800,grams=1500,slot='bags',component=0x1D4EDB88},
 horse_brush={name='Horse brush',price=250,grams=250,slot='brush'},
 horse_stirrups={name='Stirrups',price=600,grams=500,slot='stirrups'}
 },
 bagSlots=12,bagGrams=25000,carePrice=100,healPrice=350,transferPrice=150
}

-- Appearance labels describe the actual model, not independently generated cosmetic data.
HorseConfig.appearance={
 a_c_horse_morgan_bay={coat='Bay',pattern='Solid'},
 a_c_horse_kentuckysaddle_black={coat='Black',pattern='Solid'},
 a_c_horse_shire_darkbay={coat='Dark bay',pattern='Solid with white markings'},
 a_c_horse_turkoman_darkbay={coat='Dark bay',pattern='Solid'},
 a_c_horse_americanstandardbred_black={coat='Black',pattern='Solid'}
}
