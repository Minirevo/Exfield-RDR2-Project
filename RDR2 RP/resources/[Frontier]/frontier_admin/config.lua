FrontierAdminConfig = {
    TeleportCommand = 'tp',
    CoordinatesCommand = 'coords',
    TeleportAce = 'frontier.admin.teleport',

    -- Broad safety limits for RedM world coordinates.
    CoordinateLimits = {
        x = 10000.0,
        y = 10000.0,
        zMin = -1000.0,
        zMax = 3000.0,
    },
}
