fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'frontier_property'
version '0.1.0'
dependencies { '/onesync', 'oxmysql', 'frontier_core', 'frontier_economy', 'frontier_inventory' }

shared_script 'shared/agents.lua'
server_scripts { '@oxmysql/lib/MySQL.lua', 'config.lua', 'server/world_data.lua', 'server/world_policy.lua', 'server/defaults.lua', 'server/registry.lua', 'server/agents.lua', 'server/policy.lua', 'server/survey.lua', 'server/overview.lua', 'server/land.lua', 'server/rentals.lua', 'server/survey_command.lua', 'server/planner.lua', 'server/furniture.lua', 'server/sales.lua', 'server/construction.lua', 'server/foreclosure.lua' }

client_script 'client/furniture.lua'

client_script 'client/agents.lua'
ui_page 'html/agent.html'
files { 'html/agent.html', 'html/agent.css', 'html/agent.js', 'html/planner.js' }

client_script 'client/build_preview.lua'
