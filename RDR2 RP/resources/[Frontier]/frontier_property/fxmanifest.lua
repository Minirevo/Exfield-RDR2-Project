fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'frontier_property'
description 'Persistent Frontier property ownership and business access'
version '0.1.0'

dependencies { 'oxmysql', 'frontier_lib', 'frontier_core', 'frontier_economy' }

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@frontier_lib/shared/utils.lua',
    '@frontier_lib/server/logger.lua',
    'config.lua',
    'server/main.lua',
}
