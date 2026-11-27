fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'
version '1.0.0'
description 'Frontier character inventories, storage and ground pickups'

dependencies { '/onesync', 'oxmysql', 'frontier_lib', 'frontier_core' }
shared_scripts {'config.lua','weapons.lua'}
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@frontier_lib/shared/utils.lua',
    '@frontier_lib/server/logger.lua',
    'server/database.lua',
    'server/items.lua',
    'server/slots.lua',
    'server/service.lua',
    'server/ammo_recovery.lua',
    'server/interface.lua',
}
client_script 'client/inventory.lua'
ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/app.js' }
