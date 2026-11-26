'use strict';
const $=id=>document.getElementById(id);
let data=null,selected=null,workToken=null,workFrame=0;
function send(action,extra={}){fetch('https://'+GetParentResourceName()+'/farmAction',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action,data:{id:selected,...extra}})}).catch(()=>{$('notice').textContent='Request failed'})}
function el(tag,text,parent){const n=document.createElement(tag);if(text!=null)n.textContent=text;if(parent)parent.append(n);return n}
function button(parent,text,action,extra){const b=el('button',text,parent);b.onclick=()=>send(action,typeof extra==='function'?extra():extra)}
function select(parent,options){const s=el('select',null,parent);for(const [k,v] of options){const o=el('option',v,s);o.value=k}return s}
function render(){
 const list=data.facilities||[];const tabs=$('tabs'),root=$('content');tabs.replaceChildren();root.replaceChildren();
 if(!list.some(v=>v.building.id===selected))selected=list[0]?.building.id;
 for(const f of list){const b=el('button',f.building.size+' '+f.building.kind,tabs);b.onclick=()=>{selected=f.building.id;render()};if(f.building.id===selected)b.style.borderColor='#ddd0a0'}
 const f=list.find(v=>v.building.id===selected);if(!f){el('p','No authorized completed farm facilities nearby.',root);return}
 const b=f.building;el('h2',b.size+' '+b.kind,root);
 if(f.unbound){button(root,'Register personally','bind');el('label','Or company ID with farm grant',root);const i=el('input',null,root);button(root,'Register company','bind',()=>({company:i.value.trim()}));return}
 el('small',f.ownerType+' · '+f.owner,root);el('p','Facility ID: '+b.id,root);
 const storage=el('section',null,root);el('h2','Linked storage',storage);const s=select(storage,(f.stocks||[]).map(v=>[v.id,v.name]));s.value=f.storage||'';button(storage,'Link chest','link',()=>({storage:s.value}));if(f.storage)button(storage,'Unlink chest','unlink');el('p',f.storage||'No chest linked',storage);
 if(f.pending){el('p','Pending transaction recovery. Actions disabled.',root);return}
 const v=f.state,work=el('section',null,root);el('h2','Work',work);
 if(b.kind==='field'){
  el('p',v.crop?'Crop: '+v.crop+' · Soil: '+v.soil+'%':'Empty field · Soil: '+v.soil+'%',work);
  if(!v.crop){const c=select(work,Object.keys(data.crops).map(k=>[k,k]));button(work,'Plant','plant',()=>({crop:c.value}))}
  else if(v.dead)button(work,'Clear dead crops','clearCrop');
  else{const p=el('progress',null,work);p.max=1;p.value=v.growth;el('p',Math.floor(v.growth*100)+'% · Water reserve '+Math.floor(v.water/3600)+'h',work);button(work,'Water','water');button(work,'Fertilize','fertilize');if(v.growth>=1)button(work,v.harvestRemaining?'Harvest next batch ('+v.harvestRemaining+' remaining)':'Harvest','harvest')}
  button(work,'Convert 5 manure to fertilizer','fertilizer');
 }else if(b.kind==='livestock'||b.kind==='chicken'){
  el('p',(v.species||'Empty')+' · Female '+v.female+' · Male '+v.male+' · Young '+v.young,work);el('p','Health '+Math.round(v.health)+'% · Products '+v.products+' · Manure '+Math.floor(v.manure),work);
  el('p','Food reserve '+Math.floor(v.feed/3600)+' animal-hours · Water '+Math.floor(v.water/3600)+' animal-hours',work);
  const c=select(work,Object.keys(data.species).filter(k=>(b.kind==='chicken'?k==='chicken':k!=='chicken')).map(k=>[k,k]));const breed=select(work,[['turkoman','Turkoman'],['standardbred','Standardbred'],['shire','Shire']]);button(work,'Redeem female voucher','animal',()=>({species:c.value,sex:'female',breed:breed.value}));button(work,'Redeem male voucher','animal',()=>({species:c.value,sex:'male',breed:breed.value}));
  if(v.species==='horse'){for(const h of v.horses||[]){const box=el('section',null,work);el('p',h.breed+' · '+h.sex+' · '+Math.floor(h.age/86400)+' days · Care '+Math.round(h.care)+'% · Health '+Math.round(h.health)+'%',box);el('p','Speed '+h.genes.speed+' · Stamina '+h.genes.stamina+' · Health genetics '+h.genes.health+' · Training '+h.training,box);button(box,'Train horse','trainHorse',()=>({horse:h.id}));button(box,'Ride horse','mountHorse',()=>({horse:h.id}));const price=el('input',null,box);price.type='number';price.min=1;price.value=h.listed||Math.round((h.genes.speed+h.genes.stamina+h.genes.health)*60*(.25+.75*h.care/100)*(.5+.5*h.health/100)*(1+h.training/200)*(h.age>=345600?1:.5));if(h.listed)button(box,'Unlist horse','unlistHorse',()=>({horse:h.id}));else button(box,'List horse (price in cents)','listHorse',()=>({horse:h.id,price:Number(price.value)}));el('small','Certificate: '+h.id,box)}}if(v.species==='pig'){const food=select(work,['corn','carrot','potato','wheat','broccoli','artichoke'].map(k=>['farm_'+k,k]));button(work,'Feed','feed',()=>({food:food.value}))}else button(work,'Feed','feed');button(work,'Water','water');if(v.species!=='chicken')button(work,'Collect products','collect');button(work,'Collect manure','manure');const sex=select(work,[['female','Female'],['male','Male']]);const qty=el('input',null,work);qty.type='number';qty.min=1;qty.value=1;button(work,'Butcher selected animals','slaughter',()=>({sex:sex.value,count:Number(qty.value)}));
 }else button(work,'Fill 10 water units into linked stock','fill');
 button(root,'Refresh','open');const release=el('button','Release empty facility',root);release.onclick=()=>{if(confirm('Release this empty facility?'))send('release')}
}
window.addEventListener('message',e=>{const d=e.data;if(d.type==='menu'){data=d.data;document.body.hidden=false;render()}else if(d.type==='close')document.body.hidden=true;else if(d.type==='notice')$('notice').textContent=d.message});
function close(){cancelAnimationFrame(workFrame);workToken=null;fetch('https://'+GetParentResourceName()+'/close',{method:'POST',body:'{}'});document.body.hidden=true}
$('close').onclick=close;document.addEventListener('keydown',e=>{if(e.key==='Escape')close()});

