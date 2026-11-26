'use strict';
const byId = (id) => document.getElementById(id);
let state;
const rows = (value) => Object.values(value || {});
const types = { active: 'Aktiv', expired: 'Abgelaufen', cancelled: 'Storniert', closed: 'Abgeschlossen',
    stock: 'Warenprüfung', payment: 'Zahlung ausstehend', complete: 'Abgerechnet', rejected: 'Abgelehnt' };
async function nui(action, data = {}) {
    const response = await fetch('https://' + GetParentResourceName() + '/' + action, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data),
    });
    return response.json();
}
function status(message) { byId('status').textContent = message; }
async function submit(action, args) {
    try {
        const reply = await nui('action', { action, args });
        status(reply.ok ? 'Anfrage weitergeleitet. Ergebnis im Spielchat; danach aktualisieren.' : 'Ungültige Eingabe.');
    } catch { status('Der Handel ist momentan nicht erreichbar.'); }
}
function button(label, handler) {
    const node = document.createElement('button');
    node.type = 'button';
    node.textContent = label;
    node.addEventListener('click', handler);
    return node;
}
function record(list, text) {
    const node = document.createElement('article');
    node.textContent = text;
    list.append(node);
    return node;
}
function render() {
    if (!state) return;
    const filter = byId('filter').value;
    const offers = byId('offers'), sales = byId('sales');
    offers.replaceChildren(); sales.replaceChildren();
    const name = (id) => state.products[id] || id;
    const market = byId('requests'), contracts = byId('contracts'), deliveries = byId('deliveries'), prices = byId('prices');
    market.replaceChildren(); contracts.replaceChildren(); deliveries.replaceChildren(); prices.replaceChildren();
    for (const row of rows(state.offers)) {
        if (filter && filter !== row.item_id) continue;
        const labels = { stock: 'Warenprüfung', open: 'Offen', return: 'Rückgabe läuft', closed: 'Abgeschlossen', rejected: 'Abgelehnt' };
        const node = record(offers, name(row.item_id) + ' × ' + row.available + ' | ' + row.unit_minor + ' Cent | ' + labels[row.state] + ' ');
        if (Number(row.buyable)) {
            const count = document.createElement('input');
            count.type = 'number'; count.min = '1'; count.max = String(row.available); count.value = '1';
            count.setAttribute('aria-label','Kaufmenge');
            node.append(count,button('Kaufen',() => {
                if (!count.checkValidity()) { count.reportValidity(); return; }
                submit('buy',[row.id,count.value]);
            }));
        }
        if (Number(row.cancellable)) node.append(button('Angebot stornieren',() => submit('cancelOffer',[row.id])));
    }
    for (const row of rows(state.sales)) {
        const node = record(sales,name(row.item_id) + ' × ' + row.quantity + ' | ' +
            (row.claimed_at ? 'Abgeholt' : row.state === 'reverse' ? 'Warenrückgabe' : types[row.state]) + ' ');
        if (Number(row.claimable)) node.append(button('Kauf abholen',() => submit('claimSale',[row.id])));
    }
    for (const row of rows(state.requests)) {
        if (filter && filter !== row.item_id) continue;
        const node = record(market, name(row.item_id) + ' × ' + row.remaining + ' | ' + row.price_minor + ' Cent je Stück ');
        if (Number(row.available)) node.append(button('Annehmen', () => submit('accept', [row.id, String(row.price_minor)])));
        if (Number(row.cancellable)) node.append(button('Stornieren', () => submit('cancel', [row.id])));
    }
    for (const row of rows(state.contracts)) {
        const node = record(contracts, name(row.item_id) + ' | ' + types[row.state] + ' | Offen: ' + row.remaining + ' | Frist ' + row.due_at + ' UTC ');
        if (Number(row.cancellable)) node.append(button('Vertrag stornieren', () => submit('cancelContract', [row.id])));
        if (Number(row.deliverable)) {
            const count = document.createElement('input');
            count.type = 'number'; count.min = '1'; count.max = String(row.remaining); count.value = '1';
            count.setAttribute('aria-label', 'Liefermenge');
            node.append(count, button('Liefern', () => {
                if (!count.checkValidity()) { count.reportValidity(); return; }
                submit('deliver', [row.id, count.value]);
            }));
        }
    }
    for (const row of rows(state.deliveries)) {
        const node = record(deliveries, name(row.item_id) + ' × ' + row.quantity + ' | ' + (row.claimed_at ? 'Abgeholt' : types[row.state]) + ' ');
        if (Number(row.claimable)) node.append(button('Abholen', () => submit('claim', [row.id])));
    }
    for (const row of rows(state.prices)) {
        if (filter && filter !== row.item_id) continue;
        record(prices, name(row.item_id) + ' | ' + row.price_minor + ' Cent | ' + row.quoted_at + ' UTC');
    }
    for (const node of [market, contracts, deliveries, prices, offers, sales]) if (!node.childElementCount) record(node, 'Keine Einträge.');
}
window.addEventListener('message', ({ data: event }) => {
    if (event?.type === 'close') { document.body.hidden = true; state = null; return; }
    if (event?.type === 'status') { status(event.message); return; }
    if (event?.type !== 'snapshot') return;
    const oldFilter = byId('filter').value;
    state = event.data;
    const options = (values) => Object.entries(values).map(([id,label]) => new Option(label,id));
    byId('market').replaceChildren(...options(state.markets));
    byId('market').value = state.market;
    byId('product').replaceChildren(...options(state.products));
    byId('filter').replaceChildren(new Option('Alle Waren',''),...options(state.products));
    if (oldFilter && state.products[oldFilter]) byId('filter').value = oldFilter;
    document.body.hidden = false;
    status(state.available ? '' : 'Marktdaten sind momentan unvollständig.');
    render();
});
const close = () => nui('close').catch(() => status('Schließen fehlgeschlagen.'));
const refresh = () => nui('refresh', { market: byId('market').value }).catch(() => status('Aktualisieren fehlgeschlagen.'));
byId('close').addEventListener('click',close);
byId('refresh').addEventListener('click',refresh);
byId('market').addEventListener('change',refresh);
byId('filter').addEventListener('change',render);
document.addEventListener('keydown',(event) => { if (event.key === 'Escape' && !document.body.hidden) close(); });
byId('create').addEventListener('submit',(event) => {
    event.preventDefault();
    const args = [byId('market').value,byId('product').value,byId('quantity').value,byId('price').value];
    if (byId('cap').value) {
        if (Number(byId('cap').value) < Number(byId('price').value)) {
            status('Die Preisobergrenze darf nicht unter dem Startpreis liegen.');
            return;
        }
        args.push(byId('cap').value);
    }
    submit('create',args);
});
byId('sell').addEventListener('click',() => {
    if (!byId('quantity').reportValidity() || !byId('price').reportValidity()) return;
    submit('sell',[byId('market').value,byId('product').value,byId('quantity').value,byId('price').value]);
});
nui('ready').catch(() => {});

byId('propertyMarket').addEventListener('click',()=>nui('propertyMarket').catch(()=>status('Grundstücksmarkt nicht erreichbar.')));

let tradePage='market';
function showTradePage(page){tradePage=page;for(const panel of document.querySelectorAll('[data-page]'))panel.hidden=panel.dataset.page!==page;for(const b of document.querySelectorAll('[data-trade]'))b.setAttribute('aria-pressed',String(b.dataset.trade===page));document.querySelector('main').scrollTop=0}
for(const b of document.querySelectorAll('[data-trade]'))b.addEventListener('click',()=>showTradePage(b.dataset.trade));showTradePage(tradePage);
