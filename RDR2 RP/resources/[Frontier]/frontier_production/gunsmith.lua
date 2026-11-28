-- All statistics below are fictional game balancing, not physical firearm properties.
local C,R=StationConfig,StationRules
GunCraft={}
local G=GunCraft
G.materials={
 iron={name='Iron',item='iron_ingot',durability=85,handling=100,service=115,reload=100,weight=100},
 steel={name='Steel',item='gather_steel',durability=125,handling=95,service=95,reload=100,weight=108},
 copper={name='Copper',item='prod_copper',durability=75,handling=108,service=110,reload=105,weight=96},
 brass={name='Decorative brass',item='prod_copper',durability=90,handling=103,service=105,reload=98,weight=99}
}
G.slots={'body','balance','finish'}
G.stages={'Design inspection','Workshop preparation','Precision challenge','Detail work','Finish application','Quality inspection','Craftsman signature'}
G.slotsLabel={body='Workshop material',balance='Handling material',finish='Finish material'}
local function validName(v) return type(v)=='string' and #v<=48 and utf8.len(v) and not v:find('[%c<>]') end
function G.design(r,d)
 if type(d)~='table' or type(d.materials)~='table' or type(d.cosmetics)~='table' or not validName(d.name or '') then return nil,'Invalid design' end
 local c=GunCraftCatalog[r.output];if not c then return nil,'Unknown design' end
 local material,cosmetic,hashes,inputs={},{},{},{}
 for k,v in pairs(r.inputs) do inputs[k]=v end
 for _,slot in ipairs(G.slots) do
  local id=d.materials[slot];local m=G.materials[id];if not m then return nil,'Choose a material for every slot' end
  material[slot]=id;inputs[m.item]=(inputs[m.item] or 0)+1
 end
 local n=0
 for k,v in pairs(d.cosmetics) do
  n=n+1;if n>24 or type(k)~='string' or type(v)~='number' then return nil,'Invalid cosmetics' end
  local found;for _,a in ipairs(c.cosmetics[k] or {}) do if a.hash==v then found=a;break end end
  if not found then return nil,'Unsupported cosmetic' end
  cosmetic[k]=found.label;hashes[k]=v
  if found.label=='Gold' then inputs.prod_gold=(inputs.prod_gold or 0)+1 end
  if found.label=='Copper' or found.label=='Brass' then inputs.prod_copper=(inputs.prod_copper or 0)+1 end
 end
 return {name=d.name~='' and d.name or c.name,materials=material,cosmetics=cosmetic,components=hashes,inputs=inputs}
end
function G.output(r,level,score,equipment,maker,actor)
 local d=r.design;local q=R.manualQuality(level,score,equipment)
 local ratings={};local avg={durability=0,handling=0,service=0,reload=0,weight=0}
 for _,slot in ipairs(G.slots) do local m=G.materials[d.materials[slot]]
  for k in pairs(avg) do avg[k]=avg[k]+m[k]/#G.slots end
 end
 for k,v in pairs(avg) do ratings[k]=math.floor(v+.5) end
 ratings.durability=math.max(65,math.min(180,math.floor(avg.durability+(q-50)*.7+.5)))
 ratings.reload=math.max(85,math.min(120,math.floor(avg.reload+(q-50)*.15+.5)))
 return {{id=r.output,count=1,metadata=json.encode({condition=100,loaded=0,crafted=true,customName=d.name,quality=q,manufacturer=maker,craftsman=actor,createdAt=os.time(),materials=d.materials,cosmetics=d.cosmetics,components=d.components,craftStats=ratings,shotsFired=0})}}
end
for id,w in pairs(GunCraftCatalog) do
 local key='craft_'..id
 C.recipes[key]={id=key,station='gunsmith',skill='gunsmithing',name=w.name,category=w.category,output=id,quantity=1,
 inputs={prod_handle=1,prod_leather=1},quality='weapon',rounds=7,manual=70,npc=70,manualOnly=true,difficulty='Master',model=w.model,cosmetics=w.cosmetics,designMaterials=G.materials,designSlots=G.slots,designSlotLabels=G.slotsLabel,stages=G.stages}
end
