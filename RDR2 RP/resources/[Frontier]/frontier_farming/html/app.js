'use strict';
const $=id=>document.getElementById(id);
let data=null,selected=null,workToken=null,workFrame=0;
const rememberedTabs=new Map();
function send(action,extra={}){fetch('https://'+GetParentResourceName()+'/farmAction',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action,data:{id:selected,...extra}})}).catch(()=>{$('notice').textContent='Request failed'})}
function el(tag,text,parent){const n=document.createElement(tag);if(text!=null)n.textContent=text;if(parent)parent.append(n);return n}
function button(parent,text,action,extra){const b=el('button',text,parent);b.onclick=()=>send(action,typeof extra==='function'?extra():extra)}
function select(parent,options){const s=el('select',null,parent);for(const [k,v] of options){const o=el('option',v,s);o.value=k}return s}

function stockQty(f,id){return Number(f.counts?.[id]||0)}
function nameOf(id){return data.items?.[id]?.name||id}
const toolNames={hoe:'Hoe',sickle:'Sickle',water:'Watering can',bucket:'Bucket',fork:'Pitchfork',milk:'Milking kit',shear:'Shears',knife:'Butcher knife'};
function actionPanel(parent,f,title,action,{tool=null,item=null,required=0,extra=()=>({}),condition=true,reason='',output='',chest=true}={}){
 const panel=el('div',null,parent);panel.className='action-panel';
 el('strong',title,panel);
 if(tool){const t=el('small',(data.tools?.[tool]?'✓ ':'Missing: ')+toolNames[tool]+' (personal inventory)',panel);t.className=data.tools?.[tool]?'good':'bad'}
 let line=null;if(item)line=el('small','',panel);
 if(output)el('small',output,panel);
 const msg=el('small','',panel);msg.className='bad';
 const btn=el('button',title,panel);btn.onclick=()=>send(action,extra());
 const update=(id=item,n=required,valid=condition,why=reason)=>{
  const has=id?stockQty(f,id):0;
  if(line){line.textContent=nameOf(id)+': '+has+' / '+n+' in linked chest'+(has<n?' · missing '+(n-has):'');line.className=has>=n?'good':'bad'}
  const issue=chest&&!f.stockAvailable?'Link a valid stock chest first':!valid?why:tool&&!data.tools?.[tool]?'Required tool missing':id&&has<n?'Not enough stock':'';
  msg.textContent=issue;btn.disabled=Boolean(issue);
 };
 update();return {panel,update,btn};
}
function supplyPanel(parent,f,b,v,action,foodSelect){
 const n=Number(v.female||0)+Number(v.male||0)+Number(v.young||0),field=b.kind==='field',isFeed=action==='feed';
 const base=isFeed?n:field?Math.ceil(data.capacity[b.size]/25):Math.ceil(n/4);
 const factor=field?1:n,perUnit=base>0?43200*factor/base:0;
 const reserve=isFeed?v.feed:v.water;
 const max=perUnit>0?Math.max(0,Math.ceil((172800*factor-reserve)/perUnit-1e-7)):0;
 const item=()=>isFeed?(foodSelect?foodSelect.value:data.species[v.species]?.feed):'farm_water';
 const label=isFeed?'Add feed':'Add water';
 const box=el('div',null,parent);box.className='supply-box';
 const qty=el('input',null,box);qty.type='number';qty.min=1;qty.step=1;qty.setAttribute('aria-label',label+' quantity');
 const estimate=el('small','',box);
 const a=actionPanel(box,f,label,action,{tool:isFeed?'fork':'water',item:item(),extra:()=>({quantity:Number(qty.value),...(isFeed?{food:item()}:{})})});
 function refresh(reset=false){
  const available=stockQty(f,item());qty.max=Math.min(max,available);
  if(reset)qty.value=Math.min(base,max,available)||1;
  const amount=Number(qty.value),valid=base>0&&Number.isInteger(amount)&&amount>=1&&amount<=max;
  estimate.textContent=max===0?'Reserve full or no eligible animals/crops.':'Maximum reserve: 48 hours · '+max+' units can fit · selected adds up to '+(amount*perUnit/factor/3600).toFixed(1)+'h before work bonus';
  a.update(item(),Number.isFinite(amount)?amount:0,valid,max===0?'Reserve full or no eligible target':'Select a whole quantity between 1 and '+max);
 }
 qty.oninput=()=>refresh();if(foodSelect)foodSelect.onchange=()=>refresh(true);refresh(true);
}

