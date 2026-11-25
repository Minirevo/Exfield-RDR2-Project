fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'
version '0.1.0'
dependencies { 'oxmysql', 'frontier_lib', 'frontier_core', 'frontier_economy', 'frontier_inventory' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@frontier_lib/shared/utils.lua',
    '@frontier_lib/server/logger.lua', 'config.lua', 'server/requests.lua', 'server/deliveries.lua', 'server/sales.lua', 'server/npcs.lua', 'server/business.lua' }

client_script 'client/market.lua'
ui_page 'html/index.html'
files { 'html/index.html', 'html/app.js', 'html/style.css' }
