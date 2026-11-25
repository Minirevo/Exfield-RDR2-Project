EconomyConfig = {
    -- Enable individual resources explicitly when they need the server API.
    TrustedResources = {
        frontier_production = true,
        frontier_farming = true,
        frontier_property = true,
        frontier_business = true,
		frontier_trade = true,
	},

    AdminPermission = 'frontier.economy.admin',
    AdminCreditCommand = 'frontier_gutschrift',
    BalanceCommand = 'frontier_kontostand',
    ProvisionRetryMs = 15000,
}
