-- Client: Strecken-Cache, Blips, Menü, Callbacks, NUI
TrackList = {}
MenuOpen = false

-- ===== Server-Callbacks =====
local cbId, pending = 0, {}

function ServerCallback(name, ...)
    cbId = cbId + 1
    local id = cbId
    local p = promise.new()
    pending[id] = p
    TriggerServerEvent('kartbahn:cb', name, id, ...)
    SetTimeout(10000, function()
        if pending[id] then pending[id]:resolve(nil) pending[id] = nil end
    end)
    return Citizen.Await(p)
end

RegisterNetEvent('kartbahn:cbResp', function(id, data)
    local p = pending[id]
    if p then pending[id] = nil p:resolve(data) end
end)

-- ===== Benachrichtigungen =====
function Notify(msg, kind)
    SendNUIMessage({ action = 'notify', text = msg, kind = kind or 'info' })
end
RegisterNetEvent('kartbahn:notify', Notify)

RegisterNetEvent('kartbahn:record', function(data)
    SendNUIMessage({ action = 'record', text = data.text })
    PlaySoundFrontend(-1, 'MEDAL_UP', 'HUD_MINI_GAME_SOUNDSET', true)
end)

-- ===== Strecken =====
RegisterNetEvent('kartbahn:tracks', function(list)
    TrackList = list or {}
    if OnTracksUpdated then OnTracksUpdated() end
end)

CreateThread(function()
    TriggerServerEvent('kartbahn:requestTracks')
end)

-- ===== Blips =====
local blips = {}
CreateThread(function()
    for _, loc in ipairs(Config.Locations) do
        if loc.blip then
            local b = AddBlipForCoord(loc.coords.x, loc.coords.y, loc.coords.z)
            SetBlipSprite(b, Config.Blip.sprite)
            SetBlipColour(b, Config.Blip.color)
            SetBlipScale(b, Config.Blip.scale)
            SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(Config.Blip.name)
            EndTextCommandSetBlipName(b)
            blips[#blips + 1] = b
        end
    end
end)

-- ===== Menü =====
local function refreshMenu()
    local data = ServerCallback('getMenu')
    if data then SendNUIMessage({ action = 'menuData', data = data }) end
end

function OpenMenu()
    if MenuOpen then return end
    MenuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open' })
    refreshMenu()
end

function CloseMenu()
    MenuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterNetEvent('kartbahn:lobbyUpdate', function()
    if MenuOpen then refreshMenu() end
end)

-- Interaktions-Schleife: im Leerlauf nur 1x pro Sekunde
CreateThread(function()
    while true do
        local sleep = 1000
        if not MenuOpen and not IsRacing() and not IsEditing() then
            local pc = GetEntityCoords(PlayerPedId())
            for _, loc in ipairs(Config.Locations) do
                local d = #(pc - loc.coords)
                if d < Config.MarkerDrawDistance then
                    sleep = 0
                    DrawMarker(1, loc.coords.x, loc.coords.y, loc.coords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        1.5, 1.5, 0.6, 255, 204, 0, 120, false, false, 2, false, nil, nil, false)
                    if d < Config.InteractDistance then
                        BeginTextCommandDisplayHelp('STRING')
                        AddTextComponentSubstringPlayerName(KB.T('open_menu'))
                        EndTextCommandDisplayHelp(0, false, true, -1)
                        if IsControlJustReleased(0, Config.InteractKey) then OpenMenu() end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- ===== NUI-Callbacks =====
RegisterNUICallback('close', function(_, cb) CloseMenu() cb('ok') end)

RegisterNUICallback('refresh', function(_, cb) refreshMenu() cb('ok') end)

RegisterNUICallback('joinRace', function(d, cb)
    local res = ServerCallback('joinRace', d.track, d.laps) or {}
    if res.msg then Notify(res.msg, res.ok and 'success' or 'error') end
    refreshMenu()
    cb(res)
end)

RegisterNUICallback('leaveLobby', function(_, cb)
    local res = ServerCallback('leaveLobby') or {}
    if res.msg then Notify(res.msg, 'info') end
    refreshMenu()
    cb(res)
end)

RegisterNUICallback('startTT', function(d, cb)
    local res = ServerCallback('startTT', d.track) or {}
    if res.msg then Notify(res.msg, res.ok and 'success' or 'error') end
    if res.ok then CloseMenu() end
    cb(res)
end)

RegisterNUICallback('getLeaderboard', function(_, cb) cb(ServerCallback('getLeaderboard') or { rows = {} }) end)
RegisterNUICallback('getTrackTimes', function(d, cb) cb(ServerCallback('getTrackTimes', d.track) or { rows = {} }) end)
RegisterNUICallback('getRecent', function(_, cb) cb(ServerCallback('getRecent') or { rows = {} }) end)
RegisterNUICallback('closeResult', function(_, cb) SetNuiFocus(false, false) cb('ok') end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, b in ipairs(blips) do RemoveBlip(b) end
    if MenuOpen then SetNuiFocus(false, false) end
end)
