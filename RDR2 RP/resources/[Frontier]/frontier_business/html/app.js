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
function render(){let root=$('content');root.replaceChildren();if(state.fixture){renderFixture(root,state.fixture);return;}if(state.office){let s=section(root,'Government registry'),n=field(s,'Company name'),d=field(s,'Description');btn(s,'Register company',()=>act('register',{name:n.value,description:d.value}));let l=select(s,Object.entries(state.licenses).map(([k,v])=>[k,k+' '+money(v.fee)]));btn(s,'Buy personal license',()=>act('license',{category:l.value}))}
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
if(b.owner||b.rights.locations){let plot=select(s,vals(state.plots).map(p=>[p.id,p.name])),rights={};for(const k of ['stock','retail','farm','production']){let l=el('label',k,s);rights[k]=el('input',undefined,l);rights[k].type='checkbox'}btn(s,'Grant plot usage',()=>a('grant',{property:plot.value,rights:Object.fromEntries(Object.entries(rights).map(([k,v])=>[k,v.checked]))}));btn(s,'Revoke plot usage',()=>a('revoke',{property:plot.value}))}if(b.trade)renderTrade(s,b,a);for(const v of vals(b.receipts)){let r=el('article',v.detail,s);btn(r,'Hide receipt',()=>a('hideReceipt',{id:v.id}))}for(const v of vals(b.logs))el('p',v.action+' · '+v.actor+' · '+v.detail,s)
}
for(const v of vals(state.orders)){let r=el('article','Paid purchase: '+v.quantity+' '+v.item_id,root);btn(r,'Collect at counter',()=>act('claimRetail',{id:v.id}))}btn(root,'Resign from employment',()=>act('resign',{}));let l=section(root,'Personal licenses');for(const v of vals(state.personal))el('p',v.category+' · '+(Number(v.active)?'Active':'Inactive')+' · Debt '+money(v.debt),l);
for(const v of vals(state.receipts)){let r=el('article',v.detail,root);btn(r,'Hide receipt',()=>act('hideReceipt',{id:v.id}))}
}
window.addEventListener('message',e=>{let d=e.data;if(d.type==='view'){state=d.data;render();document.body.hidden=false}else if(d.type==='close')document.body.hidden=true;else if(d.type==='notice')$('status').textContent=d.message});
function close(){document.body.hidden=true;post('close')}$('close').onclick=close;$('refresh').onclick=()=>post('refresh');document.addEventListener('keydown',e=>{if(e.key==='Escape')close()});

function renderFixture(root,f){let s=section(root,f.registered?.name||'Configure '+f.kind);
 if(!f.registered&&f.setup){let name=field(s,'Storage / counter name'),co=select(s,[['','Personal'],...vals(f.companies).map(b=>[b.id,b.name])]);btn(s,'Register',()=>act('fixtureSetup',{name:name.value,company:co.value}))}
 if(f.access)btn(s,'Open stock',()=>act('fixtureStock',{}));
 if(f.manage&&f.kind==='counter'){let item=field(s,'Item ID'),price=field(s,'Price USD (0 removes)','number');btn(s,'Set price',()=>act('fixturePrice',{item:item.value,price:cents(price)}))}
 for(const v of vals(f.products)){let r=el('article',v.item+' · '+v.quantity+' available · '+money(v.price),s),q=field(r,'Quantity','number');q.value=1;btn(r,'Buy',()=>act('fixtureBuy',{item:v.item,quantity:Number(q.value)}))}
 if(f.unregister)btn(s,'Unregister empty fixture',()=>act('fixtureRemove',{}));
}

function renderTrade(parent,b,a){
 const s=section(parent,'Company Trade'),t=b.trade,send=(operation,d={})=>a('trade',{operation,...d});
 const locations=vals(b.tradeFixtures),src=select(s,locations.filter(x=>x.retrieve).map(x=>[x.id,x.name])),dst=select(s,locations.filter(x=>x.deposit).map(x=>[x.id,x.name]));
 el('p','First storage: source for deliveries/offers. Second storage: destination for purchases. Approach the designated storage for physical dispatch or collection.',s);
 if(b.status==='active'){
 const market=select(s,Object.entries(t.markets)),item=select(s,Object.entries(t.products)),q=field(s,'Quantity','number'),p=field(s,'Unit price USD','number'),cap=field(s,'Maximum price USD','number');
 btn(s,'Create purchase request',()=>send('request',{market:market.value,item:item.value,quantity:Number(q.value),price:cents(p),cap:cap.value?cents(cap):cents(p),fixture:dst.value}));
 btn(s,'Create sale offer',()=>send('offer',{market:market.value,item:item.value,quantity:Number(q.value),price:cents(p),fixture:src.value}));
 for(const r of vals(t.requests)){let row=el('article',r.market_id+' · '+r.remaining+' '+r.item_id+' · '+money(r.price)+' · '+r.state,s);
 if(r.state==='open'&&!r.active_contract){if(r.buyer_id===b.id)btn(row,'Cancel request',()=>send('cancelRequest',{id:r.id}));else btn(row,'Accept contract',()=>send('accept',{id:r.id}))}}
 for(const r of vals(t.offers)){let row=el('article',r.market_id+' · '+r.available+' '+r.item_id+' · '+money(r.price)+' · '+r.state,s);
 if(r.state==='open'&&!r.active_sale){if(r.seller_id===b.id)btn(row,'Cancel offer',()=>send('cancelOffer',{id:r.id}));else{let n=field(row,'Quantity','number');n.value=1;btn(row,'Buy',()=>send('buy',{id:r.id,quantity:Number(n.value),fixture:dst.value}))}}}
 for(const r of vals(t.contracts)){let row=el('article','Contract '+r.id+' · '+r.remaining+' '+r.item_id+' · '+r.state,s);
 if(r.state==='active'&&!r.active_delivery){btn(row,'Cancel contract',()=>send('cancelContract',{id:r.id}));if(r.seller_id===b.id){let n=field(row,'Quantity','number');n.value=1;btn(row,'Dispatch from source storage',()=>send('deliver',{id:r.id,quantity:Number(n.value),fixture:src.value}))}}}
 }
 for(const [rows,operation] of [[t.deliveries,'claimDelivery'],[t.sales,'claimSale']])for(const r of vals(rows)){let row=el('article',r.quantity+' '+r.item_id+' · '+r.state,s);if(r.buyer_id===b.id&&r.state==='complete'&&!r.claimed_at)btn(row,'Collect at designated storage',()=>send(operation,{id:r.id}))}
}
