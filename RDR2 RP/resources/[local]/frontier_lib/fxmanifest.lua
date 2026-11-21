fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware that resources may become incompatible once RedM ships.'
lua54 'yes'

name 'frontier_lib'
description 'Shared utilities for the Frontier framework'
version '0.1.0'

shared_scripts {
    'shared/utils.lua',
}

server_scripts {
    'server/logger.lua',
}
