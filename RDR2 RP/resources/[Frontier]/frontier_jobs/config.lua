-- Coordinates are provisional: check each prompt and NPC on the test server.
JobsConfig={
 boardSprite='blip_job_board',employerSprite='blip_job',
 boardProp='p_noticeboard01x', -- provisional asset, prompt still works if unavailable
 reach=4.0,employerReach=8.0,stream=85.0,spawnRetryMs=12000,fallbackPed='S_M_M_UNIBUTCHERS_01',duration=86400,postingDuration=604800,perCharacterDaily=3,perJobDaily=25,maxCompanyOpen=20,maxReward=100000,
 boards={
  valentine={name='Valentine saloon employment board',x=-311.3,y=805.4,z=118.98},
  strawberry={name='Strawberry employment board',x=-1789.66,y=-387.918,z=159.32},
  blackwater={name='Blackwater saloon employment board',x=-816.4,y=-1317.9,z=43.7},
  rhodes={name='Rhodes saloon employment board',x=1340.3,y=-1375.1,z=80.5},
  saint_denis={name='Saint Denis saloon employment board',x=2635.7,y=-1228.3,z=53.4},
  annesburg={name='Annesburg employment board',x=2935.0,y=1284.8,z=44.7}
 },
 employers={
  timber={name='Timber yard foreman',x=-552.5,y=527.0,z=97.7,heading=90,model='A_M_M_VALTOWNFOLK_01'},
  mine={name='Annesburg mining foreman',x=2789.5,y=1342.6,z=71.3,heading=90,model='A_M_M_ASBMINER_01'},
  butcher={name='Valentine butcher',x=-339.0,y=767.3,z=116.6,heading=90,model='S_M_M_UNIBUTCHERS_01'},
  fish={name='Blackwater fish buyer',x=-733.6,y=-1232.0,z=43.0,heading=90,model='A_M_M_BLWTOWNFOLK_01'}
 },
 jobs={
  logging={title='Lumberjack',employer='timber',description='Cut trees using the existing gathering system and bring timber to the yard.',item='wood',quantity=8,reward=160,onsite=true,loan='gather_axe_job'},
  mining={title='Mine worker',employer='mine',description='Gather stone from suitable rocks and deliver it to the foreman.',item='gather_stone',quantity=10,reward=180,onsite=true,loan='gather_pickaxe_job'},
  hunting={title='Hunting delivery',employer='butcher',description='Bring animal pelts from hunting to the butcher. Bring your own hunting equipment.',item='gather_pelt',quantity=5,reward=200,onsite=false},
  fishing={title='Fishing delivery',employer='fish',description='Catch fresh fish and deliver them to the buyer. Bring your own rod and bait.',item='gather_fish',quantity=8,reward=200,onsite=false}
 },
 loans={
  gather_axe_job={name='Loaned lumber axe',grams=1800},
  gather_pickaxe_job={name='Loaned mining pickaxe',grams=2500}
 }
}
