fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'frontier_economy'
description 'Persistent Frontier accounts and financial ledger'
version '1.0.0'

dependencies {
    'oxmysql',
    'frontier_lib',
    'frontier_core',
}

shared_script 'shared/banking.lua'
-- client_script 'client/banking.lua'

-- ui_page 'html/index.html'
files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@frontier_lib/shared/utils.lua',
    '@frontier_lib/server/logger.lua',
    'config.lua',
    'server/database.lua',
    'server/accounts.lua',
    'server/transactions.lua',
    'server/commands.lua',
    'server/banking.lua',
}