function pages(root,key,labels){
 const nav=$('pages'),panels={},buttons={};let active=rememberedTabs.get(key);
 if(!labels.includes(active))active=labels[0];
 nav.replaceChildren();nav.hidden=false;
 function activate(name){
  rememberedTabs.set(key,name);
  for(const label of labels){panels[label].hidden=label!==name;buttons[label].setAttribute('aria-pressed',String(label===name))}
  root.scrollTop=0;
 }
 for(const label of labels){
  const b=el('button',label,nav);b.type='button';b.onclick=()=>activate(label);buttons[label]=b;
  panels[label]=el('div',null,root);panels[label].className='page';
 }
 activate(active);return panels;
}
function metric(parent,label,value,ratio){
 const m=el('div',null,parent);m.className='metric';el('small',label,m);el('strong',value,m);
 if(Number.isFinite(ratio)){const p=el('progress',null,m);p.max=1;p.value=Math.max(0,Math.min(1,ratio))}
}
function breeding(parent,v,b){
 const cfg=data.species[v.species],n=Number(v.female||0)+Number(v.male||0)+Number(v.young||0);
 if(!cfg){el('p','Introduce animals to begin breeding.',parent);return}
 const horse=v.species==='horse',hours=horse?48:24,capacity=cfg.capacity[b.size],free=Math.max(0,capacity-n);
 const healthy=horse?(v.horses||[]).filter(h=>h.age>=cfg.mature*3600&&h.health>=70&&!h.listed):null;
 const male=horse?healthy.some(h=>h.sex==='male'):v.male>0;
 const female=horse?healthy.some(h=>h.sex==='female'):v.female>0;
 const conditions=[['Eligible adult male',male],['Eligible adult female',female],['Health requirement',horse?male&&female:v.health>=50],['Food available',v.feed>0],['Water available',v.water>0],['Free capacity',free>0]];
 const progress=Math.min(1,Math.max(0,Number(v.breedClock||0)/(hours*3600))),active=conditions.every(x=>x[1]);
 const metrics=el('div',null,parent);metrics.className='metrics';
 metric(metrics,'Breeding cycle',(progress*hours).toFixed(1)+' / '+hours+'h',progress);
 metric(metrics,'Potential next litter',String(male&&female?Math.min(free,horse?1:v.female||0):0));
 metric(metrics,'Young animals',String(v.young||0));
 metric(metrics,'Remaining care time',((1-progress)*hours).toFixed(1)+'h');
 el('p',active?'Breeding active when supplied':'Breeding paused or blocked',parent).className=active?'good':'bad';
 for(const [label,ok] of conditions)el('p',(ok?'✓ ':'✗ ')+label,parent).className=ok?'good':'bad';
 if(!horse&&v.young>0){const ratio=Math.min(1,Number(v.matureClock||0)/(cfg.mature*3600));const m=el('div',null,parent);m.className='metrics';metric(m,'Maturation',(ratio*cfg.mature).toFixed(1)+' / '+cfg.mature+'h',ratio)}
 el('small','Timers show the last server snapshot. Refresh for current progress. Animals need food and water throughout the care time.',parent);
}
function render(){
 const list=data.facilities||[];const tabs=$('tabs'),root=$('content');tabs.hidden=false;tabs.replaceChildren();root.replaceChildren();$('pages').replaceChildren();$('pages').hidden=true;
 if(!list.some(v=>v.building.id===selected))selected=list[0]?.building.id;
 for(const f of list){const b=el('button',f.building.size+' '+f.building.kind,tabs);b.onclick=()=>{selected=f.building.id;render()};if(f.building.id===selected)b.style.borderColor='#ddd0a0'}
 const f=list.find(v=>v.building.id===selected);if(!f){el('p','No authorized completed farm facilities nearby.',root);return}
 const b=f.building;el('h2',b.size+' '+b.kind,root);
 if(f.unbound){button(root,'Register personally','bind');el('label','Or company ID with farm grant',root);const i=el('input',null,root);button(root,'Register company','bind',()=>({company:i.value.trim()}));return}
 el('small',f.ownerType+' · '+f.owner,root);el('p','Facility ID: '+b.id,root);
 const v=f.state;const field=b.kind==='field',animals=b.kind==='livestock'||b.kind==='chicken',horse=v.species==='horse';
 const labels=field?['Overview','Cultivation','Supplies','Harvest','Settings']:animals?['Overview','Animals','Supplies','Breeding','Production',...(horse?['Training','Sales']:[]),'Settings']:['Overview','Work','Settings'];
 const pgs=pages(root,b.id,labels);const overview=pgs.Overview,settings=pgs.Settings;
 const storage=el('section',null,settings);el('h2','Linked storage',storage);const s=select(storage,(f.stocks||[]).map(v=>[v.id,v.name]));s.value=f.storage||'';button(storage,'Link chest','link',()=>({storage:s.value}));if(f.storage)button(storage,'Unlink chest','unlink');el('p',(f.stocks||[]).find(x=>x.id===f.storage)?.name||f.storage||'No chest linked',storage);el('small','Tools go in personal inventory. Supplies and harvested goods use this chest.',storage);
 if(f.pending){$('notice').textContent='Pending transaction recovery. Actions disabled.';button(overview,'Refresh snapshot','open');return}
 let work=pgs.Work||pgs.Cultivation||pgs.Animals;
 const stats=el('div',null,overview);stats.className='metrics';
 if(field){metric(stats,'Crop',v.crop||'Empty');metric(stats,'Soil',Math.round(v.soil)+'%',v.soil/100);metric(stats,'Growth',Math.round(v.growth*100)+'%',v.growth);metric(stats,'Water reserve',(v.water/3600).toFixed(1)+'h',v.water/172800)}
 if(animals){const n=v.female+v.male+v.young;const cap=data.species[v.species]?.capacity[b.size]||0;metric(stats,'Population',n+(cap?' / '+cap:''),cap?n/cap:0);metric(stats,'Health',Math.round(v.health)+'%',v.health/100);metric(stats,'Food reserve',(n?v.feed/n/3600:0).toFixed(1)+'h',n?v.feed/n/172800:0);metric(stats,'Water reserve',(n?v.water/n/3600:0).toFixed(1)+'h',n?v.water/n/172800:0);breeding(pgs.Breeding,v,b)}
 if(!field&&!animals)el('p','Use the Work tab to fill water.',overview);
 button(overview,'Refresh snapshot','open');

 if(b.kind==='field'){
  el('p',v.crop?'Crop: '+v.crop+' · Soil: '+v.soil+'%':'Empty field · Soil: '+v.soil+'%',work);
  const units=data.capacity[b.size];
  el('p',v.crop&&!v.dead&&v.growth>=1?'Ready to harvest.':'No mature crop ready.',pgs.Harvest);
  if(!v.crop){
   const c=select(work,Object.keys(data.crops).map(k=>[k,k]));
   const a=actionPanel(work,f,'Plant entire field','plant',{tool:'hoe',item:'farm_seed_'+c.value,required:units,extra:()=>({crop:c.value}),output:'Plants all '+units+' seed positions in one operation.'});
   c.onchange=()=>a.update('farm_seed_'+c.value,units,true);
  }else if(v.dead){actionPanel(work,f,'Clear dead crops','clearCrop',{tool:'hoe',chest:false})}
  else{
   const p=el('progress',null,work);p.max=1;p.value=v.growth;
   el('p',Math.floor(v.growth*100)+'% grown · Water reserve '+(v.water/3600).toFixed(1)+'h · '+(v.fertilized?'Fertilized':'Not fertilized'),work);
   if(v.growth<1){
    el('small','Growth: '+data.crops[v.crop].hours+'h base time; pauses without water.',work);
    supplyPanel(pgs.Supplies,f,b,v,'water');
    actionPanel(pgs.Supplies,f,'Fertilize','fertilize',{tool:'fork',item:'farm_fertilizer',required:Math.ceil(units/25),condition:!v.fertilized,reason:'Already fertilized',output:'25% faster growth and higher yield.'});
   }else{
    const base=v.harvestRemaining??Math.floor(units*(v.fertilized?2.5:2)*v.soil/100);
    const best=v.harvestRemaining??Math.floor(units*(v.fertilized?2.5:2)*v.soil/100*1.25);
    const seeds=v.seedRemaining??units+Math.floor(units/10);
    actionPanel(pgs.Harvest,f,'Harvest entire remaining crop','harvest',{tool:'sickle',output:'One minigame. Deposits '+base+(best!==base?'–'+best:'')+' '+v.crop+' and '+seeds+' seeds directly into the linked chest. Chest must fit the full harvest.'});
   }
  }
  actionPanel(pgs.Supplies,f,'Make fertilizer','fertilizer',{item:'farm_manure',required:5,output:'Converts 5 manure into 1 fertilizer.'});
 }else if(b.kind==='livestock'||b.kind==='chicken'){
  const n=v.female+v.male+v.young;
  el('p',(v.species||'Empty')+' · Female '+v.female+' · Male '+v.male+' · Young '+v.young,work);
  el('p','Health '+Math.round(v.health)+'% · Products ready '+v.products+' · Manure ready '+Math.floor(v.manure),work);
  if(n){
   el('p','Food remaining '+(v.feed/n/3600).toFixed(1)+'h · Water remaining '+(v.water/n/3600).toFixed(1)+'h',work);
   let food;
   if(v.species==='pig')food=select(pgs.Supplies,['corn','carrot','potato','wheat','broccoli','artichoke'].map(k=>['farm_'+k,k]));
   supplyPanel(pgs.Supplies,f,b,v,'feed',food);supplyPanel(pgs.Supplies,f,b,v,'water');
   const product=data.species[v.species]?.product;
   if(product){const chicken=v.species==='chicken';actionPanel(pgs.Production,f,chicken?'Collect eggs':v.species==='sheep'?'Shear wool':'Collect milk','collect',{tool:chicken?null:v.species==='sheep'?'shear':'milk',condition:v.products>0,reason:'No products ready',output:v.products+' '+nameOf(product)+' ready'+(chicken?' · no minigame.':' · work bonus may increase yield.')});}
   actionPanel(pgs.Production,f,'Collect manure','manure',{tool:'fork',condition:Math.floor(v.manure)>0,reason:'No manure ready',output:Math.floor(v.manure)+' manure ready.'});
  }else if(v.products>0&&data.species[v.species]?.product){const chicken=v.species==='chicken';actionPanel(work,f,'Collect remaining '+nameOf(data.species[v.species].product),'collect',{tool:chicken?null:v.species==='sheep'?'shear':'milk',output:v.products+' ready'});}
  if(!n&&Math.floor(v.manure)>0)actionPanel(pgs.Production,f,'Collect remaining manure','manure',{tool:'fork',output:Math.floor(v.manure)+' ready'});
  el('p','Buy new animals at the agricultural supplier and choose this enclosure for delivery.',work);
  if(v.species==='horse'){
   for(const h of v.horses||[]){
    const box=el('section',null,work);el('p',h.breed+' · '+h.sex+' · '+Math.floor(h.age/86400)+' days · Care '+Math.round(h.care)+'% · Health '+Math.round(h.health)+'%',box);
    el('p','Speed '+h.genes.speed+' · Stamina '+h.genes.stamina+' · Health genetics '+h.genes.health+' · Training '+h.training,box);
    const adult=h.age>=data.species.horse.mature*3600,wait=Math.max(0,data.trainingInterval-(data.now-h.trainedAt));
    const train=el('section',null,pgs.Training);el('h2',h.breed+' · '+h.sex+' · '+h.id.slice(-6),train);
    actionPanel(train,f,'Train horse','trainHorse',{chest:false,condition:adult&&h.health>=60&&!h.listed&&h.training<100&&wait===0,reason:'Requires adult healthy unlisted horse, training below 100 and completed cooldown ('+wait+'s remaining)',extra:()=>({horse:h.id})});
    actionPanel(box,f,'Release riding horse','mountHorse',{chest:false,condition:adult&&!h.listed&&h.health>=30,reason:'Requires a healthy adult unlisted horse and a saddle from the stable',extra:()=>({horse:h.id})});
    const sales=el('section',null,pgs.Sales);el('h2',h.breed+' · '+h.sex+' · '+h.id.slice(-6),sales);
    const price=el('input',null,sales);price.type='number';price.min=1;price.value=h.listed||Math.round((h.genes.speed+h.genes.stamina+h.genes.health)*60*(.25+.75*h.care/100)*(.5+.5*h.health/100)*(1+h.training/200)*(adult?1:.5));
    if(h.listed)button(sales,'Unlist horse','unlistHorse',()=>({horse:h.id}));else button(sales,'List horse (price in cents)','listHorse',()=>({horse:h.id,price:Number(price.value)}));
    el('small','Certificate: '+h.id,box);
   }
  }else if(n){
   const sex=select(work,[['female','Female'],['male','Male']]);const qty=el('input',null,work);qty.type='number';qty.min=1;qty.step=1;qty.value=1;
   const a=actionPanel(work,f,'Butcher selected animals','slaughter',{tool:'knife',extra:()=>({sex:sex.value,count:Number(qty.value)}),output:'Complete the minigame, then physically slaughter the spawned animals.'});
   const update=()=>{qty.max=v[sex.value];const q=Number(qty.value);a.update(null,0,Number.isInteger(q)&&q>=1&&q<=v[sex.value],'Select 1–'+v[sex.value]+' adult '+sex.value+' animals')};qty.oninput=update;sex.onchange=update;update();
  }
 }else actionPanel(work,f,'Fill well water','fill',{tool:'bucket',output:'Deposits 10 farm water units into linked chest.'});
 const release=el('button','Release empty facility',settings);release.className='danger';release.onclick=()=>{if(confirm('Release this empty facility?'))send('release')}
}
window.addEventListener('message', e => {
    const d = e.data;

    if (d.type === 'menu') {
        data = d.data;
        if (data.selected) selected = data.selected;
        document.body.hidden = false;
        document.querySelector('main').hidden = false;
        render();
    } else if (d.type === 'close') {
        document.body.hidden = true;
        document.querySelector('main').hidden = false;
    } else if (d.type === 'notice') {
        $('notice').textContent = d.message;
    }
});
function close(){cancelAnimationFrame(workFrame);workToken=null;fetch('https://'+GetParentResourceName()+'/close',{method:'POST',body:'{}'});document.body.hidden=true}
$('close').onclick=close;document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!document.querySelector('main').hidden)close()});