function workRound(d){
 cancelAnimationFrame(workFrame);workToken=d.token;
 const root=$('content');root.replaceChildren();el('h2','Physical work · '+d.round+'/5',root);
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

window.addEventListener('message',e=>{if(e.data.type==='slaughter'){cancelAnimationFrame(workFrame);workToken=e.data.data.token;document.body.hidden=true}});

window.addEventListener('message',e=>{
 if(e.data.type!=='horseMarket')return;
 document.body.hidden=false;$('tabs').replaceChildren();const root=$('content');root.replaceChildren();
 el('h2','Horse certificates · Trade market',root);
 const d=e.data.data;const dest=select(root,(d.destinations||[]).map(v=>[v.id,v.name+' · '+v.id]));
 if(!dest.options.length)el('p','Approach your registered empty or horse enclosure to buy.',root);
 for(const v of d.listings||[]){const h=v.horse;const box=el('section',null,root);el('p',h.breed+' · '+h.sex+' · $'+(v.price/100).toFixed(2),box);el('p','Speed '+h.genes.speed+' / Stamina '+h.genes.stamina+' / Health '+h.genes.health+' · Care '+Math.round(h.care)+'% · Training '+h.training,box);el('small',h.id,box);if(dest.options.length)button(box,'Buy certificate and horse','buyHorse',()=>({source:v.facility,dest:dest.value,horse:h.id,price:v.price}))}
});
