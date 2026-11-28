fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'
description 'Frontier radial equipment and persistent weapon interface'
version '0.1.0'
dependencies {'frontier_inventory','frontier_core','oxmysql'}
client_scripts {'@frontier_inventory/weapons.lua','rules.lua','layout.lua','appearance_groups.lua','weapons_client.lua','client.lua'}
server_scripts {'@oxmysql/lib/MySQL.lua','server.lua','documents.lua'}
ui_page 'html/index.html'
files {'html/index.html','html/style.css','html/app.js'}
