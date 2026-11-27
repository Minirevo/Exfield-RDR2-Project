'use strict';

const el = (id) => document.getElementById(id);
const labels = ['player', 'storage', 'belt', 'equipment'];
let drag=null, suppressClick=false;
const buttons = [...document.querySelectorAll('[data-action]')];
const kg = new Intl.NumberFormat('de-DE', { maximumFractionDigits: 3 });
const weight = (grams) => kg.format(grams / 1000) + ' kg';
let data, selection, waiting, retry;
let counter = 0;

const text = {
    empty: 'Leer',
    invalidQuantity: 'Gib eine ganze, positive Menge ein.',
    invalidTarget: 'Gib einen gültigen Zielplatz ein.',
    unavailable: 'Die Oberfläche konnte den Auftrag nicht bestätigen.',
    pending: 'Inventar wird aktualisiert …',
};

async function nuicall(action, body = {}) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 5000);
    try {
        const response = await fetch('https://' + GetParentResourceName() + '/' + action, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
            signal: controller.signal,
        });
        if (!response.ok) throw new Error('NUI unavailable');
        return await response.json();
    } finally {
        clearTimeout(timer);
    }
}

const rows = (list) => Object.values(list || {});
const itemAt = (box, slot) => rows(box?.slots).find((entry) => Number(entry.slot) === Number(slot));

function makeButton(text, fn, disabled = false) {
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = text;
    button.disabled = disabled;
    button.addEventListener('click', fn);
    return button;
}

