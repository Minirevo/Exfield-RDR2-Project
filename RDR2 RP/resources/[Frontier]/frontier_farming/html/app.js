'use strict';
const $=id=>document.getElementById(id);
let data=null,selected=null,workToken=null,workFrame=0;
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

function render(){
 const list=data.facilities||[];const tabs=$('tabs'),root=$('content');tabs.replaceChildren();root.replaceChildren();
 if(!list.some(v=>v.building.id===selected))selected=list[0]?.building.id;
 for(const f of list){const b=el('button',f.building.size+' '+f.building.kind,tabs);b.onclick=()=>{selected=f.building.id;render()};if(f.building.id===selected)b.style.borderColor='#ddd0a0'}
 const f=list.find(v=>v.building.id===selected);if(!f){el('p','No authorized completed farm facilities nearby.',root);return}
 const b=f.building;el('h2',b.size+' '+b.kind,root);
 if(f.unbound){button(root,'Register personally','bind');el('label','Or company ID with farm grant',root);const i=el('input',null,root);button(root,'Register company','bind',()=>({company:i.value.trim()}));return}
 el('small',f.ownerType+' · '+f.owner,root);el('p','Facility ID: '+b.id,root);
 const storage=el('section',null,root);el('h2','Linked storage',storage);const s=select(storage,(f.stocks||[]).map(v=>[v.id,v.name]));s.value=f.storage||'';button(storage,'Link chest','link',()=>({storage:s.value}));if(f.storage)button(storage,'Unlink chest','unlink');el('p',(f.stocks||[]).find(x=>x.id===f.storage)?.name||f.storage||'No chest linked',storage);el('small','Tools go in personal inventory. Supplies and harvested goods use this chest.',storage);
 if(f.pending){el('p','Pending transaction recovery. Actions disabled.',root);return}
 const v=f.state,work=el('section',null,root);el('h2','Work',work);

 if(b.kind==='field'){
  el('p',v.crop?'Crop: '+v.crop+' · Soil: '+v.soil+'%':'Empty field · Soil: '+v.soil+'%',work);
  const units=data.capacity[b.size];
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
    supplyPanel(work,f,b,v,'water');
    actionPanel(work,f,'Fertilize','fertilize',{tool:'fork',item:'farm_fertilizer',required:Math.ceil(units/25),condition:!v.fertilized,reason:'Already fertilized',output:'25% faster growth and higher yield.'});
   }else{
    const base=v.harvestRemaining??Math.floor(units*(v.fertilized?2.5:2)*v.soil/100);
    const best=v.harvestRemaining??Math.floor(units*(v.fertilized?2.5:2)*v.soil/100*1.25);
    const seeds=v.seedRemaining??units+Math.floor(units/10);
    actionPanel(work,f,'Harvest entire remaining crop','harvest',{tool:'sickle',output:'One minigame. Deposits '+base+(best!==base?'–'+best:'')+' '+v.crop+' and '+seeds+' seeds directly into the linked chest. Chest must fit the full harvest.'});
   }
  }
  actionPanel(work,f,'Make fertilizer','fertilizer',{item:'farm_manure',required:5,output:'Converts 5 manure into 1 fertilizer.'});
 }else if(b.kind==='livestock'||b.kind==='chicken'){
  const n=v.female+v.male+v.young;
  el('p',(v.species||'Empty')+' · Female '+v.female+' · Male '+v.male+' · Young '+v.young,work);
  el('p','Health '+Math.round(v.health)+'% · Products ready '+v.products+' · Manure ready '+Math.floor(v.manure),work);
  if(n){
   el('p','Food remaining '+(v.feed/n/3600).toFixed(1)+'h · Water remaining '+(v.water/n/3600).toFixed(1)+'h',work);
   let food;
   if(v.species==='pig')food=select(work,['corn','carrot','potato','wheat','broccoli','artichoke'].map(k=>['farm_'+k,k]));
   supplyPanel(work,f,b,v,'feed',food);supplyPanel(work,f,b,v,'water');
   const product=data.species[v.species]?.product;
   if(product){const chicken=v.species==='chicken';actionPanel(work,f,chicken?'Collect eggs':v.species==='sheep'?'Shear wool':'Collect milk','collect',{tool:chicken?null:v.species==='sheep'?'shear':'milk',condition:v.products>0,reason:'No products ready',output:v.products+' '+nameOf(product)+' ready'+(chicken?' · no minigame.':' · work bonus may increase yield.')});}
   actionPanel(work,f,'Collect manure','manure',{tool:'fork',condition:Math.floor(v.manure)>0,reason:'No manure ready',output:Math.floor(v.manure)+' manure ready.'});
  }else if(v.products>0&&data.species[v.species]?.product){const chicken=v.species==='chicken';actionPanel(work,f,'Collect remaining '+nameOf(data.species[v.species].product),'collect',{tool:chicken?null:v.species==='sheep'?'shear':'milk',output:v.products+' ready'});}
  if(!n&&Math.floor(v.manure)>0)actionPanel(work,f,'Collect remaining manure','manure',{tool:'fork',output:Math.floor(v.manure)+' ready'});
  el('p','Buy new animals at the agricultural supplier and choose this enclosure for delivery.',work);
  if(v.species==='horse'){
   for(const h of v.horses||[]){
    const box=el('section',null,work);el('p',h.breed+' · '+h.sex+' · '+Math.floor(h.age/86400)+' days · Care '+Math.round(h.care)+'% · Health '+Math.round(h.health)+'%',box);
    el('p','Speed '+h.genes.speed+' · Stamina '+h.genes.stamina+' · Health genetics '+h.genes.health+' · Training '+h.training,box);
    const adult=h.age>=data.species.horse.mature*3600,wait=Math.max(0,data.trainingInterval-(data.now-h.trainedAt));
    actionPanel(box,f,'Train horse','trainHorse',{chest:false,condition:adult&&h.health>=60&&!h.listed&&h.training<100&&wait===0,reason:'Requires adult healthy unlisted horse, training below 100 and completed cooldown ('+wait+'s remaining)',extra:()=>({horse:h.id})});
    actionPanel(box,f,'Ride horse','mountHorse',{chest:false,condition:adult&&!h.listed&&h.health>=30,reason:'Requires a healthy adult unlisted horse',extra:()=>({horse:h.id})});
    const price=el('input',null,box);price.type='number';price.min=1;price.value=h.listed||Math.round((h.genes.speed+h.genes.stamina+h.genes.health)*60*(.25+.75*h.care/100)*(.5+.5*h.health/100)*(1+h.training/200)*(adult?1:.5));
    if(h.listed)button(box,'Unlist horse','unlistHorse',()=>({horse:h.id}));else button(box,'List horse (price in cents)','listHorse',()=>({horse:h.id,price:Number(price.value)}));
    el('small','Certificate: '+h.id,box);
   }
  }else if(n){
   const sex=select(work,[['female','Female'],['male','Male']]);const qty=el('input',null,work);qty.type='number';qty.min=1;qty.step=1;qty.value=1;
   const a=actionPanel(work,f,'Butcher selected animals','slaughter',{tool:'knife',extra:()=>({sex:sex.value,count:Number(qty.value)}),output:'Complete the minigame, then physically slaughter the spawned animals.'});
   const update=()=>{qty.max=v[sex.value];const q=Number(qty.value);a.update(null,0,Number.isInteger(q)&&q>=1&&q<=v[sex.value],'Select 1–'+v[sex.value]+' adult '+sex.value+' animals')};qty.oninput=update;sex.onchange=update;update();
  }
 }else actionPanel(work,f,'Fill well water','fill',{tool:'bucket',output:'Deposits 10 farm water units into linked chest.'});
 button(root,'Refresh','open');const release=el('button','Release empty facility',root);release.onclick=()=>{if(confirm('Release this empty facility?'))send('release')}
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
 const root=$('content');root.replaceChildren();el('h2',({harvest:'Harvesting field',plant:'Planting field',water:'Watering',feed:'Feeding animals',fertilize:'Fertilizing',collect:'Collecting products',manure:'Collecting manure',slaughter:'Preparing slaughter',trainHorse:'Training horse',clearCrop:'Clearing field'})[d.action]||'Physical work',root);el('p','Round '+d.round+' of 5 · Stop the marker in the green zone.',root);
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
 document.body.hidden=false;$('tabs').replaceChildren();const root=$('content');root.replaceChildren();
 el('h2','Agricultural supplier',root);const d=e.data.data;
 const item=select(root,d.items.map(v=>[v.id,v.name+' · $'+(v.price/100).toFixed(2)]));
 const qty=el('input',null,root);qty.type='number';qty.min=1;qty.max=1000;qty.value=1;
 el('label','Destination facility (required for animals; optional for company goods)',root);const facility=select(root,[['','Personal inventory'],...(d.destinations||[]).map(f=>[f.id,f.name+' · '+f.id])]);const breed=select(root,[['turkoman','Turkoman'],['standardbred','Standardbred'],['shire','Shire']]);const young=el('input',null,root);young.type='checkbox';el('span',' Juvenile (60% price for animals)',root);
 button(root,'Purchase','buySupply',()=>({item:item.value,quantity:Number(qty.value),facility:facility.value.trim(),breed:breed.value,juvenile:young.checked}));
 for(const j of d.orders||[])el('p',j.item+' × '+j.quantity+' · '+j.phase+' (automatically retried)',root);
});

window.addEventListener('message',e=>{if(e.data.type==='slaughter'){cancelAnimationFrame(workFrame);workToken=e.data.data.token;document.body.hidden=false;document.querySelector('main').hidden=true}});

window.addEventListener('message',e=>{
 if(e.data.type!=='horseMarket')return;
 document.body.hidden=false;$('tabs').replaceChildren();const root=$('content');root.replaceChildren();
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
