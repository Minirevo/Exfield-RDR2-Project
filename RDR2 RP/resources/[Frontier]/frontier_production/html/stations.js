(()=>{'use strict';
const $=s=>document.getElementById(s), root=$('station-ui'), hud=$('station-hud'), old=document.querySelector('body > main');
let state,waiting=false,retry=null,frame=0,active=false,working=false,page='craft',category='All',design={},designRecipe=null,showroom=false,previewTimer;
const rows=x=>Object.values(x||{}), sec=n=>Math.floor(n/60)+'m '+n%60+'s';
const money=n=>'$'+(Number(n)/100).toFixed(2);
function select(id,items,defaultValue){
 const e=$(id);e.replaceChildren(...items.map(x=>new Option(x.name,x.id)));if(items.some(x=>x.id===defaultValue))e.value=defaultValue;
}
function status(s){$('st-status').textContent=s||''}
async function post(route,data={}){
 const res=await fetch('https://'+GetParentResourceName()+'/'+route,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});return res.json();
}
async function request(action,data={},again=false){
 if(waiting||!active)return;
 const order=again&&retry?retry:{action,data};waiting=true;retry=null;render();
 try{const result=await post('stationRequest',order);if(!result.ok){waiting=false;status('Request not accepted');render();return}order.seq=result.seq;lastOrder=order}
 catch{waiting=false;status('No request acknowledgement. Refresh before resubmitting.');render()}
}
let lastOrder;
function button(label,fn){const b=document.createElement('button');b.type='button';b.textContent=label;b.onclick=fn;b.disabled=waiting||!!retry;return b}
function recipe(){return rows(state?.recipes).find(r=>r.id===$('st-recipe').value)}
function node(tag,text,parent){const e=document.createElement(tag);if(text!=null)e.textContent=text;if(parent)parent.append(e);return e}
function label(id){return id.replace(/^(prod_|gather_|farm_|property_|weapon_)/,'').replaceAll('_',' ')}
function catalog(){
 const all=rows(state.recipes),cats=['All',...new Set(all.map(r=>r.category||'General'))];
 if(!cats.includes(category))category='All';const c=$('st-categories');c.replaceChildren();
 for(const name of cats){const b=button(name,()=>{category=name;catalog()});b.classList.toggle('chosen',category===name);c.append(b)}
 const search=$('st-search').value.toLowerCase(),list=$('st-cards');list.replaceChildren();
 for(const r of all.filter(r=>(category==='All'||(r.category||'General')===category)&&r.name.toLowerCase().includes(search))){
  const b=button('',()=>{$('st-recipe').value=r.id;designRecipe=null;catalog();preview()});b.className='recipeCard'+(recipe()?.id===r.id?' chosen':'');node('strong',r.name,b);node('small',(r.difficulty||'Basic')+' · '+r.rounds+' stages',b);list.append(b)
 }
}
function stopGunPreview(){if(!showroom)return;showroom=false;clearTimeout(previewTimer);root.classList.remove('gunShowroom');post('gunPreviewStop').catch(()=>{})}
function refreshGunPreview(){if(!showroom)return;clearTimeout(previewTimer);previewTimer=setTimeout(()=>{const r=recipe();if(r?.manualOnly)post('gunPreview',{id:r.id,cosmetics:design.cosmetics}).then(x=>{if(!x.ok){stopGunPreview();status('Preview unavailable')}}).catch(()=>stopGunPreview())},120)}
const gunStats=[
 {key:'durability',name:'Durability',tip:'Condition retention during use. Higher is better.',live:true},
 {key:'reload',name:'Ammo retrieval',tip:'Speed of retrieving ammunition from the satchel, not the native reload animation.',live:true},
 {key:'handling',name:'Handling',tip:'Planned gameplay attribute; not active yet.'},
 {key:'service',name:'Serviceability',tip:'Planned maintenance attribute; not active yet.'},
 {key:'weight',name:'Weight index',tip:'Estimated weight relative to standard; actual inventory weight is unchanged.',lower:true}
];
const slotHelp={body:'A fictional material choice affecting the overall design ratings.',balance:'A fictional material choice affecting the same combined ratings.',finish:'A fictional material choice affecting the combined ratings. Visible finishes are chosen separately below.'};
const cosmeticNames={barrel:'Barrel finish',frame:'Frame finish',trigger:'Trigger finish',cylinder:'Cylinder finish',frontsight:'Front sight finish',scope:'Scope finish',gripbody:'Grip / stock material',grip:'Grip / stock carving',wrapcolor:'Wrap colour'};
function cosmeticLabel(key){
 const [type,part]=key.split(':');
 if(type==='decal')return 'Engraving · '+label(part||'body');
 if(type==='decalcolor')return 'Engraving colour · '+label(part||'body');
 return cosmeticNames[type]||label(key.replace(':',' '));
}
function cosmeticHelp(key){
 if(key.startsWith('decal:'))return 'Changes the decorative engraving pattern on this region.';
 if(key.startsWith('decalcolor:'))return 'Changes the engraving colour; select a pattern on this region to see it.';
 if(key==='gripbody')return 'Changes the visible grip or stock finish.';
 if(key==='grip')return 'Adds a decorative carving where supported.';
 if(key==='wrapcolor')return 'Changes the colour of a compatible wrap, if present.';
 return 'Changes the visible finish only; no gameplay bonus.';
}
function relative(v,base=100){const d=v-base;return d===0?'Standard':(d>0?'+':'')+d+'%'}
function updateGunStats(r){
 const materials=Object.values(design.materials).map(id=>r.designMaterials[id]).filter(Boolean);
 const grid=$('st-gun-stats-grid');if(!grid||!materials.length)return;grid.replaceChildren();
 for(const stat of gunStats){
  const v=Math.round(materials.reduce((a,m)=>a+Number(m[stat.key]),0)/materials.length);
  const item=node('div',null,grid);item.className='gunStat';item.title=stat.tip;
  const line=node('div',null,item);line.className='gunStatLine';node('span',stat.name,line);
  const delta=node('strong',relative(v),line);delta.className=v===100?'neutral':(stat.lower?v<100:v>100)?'available':'missing';
  const track=node('div',null,item);track.className='gunStatTrack';const bar=node('span',null,track);bar.style.width=Math.min(100,v/1.5)+'%';bar.className=delta.className;
  node('small',stat.live?'Active · '+v+'%':'Planned · '+v+'%',item);
 }
 for(const [slot,id] of Object.entries(design.materials)){
  const m=r.designMaterials[id],detail=$('st-material-'+slot);if(!m||!detail)continue;detail.replaceChildren();
  for(const stat of gunStats){const val=m[stat.key];const chip=node('span',stat.name+': '+relative(val),detail);chip.className=val===100?'neutral':(stat.lower?val<100:val>100)?'available':'missing';chip.title=stat.tip}
 }
}
function buildDesign(r){
 const box=$('st-design');box.hidden=!r.manualOnly;
 if(!r.manualOnly){stopGunPreview();designRecipe=null;return}
 if(designRecipe===r.id)return;
 stopGunPreview();designRecipe=r.id;design={name:'',materials:{},cosmetics:{}};box.replaceChildren();node('h3','Custom design',box);const actions=node('div',null,box);actions.className='gunPreviewActions';actions.append(button('Live 3D preview',()=>{showroom=!showroom;root.classList.toggle('gunShowroom',showroom);if(showroom)refreshGunPreview();else post('gunPreviewStop').catch(()=>{})}),button('Rotate left',()=>{if(showroom)post('gunPreviewRotate',{direction:'left'}).catch(()=>{})}),button('Rotate right',()=>{if(showroom)post('gunPreviewRotate',{direction:'right'}).catch(()=>{})}));
 const summary=node('section',null,box);summary.id='st-gun-stats';node('h3','Combined design ratings',summary);const grid=node('div',null,summary);grid.id='st-gun-stats-grid';node('small','Standard = 100%. Before workmanship. Planned ratings are informational only.',summary);
 const name=node('input',null,box);name.maxLength=48;name.placeholder='Optional weapon name';name.oninput=()=>design.name=name.value;node('h3','Material choices',box);node('p','Each slot contributes equally to the combined fictional ratings. Appearance is separate.',box);
 for(const slot of r.designSlots){const l=node('label',r.designSlotLabels[slot],box);node('small',slotHelp[slot]||'Contributes to combined design ratings.',l);const s=node('select',null,l);for(const [id,m] of Object.entries(r.designMaterials))s.add(new Option(m.name,id));design.materials[slot]=s.value;s.onchange=()=>{design.materials[slot]=s.value;preview()};const detail=node('div',null,box);detail.id='st-material-'+slot;detail.className='gunMaterialDetail'}
 const details=node('details',null,box);node('summary','Appearance & finishes',details);
 for(const [key,opts] of Object.entries(r.cosmetics||{}).sort(([a],[b])=>cosmeticLabel(a).localeCompare(cosmeticLabel(b)))){const l=node('label',cosmeticLabel(key),details);node('small',cosmeticHelp(key),l);const s=node('select',null,l);s.add(new Option('Default',''));for(const o of opts){const cost=o.label==='Gold'?' · + refined gold':o.label==='Copper'||o.label==='Brass'?' · + copper ingot':'';s.add(new Option(o.label+cost,String(o.hash)))}s.onchange=()=>{if(s.value)design.cosmetics[key]=Number(s.value);else delete design.cosmetics[key];preview();refreshGunPreview()}}
 node('p','Each choice is saved with the individual weapon. Cosmetic visibility and additional performance modifiers require in-game verification.',box);
}
function preview(){
 const r=recipe();if(!r)return;buildDesign(r);$('st-selected').textContent=r.name;
 if(r.manualOnly){$('st-mode').value='manual';$('st-batches').value=1}
 const npc=$('st-mode').value==='npc', n=Number($('st-batches').value);
 $('st-batches').disabled=waiting||!!retry||!!r.manualOnly;$('st-mode').disabled=waiting||!!r.manualOnly;$('st-input').disabled=npc||waiting;$('st-output').disabled=npc||waiting;
 if(!r)return;
 const counts=npc||$('st-input').value==='storage'?state.inputCounts:state.bag;
 const inputs={...r.inputs};if(r.manualOnly){for(const id of Object.values(design.materials)){const item=r.designMaterials[id].item;inputs[item]=(inputs[item]||0)+1}for(const [k,v] of Object.entries(design.cosmetics)){const name=r.cosmetics[k]?.find(o=>o.hash===v)?.label;const item=name==='Gold'?'prod_gold':name==='Copper'||name==='Brass'?'prod_copper':null;if(item)inputs[item]=(inputs[item]||0)+1}}
 const p=$('st-preview');p.replaceChildren();node('h3','Materials required',p);
 for(const [id,count] of Object.entries(inputs)){const have=Number(counts?.[id]||0),row=node('div',null,p);row.className='materialRow';node('span',label(id),row);const value=node('strong',have+' / '+count*n,row);value.className=have>=count*n?'available':'missing'}
 const timing=[3.6,3.3,3.1,2.6,2.2,2.05,1.9],duration=npc?r.npc:r.manualOnly?70:r.rounds*timing[r.rounds-1];
 node('p',r.quantity*n+' × '+label(r.output)+' · '+sec(Math.ceil(duration*n))+(npc?' · Wage '+money(Math.ceil(r.npc*n*state.wage/state.wageInterval)):' · '+r.rounds*n+' stages · '+r.difficulty),p);
 if(r.manualOnly)updateGunStats(r);
 const valid=Object.entries(inputs).every(([id,count])=>Number(counts?.[id]||0)>=count*n);
 $('st-start').disabled=waiting||!!retry||!valid||!Number.isInteger(n)||n<1||n>state.maxBatches||(npc&&!state.canNpc);
}
function render(){
 if(!state)return;
 const s=state.station;$('st-name').textContent=s.name;$('st-sub').textContent=s.plot+' · '+(s.ownerType==='company'?'Company':'Private')+' · profession level '+state.skill;
 const previous=$('st-recipe').value;select('st-recipe',rows(state.recipes),previous);catalog();
 $('st-batches').max=state.maxBatches;
 $('st-mode').querySelector('[value=npc]').disabled=!state.canNpc;
 if(!state.canNpc)$('st-mode').value='manual';
 const prevInput=$('st-input').value,prevOutput=$('st-output').value;
 select('st-input',[{id:'bag',name:'Personal inventory'},...(state.inputReady?[{id:'storage',name:'Linked input storage'}]:[])],prevInput);
 select('st-output',[{id:'bag',name:'Personal inventory'},...(state.outputReady?[{id:'storage',name:'Linked output storage'}]:[])],prevOutput);
 $('st-settings').hidden=!state.manage;
 select('st-link-input',[{id:'',name:'No input storage'},...rows(state.stocks)],s.input);
 select('st-link-output',[{id:'',name:'No output storage'},...rows(state.stocks)],s.output);
 select('st-company',[{id:'',name:'Private operation'},...rows(state.companies).map(c=>({id:c.id,name:c.name}))],s.ownerType==='company'?s.ownerId:'');
 $('st-hire').textContent=s.employee?'Dismiss NPC worker':'Hire NPC worker';
 $('st-worker').textContent=s.employee?'Worker hired · linked stock only':'No worker hired';
 $('st-retry').hidden=!retry;
 for(const e of root.querySelectorAll('button:not(#st-close)'))e.disabled=waiting||!!retry;
 $('st-retry').disabled=waiting;$('st-close').disabled=false;
 for(const b of $('st-tabs').querySelectorAll('button'))b.classList.toggle('chosen',b.dataset.page===page);
 $('st-craft').hidden=page!=='craft';$('st-orders').hidden=page!=='orders';$('st-management').hidden=page!=='management';
 const jobs=$('st-jobs');jobs.replaceChildren();
 for(const j of rows(state.jobs)){
  const card=document.createElement('article'),title=document.createElement('strong'),sub=document.createElement('p');
  title.textContent=j.name+' × '+j.batches+' · '+j.mode;sub.textContent=j.state+(j.remaining?' · '+sec(j.remaining):'')+(j.issue?' · '+j.issue:'');
  card.append(title,sub);if(j.cancel)card.append(button('Cancel / return materials',()=>request('cancel',{job:j.id})));
  jobs.append(card);
 }
 if(!jobs.children.length)jobs.textContent='No orders yet.';
 preview();
}
$('st-tabs').onclick=e=>{if(e.target.dataset.page&&!waiting){stopGunPreview();page=e.target.dataset.page;render()}};$('st-search').oninput=catalog;
$('st-close').onclick=()=>post('stationClose');$('st-refresh').onclick=()=>request('refresh');
$('st-retry').onclick=()=>{if(retry)request(retry.action,retry.data,true)};
$('st-start').onclick=()=>{if(recipe())request('start',{recipe:recipe().id,mode:$('st-mode').value,batches:Number($('st-batches').value),input:$('st-input').value,output:$('st-output').value,design:recipe().manualOnly?design:undefined})};
$('st-link').onclick=()=>request('link',{input:$('st-link-input').value,output:$('st-link-output').value});
$('st-owner').onclick=()=>{request('setup',{company:$('st-company').value})};
$('st-hire').onclick=()=>request(state.station.employee?'dismiss':'hire');
$('st-release').onclick=()=>{request('release')};
for(const id of ['st-recipe','st-batches','st-mode','st-input','st-output'])$(id).addEventListener('change',preview);
$('st-batches').addEventListener('input',preview);
document.addEventListener('keydown',e=>{if((active||working)&&e.key==='Escape'){e.stopImmediatePropagation();e.preventDefault();if(active)post('stationClose')}},true);
let qte=null;
function hide(){stopGunPreview();qte=null;active=false;working=false;root.hidden=true;hud.hidden=true;old.hidden=false;document.body.hidden=true;cancelAnimationFrame(frame)}
window.addEventListener('message',({data:d})=>{
 if(d.type==='stationOpen'){
  active=true;working=false;page='craft';category='All';designRecipe=null;$('st-search').value='';state=d.snapshot;waiting=false;retry=null;old.hidden=true;hud.hidden=true;root.hidden=false;document.body.hidden=false;status('');render();
 }else if(d.type==='stationResult'&&active){
  waiting=false;retry=d.retry&&lastOrder?{...lastOrder,retry:true,seq:d.seq}:null;if(d.snapshot)state=d.snapshot;status(d.message);render();
 }else if(d.type==='gunPreviewStatus'&&active&&showroom){if(!d.ok){stopGunPreview();status(d.message)}}else if(d.type==='stationNotice'&&active){status(d.message)}
 else if(d.type==='stationClose'){hide()}
 else if(d.type==='stationWork'){
  stopGunPreview();active=false;working=true;root.hidden=true;old.hidden=true;hud.hidden=false;document.body.hidden=false;
  $('st-work-label').textContent=d.label;
  cancelAnimationFrame(frame);
  qte={round:0,hits:{},results:{},elapsed:Number(d.elapsed)||0,anchor:performance.now()};
  $('st-round-dots').replaceChildren(...Array.from({length:d.rounds},()=>{const dot=document.createElement('span');dot.className='st-dot';return dot}));
  const tick=t=>{
   if(!working||!qte)return;
   const clock=qte.elapsed+Math.max(0,t-qte.anchor),elapsed=Math.max(0,clock),round=Math.min(d.targets.length,Math.floor(elapsed/d.roundMs)+1);
   const relative=elapsed-(round-1)*d.roundMs, batch=Math.floor((round-1)/d.rounds)+1, localRound=(round-1)%d.rounds+1;
   if(qte.round!==round){
    qte.round=round;$('st-target').style.left=(d.targets[round-1]-d.width)*100+'%';$('st-target').style.width=d.width*200+'%';
    $('st-round').textContent=(d.stages?.[localRound-1]||('Batch '+batch+' / '+d.batches))+' · Stage '+localRound+' / '+d.rounds;
   }
   const hit=qte.hits[round],score=qte.results[round],expired=relative>d.sweepMs;
   $('st-marker').style.left=(hit===undefined?Math.min(1,relative/d.sweepMs):hit)*100+'%';
   $('st-instruction').textContent=score!==undefined?(score>=.75?'Excellent strike':score>0?'Strike recorded':'Missed'):(hit!==undefined?'Checking strike…':clock<0?'Get ready…':expired?'Missed · next round shortly':'Press SPACE in the green zone');
   $('st-instruction').dataset.result=score!==undefined?(score>=.75?'good':score>0?'partial':'miss'):(expired&&hit===undefined?'miss':'');
   [...$('st-round-dots').children].forEach((dot,i)=>{
    const k=(batch-1)*d.rounds+i+1,s=qte.results[k];
    dot.dataset.state=s!==undefined?(s>=.75?'good':s>0?'partial':'miss'):k<round?'miss':k===round?(expired&&hit===undefined?'miss':'active'):'pending';
   });
   $('st-progress').value=Math.min(1,elapsed/d.ms);
   if(elapsed<d.ms)frame=requestAnimationFrame(tick);else $('st-instruction').textContent='Finishing production…';
  };frame=requestAnimationFrame(tick);
 }else if(d.type==='stationClock'&&qte){qte.elapsed=Number(d.elapsed)||0;qte.anchor=performance.now()}
 else if(d.type==='stationStrike'&&qte){qte.hits[d.round]=d.position}
 else if(d.type==='stationStrikeResult'&&qte){qte.results[d.round]=d.score}
 else if(d.type==='stationEnd'){hide()}
});
// Refresh is explicit so it never resets partially edited ownership or storage links.
})();
