# Frontier Player & Character System v1

Frontier Core owns persistent identities, character profiles and active player sessions. The VORP 3.4 adapter supplies authenticated selections. Economy and future resources consume Frontier's own session and character APIs.

## Install or upgrade

Use Lua 5.4, oxmysql, InnoDB and MySQL 8.0.16+ or MariaDB 10.6+. Apply `sql/migrations/001_characters.sql` to the schema used by oxmysql. Use a deployment principal for DDL. At runtime Core needs SELECT and INSERT on its identity and data tables, UPDATE on `account_identifier` and `updated_at` for the identity table, and UPDATE on profile fields, version and timestamp for the data table. The idempotent insert statements additionally require UPDATE on identity `id` and profile `character_id` for their no-op duplicate clauses.

If using Economy, follow the [Economy cutover and rollback instructions](../frontier_economy/README.md#character-identity-cutover) before restarting either resource. Existing deployments should stop both resources and take a database backup before applying migrations.

```cfg
ensure oxmysql
ensure vorp_core
ensure frontier_lib
ensure frontier_core
ensure frontier_economy
```

## Ownership and provider contract

An ID is an opaque string beginning with `f_` followed by 32 lowercase hexadecimal digits. A database constraint uniquely maps `(provider, provider_character_id)` to the Frontier ID. Identity creation and the first profile insert share a database transaction. An existing non-null account identifier must match the authenticated provider snapshot. Account moves or identifier changes require an explicit administrative migration. Economy uses the Frontier ID regardless of the provider.

The configured server adapter provides `name`, `status() -> available, issue` and `read(source) -> selection | nil, issue`. A selection contains `providerCharacterId` (1–64 ASCII letters, digits, underscores or hyphens), `identifier` and/or `license` where available, profile seed fields (see below), and optional session group/job fields. A provider sends selection notifications through `Core.ScheduleSync(source, provider)` and uses `Core.SyncOnline(provider)` and `Core.EndProviderSessions(provider)` when starting or stopping. A new provider needs an adapter and manifest wiring. Existing characters must be explicitly mapped when changing identity providers. Only the VORP adapter invokes VORP APIs. It reads the provider's selection server-side and supports Cfx callable export proxies.

A profile stores `firstname`, `lastname`, `name`, `dateOfBirth`, `gender`, `metadataJson`, `attributesJson`, `version`, `createdAt` and `updatedAt`. The adapter seeds fields only when the initial profile is created. Unknown optional fields remain SQL NULL and may be absent in Lua. VORP's age is not converted into a birth date. Metadata and extensible attributes are UTF-8 JSON object strings, initially `{}`, with an 8192-byte limit per object. Updates replace only supplied fields, and a supplied JSON object replaces that entire field. If updating names, supply `name` as well when the display name should change. Clearing nullable fields is outside the v1 patch API.

## Server API

- `GetPlayer(source)` returns a copied active session or nil. `GetPlayers()` returns a copied map keyed by source, and `IsPlayerLoaded(source)` returns a boolean.
- `GetPlayerCharacterId(source)` returns the active Frontier ID or nil. Session `characterId` is an alias of `frontierCharacterId`. `providerCharacterId`, `provider` and the legacy `framework` label are diagnostic fields. Use the Frontier ID in persistent gameplay records.
- `GetCharacterData(id)` returns `true, profile` or `false, code` for an offline or online character with a stored profile. Profiles created through legacy account migration are initialized when the owner next selects the character.
- `UpdateCharacterData(id, expectedVersion, patch)` returns `true, profile` or `false, code`. Enable exact resource names in `FrontierConfig.CharacterWriters`. Character patches are whole-field replacements checked against an optimistic version. The caller owns authorization for any client input it forwards. The read APIs are server-only and may contain private player information.
- Existing `HasPermission(source, ace)`, `GetStatus()`, `RegisterCallback(name, handler)` and `TriggerCallback(name, ...)` remain available. The German `frontier_status` command reports schema initialization, provider availability and active session count.

```lua
local core = exports.frontier_core
local session = core:GetPlayer(playerSource)
if not session then return false, 'character_unavailable' end

local ok, profile = core:GetCharacterData(session.frontierCharacterId)
if not ok then return false, profile end

-- This server resource must be configured as a character writer.
return core:UpdateCharacterData(session.frontierCharacterId, profile.version, {
    attributesJson = '{"experience":10}',
})
```

Update errors include `forbidden`, `invalid_character_id`, `invalid_patch`, `character_missing_or_version_conflict`, `database_error` and `update_committed_reload_failed`. If a write outcome is uncertain or its post-commit reload fails, read the profile and its version before retrying.

## Session lifecycle and events

The session loads only after identity and profile resolution. It contains the source, provider mapping, identifier/license, profile, optional group/job fields, and Unix `connectedAt`, `loadedAt` and `updatedAt` timestamps. After a Core restart, `connectedAt` is the time the already-connected source was rediscovered. Each source's pending request carries a token; disconnects and newer selection notifications invalidate stale requests before publication. Temporary database failures retry while the request is current.

All notifications are server-local. Arguments are snapshots.

| Event | Arguments and timing |
| --- | --- |
| `frontier:characterCreated` | `id, profile`, when normal provider processing creates an identity and reads its new profile. Offline SQL migrations do not emit events. |
| `frontier:playerLoaded` | `session` with state `active`, after publication. Repeated selection notifications for an unchanged active session do not emit it again. |
| `frontier:playerUnloaded` | `session, reason` with state `ending`. Active getters no longer return the previous session by the time listeners run. |
| `frontier:characterSwitched` | `previousSession, newSession`, after the new session's loaded event, if the Frontier ID changed. |
| `frontier:characterUpdated` | `id, profile, committedVersion`, after a successful patch and reload. Under concurrent writes the reloaded profile may be newer than the version committed by this call. |

Events report in-process observations and are not a durable change feed. A database commit followed by loss of the response or a failed reload can leave a persisted change without a notification. Use the database-backed read API as the authority.

## Tests

Run `lua54 tests/service.lua` from this resource directory. The mock harness covers first registration, reconnects, duplicate and concurrent registration, independent identities, invalid input, database errors, profile updates and version conflicts, session disconnect and switch, stale asynchronous completion and online startup synchronization. Run the Economy harness and disposable database test described in the Economy README. On live RedM, verify selection and switch through VORP 3.4, Core and provider restarts, German command output and normal Economy API behavior after the cutover.
