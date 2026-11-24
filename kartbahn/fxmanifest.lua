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
    'server/features.lua',
    'server/race.lua',
    'server/editor.lua'
}

client_scripts {
    'client/main.lua',
    'client/kart.lua',
    'client/features.lua',
    'client/ghost.lua',
    'client/spectate.lua',
    'client/podium.lua',
    'client/track.lua',
    'client/race.lua',
    'client/editor.lua'
}

ui_page 'html/index.html'

files {
    'data/meta/handling.meta',
    'html/index.html',
    'html/style.css',
    'html/app.js'
}

dependencies {
    'oxmysql'
}

-- Eigenes Kart-Handling als Mod-Datei (wird beim Verbinden geladen)
data_file 'HANDLING_FILE' 'data/meta/handling.meta'
