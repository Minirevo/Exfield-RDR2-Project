# Frontier Admin

Small, standalone staff utility resource. The first feature is coordinate-based teleportation.

## Installation

Add the resource to `server.cfg` after the other Frontier resources:

```cfg
ensure frontier_admin
add_ace group.admin frontier.admin.teleport allow
```

Make sure your own license identifier is assigned to `group.admin` (only once):

```cfg
add_principal identifier.license:YOUR_LICENSE_HERE group.admin
```

Replace the placeholder with your full `license:...` identifier. Restart the server after changing permissions.

## Commands

- `/tp X Y Z` — teleport yourself to the supplied world coordinates. Example: `/tp -281 806 119.4`.
- `/coords` — print your current coordinates and a ready-to-copy `/tp` command in the client F8 console.

The teleport command is registered server-side and requires the `frontier.admin.teleport` ACE permission. Coordinates are checked against broad configurable world bounds in `config.lua`.

Player-facing messages are German. The resource does not depend on VORP or Frontier Core.