function workRound(d){
 cancelAnimationFrame(workFrame);workToken=d.token;
 $('pages').hidden=true;$('tabs').hidden=true;const root=$('content');root.replaceChildren();el('h2',({harvest:'Harvesting field',plant:'Planting field',water:'Watering',feed:'Feeding animals',fertilize:'Fertilizing',collect:'Collecting products',manure:'Collecting manure',slaughter:'Preparing slaughter',trainHorse:'Training horse',clearCrop:'Clearing field'})[d.action]||'Physical work',root);el('p','Round '+d.round+' of 5 · Stop the marker in the green zone.',root);
 const bar=el('div',null,root);bar.style.cssText='height:30px;background:#554533;position:relative;margin:20px 0';
 const target=el('div',null,bar);target.style.cssText='position:absolute;height:100%;background:#73915c;left:'+((d.target-.13)*100)+'%;width:26%';
 const marker=el('div',null,bar);marker.style.cssText='position:absolute;height:100%;width:4px;background:white';
 const start=performance.now();function frame(t){marker.style.left=(((t-start)%1800)/18)+'%';workFrame=requestAnimationFrame(frame)}workFrame=requestAnimationFrame(frame);
 const hit=el('button','Stop marker',root);hit.onclick=()=>{hit.disabled=true;send('workHit',{token:workToken})};
 button(root,'Cancel work','cancelWork');root.lastChild.onclick=()=>{send('cancelWork',{reopen:true});cancelAnimationFrame(workFrame);workToken=null};
}
window.addEventListener('message',e=>{const d=e.data;if(d.type==='workRound')workRound(d.data);else if(d.type==='workEnd'){cancelAnimationFrame(workFrame);workToken=null;setTimeout(()=>{if(!document.body.hidden)send('open')},650)}});

