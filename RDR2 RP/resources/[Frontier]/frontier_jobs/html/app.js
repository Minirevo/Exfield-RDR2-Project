'use strict';
const $=id=>document.getElementById(id),cash=n=>'$'+(Number(n||0)/100).toFixed(2);
let data=null,tab='',pending=false,timeout;
function el(t,s,p){const n=document.createElement(t);if(s!==undefined)n.textContent=s;if(p)p.append(n);return n}
function post(route,payload={}){return fetch('https://'+GetParentResourceName()+'/'+route,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)}).then(r=>r.json())}
function unlock(){pending=false;clearTimeout(timeout)}
function send(op,payload={}){if(pending)return;pending=true;$('status').textContent='Submitting…';timeout=setTimeout(()=>{unlock();$('status').textContent='No reply. Refresh before retrying.';render()},10000);render();post('action',{op,data:payload}).then(r=>{if(!r.ok){unlock();$('status').textContent='Session closed.';render()}}).catch(()=>{unlock();$('status').textContent='Request failed.';render()})}
function btn(p,t,fn,disabled=false){const b=el('button',t,p);b.disabled=disabled||pending;b.onclick=fn;return b}
function field(p,title,type='text'){const l=el('label',title,p),i=el(type==='textarea'?'textarea':type==='select'?'select':'input',undefined,l);if(type!=='textarea'&&type!=='select')i.type=type;return i}
function select(p,title,opts){const i=field(p,title,'select');for(const [v,t] of opts){const o=el('option',t,i);o.value=v}return i}
function article(p,title,desc,meta){const a=el('article',undefined,p);el('h3',title,a);if(desc)el('p',desc,a);if(meta){const m=el('p',meta,a);m.className='meta'}return a}
function actions(a){const n=el('div',undefined,a);n.className='actions';return n}
function waypoint(p,id){btn(p,'Mark on map',()=>post('waypoint',{id}).then(r=>{$('status').textContent=r.ok?'GPS route set. Close the menu to follow it.':'Waypoint unavailable.'}))}
let confirmation=null;
function confirmDo(text,op,payload){
 if(confirmation)confirmation.remove();
 const a=el('article',undefined,$('content'));confirmation=a;el('h3','Confirm action',a);el('p',text,a);
 const b=actions(a);btn(b,'Confirm',()=>{confirmation=null;send(op,payload)});btn(b,'Cancel',()=>{a.remove();confirmation=null});a.scrollIntoView({block:'nearest'});
}
function board(p){for(const j of data.jobs){const emp=data.employers[j.employer],a=article(p,j.title,j.description,emp.name+' · '+j.quantity+' × '+j.item+' · '+cash(j.reward)+' · '+j.available+' openings for you today'),b=actions(a);waypoint(b,j.employer);
 if(data.mode==='board'&&j.onsite)el('p','Visit the foreman to accept work and borrow tools.',a);
 else {btn(b,'Accept with own tools',()=>send('acceptNpc',{id:j.id,loan:false}),!j.available);if(j.loan)btn(b,'Accept & borrow tool',()=>send('acceptNpc',{id:j.id,loan:true}),!j.available)}
 }
 if(data.mode==='board')for(const j of data.postings){const a=article(p,j.title,j.description,j.employer+' · '+data.boards[j.town]?.name+' · '+(j.kind==='task'?cash(j.reward)+' reserved':'Recruitment')),b=actions(a);waypoint(b,j.town);
 if(j.kind==='task')btn(b,'Accept task',()=>confirmDo('Accept this one-time task?', 'acceptTask',{id:j.id}));else{const msg=field(a,'Application message','textarea');btn(a,'Apply',()=>send('apply',{id:j.id,message:msg.value}))}}
}
function mine(p){for(const j of data.mine){const a=article(p,j.title,j.description,j.state+' · '+cash(j.reward)+(j.receipt?' · Receipt '+j.receipt:'')),b=actions(a);
 if(j.kind==='npc'){waypoint(b,j.employer);if(j.state==='active'&&data.mode==='employer'&&data.place===j.employer)btn(b,'Deliver '+j.quantity+' × '+j.item,()=>send('deliver',{id:j.id}));if(j.state==='loaning'&&data.mode==='employer'&&data.place===j.employer)btn(b,'Retry equipment pickup',()=>send('retry',{id:j.id}));}
 else if(j.town)waypoint(b,j.town);
 if(j.kind==='task'&&j.state==='active')btn(b,'Submit completed task',()=>confirmDo('Submit for employer review?','submitTask',{id:j.id}));
 if(['active','loaning'].includes(j.state))btn(b,'Abandon',()=>confirmDo('End this contract? Loaned tools are returned.','abandon',{id:j.id}));
 }}
