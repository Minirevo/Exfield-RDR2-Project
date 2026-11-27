# Frontier Logistics — development model lab
**Draft, not the complete phases 1–5 update.** This resource currently contains an isolated native/model lab, provisional wagon/part catalogue and pure rules. It does not modify live inventory, stable ownership, businesses, production or trade. No migration or server.cfg changes are required for existing resources.

## Test setup
Copy the resource to [Frontier]. Temporarily add:
```cfg
add_ace group.admin frontier.logistics.models allow
ensure frontier_logistics
```
On clear flat ground, use:
- /logisticsmodels wagon supplywagon (or wagon03x, wagon02x, wagon04x, logwagon)
- /logisticsmodels cargo crate 0 0 0.8
- /logisticsmodels cargo barrel -0.4 -0.6 0.8
- /logisticsmodels cargo sack 0.4 -0.6 0.8
- /logisticsmodels horse 0
- /logisticsmodels horse 1
- /logisticsmodels drive
- /logisticsmodels export (copy JSON from F8)
- /logisticsmodels clear
- /logisticsmodels bench

Cargo offsets are wagon-local and provisional. Try different xyz and heading until visible and correctly aligned. Test native harness slot indices 0–3 against each model; do not assume suggested horse count is supported. The lab uses local entities only; this cannot validate OneSync persistence, ownership migration or server-authoritative damage. Stop the resource after testing. No economic or player data is written.

## Accepted asset catalogue
Crate/recovery crate: p_crate02x; construction bench: mp005_p_mp_tableplank04x; barrel: p_barrelladle1x_culture; sacks: p_cs_sandbag01x. No timber-specific prop. Wagon frame, wheel, axle, fittings and harness are inventory items/icons only. Icon names in config are placeholders, not shipped textures.

## Agreed phases 1–5 (release acceptance criteria, not implemented yet)
1. Persistent private/company wagon identity, registration, last server-observed world position, exclusive owned horse assignments. OneSync entity lifecycle with no second spawn while a lease is active; distinguish a missing network entity from confirmed destruction; loaded wagons cannot teleport by stable storage. Existing VORP carts and Frontier cargo must not share mutable stock or generate duplicate ownership.
2. Wagon interaction opens two-pane cargo planner. Select bag/authorized nearby property/business chests; stage multiple exact-stack transfers in either direction, including unique metadata. Confirm whole plan, close UI, show timed loading. Validate source revisions, capacity, vehicle speed, physical location, access before and after progress; use atomic inventory commits or journaled reservation with safe returns. Never chain unjournaled partial multi-container writes. Cargo visuals derive from actual stock.
3. Driving theft permitted, legal ownership unchanged. Lock protects stock, lockpicking consumes tool condition and has server-validated QTE. Unsecured cargo can be stolen. Confirmed destruction freezes a 90% expected per-stack recovery decision (unique items are indivisible), moves remaining items to persistent lootable crates at last position with idempotent receipt. Do not delete cargo on ordinary despawn. Reports and ownership inspection without GPS.
4. Freight contracts use escrow payment, separate reserved cargo ownership, pickup/delivery proximity, atomic handoffs and idempotent payout/XP. Company transport license, distinct driving/deposit/retrieve/finance permissions. Cancellation, destruction, theft and recovery must not release payment for undelivered goods. No double payout or stock duplication after reconnect.
5. Player-made frames/wheels/axles/fittings/harnesses via existing stations, dedicated construction bench on property, frozen input quality and assembly recipe. Register completed wagon once using durable order ID; repairs consume parts and maintain condition; no arbitrary client-provided wagon spawn. Keep NPC stable supply as bootstrap.
NPC journeys and insurance are subsequent scope.

References for experimental native calls:
- https://www.rdr2mods.com/nativedb/index/_namespace79/_0x316cdb5b6e8f4110-r6425/ (horse, wagon, harness index)
- https://the-lab.oxdev.fr/redm/natives/vehicle/create_vehicle (draft animal suppression flag)

## Verified local model test (2026-11-27)
Server owner reports all tests working. Export identifies `supplywagon` (signed hash -1753201617) with two `a_c_horse_shire_darkbay` horses (hash 1066034872), harness slots 0 and 1. Two `p_crate02x` attachments verified at (0,-0.99,0.2) and (0,0,0.2), heading 0. Crate dimensions 1.16285 × 0.83414 × 1.00064 m. Configuration now records the measured offsets instead of applying generic positions to this wagon. Only these exact harness/offset combinations are established by the export; no barrel/sack offsets or other wagon models are inferred. Local success does not yet verify networked entity persistence, migration of ownership, or theft/damage across clients.
