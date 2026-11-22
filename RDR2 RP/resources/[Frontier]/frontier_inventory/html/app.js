'use strict';

const el = (id) => document.getElementById(id);
const labels = ['player', 'storage'];
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

function showSlots(side, box) {
    const list = el(side + '-slots');
    el(side + '-count').textContent = weight(box.weight) + ' / ' + weight(box.weightLimit)
        + ' · ' + box.available + ' von ' + box.capacity + ' Plätzen frei';
    list.replaceChildren();
    for (let slot = 1; slot <= box.capacity; slot += 1) {
        const item = itemAt(box, slot);
        const heading = item ? item.name + ' × ' + item.quantity + ' · ' + weight(item.grams * item.quantity) : text.empty;
        const button = makeButton(slot + ' · ' + heading, () => {
            if (item) {
                selection = { side, slot };
                el('quantity').value = '1';
                el('target').value = '';
                render();
            } else if (selection) {
                el('target').value = String(slot);
            }
        }, Boolean(waiting || retry));
        button.setAttribute('aria-pressed', String(selection?.side === side && selection.slot === slot));
        list.append(button);
    }
}

function render() {
    if (!data) return;
    const disabled = Boolean(waiting || retry);
    el('storage').hidden = !data.storage;
    if (data.storage) el('storage-label').textContent = data.storage.label || 'Lager';
    for (const side of labels) if (data[side]) showSlots(side, data[side]);

    const box = selection && data[selection.side];
    const item = box && itemAt(box, selection.slot);
    el('selection').hidden = !item;
    if (item) {
        const personal = selection.side === 'player';
        el('item').textContent = item.name;
        el('description').textContent = item.description;
        el('quantity').max = item.quantity;
        el('recipient-field').hidden = !personal;
        el('recipient').replaceChildren();
        for (const player of rows(data.nearby)) el('recipient').append(new Option(player.name + ' (' + player.source + ')', player.source));
        const allowed = {
            move: true, split: item.quantity > 1, use: personal && item.usable,
            give: personal && item.transfer && el('recipient').options.length > 0,
            drop: personal && item.drop, store: personal && Boolean(data.storage) && item.store,
            retrieve: !personal,
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
    if (['move', 'split', 'store', 'retrieve'].includes(action)) {
        payload.target = Number(el('target').value);
        const side = action === 'store' ? 'storage' : action === 'retrieve' ? 'player' : selection.side;
        if (!Number.isInteger(payload.target) || payload.target < 1 || payload.target > data[side].capacity) {
            el('message').textContent = text.invalidTarget;
            return;
        }
    }
    if (action === 'give') payload.recipient = Number(el('recipient').value);
    if (selection.side === 'storage' && action === 'move') action = 'storageMove';
    if (selection.side === 'storage' && action === 'split') action = 'storageSplit';
    submit(action, payload);
}

function close() {
    nuicall('close').catch(() => { el('message').textContent = text.unavailable; });
}

window.addEventListener('message', ({ data: event }) => {
    if (event?.type === 'open') {
        data = event.data;
        selection = waiting = retry = null;
        el('message').textContent = '';
        document.body.hidden = false;
        render();
        el('close').focus();
    } else if (event?.type === 'close') {
        document.body.hidden = true;
        data = selection = waiting = retry = null;
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
