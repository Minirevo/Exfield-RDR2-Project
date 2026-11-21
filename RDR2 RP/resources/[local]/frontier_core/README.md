# Frontier Core (foundation scaffold)

Frontier is being developed as the server's independent framework. This initial milestone is deliberately limited to shared utilities, a player/character registry, permission checks, server callbacks, and a VORP adapter.

## Requirements

- RedM server with Lua 5.4
- `frontier_lib`
- `vorp_core` (temporary character/session provider)

## Startup order

Ensure these resources after VORP Core:

```cfg
ensure frontier_lib
ensure frontier_core
```

Both resources currently live in `resources/[local]`. If your server config ensures that category as a group, ensure it after `[VORP]`. Otherwise add the two resource names explicitly after `vorp_core`.

## API (server-side)

```lua
local player = exports.frontier_core:GetPlayer(source)
local players = exports.frontier_core:GetPlayers()
local loaded = exports.frontier_core:IsPlayerLoaded(source)
local allowed = exports.frontier_core:HasPermission(source, 'frontier.admin')
```

Player records are copies, not mutable references to Core's registry.

The record currently contains: `source`, `identifier`, `license`, `characterId`, `firstname`, `lastname`, `name`, `group`, `job`, `jobGrade`, `jobLabel`, `loadedAt`, `updatedAt`, and `framework`.

Server callback registration and invocation:

```lua
exports.frontier_core:RegisterCallback('example:sum', function(a, b)
    return (tonumber(a) or 0) + (tonumber(b) or 0)
end)

local ok, result = exports.frontier_core:TriggerCallback('example:sum', 2, 3)
```

These callbacks are server-to-server only; this milestone does not expose client-triggered RPCs.

## Lifecycle events

- `frontier:playerLoaded` — emitted with a player record after a VORP character selection is synchronized.
- `frontier:playerUnloaded` — emitted with a player record and reason when the player disconnects.

## Permissions

Permissions are ACE-based in this first milestone. Configure them in server configuration, e.g.:

```cfg
add_ace group.admin frontier.admin allow
```

Do not rely on client-side permission checks.

## Important limitations in this milestone

- VORP is still the character source of truth.
- No Frontier database tables or migrations yet.
- No cash, bank, jobs, inventory or business systems.
- No client callback/event surface.
- This is an initial API scaffold and must be runtime-tested on the actual RedM server before being treated as production-ready.
