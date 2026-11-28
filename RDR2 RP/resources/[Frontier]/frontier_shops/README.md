# Frontier Shops V1

18 locations copied from bundled VORP stores: eight general stores, five gunsmiths, three butchers, Blackwater fishing supplies and Wapiti trading post. Use G or /shop at a counter. Store inventory is a fixed-price NPC catalogue (not simulated merchant stock yet). Cash only. Buy/sell basket, category/search, item weights, inventory counts, receipts. Only configured commodities can be sold. Player business stores, property furniture shops, farming vendors and regular trade remain independent.

## Install

1. Stop server, pull main.
2. Apply frontier_shops/sql/001_shops.sql.
3. Disable/stop vorp_stores; keep VORP inventory/weapon resources disabled as required by Frontier weapon projection.
4. ensure frontier_shops after frontier_core, frontier_economy and frontier_inventory. Start gathering, production and property normally to register their items. Restart full server because the shared weapon catalog is used by inventory and wheel. New item definitions seed automatically; existing Cattleman/Lancaster IDs and definitions preserved.
5. Visit Valentine General Store, buy bread/water, test overweight refund, then Valentine Gunsmith, equip a newly purchased weapon in appropriate slot and load regular matching ammo. Test every new weapon model before public release.

30 weapon model definitions, including 24 standard firearms, four VORP variant firearms and two experimental bows. Both bows disabled in shop by default until their native reload/draw behavior is live-tested (enableExperimentalBows). Regular ammo types only. Melee, lasso, throwable/consumable weapons, alternate rounds, special story models and LeMat alternate firing mode need separate native handling and are not exposed as purchasable combat weapons. All weapon models must be tested in RedM; no direct game runtime here. No changes to existing gathering knife/axe/rod mechanics.

Orders persist across restarts: server validates location, current character, catalog, quantities, total, cash and satchel capacity. Debit/grant/refund or take/credit phases use stable economy/inventory keys and a single atomic basket change. Recovery retries uncertain outcomes without duplicate payment or goods. No client price authority. NPC inventory is unlimited for V1; butcher sale prices are deliberately below starter job rates. Prices are configurable and need economy balancing. Shopkeeper coords use original VORP NPC offsets; verify interiors and blips. Shop UI product pictures reuse existing bundled VORP assets; missing icons use category fallback.

Gunsmith cards display matching cartridge type, equipment slot and supported magazine capacity. Purchase receipts include the economy debit operation; refund receipts refer to the refund. Repeated checkout with a previously saved ticket resumes the saved order rather than creating another.

## Unified general stores (1.1)
All general stores now include the live Property catalogue (furniture, settlement kits, production stations, gathering tools) and Farming supplies (seeds, feed, fertilizer, tools). Ordinary retail uses the cash basket. The Farm deliveries tab uses the existing farming server's authorized facility, ownership, capacity, company funding and persistent order logic for livestock and company-stock deliveries. Personal livestock purchases use cash; company orders use company bank funds. No new animal vouchers are sold as ordinary satchel goods. Old agricultural supplier NPCs/prompts and property shop prompts are suppressed when frontier_shops is running. /farmshop and /propertyshop redirect to /shop; existing pending legacy orders continue to recover. If Shops is stopped, legacy menus remain fallback. Restart farming, property and shops together (full restart preferred). No new SQL migration beyond the corrected 001_shops.sql. Startup now checks every receipt column and logs the unified version. The old log with unquoted lines means the older server.lua was still loaded. Live test all paths before release.
