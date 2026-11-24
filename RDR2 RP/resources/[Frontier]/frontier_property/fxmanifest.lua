fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'
version '2.0.0'
dependencies { '/onesync', 'oxmysql', 'frontier_core', 'frontier_inventory', 'frontier_economy' }
shared_scripts { 'config.lua', 'shared/rules.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'server/main.lua' }
client_script 'client/main.lua'
ui_page 'html/index.html'
files { 'html/index.html','html/style.css','html/app.js' }
