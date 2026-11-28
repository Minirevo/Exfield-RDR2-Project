'use strict';
(()=>{
const root=document.querySelector('#hospital'),content=document.querySelector('#hospital-content'),notice=document.querySelector('#hospital-notice');
let data=null,tab='service',search='',before=null,detail=null;
const send=(action,extra={})=>post('hospitalAction',{action,search,before,...extra});
const cash=n=>'$'+(Number(n||0)/100).toFixed(2);
const date=n=>n?new Date(Number(n)*1000).toLocaleString():'—';
function el(tag,text,cls){const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n}
function button(text,fn,disabled=false){const b=el('button',text);b.disabled=disabled;b.onclick=fn;return b}
function line(label,value){const n=el('div',undefined,'record-line');n.append(el('span',label),el('strong',String(value)));return n}
function heading(s){content.append(el('h2',s))}
function actions(...nodes){const n=el('div',undefined,'actions');n.append(...nodes);return n}
function render(){
 if(!data)return;
 document.querySelector('#hospital-title').textContent=data.name;
 document.querySelector('#hospital-status').textContent=data.mode==='station'?(data.duty?'ON DUTY':'OFF DUTY')+' · Department funds '+(data.balance===undefined?'unavailable':cash(data.balance)):'Persistent medical records';
 const tabs=[...root.querySelectorAll('[data-hospital-tab]')];
 tabs.forEach(b=>{b.hidden=data.mode!=='station'&&b.dataset.hospitalTab!=='archive';b.setAttribute('aria-pressed',String(b.dataset.hospitalTab===tab));});
 content.replaceChildren();
 if(tab==='service'){
  heading('Duty registration');content.append(el('p','Register here before responding to emergencies or collecting department equipment.'));
  content.append(actions(button(data.duty?'Leave service':'Enter service',()=>send('duty')),button('Refresh',()=>send('refresh'))));
  heading('Department treasury');content.append(line('Available funds',data.balance===undefined?'Unavailable':cash(data.balance)));
  content.append(el('p','Funds belong to the public medical service. Personal withdrawals and transfers are not available.','hint'));
 }else if(tab==='supplies'){
  heading('Equipment kits');content.append(el('p','The counter replenishes missing supplies only, using department funds.','hint'));
  if(Number(data.pending)>0)content.append(actions(button('Collect pending order',()=>send('collect'),!data.duty)));
  for(const [id,k] of Object.entries(data.kits||{})){
   let total=0;const parts=[];
   for(const [item,target] of Object.entries(k.items)){const d=data.supplies[item],missing=Math.max(0,target-Number(data.owned?.[item]||0));if(missing){parts.push(d.label+' ×'+missing);total+=missing*d.price}}
   const n=el('div',undefined,'hospital-entry');n.append(el('strong',k.label+' · '+cash(total)),el('p',parts.join(', ')||'Already fully equipped','hint'),button('Restock kit',()=>send('kit',{id}),!data.duty||!total||Number(data.pending)>0));content.append(n);
  }
  heading('Individual supplies');
  for(const [id,d] of Object.entries(data.supplies||{})){
   const owned=Number(data.owned?.[id]||0),max=Math.max(0,d.max-owned),n=el('div',undefined,'hospital-entry');
   n.append(line(d.label+' · '+cash(d.price)+' each',owned+' / '+d.max));
   const count=el('input');count.type='number';count.min='1';count.max=String(max);count.value='1';count.disabled=!max;
   n.append(actions(count,button('Collect',()=>send('item',{id,count:Number(count.value)}),!data.duty||!max||Number(data.pending)>0)));content.append(n);
  }
 }else if(tab==='finance'){
  heading('Shared treasury');content.append(line('Available funds',data.balance===undefined?'Unavailable':cash(data.balance)),actions(button('Refresh ledger',()=>send('refresh'))));
  heading('Recent transactions');
  for(const row of data.ledger||[]){const n=el('div',undefined,'hospital-entry');n.append(line(row.reason,(row.entry_type==='credit'?'+':'−')+cash(row.amount_minor)),el('p','Receipt '+row.operation_id+' · '+row.created_at,'hint'));content.append(n)}
  heading('Supply issue archive');
  for(const row of data.orders||[]){const n=el('div',undefined,'hospital-entry');n.append(line(row.doctor_name+' · '+row.hospital,cash(row.amount_minor)),el('p',row.status+' · '+date(row.created_at)+' · Ledger '+(row.debit_receipt||'pending'),'hint'));try{n.append(el('p',JSON.parse(row.items_json).map(x=>(data.supplies?.[x.item]?.label||x.item)+' ×'+x.count).join(', '),'hint'))}catch{}content.append(n)}
 }else if(tab==='dispatch'){
  heading('Active emergencies');content.append(actions(button('Refresh calls',()=>send('refresh')),button('Release assigned call',()=>post('hospitalDispatch',{action:'release'}),!data.duty)));
  for(const call of data.calls||[]){const n=el('div',undefined,'hospital-entry');n.append(line('Emergency #'+call.number,'Patient #'+call.patient),button(call.mine?'Assigned to you':call.assigned?'Assigned':'Accept emergency',()=>post('hospitalDispatch',{action:'accept',number:call.number}),!data.duty||call.assigned));content.append(n)}
  if(!data.calls?.length)content.append(el('p','No active calls.'));
 }else{
  heading(detail?'Invoice MED-'+detail.id:'Invoice archive');
  if(detail){
   content.append(actions(button('Back to archive',()=>{detail=null;render()})));
   content.append(line('Patient',detail.patient_name),line('Treating physician',detail.doctor_name),line('Hospital',detail.hospital),line('Issued',date(detail.created_at)),line('Due',date(detail.due_at)),line('Status',detail.status));
   for(const r of detail.lines||[])content.append(line(r.label+' · '+r.region.replaceAll('_',' '),cash(r.price_minor)));
   content.append(line('Total',cash(detail.amount_minor)));
   if(detail.payment_receipt)content.append(line('Payment receipt',detail.payment_receipt),line('Paid at',date(detail.paid_at)));
   if(detail.reported_at)content.append(line('Police referral',date(detail.reported_at)));
   const buttons=[];
   if(detail.canPay)buttons.push(button('Pay from bank account',()=>{const id=detail.id;detail=null;send('pay',{id})}));
   if(detail.canResolve){buttons.push(button('Waive invoice',()=>{if(confirm('Waive this invoice?')){const id=detail.id;detail=null;send('waive',{id})}}),button('Cancel invoice',()=>{if(confirm('Cancel this invoice?')){const id=detail.id;detail=null;send('cancel',{id})}}))}
   if(detail.canReport)buttons.push(button('Refer overdue invoice to police',()=>{if(confirm('Refer this overdue invoice?')){const id=detail.id;detail=null;send('report',{id})}}));
   content.append(actions(...buttons));
  }else{
   const input=el('input');input.placeholder='Patient, doctor or MED-number';input.value=search;input.maxLength=80;
   content.append(actions(input,button('Search',()=>{search=input.value;before=null;send('refresh')}),button('Newest',()=>{before=null;search='';send('refresh')})));
   for(const r of data.invoices||[]){const n=el('div',undefined,'hospital-entry');n.append(line('MED-'+r.id+' · '+r.patient_name,cash(r.amount_minor)),el('p',r.status+' · '+r.doctor_name+' · '+date(r.created_at),'hint'),button('View receipt',()=>send('detail',{id:String(r.id)})));content.append(n)}
   if(!data.invoices?.length)content.append(el('p','No matching invoices.'));
   if(data.more&&data.invoices.length)content.append(button('Older invoices',()=>{before=String(data.invoices.at(-1).id);send('refresh')}));
  }
 }
}
root.querySelectorAll('[data-hospital-tab]').forEach(b=>b.onclick=()=>{if(b.hidden)return;tab=b.dataset.hospitalTab;detail=null;render()});
document.querySelector('#hospital-close').onclick=()=>post('hospitalClose');
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!root.hidden)post('hospitalClose')});
window.addEventListener('message',({data:m})=>{
 if(m?.type==='hospitalClose'){root.hidden=true;data=null;detail=null;return}
 if(m?.type==='hospitalView'){
  if(!data||data.ticket!==m.data.ticket){tab=m.data.mode==='station'?'service':'archive';search='';before=null;detail=null;notice.textContent=''}
  data=m.data;root.hidden=false;render();
 }
 if(m?.type==='hospitalDetail'&&data){detail=m.data;tab='archive';render()}
 if(m?.type==='notice'&&!root.hidden)notice.textContent=m.message;
});
})();
