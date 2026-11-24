'use strict';
const $=id=>document.getElementById(id);
let state=null;
const entries=x=>Object.entries(x||{}), vals=x=>Object.values(x||{});
const money=n=>'$'+(Number(n||0)/100).toFixed(2);
const materials=x=>entries(x).map(([k,n])=>n+' '+k.replaceAll('_',' ')).join(' · ');
function node(tag,text,parent){const el=document.createElement(tag);if(text!==undefined)el.textContent=text;if(parent)parent.append(el);return el}
function button(parent,label,fn){const el=node('button',label,parent);el.type='button';el.onclick=fn;return el}
function input(parent,type,value,placeholder){const el=node('input',undefined,parent);el.type=type;el.value=value??'';el.placeholder=placeholder||'';return el}
function select(parent,options){const el=node('select',undefined,parent);for(const [key,label] of options){const o=node('option',label,el);o.value=key}return el}
function section(parent,title){const el=node('section',undefined,parent);node('h2',title,el);return el}
async function post(route,data){const r=await fetch('https://'+GetParentResourceName()+'/'+route,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data||{})});return r.json()}
function act(action,data={}){post('action',{action,data}).catch(()=>{$('status').textContent='Request failed.'})}
function args(data={}){return {sid:state.settlement?.id,bid:state.building?.id,...data}}
function refresh(){if(!state)return;act(state.kind,args())}
function confirmInline(parent,label,fn){const b=button(parent,label,()=>{b.textContent='Confirm '+label; b.onclick=()=>{b.disabled=true;fn()}})}
function render(){
 const root=$('content');root.replaceChildren();const s=state.settlement,b=state.building;
 $('title').textContent=s?.name||({shop:'General store',market:'Global settlement market'}[state.kind]||'Frontier Property');
 button(root,'Refresh',refresh);
 if(state.kind==='shop'){for(const item of vals(state.shop)){const r=node('article',item.name+' · '+money(item.price)+' · '+item.grams/1000+' kg',root);button(r,'Buy',()=>act('buyItem',{item:item.id}))}return}
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
 if(state.kind==='interior'&&b){
  button(root,'Leave building',()=>act('exit'));node('p','Furnishing capacity: '+b.capacity+' slots',root);
  node('p','Use a furniture item from Frontier Inventory to place it.',root);
  for(const [id,f] of entries(b.furniture)){const r=node('article',f.item,root);if(s.rights.furnish){button(r,'Move',()=>act('moveFurniture',args({fid:id})));button(r,'Pick up',()=>act('removeFurniture',args({fid:id})))}}return
 }
 node('p','Radius '+s.radius+'m · Weekly tax '+money(s.tax)+' · Outstanding '+money(s.debt),root);
 if(s.rights.expand)confirmInline(root,'Expand +25m · '+money(s.expansion),()=>act('expand',args()));
 if(s.rights.finance&&s.debt>0)button(root,'Pay tax',()=>act('tax',args()));
 if(s.rights.storage)button(root,'Camp chest',()=>act('chest',args()));
 if(s.rights.members){const sec=section(root,'Settlement management');const name=input(sec,'text',s.name);name.maxLength=60;button(sec,'Rename',()=>act('rename',args({name:name.value})));if(s.owner)button(sec,s.map?'Hide map marker':'Show map marker',()=>act('map',args()));
  const target=input(sec,'number','','Online player ID');const rights={};const list=node('div',undefined,sec);for(const k of vals(state.permissions)){const label=node('label',undefined,list);rights[k]=input(label,'checkbox');label.append(document.createTextNode(k))}
  button(sec,'Set member permissions',()=>act('member',args({target:Number(target.value),rights:Object.fromEntries(entries(rights).map(([k,v])=>[k,v.checked]))})));
  button(sec,'Remove member',()=>act('member',args({target:Number(target.value),remove:true})));
  if(s.owner){confirmInline(sec,'Add co-owner',()=>act('coowner',args({target:Number(target.value)})));confirmInline(sec,'Relinquish own co-ownership',()=>act('relinquish',args({confirm:'RELINQUISH'})))}
  for(const [id,r] of entries(s.members)){const row=node('article',id+' · '+entries(r).filter(([,v])=>v).map(([k])=>k).join(', '),sec);button(row,'Edit permissions',()=>{for(const [k,v] of entries(rights))v.checked=r[k]===true;button(row,'Save selected permissions',()=>act('member',args({character:id,rights:Object.fromEntries(entries(rights).map(([k,v])=>[k,v.checked]))}))});button(row,'Remove',()=>act('member',args({character:id,remove:true})))};
 }
 if(s.rights.build){const sec=section(root,'Construction catalogue');
  const cats=[...new Set(vals(state.catalogue).map(e=>e.category))].sort();const cat=select(sec,cats.map(c=>[c,c]));const ext=select(sec,[]);const int=select(sec,[]);const detail=node('p','',sec);
  function update(){const e=state.catalogue[ext.value];if(!e)return;int.hidden=!e.interior;const i=e.interior?state.interiors[int.value]:null;detail.textContent='Exterior: '+materials(e.materials)+' | '+e.slots+' slots'+(i?' / Interior: '+materials(i.materials)+' | '+i.slots+' slots':'')+' / Total slots: '+(e.slots+(i?.slots||0))}
  function populate(){ext.replaceChildren();for(const [key,e] of entries(state.catalogue))if(e.category===cat.value){const o=node('option',e.label,ext);o.value=key}update()}
  for(const [key,i] of entries(state.interiors)){const o=node('option',i.label,int);o.value=key}cat.onchange=populate;ext.onchange=update;int.onchange=update;populate();
  button(sec,'Place building preview',()=>act('plan',args({exterior:ext.value,interior:state.catalogue[ext.value].interior?int.value:null})));
 }
 const sec=section(root,'Buildings');
 for(const v of vals(state.buildings)){const e=state.catalogue[v.exterior];const r=node('article',e.label+' · '+(v.complete?'Complete':'Stage '+v.stage)+' · '+v.capacity+' slots',sec);const a={sid:s.id,bid:v.id};
  if(v.complete&&s.rights.move)button(r,'Relocate',()=>act('move',a));
  if(v.complete&&s.rights.members&&v.interior)button(r,v.locked?'Unlock':'Lock',()=>act('lock',a));
  if(v.complete&&s.rights.build){const choices=entries(state.catalogue).filter(([,n])=>n.category===e.category&&n.interior===e.interior&&n.slots>e.slots);if(choices.length){const up=select(r,choices.map(([k,n])=>[k,n.label]));confirmInline(r,'Upgrade',()=>act('upgrade',{...a,exterior:up.value}))}}
  if(s.rights.demolish)confirmInline(r,'Demolish without refund',()=>act('demolish',{...a,confirm:'DEMOLISH'}));
 }
 if(s.owner){const sec=section(root,'Global market');const price=input(sec,'number',s.listing?.price||50000);node('span',' price in cents',sec);button(sec,'List settlement',()=>act('list',args({price:Number(price.value)})));if(s.listing){button(sec,'Approve sale',()=>act('approve',args()));button(sec,'Cancel listing',()=>act('unlist',args()))}confirmInline(sec,'Abandon settlement',()=>act('abandon',args({confirm:'ABANDON'})))}
}
window.addEventListener('message',({data:d})=>{if(d.type==='menu'){state=d.data;document.body.hidden=false;render()}else if(d.type==='close'){document.body.hidden=true;state=null}else if(d.type==='notice'){$('status').textContent=d.message}else if(d.type==='refresh')refresh()});
$('close').onclick=()=>post('close');document.addEventListener('keydown',e=>{if(e.key==='Escape')post('close')});
