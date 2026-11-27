fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'
description 'Frontier Medical V1: persistent trauma and first aid'
dependencies {'/onesync','oxmysql','frontier_core','frontier_inventory','frontier_needs'}
shared_scripts {'config.lua','model.lua'}
server_scripts {'@oxmysql/lib/MySQL.lua','server.lua'}
client_script 'client.lua'
ui_page 'html/index.html'
files {'html/index.html','html/style.css','html/app.js'}
