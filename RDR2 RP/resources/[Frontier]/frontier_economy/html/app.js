'use strict';

const element = (id) => document.getElementById(id);
const terminal = element('terminal');
const form = element('payment');
const history = element('history');
const amount = element('amount');
const recipient = element('recipient');
const reason = element('reason');
const account = element('account');
const retry = element('retry');
const tabs = [...document.querySelectorAll('[data-panel]')];

const text = {
    deposit: 'Bargeld einzahlen',
    withdraw: 'Bargeld auszahlen',
    transfer: 'Geld überweisen',
    invalidAmount: 'Gib einen positiven Betrag mit höchstens zwei Nachkommastellen ein.',
    invalidRecipient: 'Gib eine gültige Spieler-ID ein.',
    unavailable: 'Die Bank ist momentan nicht erreichbar.',
    loading: 'Anfrage läuft …',
    unknownCharacter: 'Unbekannter Charakter',
    incoming: 'Eingang',
    outgoing: 'Ausgang',
};

const kinds = {
    deposit: 'Einzahlung',
    withdraw: 'Auszahlung',
    transfer: 'Überweisung',
    credit: 'Gutschrift',
    debit: 'Abbuchung',
};

const money = new Intl.NumberFormat('de-DE', { style: 'currency', currency: 'USD', currencyDisplay: 'code' });
const clock = new Intl.DateTimeFormat('de-DE', { dateStyle: 'short', timeStyle: 'short' });
const currency = (minor) => money.format(minor / 100);

let panel;
let nextSequence;
let uiRequest = 0;
let pending;
let repeatOrder;
let blocked = false;

function enableControls() {
    const waiting = Boolean(pending);
    const canStartOrder = !waiting && !repeatOrder && !blocked;
    for (const button of tabs) {
        button.disabled = waiting || (button.dataset.panel !== 'history' && !canStartOrder);
        button.setAttribute('aria-pressed', button.dataset.panel === panel ? 'true' : 'false');
    }
    for (const item of form.elements) item.disabled = !canStartOrder;
    for (const id of ['account', 'reload', 'refresh']) element(id).disabled = waiting;
    retry.hidden = !repeatOrder || blocked;
    retry.disabled = waiting;
    terminal.setAttribute('aria-busy', waiting ? 'true' : 'false');
}

function showBalances(data) {
    element('character').textContent = data.name || text.unknownCharacter;
    element('cash').textContent = currency(data.cash);
    element('bank').textContent = currency(data.bank);
}

function clearHistory() {
    element('entries').replaceChildren();
    element('empty').hidden = true;
    element('history-scroll').hidden = true;
}

function showHistory(rows) {
    clearHistory();
    for (const entry of rows) {
        const row = document.createElement('tr');
        const date = new Date(entry.date.replace(/(\.\d{3})\d+Z$/, '$1Z'));
        const values = [
            Number.isNaN(date.getTime()) ? '–' : clock.format(date),
            kinds[entry.kind] || 'Buchung',
            entry.direction === 'credit' ? text.incoming : text.outgoing,
            currency(entry.amount),
            currency(entry.balance),
            entry.reason || '–',
        ];
        for (const value of values) {
            const cell = document.createElement('td');
            cell.textContent = value;
            row.append(cell);
        }
        element('entries').append(row);
    }
    element('empty').hidden = rows.length !== 0;
    element('history-scroll').hidden = rows.length === 0;
}

function showPanel(nextPanel) {
    panel = nextPanel;
    history.hidden = panel !== 'history';
    form.hidden = !['deposit', 'withdraw', 'transfer'].includes(panel);
    if (!form.hidden) {
        element('payment-title').textContent = text[panel];
        element('recipient-field').hidden = panel !== 'transfer';
        element('reason-field').hidden = panel !== 'transfer';
        recipient.required = panel === 'transfer';
    }
    enableControls();
}

