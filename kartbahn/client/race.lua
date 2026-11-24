-- Client-Rennlogik: Checkpoints, Marker, GPS, HUD, Countdown, Startampel, Sektoren, Minimap
RaceState = nil  -- aktueller Renn-/Zeitfahr-Zustand (auch von features/ghost genutzt)

function IsRacing() return RaceState ~= nil end

local gpsBlip, nextBlip

local function clearGps()
    if gpsBlip then RemoveBlip(gpsBlip) gpsBlip = nil end
    if nextBlip then RemoveBlip(nextBlip) nextBlip = nil end
end

local function updateGps()
    clearGps()
    local R = RaceState
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

-- ===== 11) Sektorzeiten / Live-Delta =====
local function kvpKey(trackId) return 'kartbahn_splits_' .. trackId end

local function loadSplits(trackId)
    local raw = GetResourceKvpString(kvpKey(trackId))
    local d = raw and json.decode(raw) or nil
    return d or { cps = {}, sectors = {} }
end

local function onSplit(passed, elapsed)
    local R = RaceState
    R.cpTimes[passed] = elapsed
    local ref = R.splits.cps[tostring(passed)]
    local deltaMs = ref and (elapsed - ref) or nil
    local sectorIdx
    for k, e in ipairs(R.sectorEnds) do if e == passed then sectorIdx = k end end
    local info = { action = 'split', delta = deltaMs }
    if sectorIdx then
        local st = elapsed - (R.lastSectorEnd or 0)
        R.lastSectorEnd = elapsed
        R.curSectors[sectorIdx] = st
        local pbS = R.splits.sectors[tostring(sectorIdx)]
        local sessionBest = R.bestSectors[sectorIdx]
        -- lila = neue persönliche Sektor-Bestzeit, grün = besser als heute, gelb = langsamer
        local color = 'yellow'
        if not pbS or st < pbS then color = 'purple'
        elseif not sessionBest or st < sessionBest then color = 'green' end
        if not sessionBest or st < sessionBest then R.bestSectors[sectorIdx] = st end
        info.sector = sectorIdx
        info.sectorTime = st
        info.color = color
    end
    SendNUIMessage(info)
end

-- gültige PB-Runde: Splits lokal speichern (KVP)
local function saveSplitsIfPb(lapTime, isPb)
    local R = RaceState
    R.cpTimes[1] = lapTime
    if isPb then
        local d = { cps = {}, sectors = {} }
        for k, v in pairs(R.cpTimes) do d.cps[tostring(k)] = v end
        for k, v in pairs(R.curSectors) do d.sectors[tostring(k)] = v end
        R.splits = d
        SetResourceKvp(kvpKey(R.trackId), json.encode(d))
    end
    R.cpTimes, R.curSectors, R.lastSectorEnd = {}, {}, 0
end

local function setNextCp(idx)
    RaceState.nextCp = idx
    RaceState.pendingCp = nil
    updateGps()
    PlaySoundFrontend(-1, 'CHECKPOINT_NORMAL', 'HUD_MINI_GAME_SOUNDSET', true)
end

function StopRaceLocal()
    clearGps()
    if FeatOnStop then FeatOnStop() end
    if GhostStop then GhostStop() end
    RaceState = nil
    SendNUIMessage({ action = 'hud', show = false })
end

-- ===== Server-Events =====
RegisterNetEvent('kartbahn:prepare', function(d)
    local track = TrackList[d.trackId]
    if not track then return end
    if MenuOpen then CloseMenu() end
    RaceState = {
        sid = d.sid, type = d.type, mode = d.mode, trackId = d.trackId, track = track, laps = d.laps,
        nextCp = 2, lap = 1, started = false, finished = false, lights = 0,
        pb = d.pb, record = d.record, recordName = d.recordName, best = nil,
        standings = {}, position = d.slot, count = d.count, team = d.team,
        boost = d.boost, items = d.items,
        splits = loadSplits(d.trackId), cpTimes = {}, curSectors = {}, bestSectors = {},
        lastSectorEnd = 0, sectorEnds = KB.SectorEnds(track)
    }
    local R = RaceState
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
        ApplyKartSetup(veh, d.number, d.color) -- eigene Kart-Physik + Design
    end
    Wait(300)
    DoScreenFadeIn(500)
    updateGps()
    -- Streckenumriss für die Minimap
    local outline = {}
    for _, cp in ipairs(track.checkpoints) do outline[#outline + 1] = { cp.x, cp.y } end
    SendNUIMessage({
        action = 'hud', show = true, type = R.type, mode = d.mode, modeLabel = d.modeLabel,
        trackName = track.name, laps = R.laps, pb = R.pb, record = R.record, cps = #track.checkpoints,
        boost = d.boost, charge = d.charge, items = d.items, sectors = Config.Sectors.Count,
        outline = Config.Minimap.Enabled and outline or nil,
        team = d.team and Config.Teams.List[d.team] or nil
    })
    if FeatOnPrepare then FeatOnPrepare(d) end
    if GhostPrepare then GhostPrepare(d.ghost) end
    StartRaceThread()
end)

-- Countdown inkl. 15) Startampel
RegisterNetEvent('kartbahn:countdown', function(sec)
    CreateThread(function()
        for i = sec, 1, -1 do
            if RaceState then RaceState.lights = sec - i + 1 RaceState.lightsMax = sec end
            SendNUIMessage({ action = 'countdown', value = tostring(i) })
            PlaySoundFrontend(-1, '3_2_1', 'HUD_MINI_GAME_SOUNDSET', true)
            Wait(1000)
        end
    end)
end)

