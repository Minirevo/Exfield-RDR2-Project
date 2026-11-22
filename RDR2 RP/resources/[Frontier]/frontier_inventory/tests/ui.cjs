'use strict';
const assert = require('node:assert/strict');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

async function run() {
    const browser = await chromium.launch({ executablePath: process.env.BROWSER_EXECUTABLE || undefined });
    try {
        const page = await browser.newPage({ viewport: { width: 1100, height: 900 } });
        const errors = [];
        page.on('pageerror', (error) => errors.push(error.message));
        await page.addInitScript(() => { window.GetParentResourceName = () => 'frontier_inventory'; });
        await page.route('https://nui.local/**', async (route) => route.fulfill({
            path: path.join(process.cwd(), 'html', new URL(route.request().url()).pathname.split('/').pop()),
        }));
        const actions = [];
        await page.route('https://frontier_inventory/**', async (route) => {
            const req = route.request();
            const headers = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'POST, OPTIONS' };
            if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
            const command = new URL(req.url()).pathname.slice(1);
            if (command === 'action') actions.push(req.postDataJSON());
            await route.fulfill({ json: { ok: true }, headers });
            if (command === 'close') await send({ type: 'close' });
        });
        const send = (payload) => page.evaluate((value) => window.postMessage(value, '*'), payload);
        const byButton = (name) => page.getByRole('button', { name, exact: true });
        const entry = { slot: 1, name: 'Brot', description: 'Ein Laib Brot.', quantity: 4, grams: 350,
            transfer: true, store: true, drop: true };
        const state = {
            player: { slots: [entry], capacity: 4, available: 3, weight: 1400, weightLimit: 7500, revision: 6 },
            storage: { slots: [], capacity: 3, available: 3, weight: 0, weightLimit: 2000, label: 'Testlager', revision: 1 },
            nearby: [{ name: 'Ada', source: 12 }], drops: [{ name: 'Apfel', quantity: 1, id: 'g_apple' }],
        };
        async function action(index) {
            for (let attempt = 0; attempt < 100 && !actions[index]; attempt += 1) {
                await new Promise((resolve) => setTimeout(resolve, 20));
            }
            assert(actions[index], 'Missing NUI action');
            return actions[index];
        }
        await page.goto('https://nui.local/index.html');
        assert(await page.locator('body').isHidden());
        await send({ type: 'open', data: state });
        await page.locator('body').waitFor({ state: 'visible' });
        assert.equal(await page.locator('main').evaluate((main) => getComputedStyle(main).backgroundColor), 'rgb(0, 0, 0)');
        await page.getByRole('button', { name: /1 · Brot/ }).click();
        assert.equal(await page.locator('#description').textContent(), 'Ein Laib Brot.');
        await byButton('Teilen').click();
        assert.match(await page.locator('#message').textContent(), /Zielplatz/);
        await page.locator('#target').fill('2');
        await byButton('Teilen').click();
        const first = await action(0);
        assert.equal(first.action, 'split');
        assert.equal(first.data.target, 2);
        assert.equal(first.data.revision, 6);
        await send({ type: 'result', ok: false, retry: true, sequence: first.sequence, message: 'Keine Antwort.' });
        await byButton('Denselben Auftrag wiederholen').click();
        assert.deepEqual(await action(1), first);
        const updated = { ...state, player: { ...state.player, revision: 7, available: 2,
            slots: [{ ...entry, quantity: 3 }, { ...entry, slot: 2, quantity: 1 }] } };
        await send({ type: 'result', ok: true, sequence: first.sequence, snapshot: updated, message: 'Inventar aktualisiert.' });
        await page.getByRole('button', { name: /2 · Brot × 1/ }).waitFor();
        await byButton('Apfel × 1 aufheben').click();
        const pickup = await action(2);
        assert.equal(pickup.data.drop, 'g_apple');
        await send({ type: 'result', ok: false, sequence: pickup.sequence, message: 'Du bist zu weit entfernt.' });
        await page.getByText('Du bist zu weit entfernt.').waitFor();
        if (process.env.INVENTORY_SCREENSHOT) await page.screenshot({ path: process.env.INVENTORY_SCREENSHOT });
        await page.keyboard.press('Escape');
        await page.locator('body').waitFor({ state: 'hidden' });
        await send({ type: 'open', data: state });
        await page.locator('body').waitFor({ state: 'visible' });
        await byButton('Schließen (Esc)').click();
        await page.locator('body').waitFor({ state: 'hidden' });
        assert.deepEqual(errors, []);
        console.log('Frontier Inventory browser contract passed');
    } finally {
        await browser.close();
    }
}
run().catch((error) => { console.error(error); process.exitCode = 1; });
