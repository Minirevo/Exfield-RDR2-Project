'use strict';
const $=id=>document.getElementById(id);
let state=null;const lastTabs=new Map();
const entries=x=>Object.entries(x||{}), vals=x=>Object.values(x||{});
const money=n=>'$'+(Number(n||0)/100).toFixed(2);
const materials=x=>entries(x).map(([k,n])=>n+' '+k.replace(/_/g,' ')).join(' · ');
function node(tag,text,parent){const el=document.createElement(tag);if(text!==undefined)el.textContent=text;if(parent)parent.append(el);return el}
function button(parent,label,fn){const el=node('button',label,parent);el.type='button';el.onclick=fn;return el}
function input(parent,type,value,placeholder){const el=node('input',undefined,parent);el.type=type;el.value=value??'';el.placeholder=placeholder||'';return el}
function select(parent,options){const el=node('select',undefined,parent);for(const [key,label] of options){const o=node('option',label,el);o.value=key}return el}
function section(parent,title){const el=node('section',undefined,parent);node('h2',title,el);return el}
async function post(route,data){const r=await fetch('https://'+GetParentResourceName()+'/'+route,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data||{})});return r.json()}
function act(action,data={}){post('action',{action,data}).then(r=>{if(!r.ok)$('status').textContent='Menu not active. Reopen and try again.'}).catch(()=>{$('status').textContent='Request failed.'})}
function args(data={}){return {sid:state.settlement?.id,bid:state.building?.id,...data}}
function refresh(){if(!state)return;act(state.kind,args())}
function confirmInline(parent,label,fn){const b=button(parent,label,()=>{b.textContent='Confirm '+label; b.onclick=()=>{b.disabled=true;fn()}})}
function propertyTabs(root,s){
 const nav=$('sections'),labels=['Overview','Buildings','Construction','Members','Finances','Settings'],panels={},buttons={};
 let active=lastTabs.get(s.id)||'Overview';
 function show(label){lastTabs.set(s.id,label);for(const l of labels){panels[l].hidden=l!==label;buttons[l].setAttribute('aria-pressed',String(l===label))}root.scrollTop=0}
 nav.hidden=false;for(const label of labels){buttons[label]=button(nav,label,()=>show(label));panels[label]=node('div',undefined,root);panels[label].className='page'}show(active);return panels
}
function render(){
 const root=$('content');root.replaceChildren();$('sections').replaceChildren();$('sections').hidden=true;const s=state.settlement,b=state.building;
 $('title').textContent=s?.name||({shop:'General store',market:'Global settlement market'}[state.kind]||'Frontier Property');
 button(root,'Refresh',refresh);
 if(state.kind==='shop'){node('p','Purchases are paid from your bank and delivered to your inventory.',root);for(const item of vals(state.shop)){const r=node('article',item.name+' · '+money(item.price)+' · '+item.grams/1000+' kg',root);const b=button(r,'Buy',()=>{b.disabled=true;$('status').textContent='Submitting purchase…';act('buyItem',{item:item.id});setTimeout(()=>{b.disabled=false},2500)})}return}
 if(state.kind==='market'){for(const offer of vals(state.market)){const r=node('article',offer.name+' · '+offer.radius+'m · '+offer.buildings+' buildings · '+money(offer.price),root);confirmInline(r,'Buy entire settlement',()=>act('buySettlement',{sid:offer.id,price:offer.price}))}return}
 if(!s)return;
 if(state.kind==='site'&&b){
  const stage=Array.isArray(b.stages)?b.stages[b.stage-1]:b.stages[b.stage];if(!stage||b.complete){node('p','Construction finished.',root);return}
  node('h2',stage.label,root);node('p','Tools: '+vals(stage.tools).join(', '),root);
  const progress=node('progress',undefined,root);progress.max=stage.seconds;progress.value=b.progress;
  node('p',b.progress+' / '+stage.seconds+' seconds',root);
  for(const [k,n] of entries(stage.materials)){const left=n-(b.delivered?.[k]||0);const r=node('article',k+' · '+(n-left)+' / '+n,root);if(left>0&&s.rights.deliver){const q=input(r,'number',Math.min(left,5));q.min=1;q.max=left;button(r,'Deliver',()=>act('deliver',args({item:k,quantity:Number(q.value)})))}}
  if(s.rights.work)button(root,'Start work',()=>act('work',args()));button(root,'Stop work',()=>act('stopWork',args()));return
 }
 if(state.kind==='furnitureMenu'){
  node('p','Use furniture from inventory anywhere on your settlement. Move or pick up nearby objects below.',root);
  for(const [id,f] of entries(state.furniture)){const r=node('article',f.item,root);button(r,'Move',()=>act('moveFurniture',args({fid:id})));button(r,'Pick up',()=>act('removeFurniture',args({fid:id})))}
  return
 }
 if(state.kind==='interior'&&b){
  button(root,'Leave building',()=>act('exit'));node('p','Furnishing capacity: '+b.capacity+' slots',root);
  node('p','Use a furniture item from Frontier Inventory to place it.',root);
  for(const [id,f] of entries(b.furniture)){const r=node('article',f.item,root);if(s.rights.furnish){button(r,'Move',()=>act('moveFurniture',args({fid:id})));button(r,'Pick up',()=>act('removeFurniture',args({fid:id})))}}return
 }
 const p=propertyTabs(root,s);
 const summary=node('div',undefined,p.Overview);summary.className='metrics';
 for(const [label,value] of [['Territory',s.radius+'m'],['Buildings',String(vals(state.buildings).length)],['Weekly tax',money(s.tax)],['Outstanding',money(s.debt)]]){const m=node('article',undefined,summary);node('small',label,m);node('strong',value,m)}
 if(s.rights.expand)confirmInline(p.Construction,'Expand +25m · '+money(s.expansion),()=>act('expand',args()));
 if(s.rights.finance&&s.debt>0)button(p.Finances,'Pay tax',()=>act('tax',args()));
 if(s.rights.furnish){button(p.Buildings,'Manage plot furniture',()=>act('furnitureMenu',args()));for(const [id,f] of entries(state.legacyFurniture)){const r=node('article','Legacy interior item: '+f.item,p.Buildings);button(r,'Recover to inventory',()=>act('removeFurniture',args({bid:f.bid,fid:id})))}}
 if(s.rights.storage)button(p.Overview,'Camp chest',()=>act('chest',args()));
 if(s.rights.members){const sec=section(p.Members,'Settlement management');const name=input(p.Settings,'text',s.name);name.maxLength=60;button(p.Settings,'Rename',()=>act('rename',args({name:name.value})));if(s.owner)button(p.Settings,s.map?'Hide map marker':'Show map marker',()=>act('map',args()));
  const target=input(sec,'number','','Online player ID');const rights={};const list=node('div',undefined,sec);for(const k of vals(state.permissions)){const label=node('label',undefined,list);rights[k]=input(label,'checkbox');label.append(document.createTextNode(k))}
  button(sec,'Set member permissions',()=>act('member',args({target:Number(target.value),rights:Object.fromEntries(entries(rights).map(([k,v])=>[k,v.checked]))})));
  button(sec,'Remove member',()=>act('member',args({target:Number(target.value),remove:true})));
  if(s.owner){confirmInline(sec,'Add co-owner',()=>act('coowner',args({target:Number(target.value)})));confirmInline(sec,'Relinquish own co-ownership',()=>act('relinquish',args({confirm:'RELINQUISH'})))}
  for(const [id,r] of entries(s.members)){const row=node('article',id+' · '+entries(r).filter(([,v])=>v).map(([k])=>k).join(', '),sec);button(row,'Edit permissions',()=>{for(const [k,v] of entries(rights))v.checked=r[k]===true;button(row,'Save selected permissions',()=>act('member',args({character:id,rights:Object.fromEntries(entries(rights).map(([k,v])=>[k,v.checked]))})));});button(row,'Remove',()=>act('member',args({character:id,remove:true})))};
 }
 if(s.rights.build){const sec=section(p.Construction,'Construction catalogue');
  const cats=[...new Set(vals(state.catalogue).map(e=>e.category))].sort();const cat=select(sec,cats.map(c=>[c,c]));const ext=select(sec,[]);const detail=node('p','',sec);
  function update(){const e=state.catalogue[ext.value];if(e)detail.textContent='Materials: '+materials(e.materials)+' | Physical building'}
  function populate(){ext.replaceChildren();for(const [key,e] of entries(state.catalogue))if(e.category===cat.value){const o=node('option',e.label,ext);o.value=key}update()}
  cat.onchange=populate;ext.onchange=update;populate();
  button(sec,'Place building preview',()=>act('plan',args({exterior:ext.value})));
 }
 const sec=section(p.Buildings,'Buildings');
 for(const v of vals(state.buildings)){const e=state.catalogue[v.exterior];const r=node('article',e.label+' · '+(v.complete?'Complete':'Stage '+v.stage)+' · '+v.capacity+' slots',sec);const a={sid:s.id,bid:v.id};
  if(v.complete&&s.rights.move)button(r,'Relocate',()=>act('move',a));
  // Physical door locking is not implemented; do not expose a misleading lock button.
  if(v.complete&&s.rights.build){const choices=entries(state.catalogue).filter(([,n])=>n.category===e.category&&n.interior===e.interior&&n.slots>e.slots);if(choices.length){const up=select(r,choices.map(([k,n])=>[k,n.label]));confirmInline(r,'Upgrade',()=>act('upgrade',{...a,exterior:up.value}))}}
  if(s.rights.demolish)confirmInline(r,'Demolish without refund',()=>act('demolish',{...a,confirm:'DEMOLISH'}));
 }
 if(s.owner){const sec=section(p.Finances,'Global market');const price=input(sec,'number',s.listing?.price||50000);node('span',' price in cents',sec);button(sec,'List settlement',()=>act('list',args({price:Number(price.value)})));if(s.listing){button(sec,'Approve sale',()=>act('approve',args()));button(sec,'Cancel listing',()=>act('unlist',args()))}confirmInline(p.Settings,'Abandon settlement',()=>act('abandon',args({confirm:'ABANDON'})))}
}
let menuToken=null;
function hide(){document.body.hidden=true;state=null;menuToken=null}
function closeMenu(){hide();post('close').catch(console.error)}
window.addEventListener('message',function(event){
 const d=event.data;if(!d||typeof d!=='object')return;
 if(d.type==='menu'){
  menuToken=d.token;
  try{
   state=d.data;
   if(!state||typeof state.kind!=='string')throw new Error('Invalid menu data');
   render();
   document.body.hidden=false;
   post('menuReady',{token:d.token}).then(function(result){if(!result.ok&&menuToken===d.token)hide()}).catch(function(error){console.error(error);if(menuToken===d.token)hide()});
  }catch(error){
   console.error('Property menu render failed',error);
   hide();post('menuError',{token:d.token,message:String(error)}).catch(console.error);
  }
 }else if(d.type==='close'){hide()}
 else if(d.type==='notice'){$('status').textContent=d.message}
 else if(d.type==='refresh'){refresh()}
});
$('close').onclick=closeMenu;
document.addEventListener('keydown',function(e){if(e.key==='Escape'){e.preventDefault();closeMenu()}});
