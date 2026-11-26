'use strict';

const el = (id) => document.getElementById(id);
const labels = ['player', 'storage', 'belt'];
let drag=null;
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
const itemAt = (box, slot) => rows(box.slots).find((entry) => entry.slot === slot);

function makeButton(text, fn, disabled = false) {
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = text;
    button.disabled = disabled;
    button.addEventListener('click', fn);
    return button;
}

function meta(item){try{return typeof item.metadata==='string'?JSON.parse(item.metadata):item.metadata||{}}catch{return {}}}
function glyph(item){const id=item.item||'',s=(item.category||'').toLowerCase();if(item.beltEligible)return /pickaxe/.test(id)?'⛏':/axe/.test(id)?'🪓':/knife/.test(id)?'🔪':'⚒';if(/wood|plank/.test(id))return '🪵';if(/ore|coal|stone|clay|sand/.test(id))return '◆';if(/gold/.test(id))return '◈';if(/bread|meat|food|nahrung/.test(id+' '+s))return '🍞';if(/water|getränke/.test(id+' '+s))return '💧';if(/seed|herb|crop/.test(id))return '🌿';return '◉'}
function targetFor(side,item,qty,skip){
 const box=data[side];if(!box)return null;
 const entries=rows(box.slots);const same=entries.find(e=>e.slot!==skip&&!item.instance&&!e.instance&&e.item===item.item&&e.metadata===item.metadata&&e.quantity+qty<=(item.maxStack||1));
 if(same)return same.slot;
 for(let i=1;i<=box.capacity;i++)if(i!==skip&&!itemAt(box,i))return i;
 return null;
}
function transfer(from,to,target,qty,split=false){
 if(waiting||retry||!data)return;
 const item=itemAt(data[from.side],from.slot);if(!item)return;
 if(from.side===to&&from.slot===target)return;
 const actions={'player:player':split?'split':'move','storage:storage':split?'storageSplit':'storageMove','belt:belt':'beltMove','player:storage':'store','storage:player':'retrieve','player:belt':'beltStore','belt:player':'beltRetrieve'};
 const action=actions[from.side+':'+to];
 if(!action){el('message').textContent='Move items through your satchel first.';return}
 if(to==='belt'&&!item.beltEligible){el('message').textContent='Only tools can be placed on the belt.';return}
 if(action==='store'&&!item.store){el('message').textContent='This item cannot be stored.';return}
 if(!Number.isInteger(qty)||qty<1||qty>item.quantity){el('message').textContent=text.invalidQuantity;return}
 const dest=target||targetFor(to,item,qty,from.side===to?from.slot:null);
 if(!dest){el('message').textContent='No compatible destination slot available.';return}
 submit(action,{slot:from.slot,target:dest,quantity:qty});
}
function choose(side,slot){selection={side,slot};el('quantity').value='1';el('target').value='';render()}
function quick(side,slot,qty){const to=side==='player'?(data.storage?'storage':'belt'):'player';transfer({side,slot},to,null,qty)}
function hideContext(){el('contextMenu').hidden=true}
function showContext(ev,side,slot,item){
 choose(side,slot);const menu=el('contextMenu');menu.replaceChildren();menu.hidden=false;
 menu.style.left=Math.min(ev.clientX,window.innerWidth-220)+'px';menu.style.top=Math.min(ev.clientY,window.innerHeight-190)+'px';
 if(side==='player'&&item.usable||side==='belt'&&item.usable)menu.append(makeButton('Use',()=>{hideContext();itemAction('use')}));
 if(side==='player'&&data.storage&&item.store)menu.append(makeButton('Store full stack',()=>{hideContext();transfer({side,slot},'storage',null,item.quantity)}));
 if(side==='player'&&item.beltEligible&&data.belt)menu.append(makeButton('Equip on toolbelt',()=>{hideContext();transfer({side,slot},'belt',null,1)}));
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
        if(!item&&(filter||cat)&&side!=='belt')continue;
        const heading=item?item.name+' × '+item.quantity:text.empty;
        const button=makeButton('',()=>{},Boolean(waiting||retry));
        button.setAttribute('aria-label',slot+' · '+heading);
        button.setAttribute('aria-pressed',String(selection?.side===side&&selection.slot===slot));
        button.className='slot '+(item?'filled':'empty');
        const number=document.createElement('small');number.className='slot-number';number.textContent=slot;button.append(number);
        if(item){
            const icon=document.createElement('span');icon.className='item-icon';icon.textContent=glyph(item);
            const name=document.createElement('span');name.className='item-name';name.textContent=item.name;
            const count=document.createElement('span');count.className='item-count';count.textContent='×'+item.quantity;
            button.append(icon,name,count);const m=meta(item);
            if(Number.isFinite(m.condition)){const bar=document.createElement('progress');bar.max=100;bar.value=m.condition;button.append(bar)}
            button.title=item.name+' · '+weight(item.grams*item.quantity)+(m.quality!=null?' · Quality '+m.quality+'/100':'')+(m.condition!=null?' · Condition '+m.condition+'%':'');
            button.draggable=!waiting&&!retry;
            button.addEventListener('dragstart',ev=>{drag={side,slot,quantity:ev.shiftKey?1:item.quantity};ev.dataTransfer.effectAllowed='move';ev.dataTransfer.setData('text/plain',side+':'+slot)});
            button.addEventListener('dragend',()=>{drag=null;document.querySelectorAll('.over').forEach(e=>e.classList.remove('over'))});
            button.addEventListener('click',ev=>{hideContext();if(ev.shiftKey||ev.ctrlKey){quick(side,slot,ev.ctrlKey?1:item.quantity);return}choose(side,slot)});
            button.addEventListener('dblclick',()=>{if(item.usable&&(side==='player'||side==='belt')){selection={side,slot};itemAction('use')}});
            button.addEventListener('contextmenu',ev=>{ev.preventDefault();if(!waiting&&!retry)showContext(ev,side,slot,item)});
        }else button.addEventListener('click',()=>{if(selection)el('target').value=String(slot)});
        button.addEventListener('dragover',ev=>{if(drag&&!waiting&&!retry){ev.preventDefault();button.classList.add('over')}});
        button.addEventListener('dragleave',()=>button.classList.remove('over'));
        button.addEventListener('drop',ev=>{ev.preventDefault();button.classList.remove('over');if(drag){const d=drag;drag=null;transfer(d,side,slot,d.quantity)}});
        list.append(button);
    }
}