function meta(item){try{return typeof item.metadata==='string'?JSON.parse(item.metadata):item.metadata||{}}catch{return {}}}
function canEquip(item){return Boolean(item?.instance&&/^gather_(axe|pickaxe|shovel|pan|knife|rod)_/.test(item.item)&&Number(meta(item).uses)>0)}
function isEquipped(item){return !!item?.instance&&data?.equipped?.instance===item.instance}
function glyph(item){const id=item.item||'',s=(item.category||'').toLowerCase();const freightIcons={logistics_frame:'▤',logistics_wheel:'☸',logistics_axle:'↔',logistics_fittings:'⚙',logistics_harness:'♧',logistics_lockpick:'⚿',property_wagon_bench:'▥'};if(freightIcons[id])return freightIcons[id];if(item.beltEligible)return /pickaxe/.test(id)?'⛏':/axe/.test(id)?'🪓':/knife/.test(id)?'🔪':'⚒';if(/wood|plank/.test(id))return '🪵';if(/ore|coal|stone|clay|sand/.test(id))return '◆';if(/gold/.test(id))return '◈';if(/bread|meat|food|nahrung/.test(id+' '+s))return '🍞';if(/water|getränke/.test(id+' '+s))return '💧';if(/seed|herb|crop/.test(id))return '🌿';return '◉'}
function stackCompatible(a,b){
 return Boolean(a&&b&&!a.instance&&!b.instance&&a.item===b.item&&a.metadata===b.metadata&&Number(a.maxStack)>1);
}
function targetFor(side,item,qty,skip,emptyOnly=false){
 const box=data[side];if(!box)return null;
 const entries=rows(box.slots);
 if(side==='equipment'){
  const allowed=item.classification==='longgun'?[1]:item.classification==='sidearm'?[2]:item.classification==='ammo'?[3,4]:[];
  return allowed.find(i=>i!==skip&&(!itemAt(box,i)||(!emptyOnly&&stackCompatible(item,itemAt(box,i))&&itemAt(box,i).quantity<30)))||null;
 }
 if(!emptyOnly){
  const same=entries.find(e=>Number(e.slot)!==skip&&stackCompatible(item,e)&&e.quantity+qty<=Number(item.maxStack));
  if(same)return Number(same.slot);
 }
 for(let i=1;i<=box.capacity;i++)if(i!==skip&&!itemAt(box,i))return i;
 return null;
}
function transfer(from,to,target,qty,split=false){
 if(waiting||retry||!data)return;
 const item=itemAt(data[from.side],from.slot);if(!item)return;
 if(from.side===to&&from.slot===target)return;
 const actions={'player:player':split?'split':'move','storage:storage':split?'storageSplit':'storageMove','belt:belt':'beltMove','player:storage':'store','storage:player':'retrieve','player:belt':'beltStore','belt:player':'beltRetrieve','player:equipment':'equipmentStore','equipment:player':'equipmentRetrieve','equipment:equipment':'equipmentMove'};
 const action=actions[from.side+':'+to];
 if(!action){el('message').textContent='Move items through your satchel first.';return}
 if(to==='belt'&&!item.beltEligible){el('message').textContent='Only tools can be placed on the belt.';return}
 if(action==='store'&&!item.store){el('message').textContent='This item cannot be stored.';return}
 if(!Number.isInteger(qty)||qty<1||qty>item.quantity){el('message').textContent=text.invalidQuantity;return}
 const dest=target||targetFor(to,item,qty,from.side===to?from.slot:null,split);
 if(to==='equipment'&&dest){
  const cls=item.classification,expected=dest===1?'longgun':dest===2?'sidearm':'ammo';
  if(cls!==expected){el('message').textContent='Wrong equipment slot.';return}
  if(expected==='ammo')qty=Math.min(qty,30-(itemAt(data.equipment,dest)?.quantity||0));
  if(qty<1){el('message').textContent='Quick slot full.';return}
 }
 if(!dest){el('message').textContent='No compatible destination slot available.';return}
 const existing=itemAt(data[to],dest);
 if(existing){
  if(split||!stackCompatible(item,existing)){el('message').textContent='These items cannot be stacked.';return}
  qty=Math.min(qty,Number(item.maxStack)-existing.quantity);
  if(qty<=0){el('message').textContent='Destination stack is already full.';return}
 }
 submit(action,{slot:from.slot,target:dest,quantity:qty});
}
function choose(side,slot){
 selection={side,slot};el('quantity').value=String(itemAt(data[side],slot)?.quantity||1);el('target').value='';
 el('message').textContent='';
 for(const node of document.querySelectorAll('.slot'))node.setAttribute('aria-pressed',String(node.dataset.side===side&&Number(node.dataset.slot)===slot));
 renderSelection();
}
function slotClick(ev,side,slot,item){
 if(suppressClick||waiting||retry)return;
 hideContext();
 if(item&&(ev.shiftKey||ev.ctrlKey)){quick(side,slot,ev.ctrlKey?1:item.quantity);return}
 const from=selection&&itemAt(data[selection.side],selection.slot);
 if(from&&(selection.side!==side||selection.slot!==slot)&&(!item||stackCompatible(from,item))){
  transfer(selection,side,slot,Number(el('quantity').value));return;
 }
 if(item)choose(side,slot);
 else {selection=null;render();}
}
function clearDrag(){
 if(drag?.ghost)drag.ghost.remove();
 drag=null;
 document.querySelectorAll('.over,.drag-source').forEach(e=>e.classList.remove('over','drag-source'));
}
function slotUnder(x,y){
 const node=document.elementFromPoint(x,y)?.closest('.slot');
 return node&&!node.disabled?node:null;
}
function beginDrag(ev,side,slot,item,node){
 if(ev.button!==0||waiting||retry||ev.ctrlKey||ev.shiftKey)return;
 clearDrag();suppressClick=false;
 drag={side,slot,quantity:item.quantity,x:ev.clientX,y:ev.clientY,node,item,active:false};
}
document.addEventListener('mousemove',ev=>{
 if(!drag)return;
 if(!drag.active&&Math.hypot(ev.clientX-drag.x,ev.clientY-drag.y)<5)return;
 if(!drag.active){
  drag.active=true;drag.node.classList.add('drag-source');const ghost=document.createElement('div');ghost.className='drag-ghost';
  ghost.textContent=glyph(drag.item)+' '+drag.item.name+' ×'+drag.quantity;document.body.append(ghost);drag.ghost=ghost;
 }
 drag.ghost.style.left=(ev.clientX+12)+'px';drag.ghost.style.top=(ev.clientY+12)+'px';
 document.querySelectorAll('.over').forEach(e=>e.classList.remove('over'));slotUnder(ev.clientX,ev.clientY)?.classList.add('over');
});
document.addEventListener('mouseup',ev=>{
 if(!drag||ev.button!==0)return;
 const d=drag,target=slotUnder(ev.clientX,ev.clientY);clearDrag();
 if(!d.active)return;
 suppressClick=true;setTimeout(()=>{suppressClick=false},250);
 if(target)transfer(d,target.dataset.side,Number(target.dataset.slot),d.quantity);
});
window.addEventListener('blur',clearDrag);
function quick(side,slot,qty){const item=itemAt(data[side],slot);const to=side==='player'?(data.storage?'storage':(['longgun','sidearm','ammo'].includes(item?.classification)&&data.equipment?'equipment':'belt')):'player';transfer({side,slot},to,null,qty)}
function hideContext(){el('contextMenu').hidden=true}
function showContext(ev,side,slot,item){
 choose(side,slot);const menu=el('contextMenu');menu.replaceChildren();menu.hidden=false;
 menu.style.left=Math.min(ev.clientX,window.innerWidth-220)+'px';menu.style.top=Math.min(ev.clientY,window.innerHeight-190)+'px';
 if(side==='player'&&item.usable||side==='belt'&&item.usable)menu.append(makeButton('Use',()=>{hideContext();itemAction('use')}));
 if(side==='player'&&data.storage&&item.store)menu.append(makeButton('Store full stack',()=>{hideContext();transfer({side,slot},'storage',null,item.quantity)}));
 if(side!=='storage'&&canEquip(item))menu.append(makeButton(isEquipped(item)?'Put away':'Equip tool',()=>{hideContext();submit('equip',{side,slot})}));
 if(side==='player'&&item.beltEligible&&data.belt)menu.append(makeButton('Move to toolbelt',()=>{hideContext();transfer({side,slot},'belt',null,1)}));
 if(side==='player'&&data.equipment&&['longgun','sidearm','ammo'].includes(item.classification))menu.append(makeButton('Move to equipment',()=>{hideContext();transfer({side,slot},'equipment',null,item.quantity)}));
 if(side!=='player')menu.append(makeButton('Return to satchel',()=>{hideContext();transfer({side,slot},'player',null,item.quantity)}));
 if(item.quantity>1&&side!=='belt')menu.append(makeButton('Split stack',()=>{hideContext();el('quantity').value=String(Math.floor(item.quantity/2));itemAction('split')}));
 if(side==='player'&&item.drop)menu.append(makeButton('Drop selected quantity',()=>{hideContext();itemAction('drop')}));
}
function showSlots(side, box) {
    const list = el(side + '-slots');
    el(side + '-count').textContent = weight(box.weight) + ' / ' + weight(box.weightLimit)
        + ' · ' + box.available + ' von ' + box.capacity + ' Plätzen frei';
    list.replaceChildren();
    const filter=el('search').value.toLowerCase().trim(),cat=el('category').value;
    for (let slot=1;slot<=box.capacity;slot++){
        const item=itemAt(box,slot);
        if(item&&(filter&&!((item.name||'')+' '+(item.item||'')).toLowerCase().includes(filter)||cat&&item.category!==cat))continue;
        if(!item&&(filter||cat)&&side!=='belt'&&side!=='equipment')continue;
        const heading=item?item.name+' × '+item.quantity:text.empty;
        const button=makeButton('',()=>{},Boolean(waiting||retry));
        button.setAttribute('aria-label',slot+' · '+heading);
        button.setAttribute('aria-pressed',String(selection?.side===side&&selection.slot===slot));
        button.className='slot '+(item?'filled':'empty');button.dataset.side=side;button.dataset.slot=String(slot);
        const number=document.createElement('small');number.className='slot-number';number.textContent=side==='equipment'?['Long gun','Sidearm','Quick ammo 1','Quick ammo 2'][slot-1]:slot;button.append(number);
        if(item){
            if(isEquipped(item)){button.classList.add('equipped');const active=document.createElement('small');active.className='equipped-label';active.textContent='Equipped';button.append(active)}
            const icon=document.createElement('span');icon.className='item-icon';icon.textContent=glyph(item);
            const name=document.createElement('span');name.className='item-name';name.textContent=item.name;
            const count=document.createElement('span');count.className='item-count';count.textContent='×'+item.quantity;
            button.append(icon,name,count);const m=meta(item);
            if(Number.isFinite(m.condition)){const bar=document.createElement('progress');bar.max=100;bar.value=m.condition;button.append(bar)}
            button.title=item.name+' · '+weight(item.grams*item.quantity)+(m.quality!=null?' · Quality '+m.quality+'/100':'')+(m.condition!=null?' · Condition '+m.condition+'%':'');
            button.addEventListener('mousedown',ev=>beginDrag(ev,side,slot,item,button));
            button.addEventListener('dblclick',()=>{if(!suppressClick&&(side==='player'||side==='belt')){if(canEquip(item))submit('equip',{side,slot});else if(item.usable){selection={side,slot};itemAction('use')}}});
            button.addEventListener('contextmenu',ev=>{ev.preventDefault();clearDrag();if(!waiting&&!retry)showContext(ev,side,slot,item)});
        }
        button.addEventListener('click',ev=>slotClick(ev,side,slot,item));
        list.append(button);
    }
}

