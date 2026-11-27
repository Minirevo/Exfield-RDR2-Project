fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'
version '0.2.0'
dependencies {'/onesync','oxmysql','frontier_core','frontier_inventory','frontier_economy','frontier_property','frontier_business','frontier_skills','frontier_production','vorp_stables'}
shared_scripts {'config.lua','shared/rules.lua'}
server_scripts {'@oxmysql/lib/MySQL.lua','server/modeltest.lua','server/runtime.lua','server/wagons.lua','server/cargo.lua','server/contracts.lua','server/trade.lua','server/main.lua'}
client_scripts {'client/modeltest.lua','client/main.lua'}
ui_page 'html/index.html'
files {'html/index.html','html/style.css','html/app.js'}