RegisterNetEvent('kartbahn:go', function()
    SendNUIMessage({ action = 'countdown', value = 'GO' })
    PlaySoundFrontend(-1, 'GO', 'HUD_MINI_GAME_SOUNDSET', true)
    local R = RaceState
    if not R then return end
    R.started = true
    R.goAt = GetGameTimer()
    R.startLocal = R.goAt
    R.lapLocal = R.goAt
    R.lights = -1 -- grün
    if FeatOnGo then FeatOnGo() end
    if GhostLapStart then GhostLapStart() end
end)

RegisterNetEvent('kartbahn:cpOk', function(idx, elapsed)
    local R = RaceState
    if not R then return end
    local passed = (idx == 1) and #R.track.checkpoints or (idx - 1)
    if elapsed then
        R.lapLocal = GetGameTimer() - elapsed -- Uhr an Server-Messung angleichen
        onSplit(passed, elapsed)
    end
    setNextCp(idx)
end)

-- Korrekter Stand vom Server (nach ungültiger Meldung)
RegisterNetEvent('kartbahn:sync', function(d)
    local R = RaceState
    if not R then return end
    R.nextCp, R.lap, R.pendingCp = d.nextCp, d.lap, nil
    local t = GetGameTimer()
    R.lapLocal = t - d.lapElapsed
    R.startLocal = t - d.raceElapsed
    updateGps()
end)

RegisterNetEvent('kartbahn:lap', function(d)
    local R = RaceState
    if not R then return end
    -- letzter Sektor endet an Start/Ziel
    onSplit(1, d.time)
    if d.valid then saveSplitsIfPb(d.time, d.pb) else R.cpTimes, R.curSectors, R.lastSectorEnd = {}, {}, 0 end
    if GhostLapDone then GhostLapDone(d) end
    R.lap = d.lap
    R.best = d.best
    R.pb = d.pbTime or R.pb
    R.record = d.recordTime or R.record
    R.lapLocal = GetGameTimer()
    R.lastLap = d.time
    R.finished = d.finished or R.finished
    if R.finished then clearGps() else setNextCp(2) end
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
    local R = RaceState
    if not R then return end
    R.finished = true
    clearGps()
    SendNUIMessage({ action = 'banner', text = KB.T('finished', pos) })
    PlaySoundFrontend(-1, 'FIRST_PLACE', 'HUD_MINI_GAME_SOUNDSET', true)
end)

RegisterNetEvent('kartbahn:standings', function(rows)
    local me = GetPlayerServerId(PlayerId())
    if RaceState then
        RaceState.standings = rows
        for _, r in ipairs(rows) do if r.src == me then RaceState.position = r.pos end end
        RaceState.count = #rows
    end
    if SpectateStandings then SpectateStandings(rows) end
    local teams = {}
    for _, r in ipairs(rows) do if r.team then teams[r.src] = Config.Teams.List[r.team].hex end end
    SendNUIMessage({ action = 'standings', rows = rows, me = me, teamColors = teams })
end)

RegisterNetEvent('kartbahn:banner', function(text, kind)
    SendNUIMessage({ action = 'banner', text = text, kind = kind })
end)

RegisterNetEvent('kartbahn:outWarn', function(left)
    SendNUIMessage({ action = 'banner', text = KB.T('out_of_kart', left), kind = 'error' })
end)

RegisterNetEvent('kartbahn:stopDriving', function()
    if RaceState then RaceState.finished = true clearGps() end
end)

RegisterNetEvent('kartbahn:result', function(d)
    local wasSpectating = IsSpectating and IsSpectating()
    StopRaceLocal()
    CreateThread(function()
        -- 14) Siegerpodest vor dem Ergebnis-Fenster
        if d.type == 'race' and d.podium and PlayPodium then PlayPodium(d) end
        if wasSpectating and StopSpectate then StopSpectate() end
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'result', data = d })
    end)
end)

-- ===== Zeichnen =====
local function drawCpMarkers(R)
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

