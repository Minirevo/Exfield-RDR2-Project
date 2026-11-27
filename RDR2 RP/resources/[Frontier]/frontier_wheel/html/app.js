'use strict';
const root=document.querySelector('#wheel'), ring=document.querySelector('#ring');
const nameEl=document.querySelector('#name'), detail=document.querySelector('#detail'), title=document.querySelector('.center small');
const docs=document.querySelector('#docs'), recipient=document.querySelector('#recipient'), list=document.querySelector('#docList');
let slots=[],selected=0,page='main',loading=false;
const ns='http://www.w3.org/2000/svg';
function add(tag,attrs,text){const n=document.createElementNS(ns,tag);for(const [k,v] of Object.entries(attrs))n.setAttribute(k,v);if(text!==undefined)n.textContent=text;ring.append(n);return n;}
function point(r,a){return [250+Math.sin(a)*r,250-Math.cos(a)*r].join(' ');}
function render(){
 ring.replaceChildren();
 const count=slots.length||9,step=2*Math.PI/count;
 for(let i=0;i<count;i++){
  const a=i*step,start=a-step/2,end=a+step/2,s=slots[i]||{},empty=s.kind==='disabled'||!s.kind;
  add('path',{d:'M '+point(112,start)+' L '+point(240,start)+' A 240 240 0 0 1 '+point(240,end)+' L '+point(112,end)+' A 112 112 0 0 0 '+point(112,start)+' Z',class:'sector'+(empty?' empty':'')+(s.kind==='page'?' category':'')+(selected===i+1?' active':'')});
  const px=250+Math.sin(a)*176,py=250-Math.cos(a)*176;
  add('text',{x:px,y:py-9,class:'number'},s.kind==='page'?'›':s.kind==='disabled'?'—':String(i+1));
  const label=s.name||'Empty',display=label.length>20?label.slice(0,18)+'…':label;
  add('text',{x:px,y:py+12,class:'label'},display);
  if(s.kind==='weapon')add('text',{x:px,y:py+29,class:'label'},'Clip '+s.loaded+' · Belt '+s.quick);
  else if(s.kind==='consume')add('text',{x:px,y:py+29,class:'label'},'× '+s.quantity);
  else if(s.equipped)add('text',{x:px,y:py+29,class:'label'},'Equipped');
 }
 add('circle',{cx:250,cy:250,r:107,fill:'#171613ed',stroke:'#7d6d59','stroke-width':1});
 const s=slots[selected-1];
 title.textContent='FRONTIER / '+(page==='main'?'EQUIPMENT':page.toUpperCase());
 nameEl.textContent=s?.name||(loading?'Loading tools…':page==='main'?'Equipment':page==='character'?'Character':'Tools');
 const condition=s&&Number.isFinite(s.uses)&&s.maxUses>0?Math.round(s.uses/s.maxUses*100):null;
 detail.textContent=s?.kind==='weapon'?('Clip '+s.loaded+' · Quick '+s.quick+' · Satchel '+s.bag+' · '+s.serial):s?.kind==='tool'?('Quality '+(s.quality??'—')+'% · Condition '+(condition??'—')+'%'):s?.kind==='consume'?'Available: '+s.quantity+' · Release to use':s?.kind==='page'?'Hold here to open':s?.kind==='disabled'?'Not available':'Release TAB to select';
}
function post(action,data={}){return fetch('https://'+GetParentResourceName()+'/'+action,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});}
function showDocs(data){
 docs.hidden=false;document.querySelector('#docsTitle').textContent=data.mode==='profile'?'Character':'Documents';
 document.querySelector('#holder').textContent=data.name||'';
 document.querySelector('#docsWarning').textContent=data.warning||'';
 document.querySelector('#docsNotice').textContent='';
 recipient.replaceChildren();list.replaceChildren();
 const targets=Array.isArray(data.targets)?data.targets:[];
 const placeholder=new Option(targets.length?'Select nearby player':'No nearby players','');recipient.append(placeholder);
 for(const t of targets)recipient.append(new Option(t.name+' (#'+t.id+')',String(t.id)));
 for(const [i,row] of (data.documents||[]).entries()){
  const card=document.createElement('article'),heading=document.createElement('h2'),body=document.createElement('p'),button=document.createElement('button');
  heading.textContent=row.title;body.textContent='Holder: '+row.holder+' · '+row.status;
  button.textContent='Present';button.disabled=true;
  button.onclick=()=>{if(recipient.value)post('docsPresent',{index:i+1,target:Number(recipient.value)}).catch(()=>{});};
  card.append(heading,body,button);list.append(card);
 }
 recipient.onchange=()=>{for(const b of list.querySelectorAll('button'))b.disabled=!recipient.value;};
}
document.querySelector('#docsClose').onclick=()=>post('docsClose').catch(()=>{});
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!docs.hidden)post('docsClose').catch(()=>{});});
window.addEventListener('message',({data:d})=>{
 if(!d||typeof d.type!=='string')return;
 if(d.type==='open'){slots=[];selected=0;page='main';loading=false;root.hidden=false;render();}
 if(d.type==='page'&&!root.hidden){page=d.page;slots=Array.isArray(d.slots)?d.slots:[];selected=d.selected||0;loading=!!d.loading;render();}
 if(d.type==='select'&&!root.hidden){selected=Number(d.slot)||0;render();}
 if(d.type==='close')root.hidden=true;
 if(d.type==='docs')showDocs(d.data);
 if(d.type==='docsClose')docs.hidden=true;
 if(d.type==='docsNotice')document.querySelector('#docsNotice').textContent=d.message;
});
async function ready(){try{const res=await post('ready');if(!res.ok)throw Error('ready');await res.json();}catch(e){setTimeout(ready,500);}}ready();
