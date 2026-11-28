'use strict';
const $=s=>document.querySelector(s),chart=$('#chart'),feedback=$('#feedback'),hit=$('#hit-message'),symptoms=$('#symptoms'),flash=$('#hit-flash');
const labels={head:'Head',chest:'Chest',abdomen:'Abdomen',left_arm:'Left arm',right_arm:'Right arm',left_leg:'Left leg',right_leg:'Right leg'};
let data=null,region='chest',hitTimer=null,lastSymptoms='';
const post=(route,payload={})=>fetch('https://'+GetParentResourceName()+'/'+route,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)}).catch(()=>{});
const nodes=[...document.querySelectorAll('svg [data-region]')];
function select(r){region=r;render();}
for(const n of nodes){
 const r=n.dataset.region;n.setAttribute('tabindex','0');n.setAttribute('role','button');
 n.addEventListener('click',()=>select(r));
 n.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();select(r);}});
}
function observation(r){return data?.visible?.[r]||{injured:false,bleeding:false,types:[]};}
function render(){
 if(!data)return;
 $('#patient').textContent=(data.self?'Self examination':'Patient #'+data.target)+' · '+data.status+' · Pulse: '+data.pulse+' · Breathing: '+(data.breathing||'Not checked');
 $('#region').textContent=labels[region];
 const seen=observation(region),w=data.wounds?.[region];
 const visual=$('#visible');visual.replaceChildren();
 const text=document.createElement('div');text.textContent=seen.injured?(seen.types||[]).join(' · ')||'Visible injury':'No obvious external injury';visual.append(text);
 if(seen.bleeding){const b=document.createElement('div');b.className='bleed';b.textContent='Visible bleeding';visual.append(b);}
 const examined=$('#exam');examined.classList.toggle('pending',!w);
 examined.textContent=w?[w.severity&&'Severity: '+w.severity,w.bleeding&&'Bleeding: '+w.bleeding,w.fracture].filter(Boolean).join('\n')||'No obvious wound on examination.':'Examine for severity, bleeding extent and suspected fractures.';
 for(const n of nodes){
  const r=n.dataset.region,o=observation(r);n.classList.toggle('selected',r===region);n.classList.toggle('injured',!!o.injured);n.classList.toggle('bleeding',!!o.bleeding);
  n.setAttribute('aria-pressed',String(r===region));n.setAttribute('aria-label',labels[r]+(o.bleeding?', bleeding':o.injured?', injured':', no obvious injury'));
 }
 document.querySelectorAll('[data-action]').forEach(b=>b.disabled=!!data.busy);
 document.querySelectorAll('[data-item]').forEach(b=>{
  const item=b.dataset.item;
  b.disabled=!!data.busy||data.status==='dead'||(item==='bandage'&&!seen.bleeding)||(item==='splint'&&w?.fracture!=='Suspected fracture');
 });
 $('#progress').textContent=data.busy?'Treatment in progress — remain nearby.':'';
}
function syncFeedback(){feedback.hidden=hit.hidden&&symptoms.hidden;}
function clearHit(){if(hitTimer)clearTimeout(hitTimer);hitTimer=null;hit.hidden=true;flash.classList.remove('pulse');syncFeedback();}
function showHit(message){
 hit.textContent=message;hit.hidden=false;syncFeedback();
 flash.classList.remove('pulse');void flash.offsetWidth;flash.classList.add('pulse');
 if(hitTimer)clearTimeout(hitTimer);
 hitTimer=setTimeout(clearHit,3500);
}
function showSymptoms(s){
 const messages=Array.isArray(s?.messages)?s.messages:[],level=s?.level||'none';
 const key=JSON.stringify([level,messages]);
 if(key===lastSymptoms)return;
 lastSymptoms=key;symptoms.replaceChildren();
 symptoms.hidden=level==='none'||!messages.length;
 symptoms.classList.toggle('critical',level==='critical');
 for(const msg of messages){const p=document.createElement('p');p.textContent=msg;symptoms.append(p);}
 if(level==='none')clearHit();
 syncFeedback();
}
$('#close').onclick=()=>post('close');
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!chart.hidden)post('close');});
document.querySelectorAll('[data-action]').forEach(b=>b.onclick=()=>post('action',{action:b.dataset.action,region}));
document.querySelectorAll('[data-item]').forEach(b=>b.onclick=()=>post('action',{action:'treat',region,item:b.dataset.item}));
window.addEventListener('message',({data:m})=>{
 if(m?.type==='close'){chart.hidden=true;data=null;return;}
 if(m?.type==='view'){
  if(!data||data.ticket!==m.data.ticket){
   region=Object.keys(labels).find(r=>m.data.visible?.[r]?.bleeding)||Object.keys(labels).find(r=>m.data.visible?.[r]?.injured)||'chest';$('#notice').textContent='';
  }
  data=m.data;chart.hidden=false;render();
 }
 if(m?.type==='notice')$('#notice').textContent=m.message;
 if(m?.type==='symptoms')showSymptoms(m.data);
 if(m?.type==='injuryFeedback'&&typeof m.message==='string')showHit(m.message);
});