function render() {
    if (!data) return;
    const disabled = Boolean(waiting || retry);
    el('storage').hidden = !data.storage;
    el('belt').hidden = !data.belt;
    el('equipment').hidden = !data.equipment;
    const previous=el('category').value;const cats=[...new Set(labels.flatMap(side=>rows(data[side]?.slots).map(i=>i.category).filter(Boolean)))].sort();el('category').replaceChildren(new Option('All categories',''),...cats.map(c=>new Option(c,c)));if(cats.includes(previous))el('category').value=previous;
    if (data.storage) el('storage-label').textContent = data.storage.label || 'Lager';
    for (const side of labels) if (data[side]) showSlots(side, data[side]);

    renderSelection();
    const drops = rows(data.drops);
    el('ground').hidden = !drops.length;
    el('drops').replaceChildren(...drops.map((item) => makeButton(item.name + ' × ' + item.quantity + ' aufheben', () => submit('pickup', { drop: item.id }), disabled)));
    el('retry').hidden = !retry;el('retry').disabled = Boolean(waiting);el('refresh').disabled = disabled;el('sort').disabled = disabled;
}
function renderSelection(){
    const disabled=Boolean(waiting||retry);
    const box = selection && data[selection.side];
    const item = box && itemAt(box, selection.slot);
    el('selection').hidden = !item;
    if (item) {
        const personal = selection.side === 'player';
        el('item').textContent = item.name;
        el('description').textContent = item.description;
        const m=meta(item);el('details').textContent=[weight(item.grams*item.quantity),item.category,m.material,m.species,m.quality!=null?'Quality '+m.quality+'/100':null,m.condition!=null?'Condition '+m.condition+'%':null,m.uses!=null?'Durability '+m.uses+'/'+m.maxUses:null,m.manufacturer?'Made by '+m.manufacturer:null,['longgun','sidearm'].includes(item.classification)&&item.instance?'Serial '+item.instance:null,['longgun','sidearm'].includes(item.classification)?'Stored rounds '+(m.loaded||0):null].filter(Boolean).join(' · ');
        el('quantity').value=Math.min(Number(el('quantity').value)||1,item.quantity);
        el('quantity').max = item.quantity;
        el('recipient-field').hidden = !personal;
        el('recipient').replaceChildren();
        for (const player of rows(data.nearby)) el('recipient').append(new Option(player.name + ' (' + player.source + ')', player.source));
        const allowed = {
            equip: selection.side!=='storage'&&canEquip(item), move: selection.side!=='equipment', split: item.quantity > 1 && selection.side!=='belt'&&selection.side!=='equipment', use: (personal||selection.side==='belt') && item.usable,
            give: personal && item.transfer && el('recipient').options.length > 0,
            drop: personal && item.drop, store: personal && Boolean(data.storage) && item.store,
            retrieve: selection.side==='storage', beltStore: personal&&item.beltEligible&&Boolean(data.belt), beltRetrieve: selection.side==='belt',
        };
        for (const button of buttons) {
            button.hidden = !allowed[button.dataset.action];
            button.disabled = disabled;
            if(button.dataset.action==='equip')button.textContent=isEquipped(item)?'Put away':'Equip tool';
        }
    }

}

