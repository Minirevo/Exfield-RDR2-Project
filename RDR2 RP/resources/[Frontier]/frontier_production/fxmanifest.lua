fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'
version '1.0.0'
dependencies { 'oxmysql', 'frontier_lib', 'frontier_core', 'frontier_inventory', 'frontier_economy' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@frontier_lib/shared/utils.lua',
    '@frontier_lib/server/logger.lua', 'config.lua', 'server/production.lua' }
client_script 'client/main.lua'
ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/app.js' }
