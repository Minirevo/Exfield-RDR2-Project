'use strict';
const root=document.querySelector('#status'),wallet=document.querySelector('#wallet');
const fields=[['health','Health','#b45849'],['endurance','Stamina','#c7ad67'],['hunger','Food','#aa8150'],['thirst','Drink','#6e9caa'],['energy','Energy','#8ea178'],['deadeye','Dead eye','#a78d9d']];
const nodes={};
for(const [key,label,color] of fields){const stat=document.createElement('div'),ring=document.createElement('div'),value=document.createElement('span'),name=document.createElement('small');stat.className='stat';ring.className='ring';ring.style.setProperty('--color',color);value.textContent='—';name.textContent=label;ring.append(value);stat.append(ring,name);root.append(stat);nodes[key]={stat,ring,value};}
const money=v=>typeof v==='number'||typeof v==='string'&&v.trim()!==''?new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'}).format(Number(v)/100):'—';
window.addEventListener('message',({data:d})=>{if(d?.type==='hide'){root.hidden=wallet.hidden=true;return}if(d?.type!=='status')return;root.hidden=wallet.hidden=false;document.querySelector('#cash').textContent=money(d.cash);document.querySelector('#bank').textContent='Bank '+money(d.bank);
 for(const [key] of fields){const n=nodes[key],v=typeof d[key]==='number'?Math.max(0,Math.min(100,d[key])):null;n.stat.classList.toggle('unknown',v===null);n.value.classList.toggle('low',v!==null&&v<=20);n.value.textContent=v===null?'—':String(v);n.ring.style.setProperty('--amount',(v??0)*3.6+'deg');}
});
async function ready(){try{const r=await fetch('https://'+GetParentResourceName()+'/ready',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});if(!r.ok)throw Error('ready');await r.json();}catch{setTimeout(ready,500);}}ready();