function render() {
    if (!data) return;
    const disabled = Boolean(waiting || retry);
    el('storage').hidden = !data.storage;
    el('belt').hidden = !data.belt;
    const previous=el('category').value;const cats=[...new Set(labels.flatMap(side=>rows(data[side]?.slots).map(i=>i.category).filter(Boolean)))].sort();el('category').replaceChildren(new Option('All categories',''),...cats.map(c=>new Option(c,c)));if(cats.includes(previous))el('category').value=previous;
    if (data.storage) el('storage-label').textContent = data.storage.label || 'Lager';
    for (const side of labels) if (data[side]) showSlots(side, data[side]);

    const box = selection && data[selection.side];
    const item = box && itemAt(box, selection.slot);
    el('selection').hidden = !item;
    if (item) {
        const personal = selection.side === 'player';
        el('item').textContent = item.name;
        el('description').textContent = item.description;
        const m=meta(item);el('details').textContent=[weight(item.grams*item.quantity),item.category,m.material,m.species,m.quality!=null?'Quality '+m.quality+'/100':null,m.condition!=null?'Condition '+m.condition+'%':null,m.uses!=null?'Durability '+m.uses+'/'+m.maxUses:null,m.manufacturer?'Made by '+m.manufacturer:null].filter(Boolean).join(' · ');
        el('quantity').value=Math.min(Number(el('quantity').value)||1,item.quantity);
        el('quantity').max = item.quantity;
        el('recipient-field').hidden = !personal;
        el('recipient').replaceChildren();
        for (const player of rows(data.nearby)) el('recipient').append(new Option(player.name + ' (' + player.source + ')', player.source));
        const allowed = {
            move: true, split: item.quantity > 1 && selection.side!=='belt', use: (personal||selection.side==='belt') && item.usable,
            give: personal && item.transfer && el('recipient').options.length > 0,
            drop: personal && item.drop, store: personal && Boolean(data.storage) && item.store,
            retrieve: selection.side==='storage', beltStore: personal&&item.beltEligible&&Boolean(data.belt), beltRetrieve: selection.side==='belt',
        };
        for (const button of buttons) {
            button.hidden = !allowed[button.dataset.action];
            button.disabled = disabled;
        }
    }
    const drops = rows(data.drops);
    el('ground').hidden = !drops.length;
    el('drops').replaceChildren(...drops.map((item) => makeButton(
        item.name + ' × ' + item.quantity + ' aufheben', () => submit('pickup', { drop: item.id }), disabled,
    )));
    el('retry').hidden = !retry;
    el('retry').disabled = Boolean(waiting);
    el('refresh').disabled = disabled;
    el('sort').disabled = disabled;
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
    } });
}

function itemAction(action) {
    if (!selection) return;
    const item = itemAt(data[selection.side], selection.slot);
    if (!item) return;
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
        if(!payload.target)payload.target=targetFor(side,item,payload.quantity,side===selection.side?selection.slot:null);
        if (!Number.isInteger(payload.target) || payload.target < 1 || payload.target > data[side].capacity) {
            el('message').textContent = text.invalidTarget;
            return;
        }
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
        selection = waiting = retry = null;hideContext();el('search').value='';el('category').value='';
        el('message').textContent = '';
        document.body.hidden = false;
        render();
        el('close').focus();
    } else if (event?.type === 'close') {
        document.body.hidden = true;
        data = selection = waiting = retry = null;hideContext();drag=null;
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
        event.preventDefault();
        close();
    }
});
nuicall('ready').catch(() => {});
