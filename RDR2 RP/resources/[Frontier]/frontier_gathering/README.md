# Frontier Gathering — review build

This update combines Inventory V2, private six-slot toolbelts, persistent character skills, natural resource gathering, tool tiers/quality/durability, and workshop crafting and repair.

## Deployment
Back up the database and deploy to a test server first. Apply the new frontier_skills/sql/001_skills.sql and frontier_gathering/sql/001_gathering.sql migrations to the server database. Verify the database account can read/write the new tables. Keep all existing Frontier migrations installed. Deploy the changed resources together, not just gathering.

Start frontier_inventory and the existing Frontier dependencies, including property and production, before frontier_skills and frontier_gathering. Start the modified vorp_fishing adapter when using native fishing. Restart affected resources together during maintenance, before accepting players. Disable legacy vorp_lumberjack, vorp_mining, vorp_herbs and vorp_hunting to prevent competing interactions/rewards. Frontier hunting replaces the legacy reward flow, including legacy butcher sales; test the cutover. Existing farming water collection is unchanged.

## Player commands
- /skills: skill ledger
- /gather: inspect/interact with a nearby compatible resource; the prompt also provides the contextual interaction
- /gatherwater prospecting, clay or sand: select shoreline activity
- /fish: native fishing with the native rod equipped, Frontier rod and bait
- /smith pickaxe steel: craft a tool near a completed permitted workshop
- /repair pickaxe: repair a selected/available tool near a permitted workshop
- /gatherrecover: recover a pending gathering reward
- /gathersurvey: administrator survey command (see config and command help)
- frontier_belt_1 through frontier_belt_6: bindable preferred-tool selection commands; no default number bindings to avoid native weapon conflicts

Gathering tools and bait are sold through the existing property general store. Toolbelts are private persistent storage, restricted to eligible equipment, and do not replace the main inventory. Existing items remain in the bag.

## Security and limitations
This is a review build, not a live-tested release. Static map entities cannot always be independently verified on the server; default permissive discovery checks model, distance, action timing and persistent depletion but cannot prove every client-reported tree or rock. Set strictSurvey=true for a public server and survey approved locations. River zones are approximate and need testing. Trees are hidden and replaced with stumps rather than physically animated falling trees. Native models, animation dictionaries, fishing and skinning events need RedM validation. Fish/animal coverage is limited to configured species; fish size and animal quality are not yet fully modeled. Toolbelt shortcuts select a preferred tool, not a physical prop. Existing farm/construction/production professions are listed in the ledger, but their XP hooks remain future work; gathering and blacksmithing are the implemented progression paths.

## Test checklist
- Existing bag/chest transactions, stack splitting, retries, drag/drop and slot changes.
- Private belt: equip, remove, reconnect, weight limits, rejection of ordinary materials and simultaneous transfers.
- Every gathering action: correct tool, cancellation, five-second completion (herbs shorter), yield, wear, full bag, duplicate requests, depletion, regrowth and restart recovery.
- Skills persist by character; duplicate reward IDs never grant XP twice.
- Craft several tiers, check unique quality metadata and repair without losing the tool.
- Native fishing and hunting pay once into Frontier inventory and never also into VORP.
- Verify all new trade and production materials and balance gathering versus house construction.
- Verify legacy farm water, property construction and other existing workflows.
