# Phase 1 — Frontier inventory cutover

The actual G-Portal server.cfg is not in this repository. This PR does not change live startup state. Keep your host's endpoint, database, license, ACE, map, voice and standalone settings. Do not use a blanket ensure [VORP]. Copy frontier-inventory-cutover.cfg next to your host's server.cfg and exec it once in the appropriate startup section (or copy its individual lines). Remove conflicting legacy ensure/start lines elsewhere, including any category-wide starts. Review which resources you actually use before deploying; the fragment is an explicit proposed test-server profile, not a complete host configuration. Back up the DB and server config, then perform a full restart with all players disconnected.

## Retained
VORP Core/Character and libraries/menu/input/progress, VORP Metabolism (needs load/save and decay only), VORP Stables (horse ownership and existing riding/draft integration only). Frontier HUD, inventory, food, business, trade, farming, logistics, property and skills remain. Native weapon controls are managed by Frontier. Temporary Gun Lab is no longer loaded; old source remains for reference.

## Temporarily unavailable
Legacy saddlebag access is explicitly disabled; contents remain in the database. Legacy medical and police scripts are stopped because their server code calls VORP Inventory; dedicated replacements are not implemented. Other retired scripts are not feature-for-feature replaced (e.g. mail, job pay, legacy stores, NPC loot, herb/crawfish gathering). VORP stable purchase prices still use legacy currency; stable economy migration is a future task. Existing VORP item/weapon admin commands return a retirement notice; use Frontier admin/test commands instead. No DB rows/tables or resource directories are deleted; no automatic item, gun, cash or saddlebag migration. Restore legacy data only from a reviewed backup/migration plan. Do not run both inventory systems on the same active character.

## Test after full restart
Confirm vorp_inventory and vorp_weaponsv2 are stopped (not missing dependency errors). Login / character creation; HUD and food/drink; buy/load existing horse, mount and draft/wagon operation; saddlebag notice; all Frontier management menus; equip and fire actual inventory weapon; holster/unarmed/redraw repeatedly, including switching long gun/sidearm; quick and satchel ammo counts and delays; death, reconnect and restart. Use /frontierweaponstatus for native model ownership and counts. If unexpected native equipment remains, log out and use a clean test character; the code never blindly wipes unrelated weapons. Server and client draw paths refuse the legacy weapon resources while running. Frontier-owned native projection cleanup is tracked per model, including post-removal ammo clearing and a bounded-on-demand retry; native timing must still be tested in RedM.

## Rollback
Stop server, restore prior startup configuration and deploy prior commit; keep backup database. Any new Frontier items or spent rounds remain in the Frontier DB; no implicit conversion. Do not restart legacy inventory alongside the new exclusive weapon path.

No SQL migration. No live RedM/SQL tests executed during authoring.
