fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'
version '0.1.0'
-- Development lab only; no persistent economy or inventory access.
shared_scripts {'config.lua','shared/rules.lua'}
server_script 'server/modeltest.lua'
client_script 'client/modeltest.lua'
