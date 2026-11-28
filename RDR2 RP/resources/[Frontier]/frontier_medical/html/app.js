'use strict';
const chart=document.querySelector('#chart'),labels={head:'Head',chest:'Chest',abdomen:'Abdomen',left_arm:'Left arm',right_arm:'Right arm',left_leg:'Left leg',right_leg:'Right leg'};
const regions=[...document.querySelectorAll('svg [data-region]')];
const hit=document.querySelector('#hit'),symptoms=document.querySelector('#symptoms'),vignette=document.querySelector('#injury-vignette');
let data=null,region='chest',tab='assessment',hitTimer=null,operation=null,animation=null;
const post=(route,payload={})=>fetch('https://'+GetParentResourceName()+'/'+route,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)}).catch(()=>{});
function select(r){if(!labels[r]||operation||data?.busy)return;region=r;render();}
const tabs=[...document.querySelectorAll('[data-tab]')],panels=[...document.querySelectorAll('[data-panel]')];
function renderTabs(){
 if(tab==='procedures'&&!data?.medic)tab='assessment';
 tabs.forEach(b=>{b.hidden=b.dataset.tab==='procedures'&&!data?.medic;b.setAttribute('aria-pressed',String(b.dataset.tab===tab));b.disabled=!!operation;});
 panels.forEach(p=>p.hidden=p.dataset.panel!==tab);
 document.querySelectorAll('[data-medic-only]').forEach(n=>n.hidden=!data?.medic);
}
tabs.forEach(b=>b.onclick=()=>{if(operation||b.hidden)return;tab=b.dataset.tab;renderTabs();});
regions.forEach(n=>{
 const label=labels[n.dataset.region];
 n.setAttribute('role','button');n.setAttribute('tabindex','0');n.setAttribute('aria-label',label);
 const title=document.createElementNS('http://www.w3.org/2000/svg','title');title.textContent=label;n.append(title);
 n.addEventListener('click',()=>select(n.dataset.region));
 n.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();select(n.dataset.region);}});
});
function render(){if(!data)return;
 document.querySelector('#patient').textContent=(data.self?'Self examination':'Patient #'+data.target)+' · '+data.status;
 document.querySelector('#region').textContent=labels[region];
 const visible=data.visible?.[region],w=data.wounds?.[region];
 document.querySelector('#visible-detail').textContent=visible?[visible.description,visible.bleeding?'Visible bleeding':null].filter(Boolean).join(' · '):'No observation available';
 document.querySelector('#visible-detail').className=visible?.bleeding?'active-bleeding':'';
 document.querySelector('#details').textContent=w?[w.severity&&'Severity: '+w.severity,w.bleeding&&'Bleeding: '+w.bleeding,w.fracture].filter(Boolean).join('\n')||'No obvious wound on examination.':'Not examined closely. Assess severity or check for fractures.';
 regions.forEach(n=>{
  const r=n.dataset.region,v=data.visible?.[r],selected=r===region;
  n.classList.toggle('selected',selected);n.classList.toggle('bleeding',!!v?.bleeding);n.classList.toggle('wounded',!!v?.wounded&&!v?.bleeding);
  const label=labels[r]+(v?' — '+v.description+(v.bleeding?', bleeding':''):'');
  n.setAttribute('aria-label',label);n.setAttribute('aria-pressed',String(selected));n.querySelector('title').textContent=label;
 });
 document.querySelectorAll('[data-action]').forEach(b=>b.disabled=!!data.busy);
 document.querySelectorAll('[data-item]').forEach(b=>{
  const item=b.dataset.item;
  b.disabled=!!data.busy||data.actions?.[region]?.[item]!==true;
  b.title=b.disabled&&!data.busy?(item==='splint'&&!w?'Examine closely first.':item==='tonic'&&!data.self&&!w?'Examine closely first.':'No eligible injury for this treatment.'):'';
 });
 const mode=document.querySelector('#access-mode');
 mode.textContent=data.medic?(data.selfTest?'PROFESSIONAL MEDIC · SELF-TEST ENABLED':'PROFESSIONAL MEDIC'):'BASIC FIRST AID';
 mode.classList.toggle('licensed',data.medic===true);
 document.querySelector('#basic-pulse').textContent=data.pulse||'Not checked';
 document.querySelector('#basic-breathing').textContent=data.breathing||'Not checked';
 if(data.medic){
  const values=data.vitals||{};
  document.querySelector('#vital-bpm').textContent=values.pulse!==undefined?values.pulse+' bpm':'Not checked';
  document.querySelector('#vital-respiration').textContent=values.respiration!==undefined?values.respiration+' / min':'Not checked';
  document.querySelector('#vital-circulation').textContent=values.circulation||'Not checked';
  document.querySelector('#vital-temperature').textContent=values.temperature||'Not checked';
  document.querySelector('#findings').textContent=(data.findings?.[region]||['Perform a clinical assessment.']).join('\n');
  document.querySelector('#professional-hint').textContent=data.self&&!data.selfTest?'Professional procedures require another medic.':'Procedures consume supplies. Some require a surgical instrument kit.';
  const assessed=!!data.findings?.[region];
  document.querySelector('#procedure-help').textContent=!assessed?'Perform a clinical assessment of this region in Assessment first.':Object.values(data.procedures?.[region]||{}).some(Boolean)?'Select an eligible procedure.':'No eligible professional procedure for this region.';
  document.querySelectorAll('[data-procedure]').forEach(b=>b.disabled=!!data.busy||!!operation||data.procedures?.[region]?.[b.dataset.procedure]!==true);
 }
 renderTabs();
 document.querySelector('#progress').textContent=data.busy?'Treatment in progress — remain nearby.':'';
}
function clearHit(){clearTimeout(hitTimer);hitTimer=null;hit.hidden=true;vignette.classList.remove('hit');}
function showHit(message){
 clearHit();hit.textContent=message;hit.hidden=false;vignette.classList.add('hit');
 hitTimer=setTimeout(clearHit,2600);
}
function showSymptoms(values){
 symptoms.replaceChildren();
 let severe=false;
 for(const symptom of (Array.isArray(values)?values:[])){
  if(!symptom||typeof symptom.text!=='string')continue;
  const n=document.createElement('div');n.className=symptom.level==='severe'?'severe':'warning';n.textContent=symptom.text;symptoms.append(n);
  if(symptom.level==='severe'&&['weakness','breathing','bleeding'].includes(symptom.kind))severe=true;
 }
 symptoms.hidden=!symptoms.children.length;
 vignette.classList.toggle('distress',severe);
}
const operationPanel=document.querySelector('#operation'),needle=document.querySelector('#operation-needle'),orange=document.querySelector('#operation-acceptable'),green=document.querySelector('#operation-perfect'),press=document.querySelector('#operation-press');
function endOperation(key){
 if(key&&operation?.key!==key)return;
 if(animation!==null)cancelAnimationFrame(animation);
 animation=null;operation=null;operationPanel.hidden=true;renderTabs();
}
function startOperation(d){
 endOperation();operation={...d,start:performance.now(),pressed:false,ready:false};
 tab='procedures';renderTabs();
 operationPanel.hidden=false;press.disabled=true;needle.style.left='0%';
 operationPanel.scrollIntoView({block:'nearest'});
 document.querySelector('#operation-title').textContent=d.label;
 document.querySelector('#operation-stage').textContent='Precision stage '+d.stage+' of '+d.total;
 const feedback=document.querySelector('#operation-feedback');
 feedback.textContent=d.previous==='perfect'?'Previous stage: Perfect':d.previous==='acceptable'?'Previous stage: Acceptable':'Prepare for the moving indicator.';
 feedback.className=d.previous||'';
 function setZone(el,width){
  el.style.left=((d.center-width)/d.duration*100)+'%';
  el.style.width=(2*width/d.duration*100)+'%';
 }
 setZone(orange,d.acceptable);setZone(green,d.perfect);
 press.textContent='Get ready…';
 const current=operation;
 function frame(t){
  if(operation!==current||current.pressed)return;
  const elapsed=t-current.start-d.lead;
  if(elapsed<0){animation=requestAnimationFrame(frame);return;}
  current.ready=true;press.disabled=false;press.textContent='Perform action (Space)';
  needle.style.left=Math.min(100,elapsed/d.duration*100)+'%';
  if(elapsed<d.duration)animation=requestAnimationFrame(frame);
  else {press.disabled=true;press.textContent='Time expired';}
 }
 animation=requestAnimationFrame(frame);
}
press.onclick=()=>{
 if(!operation||!operation.ready||operation.pressed||press.disabled)return;
 operation.pressed=true;press.disabled=true;press.textContent='Checking precision…';
 post('operationPress',{key:operation.key,stage:operation.stage});
};
document.querySelectorAll('[data-procedure]').forEach(b=>b.onclick=()=>post('action',{action:'procedure',region,item:b.dataset.procedure}));
document.querySelector('#close').onclick=()=>post('close');
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!chart.hidden)post('close');else if(e.key===' '&&operation&&!e.repeat){e.preventDefault();press.click();}});
document.querySelectorAll('[data-action]').forEach(b=>b.onclick=()=>post('action',{action:b.dataset.action,region}));
document.querySelectorAll('[data-item]').forEach(b=>b.onclick=()=>post('action',{action:'treat',region,item:b.dataset.item}));
window.addEventListener('message',({data:m})=>{
 if(m?.type==='close'){endOperation();chart.hidden=true;data=null;return}
 if(m?.type==='view'){
  if(!data||data.ticket!==m.data.ticket){
   tab='assessment';
   region=Object.keys(labels).find(r=>m.data.visible?.[r]?.bleeding)||Object.keys(labels).find(r=>m.data.visible?.[r]?.wounded)||'chest';
   document.querySelector('#notice').textContent='';
  }
  data=m.data;chart.hidden=false;render();
 }
 if(m?.type==='operationStage'&&data)startOperation(m.data);
 if(m?.type==='operationEnd')endOperation(m.key);
 if(m?.type==='notice')document.querySelector('#notice').textContent=m.message;
 if(m?.type==='symptoms')showSymptoms(m.symptoms);
 if(m?.type==='injuryFeedback'&&typeof m.message==='string')showHit(m.message);
 if(m?.type==='clearFeedback'){clearHit();showSymptoms([]);}
});
