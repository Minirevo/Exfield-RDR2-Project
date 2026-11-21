// Run from the resource directory with Node and Playwright.
'use strict';

const assert = require('node:assert/strict');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

async function main() {
    const browser = await chromium.launch({
        executablePath: process.env.BROWSER_EXECUTABLE || undefined,
        headless: true,
    });
    try {
        const page = await browser.newPage({ viewport: { width: 1100, height: 850 } });
        const commands = [];
        const failures = [];
        page.on('pageerror', (error) => failures.push(error.message));
        await page.addInitScript(() => { window.GetParentResourceName = () => 'frontier_economy'; });
        await page.route('https://nui.local/**', async (route) => {
            const file = new URL(route.request().url()).pathname.split('/').pop() || 'index.html';
            await route.fulfill({ path: path.join(process.cwd(), 'html', file) });
        });
        await page.route('https://frontier_economy/**', async (route) => {
            const request = route.request();
            const headers = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'POST, OPTIONS' };
            if (request.method() === 'OPTIONS') {
                await route.fulfill({ status: 204, headers });
                return;
            }
            const command = new URL(request.url()).pathname.slice(1);
            commands.push({ command, payload: request.postDataJSON() });
            await route.fulfill({ json: { ok: true }, headers });
            if (command === 'bankClose') await send({ type: 'close' });
        });
        async function send(data) {
            await page.evaluate((payload) => window.postMessage(payload, '*'), data);
        }
        let observed = 0;
        async function waitCommand(action) {
            await page.waitForFunction(
                (name) => document.querySelector('#status').textContent.startsWith(name), 'Anfrage',
            );
            await new Promise((resolve, reject) => {
                const end = Date.now() + 3000;
                const check = () => {
                    if (commands.length > observed && commands.at(-1)?.payload.action === action) {
                        observed = commands.length;
                        resolve();
                    } else if (Date.now() >= end) reject(new Error('Missing NUI command: ' + action));
                    else setTimeout(check, 10);
                };
                check();
            });
            return commands.at(-1).payload;
        }
        const button = (name) => page.getByRole('button', { name, exact: true });
        const message = () => page.locator('#status').textContent();
        const visible = () => page.locator('#terminal').waitFor({ state: 'visible' });

        await page.goto('https://nui.local/index.html');
        assert(await page.locator('#terminal').isHidden());
        await send({ type: 'open', next: 1, balances: { name: 'Ada Holt', cash: 12500, bank: 145000 } });
        await visible();
        assert.equal(await page.locator('#character').textContent(), 'Ada Holt');
        assert.equal(await page.locator('#terminal').evaluate((node) => getComputedStyle(node).backgroundColor), 'rgb(0, 0, 0)');
        assert.match(await page.locator('#cash').textContent(), /125,00.*USD/);

        await button('Einzahlen').click();
        await page.locator('#amount').fill('1,234');
        await button('Auftrag ausführen').click();
        assert.match(await message(), /Nachkommastellen/);
        assert.equal(commands.filter(({ command }) => command === 'bankRequest').length, 0);

        await page.locator('#amount').fill('25,00');
        await button('Auftrag ausführen').click();
        const deposit = await waitCommand('deposit');
        assert.equal(deposit.sequence, 1);
        assert.deepEqual(deposit.data, { amount: '25,00' });
        await send({ type: 'result', uiRequest: deposit.uiRequest, ok: false, retry: true,
            message: 'Die Buchung konnte nicht bestätigt werden.' });
        await button('Denselben Auftrag wiederholen').click();
        const repeat = await waitCommand('deposit');
        assert.equal(repeat.sequence, 1);
        assert.deepEqual(repeat.data, deposit.data);
        assert.notEqual(repeat.uiRequest, deposit.uiRequest);
        await send({ type: 'result', uiRequest: repeat.uiRequest, next: 2, ok: true,
            message: 'Einzahlung erfolgreich.', balances: { name: 'Ada Holt', cash: 10000, bank: 147500 } });
        await page.waitForFunction(() => document.getElementById('status').textContent === 'Einzahlung erfolgreich.');
        assert.match(await page.locator('#cash').textContent(), /100,00.*USD/);

        await button('Überweisen').click();
        await page.locator('#recipient').fill('12');
        await page.locator('#amount').fill('12,10');
        await page.locator('#reason').fill('Miete');
        await button('Auftrag ausführen').click();
        const transfer = await waitCommand('transfer');
        assert.equal(transfer.sequence, 2);
        assert.deepEqual(transfer.data, { recipient: '12', amount: '12,10', reason: 'Miete' });
        await send({ type: 'result', uiRequest: transfer.uiRequest, next: 3, ok: false,
            message: 'Der Empfänger ist nicht online.' });
        await page.waitForFunction(() => document.getElementById('status').textContent.includes('nicht online'));

        await button('Verlauf').click();
        const bank = await waitCommand('history');
        assert.equal(bank.data, 'bank');
        await send({ type: 'result', uiRequest: bank.uiRequest, ok: true, history: [{
            date: '2026-11-21T12:30:00.000000Z', kind: 'transfer', direction: 'debit',
            amount: 2500, balance: 147500, reason: '<img src=x onerror=alert(1)>',
        }] });
        await page.locator('#entries tr').waitFor();
        assert.equal(await page.locator('#entries img').count(), 0);
        assert.match(await page.locator('#entries').textContent(), /Ausgang.*25,00/);
        if (process.env.BANK_TEST_SCREENSHOT) await page.screenshot({ path: process.env.BANK_TEST_SCREENSHOT });

        await page.selectOption('#account', 'cash');
        const cash = await waitCommand('history');
        assert.equal(cash.data, 'cash');
        await send({ type: 'result', uiRequest: cash.uiRequest, ok: true, history: {} });
        await page.getByText('Für dieses Konto liegen keine Buchungen vor.').waitFor();
        await page.keyboard.press('Escape');
        await page.locator('#terminal').waitFor({ state: 'hidden' });
        await send({ type: 'open', next: 1, balances: { name: 'Ada Holt', cash: 10000, bank: 147500 } });
        await visible();
        await page.getByRole('button', { name: /Schließen/ }).click();
        await page.locator('#terminal').waitFor({ state: 'hidden' });
        assert.deepEqual(failures, []);
        console.log('Frontier banking NUI browser contract passed');
    } finally {
        await browser.close();
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