async function nui(action, data = {}) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 5000);
    try {
        const result = await fetch('https://' + GetParentResourceName() + '/' + action, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data),
            signal: controller.signal,
        });
        if (!result.ok) throw new Error('NUI request failed');
        return await result.json();
    } finally {
        clearTimeout(timer);
    }
}

async function request(action, data, sequence) {
    if (pending || terminal.hidden) return;
    const order = { action, data, sequence, id: ++uiRequest };
    pending = order;
    element('status').textContent = text.loading;
    enableControls();

    try {
        const ack = await nui('bankRequest', { action, data, sequence, uiRequest: order.id });
        if (!ack.ok && pending === order) {
            pending = null;
            element('status').textContent = ack.message || text.unavailable;
            enableControls();
        }
    } catch {
        if (pending === order) {
            pending = null;
            if (sequence !== undefined) repeatOrder = order;
            element('status').textContent = text.unavailable;
            enableControls();
        }
    }
}

function readHistory() {
    clearHistory();
    request('history', account.value);
}

function applyResult(result) {
    const order = pending;
    if (!order || result.uiRequest !== order.id) return;
    pending = null;
    if (result.next !== undefined) nextSequence = result.next;
    if (order.sequence !== undefined) {
        blocked = Boolean(result.blocked);
        repeatOrder = result.retry || result.busy ? order : null;
        if (result.ok) form.reset();
    }
    if (result.balances) showBalances(result.balances);
    if (result.history) showHistory(Object.values(result.history));
    element('status').textContent = result.message || '';
    if (order.sequence === undefined && (repeatOrder || blocked) && !result.message) {
        element('status').textContent = 'Der letzte Buchungsstatus ist noch unklar. Prüfe den Verlauf.';
    }
    enableControls();
}

function close() {
    nui('bankClose').catch(() => {
        element('status').textContent = text.unavailable;
    });
}

window.addEventListener('message', ({ data }) => {
    if (!data) return;
    if (data.type === 'open') {
        pending = null;
        repeatOrder = null;
        blocked = false;
        form.reset();
        clearHistory();
        account.value = 'bank';
        nextSequence = data.next;
        showBalances(data.balances);
        showPanel(null);
        terminal.hidden = false;
        element('status').textContent = '';
        element('close').focus();
    } else if (data.type === 'close') {
        terminal.hidden = true;
        clearHistory();
        pending = null;
    } else if (data.type === 'result' && !terminal.hidden) {
        applyResult(data);
    }
});

document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && !terminal.hidden) {
        event.preventDefault();
        close();
    }
});
element('close').addEventListener('click', close);
element('refresh').addEventListener('click', () => request('balances'));
element('reload').addEventListener('click', readHistory);
account.addEventListener('change', readHistory);
retry.addEventListener('click', () => {
    if (repeatOrder) request(repeatOrder.action, repeatOrder.data, repeatOrder.sequence);
});

for (const button of tabs) {
    button.addEventListener('click', () => {
        showPanel(button.dataset.panel);
        if (panel === 'history') readHistory();
        else amount.focus();
    });
}

form.addEventListener('submit', (event) => {
    event.preventDefault();
    if (blocked || repeatOrder || !['deposit', 'withdraw', 'transfer'].includes(panel)) return;
    const data = { amount: amount.value.trim() };
    if (!/^[0-9]+(?:[.,][0-9]{1,2})?$/.test(data.amount) || !/[1-9]/.test(data.amount)) {
        element('status').textContent = text.invalidAmount;
        return;
    }
    if (panel === 'transfer') {
        data.recipient = recipient.value.trim();
        if (!/^[0-9]+$/.test(data.recipient) || !/[1-9]/.test(data.recipient)) {
            element('status').textContent = text.invalidRecipient;
            return;
        }
        data.reason = reason.value;
    }
    request(panel, data, nextSequence);
});

nui('bankReady').catch(() => {});
