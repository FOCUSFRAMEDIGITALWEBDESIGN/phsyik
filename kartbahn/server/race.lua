-- Renn- und Zeitfahr-Sessions (serverseitig autoritativ)
Race = {}

local Sessions = {}       -- [id] = session
local PlayerSession = {}  -- [src] = id
local Lobbies = {}        -- [trackId] = id (Rennen pro Strecke)
local nextId = 0

local function now() return GetGameTimer() end

local function count(t) local c = 0 for _ in pairs(t) do c = c + 1 end return c end

local function broadcastLobbies()
    TriggerClientEvent('kartbahn:lobbyUpdate', -1)
end

local function sendSession(s, event, ...)
    for src in pairs(s.racers) do TriggerClientEvent(event, src, ...) end
end

-- ===== Info für das Menü =====
function Race.GetLobbyInfo(trackId)
    local s = Sessions[Lobbies[trackId] or -1]
    if not s then return nil end
    return {
        state = s.state, count = count(s.racers), max = Config.Race.MaxPlayers, laps = s.laps,
        timeLeft = s.state == 'lobby' and math.max(0, math.ceil((s.lobbyEnd - now()) / 1000)) or 0
    }
end

function Race.GetPlayerSessionInfo(src)
    local s = Sessions[PlayerSession[src] or -1]
    if not s then return nil end
    return { type = s.type, trackId = s.trackId, state = s.state }
end

-- ===== Fahrzeuge =====
local function deleteKart(r)
    if r.veh and DoesEntityExist(r.veh) then DeleteEntity(r.veh) end
    r.veh = nil
end