window.addEventListener('message',e=>{
 if(e.data.type!=='shop')return;
 document.body.hidden=false;document.querySelector('main').hidden=false;$('tabs').hidden=true;$('tabs').replaceChildren();$('pages').hidden=true;const root=$('content');root.replaceChildren();
 el('h2','Agricultural supplier',root);const d=e.data.data;
 const shop=pages(root,'supplier',['Shop','Orders']),buy=shop.Shop;
 const category=id=>id.startsWith('farm_seed_')?'Seeds':/_(female|male)$/.test(id)?'Animals':/^farm_(hoe|sickle|watering_can|bucket|pitchfork|milking_kit|shears|knife)$/.test(id)?'Tools':'Supplies';
 el('label','Product category',buy);const cats=select(buy,[['All','All goods'],...['Seeds','Animals','Tools','Supplies'].map(k=>[k,k])]);
 el('label','Product',buy);const item=select(buy,[]);
 function populate(){item.replaceChildren();for(const v of d.items.filter(v=>cats.value==='All'||category(v.id)===cats.value)){const o=el('option',v.name+' · $'+(v.price/100).toFixed(2),item);o.value=v.id}purchase.disabled=!item.options.length}
 el('label','Quantity',buy);const qty=el('input',null,buy);qty.type='number';qty.min=1;qty.max=1000;qty.value=1;
 el('label','Destination facility (required for animals; optional for company goods)',buy);const facility=select(buy,[['','Personal inventory'],...(d.destinations||[]).map(f=>[f.id,f.name+' · '+f.id])]);
 const breed=select(buy,[['turkoman','Turkoman'],['standardbred','Standardbred'],['shire','Shire']]);const young=el('input',null,buy);young.type='checkbox';el('span',' Juvenile (60% price for animals)',buy);
 const purchase=el('button','Purchase',buy);purchase.onclick=()=>send('buySupply',{item:item.value,quantity:Number(qty.value),facility:facility.value.trim(),breed:breed.value,juvenile:young.checked});
 cats.onchange=populate;populate();
 for(const order of d.orders||[])el('p',order.item+' × '+order.quantity+' · '+order.phase+' (automatically retried)',shop.Orders);
 if(!(d.orders||[]).length)el('p','No pending orders.',shop.Orders);
});

