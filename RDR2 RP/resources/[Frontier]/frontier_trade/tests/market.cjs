'use strict';
const assert = require('node:assert/strict');
const path = require('node:path');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

async function main() {
    const browser = await chromium.launch({ executablePath: process.env.BROWSER_EXECUTABLE || undefined });
    try {
        const page = await browser.newPage();
        const actions = [];
        const errors = [];
        page.on('pageerror', (err) => errors.push(err.message));
        await page.addInitScript(() => { window.GetParentResourceName = () => 'frontier_trade'; });
        await page.route('https://nui.local/**', (route) => route.fulfill({
            path: path.join(process.cwd(), 'html', new URL(route.request().url()).pathname.split('/').pop()),
        }));
        const send = (event) => page.evaluate((value) => window.postMessage(value, '*'), event);
        await page.route('https://frontier_trade/**', async (route) => {
            const req = route.request();
            const headers = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'POST, OPTIONS' };
            if (req.method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
            const action = new URL(req.url()).pathname.slice(1);
            if (action === 'action') actions.push(req.postDataJSON());
            await route.fulfill({ json: { ok: true }, headers });
            if (action === 'close') await send({ type: 'close' });
        });
        await page.goto('https://nui.local/index.html');
        assert(await page.locator('body').isHidden());
        const request = '00000000-0000-0000-0000-000000000001';
        await send({ type: 'snapshot', data: {
            available: true, market: 'valentine', markets: { valentine: 'Valentine' }, products: { bread: 'Brot' },
            requests: [{ id: request, item_id: 'bread', remaining: 10, price_minor: 25, available: 1 }],
            contracts: [{ id: request, item_id: 'bread', remaining: 4, state: 'active', due_at: '2026-11-22 18:30', deliverable: 1 }],
            offers: [{ id: request, item_id: 'bread', available: 8, unit_minor: 25, state: 'open', buyable: 1 }],
            deliveries: [{ id: request, item_id: 'bread', quantity: 6, state: 'complete', claimable: 1 }],
        } });
        await page.getByRole('button', { name: 'Annehmen', exact: true }).click();
        await page.getByText(/Anfrage weitergeleitet/).waitFor();
        assert.deepEqual(actions[0], { action: 'accept', args: [request, '25'] });
        await page.getByRole('spinbutton', { name: 'Liefermenge' }).fill('2');
        await page.getByRole('button', { name: 'Liefern', exact: true }).click();
        for (let index = 0; index < 100 && actions.length < 2; index += 1) {
            await new Promise((resolve) => setTimeout(resolve, 20));
        }
        assert.deepEqual(actions[1], { action: 'deliver', args: [request, '2'] });
        await page.getByRole('spinbutton', { name: 'Kaufmenge' }).fill('3');
        await page.getByRole('button', { name: 'Kaufen', exact: true }).click();
        for (let index = 0; index < 100 && actions.length < 3; index += 1) {
            await new Promise((resolve) => setTimeout(resolve,20));
        }
        assert.deepEqual(actions[2],{ action:'buy', args:[request,'3'] });
        await page.keyboard.press('Escape');
        await page.locator('body').waitFor({ state: 'hidden' });
        assert.deepEqual(errors, []);
        console.log('Trade market browser contract passed');
    } finally {
        await browser.close();
    }
}
main().catch((error) => { console.error(error); process.exitCode = 1; });
