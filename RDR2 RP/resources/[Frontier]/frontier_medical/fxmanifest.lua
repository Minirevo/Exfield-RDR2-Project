fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'
description 'Frontier Medical: guarded native damage adapter and persistent physiology'
dependencies {'/onesync','oxmysql','frontier_core','frontier_inventory','frontier_needs','frontier_skills'}
shared_scripts {'config.lua','model.lua','professional.lua'}
server_scripts {'@oxmysql/lib/MySQL.lua','server.lua'}
client_scripts {'damage_rules.lua','damage_client.lua','client.lua'}
ui_page 'html/index.html'
files {'html/index.html','html/style.css','html/app.js'}