local function spawnKart(src, slot)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    -- Spieler zuerst teleportieren, damit das Fahrzeug für ihn gestreamt wird
    SetEntityCoords(ped, slot.x, slot.y, slot.z + 1.0, false, false, false, false)
    Wait(300)
    local model = Config.KartModels[math.random(#Config.KartModels)]
    local veh = CreateVehicleServerSetter(joaat(model), 'automobile', slot.x, slot.y, slot.z + 0.4, slot.h)
    local t = now()
    while not DoesEntityExist(veh) and now() - t < 3000 do Wait(0) end
    if not DoesEntityExist(veh) then return nil end
    SetVehicleNumberPlateText(veh, Config.KartPlate)
    FreezeEntityPosition(veh, true)
    SetEntityOrphanMode(veh, 0)
    return veh, NetworkGetNetworkIdFromEntity(veh)
end

-- ===== Session-Hilfen =====
local function newRacer(src)
    local ident = Bridge.GetIdentifier(src)
    local name = Bridge.GetName(src)
    local prof = DB.GetProfile(ident, name)
    return {
        src = src, cid = ident, name = name, rating = prof.rating,
        lap = 0, nextCp = 2, lapStart = 0, lastCp = 0, lapInvalid = false,
        bestLap = nil, laps = {}, validLaps = 0, finished = false, finishTime = nil,
        dnf = false, outSince = nil, progress = 0.0, paid = 0, pb = nil
    }
end

local function resync(s, r)
    local t = now()
    TriggerClientEvent('kartbahn:sync', r.src, {
        nextCp = r.nextCp, lap = r.lap,
        lapElapsed = s.startTime and (t - r.lapStart) or 0,
        raceElapsed = s.startTime and (t - s.startTime) or 0
    })
end

local function removePlayer(src)
    PlayerSession[src] = nil
end

-- Platzierung berechnen (Ziel-Reihenfolge, sonst Fortschritt)
local function computeOrder(s)
    local list = {}
    for _, r in pairs(s.racers) do list[#list + 1] = r end
    table.sort(list, function(a, b)
        if a.dnf ~= b.dnf then return not a.dnf end
        if a.finished ~= b.finished then return a.finished end
        if a.finished then return a.finishTime < b.finishTime end
        if a.progress ~= b.progress then return a.progress > b.progress end
        return a.src < b.src
    end)
    return list
end

local function updateProgress(s, r)
    if r.finished or r.dnf then return end
    local cps = s.track.checkpoints
    local n = #cps
    local passed = (r.nextCp == 1) and n or (r.nextCp - 1) -- bereits passierte CPs in dieser Runde
    local frac = 0.0
    local ped = GetPlayerPed(r.src)
    if ped ~= 0 then
        local pc = GetEntityCoords(ped)
        local target = cps[r.nextCp]
        local prev = cps[r.nextCp == 1 and n or r.nextCp - 1]
        local seg = KB.Dist2D(prev.x, prev.y, target.x, target.y)
        local d = KB.Dist2D(pc.x, pc.y, target.x, target.y)
        if seg > 0 then frac = math.max(0.0, math.min(1.0, 1.0 - d / seg)) end
    end
    r.progress = (r.lap - 1) * n + passed + frac
end

local function sendStandings(s)
    local order = computeOrder(s)
    local rows = {}
    for i, r in ipairs(order) do
        rows[i] = {
            pos = i, src = r.src, name = r.name, lap = math.min(r.lap, s.laps or r.lap),
            best = r.bestLap, finished = r.finished, dnf = r.dnf,
            time = r.finishTime
        }
    end
    sendSession(s, 'kartbahn:standings', rows)
end

-- ===== Rennende =====
local function cleanupSession(s)
    for src, r in pairs(s.racers) do
        deleteKart(r)
        if PlayerSession[src] == s.id then removePlayer(src) end
    end
    if Lobbies[s.trackId] == s.id then Lobbies[s.trackId] = nil end
    Sessions[s.id] = nil
    broadcastLobbies()
end

local function endRace(s)
    if s.state == 'finished' then return end
    s.state = 'finished'
    local order = computeOrder(s)
    local finishers = 0
    for _, r in ipairs(order) do if r.finished then finishers = finishers + 1 end end

    -- Plätze (DNFs teilen sich den letzten Platz)
    local entries = {}
    for i, r in ipairs(order) do
        r.place = r.finished and i or (finishers + 1)
        entries[#entries + 1] = { key = r.src, rating = r.rating, place = r.place }
    end
    local deltas = Elo.Calculate(entries)

    local results = {}
    for _, r in ipairs(order) do
        local prize = 0
        if r.finished and not Bridge.IsFree() then prize = Config.Race.Prizes[r.place] or 0 end
        local delta = deltas[r.src] or 0
        local newRating = math.max(0, r.rating + delta)
        if prize > 0 and GetPlayerPing(r.src) > 0 then
            Bridge.AddMoney(r.src, prize)
            Notify(r.src, KB.T('prize', prize), 'success')
        end
        DB.UpdateAfterRace(r.cid, {
            rating = newRating, win = r.finished and r.place == 1, podium = r.finished and r.place <= 3,
            dnf = r.dnf or not r.finished, prize = prize
        })
        results[#results + 1] = {
            place = r.place, name = r.name, identifier = r.cid, finished = r.finished, dnf = not r.finished,
            time = r.finishTime, best = r.bestLap, oldRating = r.rating, newRating = newRating,
            delta = delta, prize = prize, src = r.src
        }
    end
    DB.InsertRace(s.trackId, s.laps, results)

    for src in pairs(s.racers) do
        TriggerClientEvent('kartbahn:result', src, {
            type = 'race', trackName = s.track.name, laps = s.laps, results = results, me = src,
            tiers = Config.Tiers
        })
    end
    SetTimeout(Config.Race.CleanupDelay * 1000, function() cleanupSession(s) end)
end

local function endTimeTrial(s, reason)
    if s.state == 'finished' then return end
    s.state = 'finished'
    for src, r in pairs(s.racers) do
        TriggerClientEvent('kartbahn:result', src, {
            type = 'tt', trackName = s.track.name, laps = r.laps, best = r.bestLap, pb = r.pb,
            record = Records.Get(s.trackId), reason = reason
        })
    end
    cleanupSession(s)
end

local function setDnf(s, r)
    if r.dnf or r.finished then return end
    r.dnf = true
    deleteKart(r)
    Notify(r.src, KB.T('dnf'), 'error')
    TriggerClientEvent('kartbahn:stopDriving', r.src)
end

-- ===== Runde abgeschlossen =====
local function lapDone(s, r)
    local t = now()
    local lapTime = t - r.lapStart
    r.lapStart = t
    local valid = (not r.lapInvalid) and lapTime >= s.track.minLap
    r.lapInvalid = false
    local isPB, isRecord = false, false
    if valid then
        r.validLaps = r.validLaps + 1
        if not r.bestLap or lapTime < r.bestLap then r.bestLap = lapTime end
        if not r.pb or lapTime < r.pb then r.pb = lapTime isPB = true end
        isRecord = Records.Submit(s.trackId, r.cid, r.name, lapTime)
        DB.InsertLap(r.cid, r.name, s.trackId, lapTime, s.type)
        if isRecord then
            TriggerClientEvent('kartbahn:record', -1, {
                track = s.track.name, name = r.name, time = lapTime,
                text = KB.T('record_all', s.track.name, KB.FormatTime(lapTime), r.name)
            })
        end
    end
    r.laps[#r.laps + 1] = { time = lapTime, valid = valid }
    r.lap = r.lap + 1
    r.nextCp = 2

    local finished = false
    if s.type == 'race' and r.lap > s.laps then
        finished = true
        r.finished = true
        r.finishTime = t - s.startTime
        if not s.firstFinish then
            s.firstFinish = t
            sendSession(s, 'kartbahn:notify', KB.T('first_finish', r.name, Config.Race.FinishTimeout), 'info')
        end
    end

    TriggerClientEvent('kartbahn:lap', r.src, {
        lap = r.lap, time = lapTime, valid = valid, pb = isPB, record = isRecord,
        best = r.bestLap, pbTime = r.pb, recordTime = (Records.Get(s.trackId) or {}).time,
        finished = finished
    })
    if finished then
        local pos = 0
        for i, o in ipairs(computeOrder(s)) do if o == r then pos = i end end
        TriggerClientEvent('kartbahn:finished', r.src, pos)
    end
end

-- ===== Checkpoint-Meldung vom Client =====
RegisterNetEvent('kartbahn:cp', function(sid, idx)
    local src = source
    local s = Sessions[PlayerSession[src] or -1]
    if not s or s.id ~= sid or s.state ~= 'running' then return end
    local r = s.racers[src]
    if not r or r.finished or r.dnf then return end
    idx = tonumber(idx)
    local cps = s.track.checkpoints
    -- 1. richtige Reihenfolge
    if idx ~= r.nextCp then return resync(s, r) end
    local cp = cps[idx]
    -- 2. Positionsprüfung auf dem Server
    local pc = GetEntityCoords(GetPlayerPed(src))
    if KB.Dist2D(pc.x, pc.y, cp.x, cp.y) > cp.w / 2 + Config.AntiCheat.CpTolerance or math.abs(pc.z - cp.z) > 15.0 then
        return resync(s, r)
    end
    -- 3. Mindestabstand zwischen Checkpoints
    local t = now()
    if t - r.lastCp < Config.AntiCheat.MinCpInterval then return resync(s, r) end
    r.lastCp = t

    if idx == 1 then
        lapDone(s, r)
    else
        r.nextCp = (idx % #cps) + 1
        TriggerClientEvent('kartbahn:cpOk', src, r.nextCp)
    end
end)

-- ===== Ablauf einer Session (Spawn, Countdown, Rennen) =====
local function runSession(s)
    s.state = 'preparing'
    local order = {}
    for _, r in pairs(s.racers) do order[#order + 1] = r end
    -- Startaufstellung: niedrigstes Rating vorne, die Besten starten hinten
    table.sort(order, function(a, b)
        if a.rating ~= b.rating then return a.rating < b.rating end
        return a.src < b.src
    end)

    for i, r in ipairs(order) do
        local slot = s.track.grid[i] or s.track.grid[#s.track.grid]
        r.pb = DB.GetPB(r.cid, s.trackId)
        local veh, netId = spawnKart(r.src, slot)
        if not veh then
            Notify(r.src, KB.T('spawn_failed'), 'error')
            if s.type == 'race' then
                r.dnf = true
            else
                return endTimeTrial(s)
            end
        else
            r.veh, r.netId = veh, netId
            local rec = Records.Get(s.trackId)
            TriggerClientEvent('kartbahn:prepare', r.src, {
                sid = s.id, type = s.type, trackId = s.trackId, netId = netId, slot = i,
                laps = s.laps, pb = r.pb, record = rec and rec.time or nil,
                recordName = rec and rec.name or nil, count = #order
            })
        end
    end

    Wait(Config.Race.PrepareTime * 1000)
    if s.state == 'finished' then return end
    s.state = 'countdown'
    sendSession(s, 'kartbahn:countdown', Config.Race.CountdownTime)
    Wait(Config.Race.CountdownTime * 1000)
    if s.state == 'finished' then return end

    s.startTime = now()
    s.state = 'running'
    for _, r in pairs(s.racers) do
        r.lap, r.nextCp, r.lapStart, r.lastCp = 1, 2, s.startTime, 0
        if r.veh then FreezeEntityPosition(r.veh, false) end
    end
    sendSession(s, 'kartbahn:go')
    broadcastLobbies()

    -- Server-Tick: Kart-Kontrolle, Platzierung, Rennende
    while s.state == 'running' do
        Wait(1000)
        local t = now()
        local active = 0
        for src, r in pairs(s.racers) do
            if not r.finished and not r.dnf then
                active = active + 1
                local ped = GetPlayerPed(src)
                local inKart = ped ~= 0 and r.veh and DoesEntityExist(r.veh) and GetVehiclePedIsIn(ped, false) == r.veh
                if inKart then
                    r.outSince = nil
                else
                    r.outSince = r.outSince or t
                    r.lapInvalid = true -- Runde ungültig, sobald das Kart verlassen wurde
                    local limit = (s.type == 'race' and Config.Race.ExitDnfTime or Config.TimeTrial.ExitEndTime) * 1000
                    local left = math.ceil((limit - (t - r.outSince)) / 1000)
                    if left <= 0 then
                        if s.type == 'race' then setDnf(s, r) else endTimeTrial(s, 'exit') end
                    else
                        TriggerClientEvent('kartbahn:outWarn', src, left)
                    end
                end
                updateProgress(s, r)
            end
        end
        if s.state ~= 'running' then break end
        if s.type == 'race' then
            sendStandings(s)
            if active == 0 then
                endRace(s)
            elseif s.firstFinish and t - s.firstFinish >= Config.Race.FinishTimeout * 1000 then
                for _, r in pairs(s.racers) do if not r.finished then r.dnf = true end end
                endRace(s)
            end
        end
    end
end

-- ===== Lobby =====
local function lobbyThread(s)
    CreateThread(function()
        while s.state == 'lobby' do
            Wait(500)
            local c = count(s.racers)
            if c == 0 then
                Lobbies[s.trackId] = nil
                Sessions[s.id] = nil
                broadcastLobbies()
                return
            end
            if now() >= s.lobbyEnd then
                if c < Config.Race.MinPlayers then
                    for src, r in pairs(s.racers) do
                        if r.paid > 0 then Bridge.AddMoney(src, r.paid) Notify(src, KB.T('refunded', r.paid), 'info') end
                        Notify(src, KB.T('lobby_cancel'), 'error')
                        removePlayer(src)
                    end
                    Lobbies[s.trackId] = nil
                    Sessions[s.id] = nil
                    broadcastLobbies()
                    return
                end
                runSession(s)
                return
            end
        end
    end)
end

local function createSession(kind, trackId, track)
    nextId = nextId + 1
    local s = { id = nextId, type = kind, trackId = trackId, track = track, state = 'lobby', racers = {} }
    Sessions[s.id] = s
    return s
end

function Race.JoinRace(src, trackId, laps)
    local track = Tracks.Get(trackId)
    if not track then return false, KB.T('track_unknown') end
    if PlayerSession[src] then return false, KB.T('already_in') end
    local s = Sessions[Lobbies[trackId] or -1]
    if s and s.state ~= 'lobby' then return false, KB.T('race_running') end
    local created = false
    if not s then
        s = createSession('race', trackId, track)
        laps = math.floor(tonumber(laps) or track.laps)
        s.laps = math.max(Config.Race.MinLaps, math.min(Config.Race.MaxLaps, laps))
        s.lobbyEnd = now() + Config.Race.LobbyTime * 1000
        Lobbies[trackId] = s.id
        created = true
    end
    local maxP = math.min(Config.Race.MaxPlayers, #track.grid)
    if count(s.racers) >= maxP then return false, KB.T('lobby_full') end
    local fee = Bridge.IsFree() and 0 or Config.Race.EntryFee
    if fee > 0 and not Bridge.RemoveMoney(src, fee) then
        if created then Lobbies[trackId] = nil Sessions[s.id] = nil end
        return false, KB.T('no_money', fee)
    end
    local r = newRacer(src)
    r.paid = fee
    s.racers[src] = r
    PlayerSession[src] = s.id
    if fee > 0 then Notify(src, KB.T('paid', fee), 'info') end
    local c = count(s.racers)
    if c >= maxP then s.lobbyEnd = math.min(s.lobbyEnd, now() + Config.Race.FullLobbyTime * 1000) end
    if created then
        lobbyThread(s)
        TriggerClientEvent('kartbahn:notify', -1, KB.T('lobby_new', track.name, Config.Race.LobbyTime), 'info')
    end
    broadcastLobbies()
    return true, KB.T('lobby_joined', c, maxP)
end

function Race.LeaveLobby(src)
    local s = Sessions[PlayerSession[src] or -1]
    if not s or s.state ~= 'lobby' then return false end
    local r = s.racers[src]
    if r and r.paid > 0 then Bridge.AddMoney(src, r.paid) Notify(src, KB.T('refunded', r.paid), 'info') end
    s.racers[src] = nil
    removePlayer(src)
    broadcastLobbies()
    return true, KB.T('lobby_left')
end

function Race.StartTimeTrial(src, trackId)
    local track = Tracks.Get(trackId)
    if not track then return false, KB.T('track_unknown') end
    if PlayerSession[src] then return false, KB.T('already_in') end
    local fee = Bridge.IsFree() and 0 or Config.TimeTrial.Fee
    if fee > 0 and not Bridge.RemoveMoney(src, fee) then return false, KB.T('no_money', fee) end
    local s = createSession('tt', trackId, track)
    s.racers[src] = newRacer(src)
    PlayerSession[src] = s.id
    CreateThread(function() runSession(s) end)
    return true
end

function Race.Stop(src)
    local s = Sessions[PlayerSession[src] or -1]
    if not s then return false end
    if s.state == 'lobby' then return Race.LeaveLobby(src) end
    if s.type == 'tt' then endTimeTrial(s, 'stop') return true end
    local r = s.racers[src]
    if r then setDnf(s, r) end
    return true
end

-- ===== Callbacks =====
RegisterCallback('joinRace', function(src, trackId, laps)
    local ok, msg = Race.JoinRace(src, trackId, laps)
    return { ok = ok, msg = msg }
end)
RegisterCallback('leaveLobby', function(src)
    local ok, msg = Race.LeaveLobby(src)
    return { ok = ok, msg = msg }
end)
RegisterCallback('startTT', function(src, trackId)
    local ok, msg = Race.StartTimeTrial(src, trackId)
    return { ok = ok, msg = msg }
end)

-- /kartleave (Client) -> Session verlassen
RegisterNetEvent('kartbahn:stopRequest', function()
    Race.Stop(source)
end)

-- ===== Aufräumen =====
AddEventHandler('playerDropped', function()
    local src = source
    local s = Sessions[PlayerSession[src] or -1]
    if not s then return end
    local r = s.racers[src]
    if s.state == 'lobby' then
        s.racers[src] = nil -- Startgebühr verfällt beim Verlassen des Servers
    elseif s.type == 'tt' then
        endTimeTrial(s, 'drop')
    elseif r then
        r.dnf = true
        deleteKart(r)
    end
    removePlayer(src)
    broadcastLobbies()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, s in pairs(Sessions) do
        for src, r in pairs(s.racers) do
            deleteKart(r)
            if s.state == 'lobby' and r.paid > 0 then Bridge.AddMoney(src, r.paid) end
        end
    end
end)
