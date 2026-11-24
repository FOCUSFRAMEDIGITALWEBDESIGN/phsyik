-- Client-Rennlogik: Checkpoints, Marker, GPS, HUD, Countdown
local R = nil  -- aktueller Renn-/Zeitfahr-Zustand

function IsRacing() return R ~= nil end

local gpsBlip, nextBlip

local function clearGps()
    if gpsBlip then RemoveBlip(gpsBlip) gpsBlip = nil end
    if nextBlip then RemoveBlip(nextBlip) nextBlip = nil end
end

local function updateGps()
    clearGps()
    if not R or R.finished then return end
    local cps = R.track.checkpoints
    local cp = cps[R.nextCp]
    gpsBlip = AddBlipForCoord(cp.x, cp.y, cp.z)
    SetBlipSprite(gpsBlip, 1)
    SetBlipColour(gpsBlip, Config.Track.GpsColor)
    SetBlipRoute(gpsBlip, true)
    SetBlipRouteColour(gpsBlip, Config.Track.GpsColor)
    local n = cps[R.nextCp % #cps + 1]
    nextBlip = AddBlipForCoord(n.x, n.y, n.z)
    SetBlipSprite(nextBlip, 1)
    SetBlipScale(nextBlip, 0.6)
    SetBlipColour(nextBlip, Config.Track.GpsColor)
end

local function setNextCp(idx)
    R.nextCp = idx
    R.pendingCp = nil
    updateGps()
    PlaySoundFrontend(-1, 'CHECKPOINT_NORMAL', 'HUD_MINI_GAME_SOUNDSET', true)
end

local function stopRace()
    clearGps()
    R = nil
    SendNUIMessage({ action = 'hud', show = false })
end

-- ===== Server-Events =====
RegisterNetEvent('kartbahn:prepare', function(d)
    local track = TrackList[d.trackId]
    if not track then return end
    if MenuOpen then CloseMenu() end
    R = {
        sid = d.sid, type = d.type, trackId = d.trackId, track = track, laps = d.laps,
        nextCp = 2, lap = 1, started = false, finished = false,
        pb = d.pb, record = d.record, recordName = d.recordName, best = nil,
        standings = {}, position = d.slot, count = d.count
    }
    DoScreenFadeOut(300)
    Wait(350)
    -- Warten, bis das servergespawnte Kart beim Client existiert
    local t = GetGameTimer()
    while not NetworkDoesNetworkIdExist(d.netId) and GetGameTimer() - t < 5000 do Wait(50) end
    if NetworkDoesNetworkIdExist(d.netId) then
        local veh = NetToVeh(d.netId)
        R.veh = veh
        TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
        SetVehicleEngineOn(veh, true, true, false)
        SetVehRadioStation(veh, 'OFF')
    end
    Wait(300)
    DoScreenFadeIn(500)
    updateGps()
    SendNUIMessage({
        action = 'hud', show = true, type = R.type, trackName = track.name, laps = R.laps,
        pb = R.pb, record = R.record, cps = #track.checkpoints
    })
    StartRaceThread()
end)

RegisterNetEvent('kartbahn:countdown', function(sec)
    CreateThread(function()
        for i = sec, 1, -1 do
            SendNUIMessage({ action = 'countdown', value = tostring(i) })
            PlaySoundFrontend(-1, '3_2_1', 'HUD_MINI_GAME_SOUNDSET', true)
            Wait(1000)
        end
    end)
end)

RegisterNetEvent('kartbahn:go', function()
    if not R then return end
    R.started = true
    R.startLocal = GetGameTimer()
    R.lapLocal = R.startLocal
    SendNUIMessage({ action = 'countdown', value = 'GO' })
    PlaySoundFrontend(-1, 'GO', 'HUD_MINI_GAME_SOUNDSET', true)
end)

RegisterNetEvent('kartbahn:cpOk', function(idx)
    if R then setNextCp(idx) end
end)

-- Korrekter Stand vom Server (nach ungültiger Meldung)
RegisterNetEvent('kartbahn:sync', function(d)
    if not R then return end
    R.nextCp, R.lap, R.pendingCp = d.nextCp, d.lap, nil
    local t = GetGameTimer()
    R.lapLocal = t - d.lapElapsed
    R.startLocal = t - d.raceElapsed
    updateGps()
end)

RegisterNetEvent('kartbahn:lap', function(d)
    if not R then return end
    R.lap = d.lap
    R.best = d.best
    R.pb = d.pbTime or R.pb
    R.record = d.recordTime or R.record
    R.lapLocal = GetGameTimer()
    R.lastLap = d.time
    R.finished = d.finished
    if d.finished then clearGps() else setNextCp(2) end
    local kind = (not d.valid) and 'invalid' or (d.record and 'record' or (d.pb and 'pb' or 'normal'))
    SendNUIMessage({ action = 'lap', kind = kind, time = d.time, lap = d.lap - 1, best = d.best,
        pb = R.pb, record = R.record })
    if kind == 'record' or kind == 'pb' then
        PlaySoundFrontend(-1, 'MEDAL_UP', 'HUD_MINI_GAME_SOUNDSET', true)
    elseif kind == 'invalid' then
        PlaySoundFrontend(-1, 'LOSER', 'HUD_AWARDS', true)
    end
end)

RegisterNetEvent('kartbahn:finished', function(pos)
    if not R then return end
    R.finished = true
    clearGps()
    SendNUIMessage({ action = 'banner', text = KB.T('finished', pos) })
    PlaySoundFrontend(-1, 'FIRST_PLACE', 'HUD_MINI_GAME_SOUNDSET', true)
end)

RegisterNetEvent('kartbahn:standings', function(rows)
    if not R then return end
    R.standings = rows
    local me = GetPlayerServerId(PlayerId())
    for _, r in ipairs(rows) do if r.src == me then R.position = r.pos end end
    R.count = #rows
    SendNUIMessage({ action = 'standings', rows = rows, me = me })
end)

RegisterNetEvent('kartbahn:outWarn', function(left)
    SendNUIMessage({ action = 'banner', text = KB.T('out_of_kart', left), kind = 'error' })
end)

RegisterNetEvent('kartbahn:stopDriving', function()
    if R then R.finished = true clearGps() end
end)

RegisterNetEvent('kartbahn:result', function(d)
    stopRace()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'result', data = d })
