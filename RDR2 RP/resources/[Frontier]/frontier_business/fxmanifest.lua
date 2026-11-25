fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'
dependencies {'/onesync','oxmysql','frontier_core','frontier_economy','frontier_inventory','frontier_property'}
shared_script 'config.lua'
server_scripts {'@oxmysql/lib/MySQL.lua','server/main.lua'}
client_script 'client.lua'
ui_page 'html/index.html'
files {'html/index.html','html/app.js','html/style.css'}
