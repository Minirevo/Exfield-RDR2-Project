(()=>{'use strict';
const $=id=>document.getElementById(id), panel=$('panel'),content=$('content');
const rows=v=>Object.values(v||{}), money=v=>'$'+(Number(v)/100).toFixed(2),kg=g=>(Number(g)/1000).toFixed(1)+' kg';
let data=null,pending=false,retry=null,lastRequest=null,plan=[],selected=null,frame=0,drag=null;
function el(tag,text,cls){const n=document.createElement(tag);if(text!=null)n.textContent=text;if(cls)n.className=cls;return n}
function btn(text,fn,disabled=false){const b=el('button',text);b.type='button';b.disabled=pending||!!retry||disabled;b.onclick=fn;return b}
function select(options,value){const s=el('select');for(const x of options)s.add(new Option(x.name,x.id));if(options.some(x=>x.id===value))s.value=value;return s}
function label(parent,name,input){const l=el('label',name);l.append(input);parent.append(l);return input}
function number(value,min,max){const n=el('input');n.type='number';n.min=min;n.max=max;n.value=value;return n}
function heading(parent,t){parent.append(el('h2',t))}
function status(s){$('status').textContent=s||''}
async function post(path,d={}){const r=await fetch('https://'+GetParentResourceName()+'/'+path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(d)});return r.json()}
async function request(action,payload={},again=false){
 if(pending||!data)return;
 const order=again&&retry?retry:{action,data:payload};pending=true;retry=null;lastRequest=order;render();
 try{const r=await post('request',order);if(!r.ok){pending=false;status('Request not accepted');render()}else order.seq=r.seq}
 catch{pending=false;status('No acknowledgement; refresh before retrying');render()}
}
function box(id){return rows(data.inventories).find(x=>x.id===id)}
function outgoing(id,slot){return plan.filter(x=>x.from===id&&x.slot===slot).reduce((a,x)=>a+x.quantity,0)}
function add(from,to,slot,quantity){
 if(pending||retry)return;
 const a=box(from),b=box(to),s=rows(a?.box.slots).find(x=>x.slot===slot);
 if(!a||!b||!a.retrieve||!b.deposit||!s||from===to)return;
 const n=Math.min(s.quantity-outgoing(from,slot),Math.floor(Number(quantity)));
 if(!Number.isFinite(n)||n<=0)return;
 plan.push({from,to,slot,quantity:n});render();
}
function projected(id){
 const a=box(id);if(!a)return {weight:0,slots:0};
 const stacks=rows(a.box.slots).map(s=>({...s}));
 let weight=a.box.weight;
 for(const p of plan){
  const s=rows(box(p.from)?.box.slots).find(x=>x.slot===p.slot);if(!s)continue;
  if(p.from===id){weight-=s.grams*p.quantity;const x=stacks.find(x=>x.slot===s.slot);if(x)x.quantity-=p.quantity}
  if(p.to===id){weight+=s.grams*p.quantity;let left=p.quantity;
   if(!s.instance)for(const x of stacks){if(x.quantity>0&&x.item===s.item&&x.metadata===s.metadata&&!x.instance){const n=Math.min(left,x.maxStack-x.quantity);x.quantity+=n;left-=n;if(!left)break}}
   while(left>0){const n=Math.min(left,s.maxStack||1);stacks.push({...s,slot:-1,quantity:n});left-=n}
  }
 }
 return {weight,slots:stacks.filter(x=>x.quantity>0).length};
}
function pane(parent,a,target){
 const p=el('div',null,'pane drop');parent.append(p);p.append(el('h3',a.name));
 const pr=projected(a.id),extra=a.id===data.route?Number(data.freightWeight||0):0,extraSlots=a.id===data.route?Number(data.freightSlots||0):0;
 p.append(el('p',kg(pr.weight+extra)+' / '+kg(a.box.weightLimit)+' · '+(pr.slots+extraSlots)+' / '+a.box.capacity+' slots'));
 const bar=el('div',null,'weight'),fill=el('span');fill.style.width=Math.min(100,(pr.weight+extra)/a.box.weightLimit*100)+'%';bar.append(fill);p.append(bar);
 p.ondragover=e=>{if(drag&&drag.from!==a.id){e.preventDefault();p.classList.add('dragover')}};
 p.ondragleave=()=>p.classList.remove('dragover');p.ondrop=e=>{e.preventDefault();p.classList.remove('dragover');if(drag)add(drag.from,a.id,drag.slot,drag.qty);drag=null};
 for(const s of rows(a.box.slots)){
  const available=s.quantity-outgoing(a.id,s.slot);
  const r=el('div',null,'stack');p.append(r);
  const desc=el('span',s.name+' × '+available);try{const m=JSON.parse(s.metadata);if(m.quality!=null)desc.append(el('small',' · Q'+m.quality))}catch{}r.append(desc);
  const qty=number(Math.max(1,available),1,Math.max(1,available));qty.disabled=available<=0;r.append(qty);
  r.append(btn(a.id===data.route?'Unload →':'← Load',()=>add(a.id,target,s.slot,qty.value),available<=0||!a.retrieve||!box(target)?.deposit));
  r.draggable=available>0&&a.retrieve;r.ondragstart=()=>{drag={from:a.id,slot:s.slot,qty:Number(qty.value)}};r.ondragend=()=>{drag=null};
 }
 const incoming=plan.filter(x=>x.to===a.id);
 if(incoming.length)p.append(el('p',incoming.length+' staged incoming transfer(s)','muted'));
 if(!rows(a.box.slots).length)p.append(el('p','Empty','muted'));
}
function cargo(){
 const a=box(data.route),others=rows(data.inventories).filter(x=>x.id!==data.route);
 if(!a||!others.length)return content.append(el('p','No other inventory accessible.'));
 if(!others.some(x=>x.id===selected))selected=others[0].id;
 const s=select(others,selected);label(content,'Nearby inventory',s);s.onchange=()=>{selected=s.value;render()};
 const cols=el('div',null,'cols');content.append(cols);pane(cols,a,selected);pane(cols,box(selected),data.route);
 const controls=el('div',null,'buttons');controls.append(btn('Load all from selected',()=>{for(const x of rows(box(selected).box.slots)){const n=x.quantity-outgoing(selected,x.slot);if(n>0)plan.push({from:selected,to:data.route,slot:x.slot,quantity:n})}render()},!box(selected).retrieve||!a.deposit),btn('Unload all to selected',()=>{for(const x of rows(a.box.slots)){const n=x.quantity-outgoing(a.id,x.slot);if(n>0)plan.push({from:a.id,to:selected,slot:x.slot,quantity:n})}render()},!box(selected).deposit));content.append(controls);
 heading(content,'Planned transfers');
 let grams=0,units=0;
 plan.forEach((p,i)=>{const s=rows(box(p.from)?.box.slots).find(x=>x.slot===p.slot);if(!s)return;grams+=s.grams*p.quantity;units+=p.quantity;
  const r=el('div',null,'plan');r.append(el('span',p.quantity+' × '+s.name+' · '+box(p.from).name+' → '+box(p.to).name),btn('Undo',()=>{plan.splice(i,1);render()}));content.append(r)});
 const projectedWagon=projected(data.route),bad=rows(data.inventories).some(x=>{const p=projected(x.id);return p.weight+(x.id===data.route?Number(data.freightWeight||0):0)>x.box.weightLimit||p.slots+(x.id===data.route?Number(data.freightSlots||0):0)>x.box.capacity});
 content.append(el('p',units+' items · '+kg(grams)+' handled · '+(units?Math.max(3,Math.min(120,Math.ceil(2+grams/1000*.06+units*.015))):0)+'s before skill bonus',bad?'danger':'muted'));
 const submit=el('div',null,'buttons');submit.append(btn('Fertig — Confirm cargo',()=>request('load',{lines:plan,revisions:Object.fromEntries(rows(data.inventories).map(x=>[x.id,x.box.revision]))}),!plan.length||plan.length>80||bad),btn('Clear plan',()=>{plan=[];render()},!plan.length));content.append(submit);
 if(data.wagon){
  heading(content,'Wagon registration');
  content.append(el('p',data.wagon.id+' · condition '+data.wagon.condition_value+'% · quality '+data.wagon.quality+'%'+(Number(data.wagon.stolen)?' · REPORTED STOLEN':'')));
  if(data.manage)content.append(btn(Number(data.wagon.locked)?'Unlock cargo':'Lock cargo',()=>request('lock')),btn('Store empty wagon at yard',()=>request('store')));
  contracts();
 }
}
function companies(parent){return label(parent,'Owner',select([{id:'',name:'Private character'},...rows(data.companies)]))}
function registry(){
 heading(content,'Purchase wagon');const owner=companies(content);
 const models=Object.keys(data.models||{}).filter(k=>data.models[k]).map(k=>({id:k,name:data.definitions[k].name+' · '+money(data.prices[k])}));
 const m=label(content,'Wagon',select(models));content.append(btn('Purchase',()=>request('buy',{model:m.value,company:owner.value}),!models.length||!data.dealer));
 heading(content,'Registered wagons');
 for(const w of rows(data.wagons)){
  const c=el('div',null,'card');content.append(c);c.append(el('h3',w.name+' · '+w.state),el('p',w.id+' · '+w.owner_type+' · Q'+w.quality+' · condition '+w.condition_value+'%'));
  if(w.state==='stored'&&data.dealer){
   const count=data.definitions[w.model]?.horses||2;const hs=[];
   for(let i=0;i<count;i++){
    const choices=[{id:'',name:'Select horse'},...rows(data.horses).filter(h=>!h.wagon_id||h.wagon_id===w.id).map(h=>({id:String(h.id),name:h.name+' · '+h.modelname+(h.wagon_id?' (assigned)':'')}))];
    const assigned=rows(data.horses).find(h=>h.wagon_id===w.id&&Number(h.slot_no)===i);
    hs.push(label(c,'Harness '+(i+1),select(choices,assigned?String(assigned.id):'')));
   }
   c.append(btn('Assign horses',()=>request('assign',{wagon:w.id,horses:hs.map(h=>h.value)})),btn('Clear assignment',()=>request('assign',{wagon:w.id,horses:[]})),btn('Deploy',()=>request('deploy',{wagon:w.id})));
  }
  c.append(btn(Number(w.stolen)?'Clear stolen report':'Report stolen',()=>request('report',{wagon:w.id})));
 }
 heading(content,'Create freight contract');const origins=rows(data.origins),stock=rows(data.stock);
 if(!origins.length){content.append(el('p','Use /freight at an accessible warehouse to create an order.','muted'))}
 else{
  const o=label(content,'Pickup',select(origins)),dest=label(content,'Destination',select(stock.filter(x=>x.deposit&&x.id!==o.value))),list=el('div');content.append(list);
  let quantities=[];
  const cargoList=()=>{list.replaceChildren();quantities=[];const origin=origins.find(x=>x.id===o.value);for(const s of rows(origin?.box.slots)){const n=number(0,0,s.quantity);label(list,s.name+' ('+s.quantity+' available)',n);quantities.push({slot:s.slot,input:n})}};
  o.onchange=()=>{dest.replaceChildren(...stock.filter(x=>x.deposit&&x.id!==o.value).map(x=>new Option(x.name,x.id)));cargoList()};cargoList();
  const reward=label(content,'Reward (USD)',number(25,0.01,10000));reward.step='.01';
  const hours=label(content,'Pickup deadline (hours)',number(24,1,168));
  content.append(btn('Create funded contract',()=>request('createContract',{origin:o.value,destination:dest.value,reward:Math.round(Number(reward.value)*100),hours:Number(hours.value),lines:quantities.map(x=>({slot:x.slot,quantity:Number(x.input.value)})).filter(x=>x.quantity>0)})));
 }
 contracts();
}
function contracts(){
 heading(content,'Freight contracts');
 for(const c of rows(data.contracts)){
  const r=el('div',null,'card');content.append(r);
  r.append(el('h3',c.origin+' → '+c.destination),el('p',c.state+' · '+kg(c.grams)+' · '+money(c.reward)+(c.issue?' · '+c.issue:'')));
  if(c.canSteal)r.append(btn('Break freight seal / steal cargo',()=>request('stealFreight',{contract:c.id})));if(c.canAccept)r.append(btn('Accept contract',()=>request('acceptContract',{contract:c.id})));
  if(c.customer&&c.state==='open'&&data.mode==='registry')r.append(btn('Cancel / refund',()=>request('cancelContract',{contract:c.id})));
  if(c.carrier&&c.wagon===data.wagon?.id){
   if(c.state==='pickup')r.append(btn('Collect at origin',()=>request('pickup',{contract:c.id})),btn('Abandon before loading',()=>request('abandonContract',{contract:c.id})));
   if(c.state==='in_transit')r.append(btn('Deliver at destination',()=>request('deliver',{contract:c.id})),btn('Return to origin',()=>request('returnFreight',{contract:c.id})));
   const p=c.state==='pickup'?c.originPoint:c.destinationPoint;
   if(p)r.append(el('p','Location: '+p.x.toFixed(1)+', '+p.y.toFixed(1),'muted'));
  }
 }
}
function bench(){
 heading(content,'Assemble supply wagon');const owner=companies(content),source=label(content,'Component source',select(rows(data.stocks)));
 for(const [k,n] of Object.entries(data.assembly||{}))content.append(el('p',n+' × '+k.replaceAll('logistics_','').replaceAll('_',' ')));
 content.append(btn('Assemble wagon',()=>request('assemble',{model:'supplywagon',company:owner.value,route:source.value}),!source.value));
 heading(content,'Repair wagon');const w=label(content,'Wagon',select(rows(data.wagons).filter(x=>x.state==='world').map(x=>({id:x.id,name:x.name+' · '+x.condition_value+'% · '+x.id.slice(0,8)}))));
 for(const [k,n] of Object.entries(data.repair||{}))content.append(el('p',n+' × '+k.replaceAll('logistics_','').replaceAll('_',' ')));
 content.append(btn('Repair to full condition',()=>request('repair',{wagon:w.value,model:'supplywagon',route:source.value}),!w.value||!source.value));
}
function render(){
 if(!data)return;
 $('title').textContent=data.mode==='cargo'?(data.wagon?.name||'Recovery crate'):data.mode==='bench'?'Wagon construction':data.mode==='locked'?'Locked wagon':'Freight registry';
 content.replaceChildren();
 if(data.mode==='cargo')cargo();else if(data.mode==='bench')bench();else if(data.mode==='locked'){
  content.append(el('p','Cargo is locked. Legal registration: '+data.wagon.id),btn('Pick cargo lock',()=>request('pick')));
 }else registry();
 $('refresh').disabled=pending||!!retry;$('retry').hidden=!retry;$('retry').disabled=pending;
}
$('close').onclick=()=>post('close');$('refresh').onclick=()=>request('refresh');$('retry').onclick=()=>{if(retry)request(retry.action,retry.data,true)};
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&data)post('close')});
function hide(){data=null;plan=[];pending=false;retry=null;panel.hidden=true;$('activity').hidden=true;document.body.hidden=true;cancelAnimationFrame(frame)}
function activity(d,lock){
 hide();document.body.hidden=false;$('activity').hidden=false;$('activity-title').textContent=lock?'Pick cargo lock':d.label;$('activity-note').textContent=lock?'Press SPACE in the green zone':'Backspace to cancel';
 $('target').hidden=!lock;$('marker').hidden=!lock;$('progress').hidden=lock;$('target').style.left=((d.target||0)-.1)*100+'%';$('target').style.width='20%';
 const start=performance.now();const tick=t=>{const e=t-start;if(lock)$('marker').style.left=(e%2000)/20+'%';else $('progress').style.width=Math.min(100,e/d.ms*100)+'%';if(e<d.ms)frame=requestAnimationFrame(tick);else $('activity-note').textContent='Waiting for confirmation…'};frame=requestAnimationFrame(tick);
}
window.addEventListener('message',({data:d})=>{
 if(d.type==='open'){data=d.data;plan=[];pending=false;retry=null;document.body.hidden=false;panel.hidden=false;status('');render()}
 else if(d.type==='result'&&data){pending=false;retry=d.retry&&lastRequest?{...lastRequest,retry:true,seq:d.seq}:null;if(d.snapshot){data=d.snapshot;if(!d.retry)plan=[]}status(d.message);render()}
 else if(d.type==='notice'&&data)status(d.message);
 else if(d.type==='close'||d.type==='activityEnd')hide();
 else if(d.type==='activity')activity(d,false);else if(d.type==='lockpick')activity(d,true);
});
})();