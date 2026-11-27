(()=>{'use strict';
const $=s=>document.getElementById(s), root=$('station-ui'), hud=$('station-hud'), old=document.querySelector('body > main');
let state,waiting=false,retry=null,frame=0,active=false,working=false;
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
function preview(){
 const r=recipe(), npc=$('st-mode').value==='npc', n=Number($('st-batches').value);
 $('st-batches').disabled=waiting||!!retry;$('st-input').disabled=npc||waiting;$('st-output').disabled=npc||waiting;
 if(!r)return;
 const counts=npc||$('st-input').value==='storage'?state.inputCounts:state.bag;
 const needs=Object.entries(r.inputs).map(([id,count])=>{const have=Number(counts?.[id]||0);return id.replaceAll('_',' ')+' '+have+' / '+count*n});
 $('st-preview').textContent=needs.join(' · ')+' | '+r.quantity*n+' × '+r.output.replaceAll('_',' ')+' | '+sec((npc?r.npc:r.manual)*n)+(npc?' | wage '+money(Math.ceil(r.npc*n*state.wage/state.wageInterval)):' | '+r.rounds*n+' QTE round'+(r.rounds*n===1?'':'s')+' ('+r.rounds+'/batch) | skill '+state.skill);
 const valid=Object.entries(r.inputs).every(([id,count])=>Number(counts?.[id]||0)>=count*n);
 $('st-start').disabled=waiting||!!retry||!valid||!Number.isInteger(n)||n<1||n>state.maxBatches||(npc&&!state.canNpc);
}
function render(){
 if(!state)return;
 const s=state.station;$('st-name').textContent=s.name;$('st-sub').textContent=s.plot+' · '+(s.ownerType==='company'?'Company':'Private')+' · profession level '+state.skill;
 const previous=$('st-recipe').value;select('st-recipe',rows(state.recipes),previous);
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
$('st-close').onclick=()=>post('stationClose');$('st-refresh').onclick=()=>request('refresh');
$('st-retry').onclick=()=>{if(retry)request(retry.action,retry.data,true)};
$('st-start').onclick=()=>{if(recipe())request('start',{recipe:recipe().id,mode:$('st-mode').value,batches:Number($('st-batches').value),input:$('st-input').value,output:$('st-output').value})};
$('st-link').onclick=()=>request('link',{input:$('st-link-input').value,output:$('st-link-output').value});
$('st-owner').onclick=()=>{request('setup',{company:$('st-company').value})};
$('st-hire').onclick=()=>request(state.station.employee?'dismiss':'hire');
$('st-release').onclick=()=>{request('release')};
for(const id of ['st-recipe','st-batches','st-mode','st-input','st-output'])$(id).addEventListener('change',preview);
$('st-batches').addEventListener('input',preview);
document.addEventListener('keydown',e=>{if((active||working)&&e.key==='Escape'){e.stopImmediatePropagation();e.preventDefault();if(active)post('stationClose')}},true);
let qte=null;
function hide(){qte=null;active=false;working=false;root.hidden=true;hud.hidden=true;old.hidden=false;document.body.hidden=true;cancelAnimationFrame(frame)}
window.addEventListener('message',({data:d})=>{
 if(d.type==='stationOpen'){
  active=true;working=false;state=d.snapshot;waiting=false;retry=null;old.hidden=true;hud.hidden=true;root.hidden=false;document.body.hidden=false;status('');render();
 }else if(d.type==='stationResult'&&active){
  waiting=false;retry=d.retry&&lastOrder?{...lastOrder,retry:true,seq:d.seq}:null;if(d.snapshot)state=d.snapshot;status(d.message);render();
 }else if(d.type==='stationNotice'&&active){status(d.message)}
 else if(d.type==='stationClose'){hide()}
 else if(d.type==='stationWork'){
  active=false;working=true;root.hidden=true;old.hidden=true;hud.hidden=false;document.body.hidden=false;
  $('st-work-label').textContent=d.label;
  const start=performance.now();cancelAnimationFrame(frame);
  qte={round:0,hits:{},results:{}};
  $('st-round-dots').replaceChildren(...Array.from({length:d.rounds},()=>{const dot=document.createElement('span');dot.className='st-dot';return dot}));
  const tick=t=>{
   if(!working||!qte)return;
   const elapsed=Math.max(0,t-start),round=Math.min(d.targets.length,Math.floor(elapsed/d.roundMs)+1);
   const relative=elapsed-(round-1)*d.roundMs, batch=Math.floor((round-1)/d.rounds)+1, localRound=(round-1)%d.rounds+1;
   if(qte.round!==round){
    qte.round=round;$('st-target').style.left=(d.targets[round-1]-d.width)*100+'%';$('st-target').style.width=d.width*200+'%';
    $('st-round').textContent='Batch '+batch+' / '+d.batches+' · Round '+localRound+' / '+d.rounds;
   }
   const hit=qte.hits[round],score=qte.results[round],expired=relative>d.sweepMs;
   $('st-marker').style.left=(hit===undefined?Math.min(1,relative/d.sweepMs):hit)*100+'%';
   $('st-instruction').textContent=score!==undefined?(score>=.75?'Excellent strike':score>0?'Strike recorded':'Missed'):(hit!==undefined?'Checking strike…':expired?'Missed · next round shortly':'Press SPACE in the green zone');
   $('st-instruction').dataset.result=score!==undefined?(score>=.75?'good':score>0?'partial':'miss'):(expired&&hit===undefined?'miss':'');
   [...$('st-round-dots').children].forEach((dot,i)=>{
    const k=(batch-1)*d.rounds+i+1,s=qte.results[k];
    dot.dataset.state=s!==undefined?(s>=.75?'good':s>0?'partial':'miss'):k<round?'miss':k===round?(expired&&hit===undefined?'miss':'active'):'pending';
   });
   $('st-progress').value=Math.min(1,elapsed/d.ms);
   if(elapsed<d.ms)frame=requestAnimationFrame(tick);else $('st-instruction').textContent='Finishing production…';
  };frame=requestAnimationFrame(tick);
 }else if(d.type==='stationStrike'&&qte){qte.hits[d.round]=d.position}
 else if(d.type==='stationStrikeResult'&&qte){qte.results[d.round]=d.score}
 else if(d.type==='stationEnd'){hide()}
});
// Refresh is explicit so it never resets partially edited ownership or storage links.
})();
