PropertyConfig = {
    Enabled = true,
    WorkerIntervalMs = 5000,
    MaxMembers = 12,
    Currency = 'USD',

    -- Add real in-game locations here. Coordinates are intentionally not guessed.
    -- id must be unique lowercase ASCII: [a-z0-9_], max 48 characters.
    -- priceMinor/rentMinor are cents, matching frontier_economy.
    Sites = {
        -- valentine_bakery = {
        --     label = 'Bäckerei Valentine',
        --     type = 'bakery',
        --     market = 'valentine',
        --     priceMinor = 250000,
        --     rentMinor = 5000,
        --     x = -..., y = -..., z = ..., bucket = 0,
        -- },
    },
}
