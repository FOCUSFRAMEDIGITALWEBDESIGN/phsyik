fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'kartbahn'
author 'kartbahn'
description 'Kartbahn mit Rennen, Zeitfahren, Elo-Ranking und Strecken-Editor (Standalone / ESX / QBCore)'
version '1.0.0'

shared_scripts {
    'config.lua',
    'shared/utils.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/bridge.lua',
    'server/db.lua',
    'server/elo.lua',
    'server/tracks.lua',
    'server/main.lua',
    'server/race.lua',
    'server/editor.lua'
}

client_scripts {
    'client/main.lua',
    'client/track.lua',
    'client/race.lua',
    'client/editor.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js'
}

dependencies {
    'oxmysql'
}
