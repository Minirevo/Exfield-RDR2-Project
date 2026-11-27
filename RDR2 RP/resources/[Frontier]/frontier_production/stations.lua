-- Station recipes are separate from legacy orders, which retain their frozen snapshots.
StationConfig={maxQueue=3,maxBatches=10,tickMs=1000,equipment=75,recipes={},items={}}
local C=StationConfig
C.roundMs=3000 -- 2.4s sweep, 0.6s result display
C.sweepMs=2400
C.targetWidth=.12
-- Same material tiers and quality curve as gathering. Regression test compares both.
local materials={crude={label='Crude iron',uses=60,yield=.85},iron={label='Iron',uses=120,yield=1},steel={label='Steel',uses=220,yield=1.2},hardened={label='Hardened steel',uses=350,yield=1.4}}
local toolNames={axe='Axe',pickaxe='Pickaxe',shovel='Shovel',pan='Gold pan',knife='Hunting knife',rod='Fishing rod'}
local function encodeTool(material,q,maker)
 local m=materials[material];local durability,yield=1,1
 if q<20 then durability,yield=.65,.8 elseif q<40 then durability,yield=.85,.9 elseif q<60 then durability,yield=1,1 elseif q<80 then durability,yield=1.25,1.15 elseif q<95 then durability,yield=1.5,1.3 else durability,yield=1.8,1.5 end
 local uses=math.floor(m.uses*durability+.5)
 return ('{"condition":100,"material":%s,"materialId":%s,"quality":%d,"maxUses":%d,"uses":%d,"yield":%.4f,"manufacturer":%s}'):format(json.encode(m.label),json.encode(material),q,uses,uses,m.yield*yield,json.encode(maker))
end
local function item(id,name,grams,unique)
 C.items[id]={name=name,description=name,grams=grams,maxStack=unique and 1 or 40,category='Manufacturing'}
end
item('prod_copper','Copper ingot',700)
item('prod_gold','Refined gold',30)
item('prod_leather','Tanned leather',450)
item('prod_handle','Wooden tool handle',250)
item('prod_leather_strap','Leather strap',100)
item('prod_leather_pouch','Leather pouch',350,true)
item('prod_nails','Iron nails',50)
item('prod_horseshoe','Horseshoe',300,true)
item('prod_brick','Fired brick',800)
item('prod_raw_pottery','Unfired pottery',400)
item('prod_pottery','Clay pottery',500,true)
item('prod_glass','Glass',250)
item('prod_bottle','Glass bottle',180)
item('prod_preserved_fish','Preserved fish',350)
item('prod_meal','Prepared meal',450)
item('prod_herbal_extract','Herbal extract',100)
item('prod_gold_ring','Gold ring',25,true)
local function recipe(id,station,skill,name,inputs,output,count,manual,npc,quality)
 C.recipes[id]={id=id,station=station,skill=skill,name=name,inputs=inputs,output=output,quantity=count,manual=manual,npc=npc,quality=quality}
end
recipe('saw','sawmill','carpentry','Saw planks',{wood=2},'wooden_planks',3,8,90)
recipe('handle','carpentry','carpentry','Shape tool handles',{wooden_planks=1},'prod_handle',2,6,60)
recipe('smelt','smeltery','metallurgy','Smelt iron',{iron_ore=2,coal=1},'iron_ingot',1,10,120)
recipe('copper','smeltery','metallurgy','Smelt copper',{gather_copper_ore=2,coal=1},'prod_copper',1,10,120)
recipe('refine_gold_dust','smeltery','metallurgy','Refine gold dust',{gather_gold_dust=6,coal=1},'prod_gold',1,10,120)
recipe('refine_gold_flakes','smeltery','metallurgy','Refine gold flakes',{gather_gold_flakes=3,coal=1},'prod_gold',1,10,120)
recipe('refine_gold_nugget','smeltery','metallurgy','Refine gold nugget',{gather_gold_nugget=1,coal=1},'prod_gold',1,10,120)
recipe('refine_gold_ore','smeltery','metallurgy','Smelt gold ore',{gather_gold_ore=2,coal=1},'prod_gold',1,10,120)
recipe('steel','forge','blacksmithing','Refine steel',{iron_ingot=1,coal=2},'gather_steel',1,10,120)
recipe('nails','anvil','blacksmithing','Forge nails',{iron_ingot=1},'prod_nails',8,6,60)
recipe('horseshoe','anvil','blacksmithing','Forge horseshoe',{iron_ingot=1},'prod_horseshoe',1,8,90,true)
for _,kind in ipairs({'axe','pickaxe','shovel','pan','knife','rod'}) do
 for _,material in ipairs({'crude','iron','steel','hardened'}) do
  local metal=(material=='steel' or material=='hardened') and 'gather_steel' or 'iron_ingot'
  local cost=material=='hardened' and 3 or material=='crude' and 1 or 2
  local inputs={[metal]=cost,prod_handle=1}
  if material=='hardened' then inputs.coal=1 end
  recipe('tool_'..kind..'_'..material,'anvil','blacksmithing',materials[material].label..' '..toolNames[kind],inputs,'gather_'..kind..'_'..material,1,10,180,'tool')
  C.recipes['tool_'..kind..'_'..material].material=material
 end
