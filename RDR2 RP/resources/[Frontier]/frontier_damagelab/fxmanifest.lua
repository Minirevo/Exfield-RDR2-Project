fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'
description 'Frontier developer-only native damage interception laboratory'
dependency 'vorp_core'
shared_script 'rules.lua'
server_script 'server.lua'
client_scripts {'@vorp_core/client/dataview.lua','client.lua'}
