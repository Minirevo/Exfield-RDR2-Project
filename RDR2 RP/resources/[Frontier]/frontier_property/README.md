# Frontier Property

First milestone: persistent, server-only property registry. No properties are seeded.
This resource provides a read-only overview, land purchase, fixed-term rental, furnishings and recovery, construction, property sales and foreclosure. World interactions are opt-in through config and need a server-specific staging check.

## Repository audit

- Core exposes `GetPlayerCharacterId(source)`, `HasPermission(source, ace)` and server callbacks in
  `frontier_core/server/init.lua`. Use the opaque Frontier ID from the authenticated session.
- Economy supplies account lookups and idempotent transactions for allowlisted callers.
  Inventory supplies server-owned storage and transactional item changes. Later money and item
  workflows should record durable intents and reconcile each committed receipt before retrying or compensating.
- Trade declares an optional `PropertyProvider`. Production has private storage and recipe jobs.
  Keep facility authorization in Property while each resource remains responsible for its own state.
- Frontier Lib currently supplies utilities and logging. Use the existing resource-local NUI
  and localization patterns for player UI.

## Install and review

Apply `001_registry.sql` after Core's character migration in a disposable oxmysql schema,
then start Property after Core. Keep the runtime DB principal read-only on these tables for
this milestone. Use MariaDB 10.6+ as required by Core. The schema models character, government
and business ownership, but business parties do not imply character rights until a verified
business authorization provider is integrated. A character's explicit permission overrides the
direct ownership default, including a denial. Future ownership mutations must serialize per
property and maintain a total of 10,000 basis points.

Server exports in a yieldable context: `GetProperty(id)`, `CanAccessProperty(characterId, id, permission)`
and `GetPropertyFacilities(id)`. Only active properties are exposed. These are server integration
queries. The calling resource resolves the actor from the current session and separately enforces distance,
applicable tenancy and per-action checks before mutation.

## Subsequent milestones

1. Establish a two-client RedM fixture and verify entry, exit, interiors and usable object models before enabling
   an agent catalogue. Verify model streaming, collision and restoration on reconnect.
2. Implement polygon claims and expansions with server-owned exclusion maps, robust geometry and serialized
   overlap checks before Economy settlement. Geometry cannot independently prove RedM water, roads or slope.
3. Implement blueprint acquisition and construction with Inventory receipts and server-timed cooperative tasks.
4. Add furnishing with persistent transforms, access-controlled synchronization and tested capacity/bounds.
5. Add lease expiration and tenant recovery using protected Inventory custody, then recurring upkeep and
   restart-safe foreclosure accounting.
6. Add sale approvals, debt and lease rules, buyback and business/Production integration. Keep negotiated price
   separate from valuation. Use the approved rules below before enabling irreversible gameplay transitions.

## Approved gameplay policy

The server-only `CalculateForeclosure(assetValueCents, debtCents)` export applies the configurable
deduction (30% by default), pays debt from the remainder, then takes the configurable state penalty
(50% of any surplus by default). The balance is paid to former owners by share. Any unpaid debt
is forgiven. No reputation effects apply. Amounts are integer cents and deductions round down.
The future settlement flow must assemble its asset total from verified server valuations, persist the
breakdown and reconcile ledger receipts before seizing anything. This calculation does not move money.

The policy helpers deny construction or voluntary sale while property debt is outstanding, require
unanimous ownership approval for a voluntary sale, and require explicit buyer consent to transfer an
active lease. An active lease blocks structural construction in this policy. For tenant furnishing,
deny by default and require both an active lease and explicit permission. Calling workflows must
still enforce ownership, actor identity, tenancy, proximity, and operation locking. These rules are
available as server exports. Purchase, building and foreclosure workflows apply the same rules under the property lock.
Exclude furniture from voluntary market valuation, and keep recovered tenant items without automatic
deletion initially.

### Base-game prop candidates

`p_bed01x`, `p_chest01x`, `p_armoir04x`, `p_mp_furnace01x`, and `p_sawbucktable01x`.
The last model is a carpentry table candidate. A working saw or distinct blast furnace still
needs an in-game candidate. These candidate entries identify assets for testing. Add reviewed models to FurnitureCatalog to enable placement. Verify streaming, bounds, collision and
synchronization with two clients before enabling any candidate.