end
recipe('tan_pelt','tanning','leatherworking','Tan animal pelt',{gather_pelt=1,water=1},'prod_leather',1,8,120)
recipe('tan_hide','tanning','leatherworking','Tan wild hide',{gather_hide=1,water=1},'prod_leather',1,8,120)
recipe('tan_farm_hide','tanning','leatherworking','Tan farm hide',{farm_hide=1,water=1},'prod_leather',1,8,120)
-- Existing unique property furniture kits remain the actual placeable output IDs.
recipe('leather_strap','leatherwork','leatherworking','Cut leather straps',{prod_leather=1},'prod_leather_strap',3,6,60)
recipe('leather_pouch','leatherwork','leatherworking','Sew leather pouch',{prod_leather=2,prod_leather_strap=1},'prod_leather_pouch',1,10,180,true)
recipe('carpentry_chest','carpentry','carpentry','Build storage chest',{wooden_planks=5,prod_nails=4},'property_storage',1,10,180,true)
recipe('table','carpentry','carpentry','Build workbench',{wooden_planks=4,prod_nails=4},'property_table',1,10,180,true)
recipe('chair','carpentry','carpentry','Build chair',{wooden_planks=3,prod_nails=2},'property_chair',1,8,120,true)
recipe('cook','stove','cooking','Cook meat',{meat=1},'cooked_meat',1,6,60)
recipe('cook_farm','stove','cooking','Cook farm meat',{farm_meat=1},'cooked_meat',1,6,60)
recipe('meal','stove','cooking','Cook meal',{cooked_meat=1,farm_potato=1},'prod_meal',1,8,90)
recipe('preserve_fish','stove','cooking','Preserve fish',{gather_fish=1,coal=1},'prod_preserved_fish',1,8,90)
recipe('bake','oven','cooking','Bake bread',{flour=2,water=1},'bread',3,8,90)
recipe('mill','mill','milling','Mill wheat',{farm_wheat=3},'flour',2,6,60)
recipe('brick','kiln','ceramics','Fire bricks',{gather_clay=2,coal=1},'prod_brick',2,8,120)
recipe('shape','pottery','ceramics','Shape clay',{gather_clay=2,water=1},'prod_raw_pottery',1,6,60)
recipe('pottery','kiln','ceramics','Fire pottery',{prod_raw_pottery=1,coal=1},'prod_pottery',1,8,120,true)
recipe('glass','glass','glassmaking','Melt glass',{gather_sand=2,coal=1},'prod_glass',2,10,120)
recipe('bottle','glass','glassmaking','Shape bottles',{prod_glass=1,coal=1},'prod_bottle',2,8,90)
recipe('extract','apothecary','medicine','Prepare herbal extract',{gather_herbs=2,water=1},'prod_herbal_extract',1,6,60)
recipe('tonic','apothecary','medicine','Prepare tonic',{prod_herbal_extract=1,prod_bottle=1},'tonic',1,8,90)
recipe('ring','jewellery','jewellery','Make gold ring',{prod_gold=1},'prod_gold_ring',1,10,180,true)

-- Complexity determines the number of timed actions per batch, not the number of output units.
local tiers={saw=1,handle=1,nails=1,smelt=2,copper=2,refine_gold_dust=2,refine_gold_flakes=2,refine_gold_nugget=2,refine_gold_ore=2,steel=2,horseshoe=2,tan_pelt=2,tan_hide=2,tan_farm_hide=2,leather_strap=1,leather_pouch=3,carpentry_chest=3,table=3,chair=2,cook=1,cook_farm=1,meal=2,preserve_fish=1,bake=2,mill=1,brick=2,shape=1,pottery=3,glass=2,bottle=2,extract=1,tonic=3,ring=4}
local toolTiers={crude=2,iron=3,steel=4,hardened=5}
for id,r in pairs(C.recipes) do
 r.rounds=assert(r.material and toolTiers[r.material] or tiers[id],'Missing production tier: '..id)
 r.manual=r.rounds*C.roundMs/1000
end

StationRules={}
local R=StationRules
R.encodeTool=encodeTool
function R.npcQuality(level,random)
 return (random or math.random)(0,math.max(0,math.min(100,math.floor(level))))
end
function R.manualQuality(level,score,equipment)
 return math.max(0,math.min(100,math.floor(level*.4+math.max(0,math.min(1,score))*40+equipment*.2+.5)))
end
function R.score(elapsed,target)
 return math.max(0,1-math.abs((elapsed%1600)/1600-target)/.185)
end
-- A single sweep per round, with a hard time window. Missing rounds count as zero.
function R.roundScore(elapsed,round,roundMs,sweepMs,target)
 local relative=elapsed-(round-1)*roundMs
 if relative<0 or relative>sweepMs then return nil end
 return math.max(0,1-math.abs(relative/sweepMs-target)/.18)
end
function R.batchScore(scores,batch,rounds)
 local total=0
 for i=(batch-1)*rounds+1,batch*rounds do total=total+(scores[i] or 0) end
 return total/rounds
end
function R.materials(recipe,n)
 local out={}
 for id,count in pairs(recipe.inputs) do out[#out+1]={id=id,count=count*n} end
 table.sort(out,function(a,b)return a.id<b.id end);return out
end
function R.outputs(recipe,n,level,mode,score,equipment,maker)
 if not recipe.quality then return {{id=recipe.output,count=recipe.quantity*n}} end
 local out={}
 for j=1,recipe.quantity*n do
  local performance=type(score)=='table' and (score[math.floor((j-1)/recipe.quantity)+1] or 0) or score
  local q=mode=='npc' and R.npcQuality(level) or R.manualQuality(level,performance,equipment)
  local meta=recipe.quality=='tool' and encodeTool(recipe.material,q,maker) or json.encode({quality=q,manufacturer=maker})
  out[#out+1]={id=recipe.output,count=1,metadata=meta}
 end
 return out
end
