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

## Gathering input and native catch diagnostics
The contextual key is E (`0xCEFD9220`); `/gather` remains an alternative. Native hunting no longer requires current network ownership for server-confirmed dead animals. Validation checks distance, routing bucket, configured model, death evidence and duplicate claims. `nativeDebug=true` logs precise rejection reasons. `allowHuntingHealthFloor=true` permits a health value of exactly 100 only when max health is higher, the current network owner is the claimant, the client reports death and strictSurvey is false. Disable this compatibility fallback on untrusted servers. This is not equivalent to authoritative proof of native skinning. RedM runtime validation is still required.

## Position and rock detection hotfix
Gathering shares the existing inventory session policy rather than rejecting players using an independent health check. Outdoor bucket 0 is allowed by default; add an outdoor bucket to worldBuckets only if your server intentionally uses it. Do not add property interiors or character-selection buckets. Use /gatherdebug to print client nearby object hashes and server position, bucket and health. If no rock appears, stand beside a rock and run /gather mining; this explicitly searches rock models, including a direct model lookup fallback. Rock centers have an 8m horizontal and 7m vertical reach because many natural rocks have buried origins. All 441 distinct rock models from the bundled VORP configuration are included; some are small scree/stone clusters and may need balancing or removal after testing. Restart frontier_inventory then frontier_gathering together. No new migration. These changes are untested in RedM.
