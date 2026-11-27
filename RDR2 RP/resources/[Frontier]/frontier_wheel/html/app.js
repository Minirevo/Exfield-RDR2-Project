'use strict';
const root=document.querySelector('#wheel'), ring=document.querySelector('#ring');
const nameEl=document.querySelector('#name'), detail=document.querySelector('#detail');
let slots=[], selected=0, loaded=false;
const ns='http://www.w3.org/2000/svg';
function add(tag,attrs,text){const n=document.createElementNS(ns,tag);for(const [k,v] of Object.entries(attrs))n.setAttribute(k,v);if(text!==undefined)n.textContent=text;ring.append(n);return n;}
function point(r,a){return [250+Math.sin(a)*r,250-Math.cos(a)*r].join(' ');}
function render(){
 ring.replaceChildren();
 for(let i=0;i<8;i++){
  const a=i*Math.PI/4, start=a-Math.PI/8,end=a+Math.PI/8;
  const s=slots[i], empty=i<6&&(!s||!s.kind);
  add('path',{d:'M '+point(112,start)+' L '+point(240,start)+' A 240 240 0 0 1 '+point(240,end)+' L '+point(112,end)+' A 112 112 0 0 0 '+point(112,start)+' Z',class:'sector'+(empty?' empty':'')+(selected===i+1?' active':'')});
  const px=250+Math.sin(a)*176,py=250-Math.cos(a)*176;
  add('text',{x:px,y:py-9,class:'number'},i<6?String(i+1):i===6?'—':'×');
  const label=i===6?'Put away':i===7?'Cancel':s?.name||'Empty';
  const display=label.length>21?label.slice(0,19)+'…':label;
  add('text',{x:px,y:py+12,class:'label'},display);
  if(s?.equipped)add('text',{x:px,y:py+29,class:'label'},'Equipped');
 }
 add('circle',{cx:250,cy:250,r:107,fill:'#171613ed',stroke:'#7d6d59','stroke-width':1});
 const s=slots[selected-1];
 nameEl.textContent=!loaded?'Loading…':selected===7?'Put tool away':selected===8?'Cancel':selected===0?'Keep current':s?.name||'Empty';
 const condition=s&&Number.isFinite(s.uses)&&s.maxUses>0?Math.round(s.uses/s.maxUses*100):null;
 detail.textContent=!loaded?'Reading toolbelt':selected>=1&&selected<=6&&s?.kind?('Quality '+(s.quality??'—')+'% · Condition '+(condition??'—')+'%'):'Release TAB';
}
window.addEventListener('message',({data:d})=>{
 if(!d||typeof d.type!=='string')return;
 if(d.type==='open'){slots=[];selected=0;loaded=false;root.hidden=false;render();}
 if(d.type==='slots'&&!root.hidden){slots=Array.isArray(d.slots)?d.slots:[];loaded=true;render();}
 if(d.type==='select'&&!root.hidden){selected=Number(d.slot)||0;render();}
 if(d.type==='close')root.hidden=true;
});
async function ready(){try{const res=await fetch('https://'+GetParentResourceName()+'/ready',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});if(!res.ok)throw Error('ready '+res.status);await res.json();}catch(e){setTimeout(ready,500);}}ready();
