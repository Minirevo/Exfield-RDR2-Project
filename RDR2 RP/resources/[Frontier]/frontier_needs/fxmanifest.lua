fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'
description 'Frontier persistent hunger, thirst and energy'
dependencies {'/onesync','oxmysql','frontier_core','frontier_inventory'}
shared_script 'config.lua'
server_scripts {'@oxmysql/lib/MySQL.lua','server.lua'}
client_script 'client.lua'
