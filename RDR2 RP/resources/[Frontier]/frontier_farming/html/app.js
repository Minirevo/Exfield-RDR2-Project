'use strict';
const $=id=>document.getElementById(id);
let data=null,selected=null;
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
 el('small',f.ownerType+' · '+f.owner,root);
 const storage=el('section',null,root);el('h2','Linked storage',storage);const s=select(storage,(f.stocks||[]).map(v=>[v.id,v.name]));s.value=f.storage||'';button(storage,'Link chest','link',()=>({storage:s.value}));el('p',f.storage||'No chest linked',storage);
 if(f.pending){el('p','Pending transaction recovery. Actions disabled.',root);return}
 const v=f.state,work=el('section',null,root);el('h2','Work',work);
 if(b.kind==='field'){
  el('p',v.crop?'Crop: '+v.crop+' · Soil: '+v.soil+'%':'Empty field · Soil: '+v.soil+'%',work);
  if(!v.crop){const c=select(work,Object.keys(data.crops).map(k=>[k,k]));button(work,'Plant','plant',()=>({crop:c.value}))}
  else if(v.dead)button(work,'Clear dead crops','clearCrop');
  else{const p=el('progress',null,work);p.max=1;p.value=v.growth;el('p',Math.floor(v.growth*100)+'% · Water reserve '+Math.floor(v.water/3600)+'h',work);button(work,'Water','water');button(work,'Fertilize','fertilize');if(v.growth>=1)button(work,'Harvest','harvest')}
  button(work,'Convert 5 manure to fertilizer','fertilizer');
 }else if(b.kind==='livestock'||b.kind==='chicken'){
  el('p',(v.species||'Empty')+' · Female '+v.female+' · Male '+v.male+' · Young '+v.young,work);el('p','Health '+Math.round(v.health)+'% · Products '+v.products+' · Manure '+Math.floor(v.manure),work);
  el('p','Food reserve '+Math.floor(v.feed/3600)+' animal-hours · Water '+Math.floor(v.water/3600)+' animal-hours',work);
  const c=select(work,Object.keys(data.species).filter(k=>k!=='horse'&&(b.kind==='chicken'?k==='chicken':k!=='chicken')).map(k=>[k,k]));button(work,'Redeem female voucher','animal',()=>({species:c.value,sex:'female'}));button(work,'Redeem male voucher','animal',()=>({species:c.value,sex:'male'}));
  button(work,'Feed','feed');button(work,'Water','water');if(v.species!=='chicken')button(work,'Collect products','collect');button(work,'Collect manure','manure');
 }else el('p','Well construction available; filling interaction is not enabled in this build.',work);
 button(root,'Refresh','open');const release=el('button','Release empty facility',root);release.onclick=()=>{if(confirm('Release this empty facility?'))send('release')}
}
window.addEventListener('message',e=>{const d=e.data;if(d.type==='menu'){data=d.data;document.body.hidden=false;render()}else if(d.type==='close')document.body.hidden=true;else if(d.type==='notice')$('notice').textContent=d.message});
function close(){fetch('https://'+GetParentResourceName()+'/close',{method:'POST',body:'{}'});document.body.hidden=true}
$('close').onclick=close;document.addEventListener('keydown',e=>{if(e.key==='Escape')close()});