async function send(order) {
    if (waiting || !data) return;
    waiting = order;
    el('message').textContent = text.pending;
    render();
    try {
        const ack = await nuicall('action', order);
        if (!ack.ok && waiting === order) {
            waiting = null;
            el('message').textContent = text.unavailable;
            render();
        }
    } catch {
        if (waiting !== order) return;
        waiting = null;
        retry = order;
        el('message').textContent = text.unavailable;
        render();
    }
}

function submit(action, payload) {
    if (retry || waiting) return;
    send({ sequence: ++counter, action, data: {
        ...payload,
        revision: data.player.revision,
        storageRevision: data.storage?.revision,
        beltRevision: data.belt?.revision,
        equipmentRevision: data.equipment?.revision,
    } });
}

function itemAction(action) {
    if (!selection || waiting || retry) return;
    const item = itemAt(data[selection.side], selection.slot);
    if (!item) return;
    if(action==='equip'){submit('equip',{side:selection.side,slot:selection.slot});return}
    const payload = { slot: selection.slot };
    if (action !== 'use') {
        payload.quantity = Number(el('quantity').value);
        if (!Number.isInteger(payload.quantity) || payload.quantity < 1 || payload.quantity > item.quantity) {
            el('message').textContent = text.invalidQuantity;
            return;
        }
    }
    if (['move', 'split', 'store', 'retrieve','beltStore','beltRetrieve'].includes(action)) {
        payload.target = Number(el('target').value);
        const side = action === 'store' ? 'storage' : action === 'retrieve'||action==='beltRetrieve' ? 'player' : action==='beltStore'?'belt':selection.side;
        if(action==='split'&&payload.quantity>=item.quantity){payload.quantity=Math.floor(item.quantity/2);el('quantity').value=String(payload.quantity)}
        if(!payload.target)payload.target=targetFor(side,item,payload.quantity,side===selection.side?selection.slot:null,action==='split');
        if (!Number.isInteger(payload.target) || payload.target < 1 || payload.target > data[side].capacity) {
            el('message').textContent = text.invalidTarget;
            return;
        }
    }
    if (['move','split','store','retrieve','beltStore','beltRetrieve'].includes(action)){
        const side=action==='store'?'storage':action==='retrieve'||action==='beltRetrieve'?'player':action==='beltStore'?'belt':selection.side;
        transfer(selection,side,payload.target,payload.quantity,action==='split');return;
    }
    if (action === 'give') payload.recipient = Number(el('recipient').value);
    if (selection.side === 'storage' && action === 'move') action = 'storageMove';
    if (selection.side === 'storage' && action === 'split') action = 'storageSplit';
    if(selection.side==='belt'&&action==='move')action='beltMove';
    if(selection.side==='belt'&&action==='use')action='beltUse';
    submit(action, payload);
}

