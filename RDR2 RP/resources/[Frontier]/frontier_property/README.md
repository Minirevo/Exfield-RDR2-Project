# Frontier Property

First milestone: persistent, server-only property registry. No properties are seeded.
This branch contains a read-only in-game overview, registry and server-side policy and survey checks. Property transactions and furnishing are pending.

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
available as server exports. The gameplay flows, payout allocation and durable settlement remain to be built.
Exclude furniture from voluntary market valuation, and keep recovered tenant items without automatic
deletion initially.

### Base-game prop candidates

`p_bed01x`, `p_chest01x`, `p_armoir04x`, `p_mp_furnace01x`, and `p_sawbucktable01x`.
The last model is a carpentry table candidate. A working saw or distinct blast furnace still
needs an in-game candidate. These entries only identify assets for testing. No storage,
station capability or prop placement is enabled. Verify streaming, bounds, collision and
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
