# Frontier Property

First milestone: persistent, server-only property registry. No properties are seeded.
This branch is a foundation for review and is not a playable property resource yet.

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
   separate from valuation. Confirm open policy choices before enabling irreversible gameplay transitions.
