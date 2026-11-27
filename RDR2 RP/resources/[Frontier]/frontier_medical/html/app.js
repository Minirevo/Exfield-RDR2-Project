'use strict';
const chart=document.querySelector('#chart'),labels={head:'Head',chest:'Chest',abdomen:'Abdomen',left_arm:'Left arm',right_arm:'Right arm',left_leg:'Left leg',right_leg:'Right leg'};
let data=null,region='chest';
const post=(route,payload={})=>fetch('https://'+GetParentResourceName()+'/'+route,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)}).catch(()=>{});
function select(r){region=r;render();}
for(const [r,label] of Object.entries(labels)){const b=document.createElement('button');b.textContent=label;b.dataset.region=r;b.onclick=()=>select(r);document.querySelector('#regions').append(b);}
document.querySelectorAll('svg [data-region]').forEach(n=>n.addEventListener('click',()=>select(n.dataset.region)));
function render(){if(!data)return;
 document.querySelector('#patient').textContent=(data.self?'Self examination':'Patient #'+data.target)+' · '+data.status+' · Pulse: '+data.pulse+' · Breathing: '+(data.breathing||'Not checked');
 document.querySelector('#region').textContent=labels[region];
 const w=data.wounds?.[region];
 document.querySelector('#details').textContent=w?[w.kind,w.severity,w.bleeding&&'Bleeding: '+w.bleeding,w.fracture].filter(Boolean).join('\n'):'Not examined.';
 document.querySelectorAll('[data-region]').forEach(n=>n.classList.toggle('selected',n.dataset.region===region));
 document.querySelectorAll('[data-action],[data-item]').forEach(b=>b.disabled=!!data.busy||!!b.dataset.item&&!w);
 document.querySelector('#progress').textContent=data.busy?'Treatment in progress — remain nearby.':'';
}
document.querySelector('#close').onclick=()=>post('close');
document.addEventListener('keydown',e=>{if(e.key==='Escape')post('close');});
document.querySelectorAll('[data-action]').forEach(b=>b.onclick=()=>post('action',{action:b.dataset.action,region}));
document.querySelectorAll('[data-item]').forEach(b=>b.onclick=()=>post('action',{action:'treat',region,item:b.dataset.item}));
window.addEventListener('message',({data:m})=>{if(m?.type==='close'){chart.hidden=true;data=null;return}if(m?.type==='view'){data=m.data;chart.hidden=false;render()}if(m?.type==='notice')document.querySelector('#notice').textContent=m.message;});
