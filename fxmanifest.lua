fx_version 'cerulean'
game 'gta5'

author 'RyanDEV'
description ''
version '1.0.0'
lua54 'yes'
dependencies {
    'qb-core',
    'ox_lib',
    'bl_idcard',
    'ox_target',
    'ox_inventory',
    --'menuv'
}

shared_script {
    '@ox_lib/init.lua',
	'@qb-core/shared/locale.lua',
    'config.lua',
	'locales/*.lua',
}

client_scripts {
    'client/*.lua'
}

server_scripts {
    'server/*.lua'
}

files {
    'stream/**'
}