end)

-- ===== Haupt-Schleife (läuft nur während einer Session) =====
local function drawCpMarkers()
    local cps = R.track.checkpoints
    local cp = cps[R.nextCp]
    local isFinish = R.nextCp == 1
    local c = isFinish and Config.Track.FinishColor or Config.Track.CpMarkerColor
    DrawMarker(1, cp.x, cp.y, cp.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, cp.w, cp.w, 2.5,
        c[1], c[2], c[3], c[4], false, false, 2, false, nil, nil, false)
    if isFinish then
        DrawMarker(4, cp.x, cp.y, cp.z + 4.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3.0, 3.0, 3.0,
            255, 255, 255, 200, false, true, 2, false, nil, nil, false)
    end
    -- Pfeil zum nächsten Checkpoint
    local n = cps[R.nextCp % #cps + 1]
    local heading = math.deg(math.atan(n.y - cp.y, n.x - cp.x)) - 90.0
    local a = Config.Track.ArrowColor
    DrawMarker(21, cp.x, cp.y, cp.z + 3.0, 0.0, 0.0, 0.0, -90.0, 0.0, heading, 2.0, 2.0, 2.0,
        a[1], a[2], a[3], a[4], false, false, 2, false, nil, nil, false)
end

function StartRaceThread()
    CreateThread(function()
        local lastHud = 0
        while R do
            local ped = PlayerPedId()
            local pc = GetEntityCoords(ped)

            if not R.started then
                DisableControlAction(0, 71, true) -- Gas
                DisableControlAction(0, 72, true) -- Bremse
                DisableControlAction(0, 75, true) -- Aussteigen
            elseif not R.finished then
                drawCpMarkers()
                -- Checkpoint-Erkennung; Server prüft Reihenfolge und Position
                local cp = R.track.checkpoints[R.nextCp]
                if not R.pendingCp and KB.Dist2D(pc.x, pc.y, cp.x, cp.y) <= cp.w / 2 and math.abs(pc.z - cp.z) < 8.0 then
                    R.pendingCp = R.nextCp
                    R.pendingAt = GetGameTimer()
                    TriggerServerEvent('kartbahn:cp', R.sid, R.nextCp)
                elseif R.pendingCp and GetGameTimer() - R.pendingAt > 2000 then
                    R.pendingCp = nil
                end
            end

            local t = GetGameTimer()
            if t - lastHud > 100 then
                lastHud = t
                local veh = GetVehiclePedIsIn(ped, false)
                local speed = veh ~= 0 and GetEntitySpeed(veh) * 3.6 or 0.0
                SendNUIMessage({
                    action = 'hudTick',
                    speed = math.floor(speed),
                    lap = math.min(R.lap, R.laps or R.lap), laps = R.laps,
                    cp = (R.nextCp == 1) and #R.track.checkpoints or (R.nextCp - 1),
                    cps = #R.track.checkpoints,
                    lapTime = (R.started and not R.finished) and (t - R.lapLocal) or nil,
                    total = (R.started and R.type == 'race' and not R.finished) and (t - R.startLocal) or nil,
                    best = R.best, pb = R.pb, record = R.record,
                    pos = R.position, count = R.count, type = R.type
                })
            end
            Wait(0)
        end
    end)
end

RegisterCommand('kartleave', function()
    TriggerServerEvent('kartbahn:stopRequest')
end, false)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearGps()
end)
