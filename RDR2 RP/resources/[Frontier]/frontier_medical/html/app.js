'use strict';
const chart=document.querySelector('#chart'),labels={head:'Head',chest:'Chest',abdomen:'Abdomen',left_arm:'Left arm',right_arm:'Right arm',left_leg:'Left leg',right_leg:'Right leg'};
const regions=[...document.querySelectorAll('svg [data-region]')];
const hit=document.querySelector('#hit'),symptoms=document.querySelector('#symptoms'),vignette=document.querySelector('#injury-vignette');
let data=null,region='chest',hitTimer=null,operation=null,animation=null;
const post=(route,payload={})=>fetch('https://'+GetParentResourceName()+'/'+route,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)}).catch(()=>{});
function select(r){if(!labels[r])return;region=r;render();}
regions.forEach(n=>{
 const label=labels[n.dataset.region];
 n.setAttribute('role','button');n.setAttribute('tabindex','0');n.setAttribute('aria-label',label);
 const title=document.createElementNS('http://www.w3.org/2000/svg','title');title.textContent=label;n.append(title);
 n.addEventListener('click',()=>select(n.dataset.region));
 n.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();select(n.dataset.region);}});
});
function render(){if(!data)return;
 document.querySelector('#patient').textContent=(data.self?'Self examination':'Patient #'+data.target)+' · '+data.status+' · Pulse: '+data.pulse+' · Breathing: '+(data.breathing||'Not checked');
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
 const professional=document.querySelector('#professional');
 professional.hidden=!data.medic;
 if(data.medic){
  const values=data.vitals||{};
  document.querySelector('#vitals').textContent=[values.pulse!==undefined?'Pulse: '+values.pulse+' bpm':null,values.respiration!==undefined?'Breathing: '+values.respiration+'/min':null,values.circulation?'Circulation: '+values.circulation:null,values.temperature?'Temperature: '+values.temperature:null].filter(Boolean).join(' · ');
  document.querySelector('#findings').textContent=(data.findings?.[region]||['Perform a clinical assessment.']).join('\n');
  document.querySelector('#professional-hint').textContent=data.self&&!data.selfTest?'Professional procedures require another medic.':'Procedures consume supplies. Some require a surgical instrument kit.';
  document.querySelectorAll('[data-procedure]').forEach(b=>b.disabled=!!data.busy||data.procedures?.[region]?.[b.dataset.procedure]!==true);
 }
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
const operationPanel=document.querySelector('#operation'),needle=document.querySelector('#operation-needle'),zone=document.querySelector('#operation-zone'),press=document.querySelector('#operation-press');
function endOperation(key){
 if(key&&operation?.key!==key)return;
 if(animation!==null)cancelAnimationFrame(animation);
 animation=null;operation=null;operationPanel.hidden=true;
}
function startOperation(d){
 endOperation();operation={...d,start:performance.now(),pressed:false};
 operationPanel.hidden=false;press.disabled=false;
 operationPanel.scrollIntoView({block:'nearest'});
 document.querySelector('#operation-title').textContent=d.label;
 document.querySelector('#operation-stage').textContent='Precision stage '+d.stage+' of '+d.total;
 zone.style.left=(Math.max(0,d.center-d.window)/d.duration*100)+'%';
 zone.style.width=(Math.min(d.duration,d.center+d.window)-Math.max(0,d.center-d.window))/d.duration*100+'%';
 function frame(t){
  if(!operation||operation.pressed)return;
  const elapsed=Math.max(0,t-operation.start);
  needle.style.left=Math.min(100,elapsed/d.duration*100)+'%';
  if(elapsed<d.duration)animation=requestAnimationFrame(frame);else press.disabled=true;
 }
 animation=requestAnimationFrame(frame);
}
press.onclick=()=>{
 if(!operation||operation.pressed||press.disabled)return;
 operation.pressed=true;press.disabled=true;
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