function manage(p){const a=article(p,'Create advertisement','Recruitment or a funded, one-time task. The employer reviews submitted tasks; no automatic facility permissions are granted.');
 const type=select(a,'Type',[['recruitment','Recruitment'],['task','One-time task']]),title=field(a,'Title'),desc=field(a,'Description / work location and requirements','textarea'),town=select(a,'Nearest town',Object.entries(data.boards).map(([k,v])=>[k,v.name])),reward=field(a,'Reward in dollars (tasks only)','number');
 btn(a,'Publish',()=>{const cents=Math.round(Number(reward.value)*100);if(type.value==='task'&&!data.canFund){$('status').textContent='Company withdraw permission required.';return}send('post',{kind:type.value,title:title.value,description:desc.value,town:town.value,reward:cents})});
 for(const j of data.companyJobs){const c=article(p,j.title,j.description,j.kind+' · '+j.state+' · '+cash(j.reward)+(j.worker_name?' · '+j.worker_name:'')),b=actions(c);if(j.state==='open')btn(b,'Cancel posting',()=>confirmDo('Cancel unaccepted posting?','cancel',{id:j.id}));if(j.state==='submitted')btn(b,'Approve & pay',()=>confirmDo('Confirm completed work and release reserved pay?','approve',{id:j.id}));}
}
function applications(p){for(const a of data.applications){const x=article(p,a.name+' — '+a.title,a.message,a.state+(a.online?' · Player ID '+a.online:' · Offline')),b=actions(x);if(a.state==='pending'){btn(b,'Mark contacted',()=>send('application',{id:a.posting,character:a.character_id,decision:'contacted'}));btn(b,'Decline',()=>send('application',{id:a.posting,character:a.character_id,decision:'declined'}))}}el('p','Use the existing Business employee invitation workflow to hire applicants.',p)}
function render(){if(!data)return;const p=$('content'),n=$('tabs');p.replaceChildren();n.replaceChildren();$('title').textContent=data.mode==='manage'?data.company.name+' employment':data.mode==='board'?data.boards[data.place].name:data.mode==='employer'?data.employers[data.place].name:'My work contracts';
 const tabs=data.mode==='manage'?[['manage','Advertisements'],['applications','Applications'],['mine','My work']]:data.mode==='personal'?[['mine','My work']]:[['board','Available work'],['mine','My work']];
 if(!tabs.some(t=>t[0]===tab))tab=tabs[0][0];for(const [id,t] of tabs){const b=btn(n,t,()=>{tab=id;render()});if(id===tab)b.className='active'}
 ({board,mine,manage,applications})[tab](p);if(!p.children.length)el('p','No entries yet.',p)}
function close(){unlock();document.body.hidden=true;post('close').catch(()=>{})}
$('close').onclick=close;$('refresh').onclick=()=>send('refresh');
$('clearRoute').onclick=()=>post('clearRoute').then(r=>{$('status').textContent=r.ok?'Employment route cleared.':'Unable to clear route.'});
document.addEventListener('keydown',e=>{if(e.key==='Escape')close()});
window.addEventListener('message',e=>{const d=e.data;if(d.type==='view'){if(!data||data.ticket!==d.data.ticket)tab='';data=d.data;unlock();document.body.hidden=false;render()}else if(d.type==='notice'){unlock();$('status').textContent=d.message;render()}else if(d.type==='close'){unlock();document.body.hidden=true;data=null}});
