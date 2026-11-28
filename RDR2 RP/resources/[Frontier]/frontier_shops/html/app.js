'use strict';
const $=id=>document.getElementById(id),money=n=>'$'+(Number(n||0)/100).toFixed(2);
let data=null,mode='buy',cart=new Map(),pending=false,timer;
function el(tag,text,parent,cls){const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;if(parent)parent.append(n);return n}
function button(parent,text,fn,disabled=false){const b=el('button',text,parent);b.disabled=disabled;b.onclick=fn;return b}
function post(route,body={}){return fetch('https://'+GetParentResourceName()+'/'+route,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}).then(r=>r.json())}
function unlock(){pending=false;clearTimeout(timer)}
function request(route,body){if(pending)return;pending=true;renderBasket();if(mode==='farm')renderProducts();$('status').textContent='Processing…';timer=setTimeout(()=>{unlock();$('status').textContent='No reply. Refresh and check receipts before retrying.';renderBasket();if(mode==='farm')renderProducts()},12000);post(route,body).then(r=>{if(!r.ok){unlock();$('status').textContent='Shop closed.';renderBasket()}}).catch(()=>{unlock();$('status').textContent='Request failed.';renderBasket()})}
function product(id){return data.catalog.find(d=>d.id===id)}
function cap(d){return Math.min(data.maxQuantity,d.maxStack===1?1:data.maxQuantity,mode==='sell'?Number(d.owned):data.maxQuantity)}
function adjust(id,n){const d=product(id);if(!d||pending)return;const v=Math.min(cap(d),Math.max(0,(cart.get(id)||0)+n));if(v)cart.set(id,v);else cart.delete(id);renderBasket();renderProducts()}
function categories(){const c=$('category'),old=c.value;c.replaceChildren();for(const s of ['All categories',...new Set(data.catalog.filter(d=>d[mode]).map(d=>d.category))])el('option',s,c).value=s;c.value=[...c.options].some(o=>o.value===old)?old:'All categories'}
function farmDelivery(root){
 const f=data.farm;if(!f){el('p','Agricultural deliveries unavailable.',root,'empty');return}
 const a=el('article',undefined,root,'receipt');el('h3','Farm deliveries',a);el('p','Order livestock directly to an authorized enclosure, or bulk supplies to your company farm chest. Personal seeds, fertilizer and tools are in Buy goods.',a);
 const label=(name,tag)=>{const l=el('label',name,a,'farmField');return el(tag,undefined,l)};
 const goods=label('Goods','select'),qty=label('Quantity','input'),dest=label('Destination','select'),breed=label('Horse breed','select'),young=label('Juvenile (60% of adult price)','input');
 qty.type='number';qty.min=1;qty.max=1000;qty.value=1;young.type='checkbox';
 for(const d of f.items.filter(d=>d.animal||d.maxStack>1)){const o=el('option',d.name+' · '+money(d.price),goods);o.value=d.id}
 for(const [id,d] of Object.entries(f.breeds||{}))el('option',d.label,breed).value=id;
 const total=el('p','',a),submit=button(a,'Place farm order',()=>request('farmOrder',{item:goods.value,quantity:Number(qty.value),facility:dest.value,breed:breed.value,juvenile:young.checked}));
 function update(){
  const d=f.items.find(d=>d.id===goods.value);const previous=dest.value;dest.replaceChildren();
  if(d)for(const v of f.destinations.filter(v=>d.animal?(d.animal==='chicken'?v.kind==='chicken':v.kind==='livestock'):v.ownerType==='company'))el('option',v.name+' · '+v.id.slice(0,6),dest).value=v.id;
  if([...dest.options].some(o=>o.value===previous))dest.value=previous;
  breed.parentElement.hidden=!(d&&d.animal==='horse');young.parentElement.hidden=!(d&&d.animal);
  const n=Number(qty.value),price=d?(d.animal&&young.checked?Math.max(1,Math.floor(d.price*.6)):d.price):0;
  total.textContent='Total: '+money(n*price)+' · '+(dest.value&&f.destinations.find(v=>v.id===dest.value)?.ownerType==='company'?'Company bank':'Personal cash');
  submit.disabled=pending||!d||!dest.value||!Number.isInteger(n)||n<1||n>1000;
 }
 goods.onchange=()=>{young.checked=false;update()};qty.oninput=update;dest.onchange=update;young.onchange=update;update();
 if(f.orders.length){const p=el('article',undefined,root,'receipt');el('h3','Pending farm orders',p);for(const o of f.orders)el('p',o.item+' × '+o.quantity+' · '+money(o.amount)+' · '+o.phase,p)}
}
function renderProducts(){const root=$('products');root.replaceChildren();if(mode==='farm'){farmDelivery(root);return}if(mode==='receipts'){
 for(const o of data.orders){const a=el('article',undefined,root,'receipt');el('h3',(o.mode==='buy'?'Purchase':'Sale')+' · '+money(o.total),a);el('p',o.state.toUpperCase()+' · '+new Date(Number(o.created)*1000).toLocaleString(),a);for(const l of o.lines||[])el('p',l.quantity+' × '+(product(l.id)?.name||l.id),a);if(o.issue)el('p',o.issue,a);el('p','Order '+o.id+(o.receipt?' · Receipt '+o.receipt:''),a)}
 if(!data.orders.length)el('p','No transactions yet.',root,'empty');return
 }
 const query=$('search').value.toLowerCase(),category=$('category').value;
 const visible=data.catalog.filter(d=>d[mode]&&(category==='All categories'||d.category===category)&&(d.name+' '+d.category+' '+d.id).toLowerCase().includes(query));
 for(const d of visible){const a=el('article',undefined,root,'product'),img=el('div',undefined,a,'image');
 if(d.icon){const i=el('img',undefined,img);i.src='icons/'+d.icon+'.png';i.alt='';i.onerror=()=>{img.replaceChildren();el('span',d.category.toUpperCase(),img)}}else el('span',d.category.toUpperCase(),img);
 el('h3',d.name,a);el('div',d.spec?d.spec.slot+' · '+d.spec.capacity+' rounds · '+d.spec.ammo:d.description,a,'desc');el('div',(Number(d.grams)/1000).toFixed(2)+' kg · In satchel: '+d.owned,a,'meta');el('div',money(d[mode])+' / unit',a,'price');
 button(a,cart.has(d.id)?'Add more ('+cart.get(d.id)+')':'Add to basket',()=>adjust(d.id,1),pending||(cart.get(d.id)||0)>=cap(d));
 }
 if(!visible.length)el('p',mode==='sell'?'No matching goods purchased at this counter.':'No matching goods.',root,'empty')
}
function renderBasket(){if(!data)return;const b=$('basket');b.replaceChildren();let total=0;for(const [id,n] of cart){const d=product(id);if(!d||!d[mode])continue;const row=el('div',undefined,b,'line'),left=el('div',undefined,row);el('strong',d.name,left);el('div',money(d[mode]*n),left,'meta');const step=el('div',undefined,row,'stepper');button(step,'−',()=>adjust(id,-1),pending);el('span',n,step);button(step,'+',()=>adjust(id,1),pending||n>=cap(d));total+=d[mode]*n}
 if(!cart.size)el('p','Your basket is empty.',b,'muted');$('total').textContent=money(total);$('checkout').textContent=mode==='sell'?'Confirm sale':'Confirm purchase';$('checkout').disabled=pending||!cart.size||mode==='farm'||mode==='receipts'||(mode==='buy'&&total>data.cash);$('clear').disabled=pending||!cart.size;$('basketTitle').textContent=mode==='sell'?'Goods to sell':'Your basket';$('basketNote').textContent=mode==='sell'?'Payment goes to your cash balance.':'Pay in cash and receive goods in your satchel.';
}
function render(){if(!data)return;$('title').textContent=data.shop;$('kind').textContent=data.kind;$('cash').textContent=money(data.cash);$('weight').textContent=(data.weight/1000).toFixed(1)+' / '+(data.weightLimit/1000).toFixed(1)+' kg satchel';
 $('farmTab').hidden=!data.farm;if(mode==='farm'&&!data.farm)mode='buy';
 $('kind').textContent=data.kind+(data.farmUnavailable?' · Farm deliveries temporarily unavailable':'');
 for(const b of $('tabs').querySelectorAll('button')){b.classList.toggle('active',b.dataset.mode===mode);b.disabled=pending||(b.dataset.mode==='sell'&&!data.catalog.some(d=>d.sell))}
 $('search').parentElement.style.display=['receipts','farm'].includes(mode)?'none':'';categories();renderProducts();renderBasket();
}
$('tabs').onclick=e=>{const m=e.target.dataset.mode;if(!m||pending||m===mode)return;mode=m;cart.clear();$('search').value='';render()};
$('search').oninput=renderProducts;$('category').onchange=renderProducts;
$('clear').onclick=()=>{if(!pending){cart.clear();render()}};
$('checkout').onclick=()=>{if(!pending&&cart.size&&['buy','sell'].includes(mode))request('checkout',{mode,lines:[...cart].map(([id,quantity])=>({id,quantity}))})};
$('refresh').onclick=()=>request('refresh',{});
function close(){unlock();data=null;cart.clear();document.body.hidden=true;post('close').catch(()=>{})}
$('close').onclick=close;document.addEventListener('keydown',e=>{if(e.key==='Escape')close()});
window.addEventListener('message',e=>{const m=e.data;if(m.type==='view'){const fresh=!data,oldTicket=data?.ticket;data=m.data;unlock();if(fresh){mode='buy';$('search').value='';$('status').textContent='';cart.clear()}else if(oldTicket!==data.ticket){cart.clear()}document.body.hidden=false;render()}else if(m.type==='notice'){unlock();$('status').textContent=m.message;render()}else if(m.type==='close'){unlock();data=null;cart.clear();document.body.hidden=true}});
