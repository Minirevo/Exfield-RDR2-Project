fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'
version '1.0.0'
dependencies { 'oxmysql', 'frontier_lib', 'frontier_core', 'frontier_inventory', 'frontier_economy', 'frontier_property', 'frontier_business', 'frontier_skills' }
server_scripts { '@oxmysql/lib/MySQL.lua', '@frontier_lib/shared/utils.lua',
    '@frontier_lib/server/logger.lua', 'config.lua', 'stations.lua', 'server/production.lua', 'server/stations.lua' }
client_scripts { 'client/main.lua', 'client/stations.lua' }
ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/app.js', 'html/stations.js', 'html/stations.css' }
