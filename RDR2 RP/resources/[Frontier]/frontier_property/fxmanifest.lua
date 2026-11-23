fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'frontier_property'
version '0.1.0'
dependencies { '/onesync', 'oxmysql', 'frontier_core', 'frontier_economy' }

server_scripts { '@oxmysql/lib/MySQL.lua', 'config.lua', 'server/registry.lua', 'server/policy.lua', 'server/survey.lua', 'server/overview.lua', 'server/land.lua', 'server/rentals.lua', 'server/survey_command.lua' }
