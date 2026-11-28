'use strict';const $=id=>document.getElementById(id),money=n=>'$'+(Number(n)/100).toFixed(2);let data,tab='horses',busy=false,timer,selectedKey=null,previewKey=null,previewMessage='',marketOwner='';
function el(tag,text,parent){const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(parent)parent.append(n);return n}
function button(p,t,fn,off=false){const b=el('button',t,p);b.onclick=fn;b.disabled=busy||off;return b}
function post(route,p={}){return fetch('https://'+GetParentResourceName()+'/'+route,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(p)}).then(r=>r.json())}
function send(op,d={}){if(busy)return;busy=true;$('status').textContent='Processing…';render();clearTimeout(timer);timer=setTimeout(()=>{busy=false;$('status').textContent='No response. Refresh before retrying.';render()},15000);post('action',{op,data:d}).catch(()=>{busy=false;render()})}
function card(p,title,desc){const a=el('article',undefined,p);el('h2',title,a);el('p',desc,a);return a}
function render(){if(!data)return;document.body.classList.toggle('showroom',tab==='market');if(tab!=='market')stopPreview();$('title').textContent=data.sites[data.site].name;$('cash').textContent=money(data.cash);const p=$('content');p.replaceChildren();for(const b of $('tabs').querySelectorAll('button'))b.classList.toggle('active',b.dataset.tab===tab);
 if(tab==='horses'){
  const top=card(p,'Boarding','Bring your active horse to this stable to board it.');top.className='wide';button(top,'Board active horse',()=>send('board'));
  for(const h of data.horses){const a=card(p,h.name,h.breed+' · '+h.sex+' · '+h.ownerType+' · '+(h.assigned?'Assigned to wagon':h.status==='out'?'Out riding':data.sites[h.stable]?.name||h.stable));for(const [k,v] of Object.entries({...h.genes,healthCondition:h.health,care:h.care,training:h.training})){el('small',k+' '+Math.round(v)+'/100',a);const m=el('meter',undefined,a);m.min=0;m.max=100;m.value=v}
   el('p','Certificate '+h.id,a);el('p','Saddle: '+(h.gear?.saddle?'fitted':'required')+' · Bags: '+(h.gear?.bags?'fitted':'none'),a);const b=el('div',undefined,a);
   const local=h.status==='stored'&&h.stable===data.site&&!h.assigned&&!h.pending;
   if(h.status==='stored'&&h.stable!==data.site&&!h.assigned)button(b,'Transfer here '+money(data.transferPrice),()=>send('transfer',{id:h.id,site:data.site}));
   if(local){button(b,'Retrieve',()=>send('retrieve',{id:h.id}),!h.gear?.saddle||h.health<30||h.age<345600);button(b,'Feed & groom '+money(data.carePrice),()=>send('care',{id:h.id}));button(b,'Treatment '+money(data.healPrice),()=>send('heal',{id:h.id}));const input=el('input',undefined,a);input.value=h.name;button(a,'Rename',()=>send('rename',{id:h.id,name:input.value}));for(const [id,g] of Object.entries(data.gear))if(!h.gear?.[g.slot])button(b,'Fit '+g.name+' ('+g.owned+' owned)',()=>send('equip',{id:h.id,item:id}),!g.owned)}
  }
  if(!data.horses.length)el('p','You own no boarded horses yet. Buy one or release an adult ranch horse with a saddle.',p);
 }else if(tab==='shop'){for(const [id,g] of Object.entries(data.gear)){const a=card(p,g.name,money(g.price)+' · In satchel: '+g.owned);button(a,'Buy',()=>send('gear',{item:id}),data.cash<g.price)}}else renderMarket(p);
}
function offers(){
 return [...Object.entries(data.breeds||{}).map(([id,h])=>({...h,key:'npc:'+id,id,source:'npc'})),...(data.listings||[]).map(h=>({...h,key:'ranch:'+h.id,source:'ranch'}))];
}
function stopPreview(){if(previewKey!==null){previewKey=null;previewMessage='';post('previewStop').catch(()=>{})}}
function choosePreview(h){if(previewKey===h.key)return;previewKey=h.key;previewMessage='Loading horse…';if(!h.model){previewMessage='Appearance not available';return}post('previewHorse',{key:h.key}).then(r=>{if(!r.ok&&previewKey===h.key){previewMessage='3D preview unavailable';const n=$('previewStatus');if(n)n.textContent=previewMessage}}).catch(()=>{if(previewKey===h.key){previewMessage='3D preview unavailable';const n=$('previewStatus');if(n)n.textContent=previewMessage}})}
function move(step){if(busy||!data||tab!=='market')return;const rows=offers();if(!rows.length)return;let i=rows.findIndex(h=>h.key===selectedKey);selectedKey=rows[(Math.max(0,i)+step+rows.length)%rows.length].key;render()}
function renderMarket(root){
 const rows=offers();let i=rows.findIndex(h=>h.key===selectedKey);if(i<0)i=0;
 if(!rows.length){stopPreview();el('p','No horses listed.',root);return}
 const h=rows[i];selectedKey=h.key;choosePreview(h);
 const a=card(root,h.name,h.source==='npc'?'Stable stock · Saddle sold separately':'Player ranch listing · '+h.sex);a.className='marketCard';
 const appearance=h.appearance||{};el('p','Coat: '+(appearance.coat||'See preview')+' · Pattern: '+(appearance.pattern||'See preview'),a);
 if(h.source==='ranch'){el('p',(h.age<345600?'Foal (adult model preview)':'Adult')+' · Certificate '+h.id,a)}
 const stats=[['Speed',h.genes?.speed],['Stamina',h.genes?.stamina],['Health genetics',h.genes?.health],['Condition',h.source==='npc'?100:h.health],['Training',h.source==='npc'?0:h.training]];
 for(const [name,value] of stats){const v=Number(value)||0;const label=el('div',undefined,a);label.className='statLabel';el('span',name,label);el('strong',Math.round(v)+'/100',label);const m=el('meter',undefined,a);m.min=0;m.max=100;m.value=v}
 const price=el('h2',money(h.price),a);price.className='horsePrice';
 if(h.source==='npc'){
  const l=el('label','Purchase ownership',a),select=el('select',undefined,l);el('option','Personal cash',select).value='';
  for(const c of data.companies||[])el('option',c.name,select).value=c.id;
  if([...select.options].some(x=>x.value===marketOwner))select.value=marketOwner;
  const buttons=el('div',undefined,a);button(buttons,'Buy mare',()=>send('buy',{breed:h.id,sex:'female',company:select.value}),!select.value&&data.cash<h.price);button(buttons,'Buy stallion',()=>send('buy',{breed:h.id,sex:'male',company:select.value}),!select.value&&data.cash<h.price);
  select.onchange=()=>{marketOwner=select.value;for(const b of buttons.querySelectorAll('button'))b.disabled=busy||(!select.value&&data.cash<h.price)};
 }else button(a,'Buy from ranch (cash)',()=>send('buyRanch',{facility:h.facility,id:h.id,price:h.price}),data.cash<h.price);
 const nav=el('div',undefined,root);nav.className='showroomNav';button(nav,'‹ Previous',()=>move(-1),rows.length<=1);
 const counter=el('span',(i+1)+' / '+rows.length,nav);counter.className='counter';button(nav,'Next ›',()=>move(1),rows.length<=1);
 button(nav,'↶ Rotate',()=>post('previewRotate',{direction:'left'}));button(nav,'Rotate ↷',()=>post('previewRotate',{direction:'right'}));
 const status=el('small',previewMessage,root);status.id='previewStatus';status.className='previewStatus';
}
$('tabs').onclick=e=>{if(e.target.dataset.tab&&!busy){tab=e.target.dataset.tab;render()}};$('refresh').onclick=()=>send('refresh');function close(){stopPreview();document.body.classList.remove('showroom');document.body.hidden=true;data=null;busy=false;selectedKey=null;clearTimeout(timer);post('close').catch(()=>{})}$('close').onclick=close;document.addEventListener('keydown',e=>{if(e.key==='Escape')close();else if(tab==='market'&&data&&!['INPUT','SELECT','TEXTAREA'].includes(document.activeElement?.tagName)){if(e.key==='ArrowLeft'){e.preventDefault();move(-1)}else if(e.key==='ArrowRight'){e.preventDefault();move(1)}}});window.addEventListener('message',e=>{const m=e.data;if(m.type==='view'){if(!data){tab='horses';selectedKey=null;marketOwner=''}data=m.data;busy=false;clearTimeout(timer);document.body.hidden=false;render()}else if(m.type==='notice'){$('status').textContent=m.message;busy=false;clearTimeout(timer);render()}else if(m.type==='previewStatus'&&m.key===previewKey){previewMessage=m.ok?'':m.message;const n=$('previewStatus');if(n)n.textContent=previewMessage}else if(m.type==='close'){previewKey=null;previewMessage='';selectedKey=null;document.body.classList.remove('showroom');document.body.hidden=true;data=null;busy=false;clearTimeout(timer)}});