Reference: [RDR3 Discoveries object list](https://github.com/femga/rdr3_discoveries/blob/master/objects/object_list.lua)
and [entity audio emitters](https://github.com/femga/rdr3_discoveries/blob/master/objects/entity_extensions/entity_extensions___audioEmitter.lua).

Run `lua54 tests/policy.lua` from the resource directory to check calculation and eligibility rules.

## Survey validation

`ValidatePropertySurvey(points, allowedZone, blockedZones)` returns the accepted area in square
metres or `nil, errorCode`. Coordinates are planar world metres rounded to a centimetre grid.
It rejects invalid or crossing boundaries, claims outside the permitted polygon, and claims
touching or overlapping any exclusion or registered plot supplied by the server. It accepts
clockwise and counterclockwise rings. Configure the permitted area range in `config.lua`.
Run `lua54 tests/survey.lua` from the resource directory.

The calling workflow must supply authoritative map/exclusion and existing plot data and revalidate
under a database lock before payment or registration. This export makes no terrain, ownership,
pricing or database changes. Plot purchase and expansion still require those workflows.

On staging, `/grundbesitz` shows the current character's first ten active direct holdings and ownership shares using the server's chat resource. No properties are seeded. Use disposable fixture records for a smoke test. Run `lua54 tests/overview.lua` to check identity scope and character changes during a query.

### In-game survey preview

Configure a staging zone in `PropertyConfig.SurveyZones` with a boundary polygon, exclusions
and a positive integer `priceCentsPerSquareMeter`. No live map zones are enabled by default.
Run `/grundvermessung start ZONE`, add corners with `punkt`, undo with `zurück`, and preview
with `prüfen`. Position comes from the server's OneSync player entity in the public bucket.
The displayed quote uses configured exclusions only. The purchase step checks registered plot
boundaries again before payment. Add authoritative map and terrain exclusions before enabling purchases.

### Land purchase
Apply `002_land.sql` after Core and Property 001 using a MariaDB client supporting DELIMITER.
Start Economy before Property. Grant Property SELECT on both land tables, UPDATE on claim retry
timestamps and EXECUTE on the two Land procedures. The Economy allowlist on this branch includes
Property. Use one Property worker per schema.

Each configured purchasing zone must be reviewed for terrain and map restrictions. Enter its
boundary and exclusion polygons, set the rate, and explicitly set `enablePurchase = true`.
After previewing, use `/grundvermessung kaufen` to reserve the plot and debit the character's
bank account. Use `/grundvermessung status` to see whether the latest purchase is pending,
registered or declined. The ordered revision prevents overlapping claims from winning the same
race. A persisted reservation blocks overlap even during retries. The worker reuses the debit key
after interruptions. Insufficient funds releases the reservation. See the SQL fixture for
reservation conflicts, successful registration, replay and refusal.

### Government rentals
Apply `003_rentals.sql` before starting the updated resource. Configure active buildings owned
100% by the government with tested interior keys, and set an offer by property ID in
`GovernmentRentals` (`price = 1000, seconds = 86400, furnish = false`).
No offers are seeded. At the configured agent position use `/grundmiete angebot ID` and
the displayed booking command. A reserved contract serializes bookings and the worker
debits the bank once before activating the time-limited lease. The access API recognizes
active tenants. Keep one worker per database. Grant runtime SELECT and UPDATE on
`frontier_property_rentals` and EXECUTE on `frontier_property_rent_reserve_v1`.

### Private fixed-term rentals
Apply `004_private_rentals.sql` after 003. Grant the runtime
principal SELECT on `frontier_property_private_offers` and EXECUTE on the two new procedures.
A sole character owner can publish terms at the agent with `/privatmiete anbieten ID CENT STUNDEN ja|nein`.
Tenants inspect with `/privatmiete angebot ID` and use the displayed booking command. Updating
the offer invalidates old quotes. A booking reserves the property under the same row lock as
government rentals and transfers the fixed-term price to the landlord's bank with a durable
Economy idempotency key. Check the latest request with `/grundmiete status`. This flow does
supports sole-owner rental offers. Co-owner authorization for offering a rental remains outside that command.

### Refundable rental deposits
Apply `005_deposits.sql` after migration 004. Allow EXECUTE on the three v2 routines. The optional
`deposit` for government offers and final `KAUTION_CENT` argument for private offers are integer cents.
A deposit-bearing booking collects rent and deposit in one bank debit. Private rent is then credited
to the landlord. Rent and refundable liability are separate. On expiry the worker refunds the tenant
in full. Collection, landlord credit and refund have separate durable receipt keys. A full destination
account leaves the corresponding payout pending and replayable. Existing zero-deposit contracts
retain their original payment keys. Stop the resource during migration and run one worker per schema.

### Furniture and rental recovery
Apply `006_furniture.sql`. Grant SELECT and UPDATE on the furniture table and EXECUTE on
the placement routine. Configure `FurnishingRooms` by property ID with surveyed
`min`/`max` vector3 bounds, routing bucket and a capacity no greater than 100. The shipped furniture catalogue includes a bed, chest, cupboard, table and workshop table.
Model identifiers were checked against the RDR3 Discoveries data. Review collision and clearances in RedM. The shared agent lists recovered furnishings. No rooms are enabled by default.
Use `/grundmoebel kaufen ID MODELL CENT` inside a supported room to place furniture at
your position and heading. Renters need a live lease permitting furnishing. Expiry removes
the placed furniture from clients and preserves it in persistent recovery; use
`/grundmoebel lager` at the recovery agent and `/grundmoebel auslagern ID MODELL NUMMER`
to place it elsewhere without a second charge. Confirm model size, doors, collision and
synchronization in RedM. Furniture bought here is a persistent property asset.

### Character property sales and lease assumption
Apply `007_sales.sql` and configure a shared agent location if desired. At the agent, a character
owner offers the property to an online buyer with `/grundverkauf anbieten OBJEKT SPIELER CENT`.
All character co-owners must approve the fixed offer with `zustimmen ANGEBOT`. Both sides
can inspect with `info ANGEBOT`. The buyer uses `kaufen ANGEBOT CENT`, adding `miete-ja`
to explicitly accept the existing prepaid lease. A replacement lease invalidates the offer.
A sale is blocked by outstanding debt, pending rentals or pending furniture purchases.
The worker debits the buyer and pays owner shares by replayable receipts before transferring
ownership. Active tenancy continues. Former non-tenant furniture is moved to recovery.
A full destination bank account leaves settlement pending. Use one worker per schema.

### Construction
Apply `008_construction.sql`. Install the included Inventory allowlist change and start Inventory
before Property. Grant SELECT and UPDATE on build jobs, SELECT on construction and EXECUTE
on both build routines. Configure `ConstructionPlans` with a model, radius, a blueprint inventory `item`, value in cents and
stages of `{ item='...', count=1, tool='...', workSeconds=5 }`; omit the tool when unnecessary. Each stage
consumes a single configured batch through Inventory, with replay protection. The owner starts
a site on a surveyed plot with `/grundbau start GRUNDSTÜCK BAUPLAN`; the owner or authorized
workers complete stages near it using `/grundbau arbeiten BAUSTELLE`. Incomplete sites block
sales. Completed assets are streamed to nearby players in the public world. Test elevation,
visual footprint, terrain and collision in RedM for each configured plan.

### Upkeep and foreclosure

Apply 009 and forward migration 010. Grant EXECUTE on the two v2 foreclosure routines in addition
to the upkeep routines. Configure rate and grace period before opting into automatic upkeep.
No government account is required. Upkeep payments debit the payer, and the foreclosure
deduction, debt settlement and state penalty are recorded without crediting any recipient.
Only the former owners' calculated shares are issued. Legacy treasury receipt fields remain
available for reconciliation. Existing pending cases now finish owner payouts without sending
a treasury payment, and historical payments are not reversed. All actual money mutations go through Economy. Do not reuse a live account for staging.

Upkeep accrues on a real-world schedule. Owners can inspect and pay outstanding taxes with
`/grundsteuer info OBJEKT` and the displayed payment command. The foreclosure transaction checks
overdue time and the threshold, snapshots allocation, and locks the property against new sales
and construction by marking it inactive. Active leases and unsettled purchases block seizure.
Existing buildings, completed construction and eligible furniture are valued, and held tenant
furniture goes to recovery. There is no separate attached-goods inventory in this integration.
Land itself is released without payout after settlement. The worker applies configured 30% and
50% defaults in sequence, applies liquidation funds to debt, forgives the balance if needed,
credits owners with stable receipt keys, and releases the land only after receipts.
A full payout account keeps the settlement pending. Use one worker per schema.

### Staging checklist

Apply Core and Economy migrations first, then Property 001 through 010 in order on a disposable
database, then start Inventory, Economy, chat and Property with OneSync. Keep upkeep disabled
until other test cases finish. Configure one reviewed survey zone, building/room, rental agent,
furniture model, sale agent and construction plan for the test. Use two characters and test:
rent with a deposit, wait for expiry and check recovery/refund, place and recover furniture,
complete a build with the required tools, sell with all owners' approval and explicit consent
for an active lease, and finally enable a short upkeep interval and verify the foreclosure ledger.
The SQL fixtures target their matching migrations. Furniture, construction and gameplay
make use of server-specific config and still need the live RedM model/collision checks.

### Shared property agent and menu

Approach the default agent in Valentine, Rhodes, Saint Denis or Blackwater and press **E**.
The same agent covers rentals, sale approvals and purchase, owned-property information and recovery
listings. The menu uses existing server transaction handlers, with proximity verified from OneSync.
The default locations are in `shared/agents.lua`. Exact terrain height, placement and NPC model
streaming still need a live RedM check. This version lists configured government rentals and
existing private offers. Automatic discovery and seeding of government buildings is not included.
Existing chat commands still handle owner listings, offers and furnishing or construction outside
the agent interface.