-- 15) Startampel über der Startlinie (Kugel-Marker)
local function drawStartLights(R)
    if not Config.StartLights.Enabled or not R.lights or R.lights == 0 then return end
    if R.lights == -1 and GetGameTimer() - (R.goAt or 0) > 2500 then R.lights = 0 return end
    local cps = R.track.checkpoints
    local cp = cps[1]
    local dx, dy = KB.CpDirection(cps, 1)
    local nx, ny = -dy, dx
    local maxL = R.lightsMax or 3
    for i = 1, maxL do
        local off = (i - (maxL + 1) / 2) * Config.StartLights.Spacing
        local x, y, z = cp.x + nx * off, cp.y + ny * off, cp.z + Config.StartLights.Height
        local r, g, b = 40, 40, 40
        if R.lights == -1 then r, g, b = 34, 197, 94 elseif i <= R.lights then r, g, b = 239, 68, 68 end
        DrawMarker(28, x, y, z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.55, 0.55, 0.55, r, g, b, 230, false, false, 2, false, nil, nil, false)
    end
end

-- ===== Haupt-Schleife (läuft nur während einer Session) =====
function StartRaceThread()
    CreateThread(function()
        local lastHud = 0
        local me = GetPlayerServerId(PlayerId())
        while RaceState do
            local R = RaceState
            local ped = PlayerPedId()
            local pc = GetEntityCoords(ped)
            local veh = GetVehiclePedIsIn(ped, false)
            drawStartLights(R)

            if not R.started then
                DisableControlAction(0, 71, true) -- Gas
                DisableControlAction(0, 72, true) -- Bremse
                DisableControlAction(0, 75, true) -- Aussteigen
            elseif not R.finished then
                drawCpMarkers(R)
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
            -- Absturz von der angehobenen Strecke: automatisch zurücksetzen
            if R.started and not R.finished and veh ~= 0 and R.track.platform and not R.resetPending then
                local ref = R.track.checkpoints[R.nextCp == 1 and #R.track.checkpoints or R.nextCp - 1]
                if pc.z < ref.z - Config.Platform.FallReset and pc.z < R.track.checkpoints[R.nextCp].z - Config.Platform.FallReset then
                    R.resetPending = GetGameTimer()
                    TriggerServerEvent('kartbahn:resetReq')
                end
            end
            if R.resetPending and GetGameTimer() - R.resetPending > 3500 then R.resetPending = nil end
            if FeatTick then FeatTick(R, ped, veh, pc) end
            if GhostTick then GhostTick(R, ped, veh) end

            local t = GetGameTimer()
            if t - lastHud > 100 then
                lastHud = t
                local speed = veh ~= 0 and GetEntitySpeed(veh) * 3.6 or 0.0
                -- 12) Minimap-Punkte: eigene Position + andere Fahrer
                local dots = nil
                if Config.Minimap.Enabled then
                    dots = { { pc.x, pc.y, 1 } }
                    for _, row in ipairs(R.standings or {}) do
                        if row.src ~= me and not row.dnf and not row.out then
                            local pl = GetPlayerFromServerId(row.src)
                            local op = pl ~= -1 and GetPlayerPed(pl) or 0
                            if op ~= 0 and DoesEntityExist(op) then
                                local oc = GetEntityCoords(op)
                                dots[#dots + 1] = { oc.x, oc.y, 0, row.team }
                            elseif row.x then
                                dots[#dots + 1] = { row.x, row.y, 0, row.team }
                            end
                        end
                    end
                    if GhostPos then
                        local gx, gy = GhostPos()
                        if gx then dots[#dots + 1] = { gx, gy, 2 } end
                    end
                end
                SendNUIMessage({
                    action = 'hudTick',
                    speed = math.floor(speed),
                    lap = math.min(R.lap, R.laps or R.lap), laps = R.laps,
                    cp = (R.nextCp == 1) and #R.track.checkpoints or (R.nextCp - 1),
                    cps = #R.track.checkpoints,
                    lapTime = (R.started and not R.finished) and (t - R.lapLocal) or nil,
                    total = (R.started and R.type == 'race' and not R.finished) and (t - R.startLocal) or nil,
                    best = R.best, pb = R.pb, record = R.record,
                    pos = R.position, count = R.count, type = R.type, dots = dots
                })
            end
            Wait(0)
        end
    end)
end

RegisterNetEvent('kartbahn:resetTo', function(p)
    local R = RaceState
    if not R then return end
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh == 0 then veh = R.veh end
    if not veh or not DoesEntityExist(veh) then return end
    DoScreenFadeOut(150)
    Wait(200)
    SetEntityCoords(veh, p.x, p.y, p.z, false, false, false, false)
    SetEntityHeading(veh, p.h)
    SetEntityVelocity(veh, 0.0, 0.0, 0.0)
    SetVehicleFixed(veh)
    if GetVehiclePedIsIn(PlayerPedId(), false) ~= veh then TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1) end
    Wait(150)
    DoScreenFadeIn(300)
    R.pendingCp = nil
    SendNUIMessage({ action = 'banner', text = KB.T('reset_done'), kind = 'error' })
end)

-- manuell zurücksetzen (z. B. festgefahren)
RegisterCommand('kartreset', function()
    if RaceState and RaceState.started then TriggerServerEvent('kartbahn:resetReq') end
end, false)

RegisterCommand('kartleave', function()
    TriggerServerEvent('kartbahn:stopRequest')
end, false)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearGps()
end)
