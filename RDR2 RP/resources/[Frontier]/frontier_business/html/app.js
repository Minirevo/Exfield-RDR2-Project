'use strict';
const $=id=>document.getElementById(id), vals=o=>Object.values(o||{});let state;
function el(tag,text,parent){let n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(parent)parent.append(n);return n}
function btn(p,t,f){let b=el('button',t,p);b.onclick=f;return b}
function field(p,placeholder,type='text'){let i=el('input',undefined,p);i.placeholder=placeholder;i.type=type;return i}
function select(p,items){let s=el('select',undefined,p);for(const [v,t] of items){let o=el('option',t,s);o.value=v}return s}
function post(route,d={}){return fetch('https://'+GetParentResourceName()+'/'+route,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(d)})}
function act(action,data){post('action',{action,data})}
function section(p,t){let s=el('section',undefined,p);el('h2',t,s);return s}
const cents=i=>Math.round(Number(i.value)*100),money=n=>'$'+(Number(n||0)/100).toFixed(2);
function render(){let root=$('content');root.replaceChildren();if(state.office){let s=section(root,'Government registry'),n=field(s,'Company name'),d=field(s,'Description');btn(s,'Register company',()=>act('register',{name:n.value,description:d.value}));let l=select(s,Object.entries(state.licenses).map(([k,v])=>[k,k+' '+money(v.fee)]));btn(s,'Buy personal license',()=>act('license',{category:l.value}))}
for(const v of vals(state.invites)){let s=el('article','Employment invitation · '+money(v.wage)+' / 10 min',root);btn(s,'Accept',()=>act('accept',{id:v.id}))}
for(const v of vals(state.offers)){let p=JSON.parse(v.payload),s=el('article','Share offer '+p.units/100+'% · '+money(p.amount),root);btn(s,'Accept',()=>act('vote',{company:v.company_id,id:v.id}))}
for(const b of vals(state.companies)){let s=section(root,b.name+' · '+b.status),a=(action,d={})=>act(action,{company:b.id,...d});el('p','Balance '+(b.balance===undefined?'Private':money(b.balance))+' · Base tax debt '+money(b.debt),s);let amount=field(s,'Amount USD','number');
if(b.owner)btn(s,'Deposit',()=>a('deposit',{amount:cents(amount)}));if(b.rights.withdraw)btn(s,'Withdraw',()=>a('withdraw',{amount:cents(amount)}));if(b.rights.finance)btn(s,'Pay tax',()=>a('payTax'));
if(b.owner){btn(s,'Propose dividend',()=>a('dividend',{amount:cents(amount)}));let limit=field(s,'Withdrawal USD','number'),daily=field(s,'Daily count','number');btn(s,'Propose limits',()=>a('policy',{limit:cents(limit),daily:Number(daily.value)}));let mode=select(s,['disabled','manual','fixed','percentage'].map(x=>[x,x])),da=field(s,'USD or percent','number'),reserve=field(s,'Reserve USD','number');btn(s,'Propose dividend policy',()=>a('dividendPolicy',{mode:mode.value,amount:cents(da),reserve:cents(reserve)}));let target=field(s,'Buyer player ID','number'),share=field(s,'Ownership %','number');btn(s,'Offer shares',()=>a('share',{target:Number(target.value),units:cents(share),amount:cents(amount)}));btn(s,'Propose closure',()=>a('close'))}
for(const v of vals(b.shares))el('p',v.character_id+' · '+v.units/100+'%',s);
for(const v of vals(b.proposals)){let r=el('article',v.kind+' · '+v.payload,s);btn(r,'Approve',()=>a('vote',{id:v.id}))}
if(b.rights.ranks){let name=field(s,'Rank name'),level=field(s,'Hierarchy level','number'),wage=field(s,'Paycheck USD','number'),checks={};let row=el('article','Rank permissions',s);for(const k of state.permissions){let l=el('label',k,row);checks[k]=el('input',undefined,l);checks[k].type='checkbox'}btn(s,'Create rank',()=>a('rank',{name:name.value,level:Number(level.value),wage:cents(wage),rights:Object.fromEntries(Object.entries(checks).map(([k,v])=>[k,v.checked]))}))}
if(b.rights.hire){let target=field(s,'Player ID','number'),rank=select(s,vals(b.ranks).map(r=>[r.id,r.name]));btn(s,'Invite employee',()=>a('hire',{target:Number(target.value),rank:rank.value}));for(const e of vals(b.employees)){let r=el('article',e.character_id,s);btn(r,'Dismiss',()=>a('fire',{target:e.character_id}))}}
if(state.office&&b.rights.licenses){let l=select(s,Object.entries(state.licenses).map(([k,v])=>[k,k+' '+money(v.fee)]));btn(s,'Buy company license',()=>a('license',{category:l.value}))}
for(const v of vals(b.logs))el('p',v.action+' · '+v.actor+' · '+v.detail,s)
}
btn(root,'Resign from employment',()=>act('resign',{}));let l=section(root,'Personal licenses');for(const v of vals(state.personal))el('p',v.category+' · '+(Number(v.active)?'Active':'Inactive')+' · Debt '+money(v.debt),l);
for(const v of vals(state.receipts)){let r=el('article',v.detail,root);btn(r,'Hide receipt',()=>act('hideReceipt',{id:v.id}))}
}
window.addEventListener('message',e=>{let d=e.data;if(d.type==='view'){state=d.data;render();document.body.hidden=false}else if(d.type==='close')document.body.hidden=true;else if(d.type==='notice')$('status').textContent=d.message});
function close(){document.body.hidden=true;post('close')}$('close').onclick=close;$('refresh').onclick=()=>post('refresh');document.addEventListener('keydown',e=>{if(e.key==='Escape')close()});
