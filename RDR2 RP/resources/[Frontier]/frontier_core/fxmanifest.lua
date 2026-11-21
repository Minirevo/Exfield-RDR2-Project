fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'frontier_core'
description 'Frontier framework core and player/session API'
version '1.0.0'

dependency 'frontier_lib'
dependency 'oxmysql'
dependency 'vorp_core'

-- Import the library scripts into this resource's Lua runtime.
-- Resource globals are isolated; starting frontier_lib does not expose its
-- globals to frontier_core automatically.
shared_scripts {
    '@frontier_lib/shared/utils.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@frontier_lib/server/logger.lua',
    'config.lua',
    'server/registry.lua',
    'server/permissions.lua',
    'server/characters.lua',
    'server/vorp_adapter.lua',
    'server/status.lua',
    'server/init.lua',
}
