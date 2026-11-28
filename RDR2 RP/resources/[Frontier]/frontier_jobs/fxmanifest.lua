fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'
dependencies {'/onesync','oxmysql','frontier_core','frontier_inventory','frontier_economy','frontier_business','frontier_gathering'}
shared_script 'config.lua'
server_scripts {'@oxmysql/lib/MySQL.lua','rules.lua','server.lua'}
client_script 'client.lua'
ui_page 'html/index.html'
files {'html/index.html','html/app.js','html/style.css'}