window.addEventListener('message',e=>{if(e.data.type==='slaughter'){cancelAnimationFrame(workFrame);workToken=e.data.data.token;document.body.hidden=false;document.querySelector('main').hidden=true}});

window.addEventListener('message',e=>{
 if(e.data.type!=='horseMarket')return;
 document.body.hidden=false;document.querySelector('main').hidden=false;$('tabs').hidden=true;$('tabs').replaceChildren();$('pages').hidden=true;const root=$('content');root.replaceChildren();
 el('h2','Horse certificates · Trade market',root);
 const d=e.data.data;const dest=select(root,(d.destinations||[]).map(v=>[v.id,v.name+' · '+v.id]));
 if(!dest.options.length)el('p','Approach your registered empty or horse enclosure to buy.',root);
 for(const v of d.listings||[]){const h=v.horse;const box=el('section',null,root);el('p',h.breed+' · '+h.sex+' · $'+(v.price/100).toFixed(2),box);el('p','Speed '+h.genes.speed+' / Stamina '+h.genes.stamina+' / Health '+h.genes.health+' · Care '+Math.round(h.care)+'% · Training '+h.training,box);el('small',h.id,box);if(dest.options.length)button(box,'Buy certificate and horse','buyHorse',()=>({source:v.facility,dest:dest.value,horse:h.id,price:v.price}))}
});

window.addEventListener('message',e=>{
 const d=e.data,hud=$('slaughterHud'),markers=$('slaughterMarkers');
 if(d.type==='slaughterProgress'){
  document.body.hidden=false;document.querySelector('main').hidden=true;hud.hidden=false;
  $('slaughterCount').textContent=d.dead+' / '+d.total+' slaughtered';
  $('slaughterBar').max=d.total;$('slaughterBar').value=d.dead;
  $('slaughterStatus').textContent=d.finishing?'Completing slaughter…':'Butcher the marked animals';
  markers.replaceChildren();
  for(const p of d.markers){const m=el('span','▼',markers);m.style.left=(p.x*100)+'%';m.style.top=(p.y*100)+'%'}
 }else if(d.type==='slaughterHudEnd'){
  hud.hidden=true;markers.replaceChildren();document.body.hidden=true;document.querySelector('main').hidden=false;
 }
});
