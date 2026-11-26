# Frontier Farming V1 — test-server build

Start after oxmysql, frontier_core, frontier_economy, frontier_inventory, frontier_property and frontier_business. SQL tables are initialized on startup. This branch contains coordinated changes to those resources and Trade/Production; install matching revisions.

## Player workflow

- Build fields, chicken pens, livestock pens or wells via Property. Use /farm near a completed facility to register personal or authorized company ownership, and link a same-owner Business storage chest.
- /farmshop near an agricultural supplier: purchase supplies and tools, or select a registered enclosure for adult/juvenile livestock delivery.
- Keep tools in personal inventory, and consumables in the linked chest. The menu shows requirements, available stock, selected quantities and missing tools.
- Fields use 25/100/400 seeds. Water and feed amounts are selectable actual item quantities. A normal full feeding/watering dose provides 12 hours, with a work bonus; reserves are capped at 48 hours. Fertilizing costs 1/4/16 units and accelerates growth.
- A mature field is harvested in a single five-round session. The linked chest must fit the entire remaining harvest and seed return, including the possible maximum bonus. Existing partial harvests retain their remaining yield.
- Eggs accumulate in the enclosure and require a manual Collect eggs action, without a minigame. Milk, wool and manure are manually collected. Existing eggs already deposited before this update stay in storage.
- All work sessions perform server-side eligibility, tool, stock and output-space checks before starting. The final stock transaction revalidates current inventory. Stock can still change during a session, so an operation may fail safely at completion.
- Wells provide water to linked storage. /farmwater gathers at an approved river/lake access point into personal inventory; use /farmwatersite and /farmwaterremove with the frontier.farming.admin ACE to manage access points.
- For livestock slaughter, complete the work session and kill the networked animals, then /farmfinish. /farmcancel cancels without output.
- Horses have individual records, training, care and genes. /farmreturn returns a checked-out mount. /handelspferde or /farmhorses opens certificate trading; selling agricultural products requires an agriculture license.

## Testing and deployment

Run lua5.4 tests/rules.lua from frontier_farming and node --check html/app.js. The farming workflow runs these and parses Lua across the affected resources. Native scenario-prop cleanup, crop placement, networked horse/slaughter entities and end-to-end journal recovery need live RedM testing. Small/large pen geometry and slope-adjusted Property previews also need validation. Keep test mode timer overrides local to the test server; remove before production. No SQL reset is required for this patch.
