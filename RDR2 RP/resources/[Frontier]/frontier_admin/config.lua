FrontierAdminConfig = {
    -- Use a namespaced command to avoid collisions with generic /tp commands
    -- registered by VORP, admin menus, or other server resources.
    TeleportCommand = 'frontier_tp',
    CoordinatesCommand = 'coords',
    TeleportAce = 'frontier.admin.teleport',

    CoordinateLimits = {
        x = 10000.0,
        y = 10000.0,
        zMin = -1000.0,
        zMax = 3000.0,
    },
}