function close() {
    nuicall('close').catch(() => { el('message').textContent = text.unavailable; });
}

window.addEventListener('message', ({ data: event }) => {
    if (event?.type === 'open') {
        data = event.data;
        clearDrag();suppressClick=false;selection = waiting = retry = null;hideContext();el('search').value='';el('category').value='';
        el('message').textContent = '';
        document.body.hidden = false;
        render();
        el('close').focus();
    } else if (event?.type === 'close') {
        document.body.hidden = true;
        clearDrag();suppressClick=false;data = selection = waiting = retry = null;hideContext();
        for (const side of labels) el(side + '-slots').replaceChildren();
    } else if (event?.type === 'result' && waiting && event.sequence === waiting.sequence) {
        retry = event.retry ? waiting : null;
        waiting = null;
        if (event.snapshot) data = event.snapshot;
        if (event.ok) selection = null;
        el('message').textContent = event.message || '';
        render();
    }
});

el('close').addEventListener('click', close);
el('search').addEventListener('input',render);el('category').addEventListener('change',render);
for(const [id,fn] of [['one',()=>1],['half',n=>Math.max(1,Math.floor(n/2))],['all',n=>n]])el(id).onclick=()=>{const item=selection&&itemAt(data[selection.side],selection.slot);if(item)el('quantity').value=fn(item.quantity)};
document.addEventListener('pointerdown',ev=>{if(!el('contextMenu').contains(ev.target))hideContext()});
el('sort').addEventListener('click', () => submit('sort', {}));
el('refresh').addEventListener('click', () => submit('refresh', {}));
el('retry').addEventListener('click', () => { if (retry) send(retry); });
for (const button of buttons) button.addEventListener('click', () => itemAction(button.dataset.action));
document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && !document.body.hidden) {
        if(drag?.active){clearDrag();return}
        if(!el('contextMenu').hidden){hideContext();return}
        event.preventDefault();
        close();
    }
});
nuicall('ready').catch(() => {});
