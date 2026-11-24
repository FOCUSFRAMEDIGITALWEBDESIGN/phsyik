-- Renn- und Zeitfahr-Sessions (serverseitig autoritativ)
Race = {}

local Sessions = {}       -- [id] = session
local PlayerSession = {}  -- [src] = id
local Spectating = {}     -- [src] = id
local Lobbies = {}        -- [trackId] = id (ein Rennen pro Strecke)
local PendingGhost = {}   -- [src] = { time, identifier, track, name }
local nextId = 0

local function now() return GetGameTimer() end
local function count(t) local c = 0 for _ in pairs(t) do c = c + 1 end return c end

local function broadcastLobbies() TriggerClientEvent('kartbahn:lobbyUpdate', -1) end

-- an alle Fahrer (und optional Zuschauer) einer Session senden
local function sendSession(s, event, ...)
    for src in pairs(s.racers) do TriggerClientEvent(event, src, ...) end
end
local function sendAll(s, event, ...)
    sendSession(s, event, ...)
    for src in pairs(s.spectators) do TriggerClientEvent(event, src, ...) end
end

-- ===== Info für Menü / Features =====
function Race.GetLobbySession(trackId)
    return Sessions[Lobbies[trackId] or -1]
end

function Race.GetLobbyInfo(trackId, viewer)
    local s = Sessions[Lobbies[trackId] or -1]
    if not s then return nil end
    local racers = {}
    for src, r in pairs(s.racers) do racers[#racers + 1] = { src = src, name = r.name, rating = r.rating } end
    table.sort(racers, function(a, b) return a.rating > b.rating end)
    return {
        id = s.id, state = s.state, count = count(s.racers), max = math.min(Config.Race.MaxPlayers, #s.track.grid),
        laps = s.laps, mode = s.mode, modeLabel = s.modeDef.label, racers = racers,
        timeLeft = s.state == 'lobby' and math.max(0, math.ceil((s.lobbyEnd - now()) / 1000)) or 0,
        bets = Features.BetsEnabled() and Features.GetBetInfo(s.id, viewer) or nil
    }
end

function Race.GetPlayerSessionInfo(src)
    local s = Sessions[PlayerSession[src] or -1]
    if not s then return nil end
    return { type = s.type, trackId = s.trackId, state = s.state }
end

function Race.GetRunningRaces()
    local list = {}
    for _, s in pairs(Sessions) do
        if s.type == 'race' and s.state ~= 'lobby' and s.state ~= 'finished' then
            list[#list + 1] = { id = s.id, trackName = s.track.name, count = count(s.racers), modeLabel = s.modeDef.label }
        end
    end
    return list
end

function Race.TakePendingGhost(src)
    local p = PendingGhost[src]
    PendingGhost[src] = nil
    return p
end

-- ===== Fahrzeuge =====
local function deleteKart(r)
    if r.veh and DoesEntityExist(r.veh) then DeleteEntity(r.veh) end
    r.veh = nil
end

local function spawnKart(src, slot)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    -- Spieler zuerst teleportieren, damit das Kart für ihn gestreamt wird
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
        dnf = false, outSince = nil, progress = 0.0, paid = 0, pb = nil,
        boost = Config.Boost.StartCharge, boostT = 0, item = nil, boxCd = {}, team = nil
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

local function isActive(r) return not r.finished and not r.dnf and not r.fixedPlace end

-- Platzierung: Ziel-Reihenfolge, dann Fortschritt, dann Ausgeschiedene, dann DNF
local function computeOrder(s)
    local list = {}
    for _, r in pairs(s.racers) do list[#list + 1] = r end
    table.sort(list, function(a, b)
        if a.dnf ~= b.dnf then return not a.dnf end
        if a.dnf then return a.src < b.src end
        local af, bf = a.fixedPlace ~= nil, b.fixedPlace ~= nil
        if af ~= bf then return not af end
        if af then return a.fixedPlace < b.fixedPlace end
        if a.finished ~= b.finished then return a.finished end
        if a.finished then return a.finishTime < b.finishTime end
        if a.progress ~= b.progress then return a.progress > b.progress end
        return a.src < b.src
    end)
    return list
end

local function updateProgress(s, r)
    if not isActive(r) then return end
    local cps = s.track.checkpoints
    local n = #cps
    local passed = (r.nextCp == 1) and n or (r.nextCp - 1)
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

local function positionOf(s, r)
    for i, o in ipairs(computeOrder(s)) do if o == r then return i end end
    return count(s.racers)
end

local function sendStandings(s)
    local rows = {}
    for i, r in ipairs(computeOrder(s)) do
        local ped = GetPlayerPed(r.src)
        local pc = ped ~= 0 and GetEntityCoords(ped) or vector3(0.0, 0.0, 0.0)
        rows[i] = {
            pos = r.fixedPlace or i, src = r.src, name = r.name, lap = math.min(r.lap, s.laps or r.lap),
            best = r.bestLap, finished = r.finished, dnf = r.dnf, out = r.fixedPlace ~= nil,
            time = r.finishTime, team = r.team, x = pc.x, y = pc.y
        }
    end
    sendAll(s, 'kartbahn:standings', rows)
end

-- ===== Aufräumen =====
local function cleanupSession(s)
    for src, r in pairs(s.racers) do
        deleteKart(r)
        if PlayerSession[src] == s.id then PlayerSession[src] = nil end
    end
    for src in pairs(s.spectators) do
        Spectating[src] = nil
        TriggerClientEvent('kartbahn:spectateEnd', src)
    end
    if Lobbies[s.trackId] == s.id then Lobbies[s.trackId] = nil end
    Sessions[s.id] = nil
    broadcastLobbies()
end

-- ===== Rennende =====
local function endRace(s)
    if s.state == 'finished' then return end
    s.state = 'finished'
    local order = computeOrder(s)
    local nonDnf = 0
    for _, r in ipairs(order) do if not r.dnf then nonDnf = nonDnf + 1 end end

    -- Plätze (DNFs teilen sich den letzten Platz)
    local entries = {}
    for i, r in ipairs(order) do
        if r.dnf then r.place = nonDnf + 1
        elseif r.fixedPlace then r.place = r.fixedPlace
        else r.place = i end
        entries[#entries + 1] = { key = r.src, rating = r.rating, place = r.place }
    end
    local deltas = s.modeDef.ranked and Elo.Calculate(entries) or {}

    -- 9) Team-Wertung
    local teamScore, winnerTeam = nil, nil
    if s.mode == 'team' then
        teamScore = {}
        for i = 1, #Config.Teams.List do teamScore[i] = 0 end
        for _, r in ipairs(order) do
            if r.team and not r.dnf then teamScore[r.team] = teamScore[r.team] + (Config.Teams.Points[r.place] or 0) end
        end
        local best = -1
        for i, sc in ipairs(teamScore) do if sc > best then best, winnerTeam = sc, i end end
        local team = Config.Teams.List[winnerTeam]
        sendAll(s, 'kartbahn:notify', KB.T('team_won', team.name, best), 'success')
    end

    local results = {}
    local winnerSrc
    for _, r in ipairs(order) do
        local online = GetPlayerPing(r.src) > 0
        local prize = 0
        if not r.dnf and not Bridge.IsFree() then prize = Config.Race.Prizes[r.place] or 0 end
        if winnerTeam and r.team == winnerTeam and not Bridge.IsFree() then prize = prize + Config.Teams.WinBonus end
        local delta = deltas[r.src] or 0
        local newRating = math.max(0, r.rating + delta)
        if r.place == 1 and not r.dnf then winnerSrc = r.src end
        if prize > 0 and online then
            Bridge.AddMoney(r.src, prize)
            Notify(r.src, KB.T('prize', prize), 'success')
        end
        DB.UpdateAfterRace(r.cid, {
            rating = newRating, win = not r.dnf and r.place == 1, podium = not r.dnf and r.place <= 3,
            dnf = r.dnf, prize = prize
        })
        local seasonPts = 0
        if s.modeDef.ranked then seasonPts = Features.AddSeasonPoints(r.cid, r.name, r.place, r.place == 1 and not r.dnf) end
        results[#results + 1] = {
            place = r.place, name = r.name, identifier = r.cid, finished = not r.dnf, dnf = r.dnf,
            out = r.fixedPlace ~= nil, time = r.finishTime, best = r.bestLap, oldRating = r.rating,
            newRating = newRating, delta = delta, prize = prize, src = r.src, team = r.team, season = seasonPts
        }
        -- 17) Erfolge
        CreateThread(function()
            if s.mode == 'elim' and r.place == 1 and not r.dnf then Features.Unlock(r.cid, 'elim_win', r.src) end
            if winnerTeam and r.team == winnerTeam then Features.Unlock(r.cid, 'team_win', r.src) end
            Features.CheckProfileAchievements(r.cid, online and r.src or nil)
        end)
    end
    DB.InsertRace(s.trackId, s.laps, { mode = s.mode, results = results, teams = teamScore })

    -- 18) Wetten auswerten
    if winnerSrc then Features.SettleBets(s.id, winnerSrc) else Features.RefundAllBets(s.id) end

    local payload = {
        type = 'race', mode = s.mode, modeLabel = s.modeDef.label, ranked = s.modeDef.ranked,
        trackId = s.trackId, trackName = s.track.name, laps = s.laps, results = results,
        tiers = Config.Tiers, teams = teamScore, teamList = Config.Teams.List, podium = Config.Podium.Enabled
    }
    for src in pairs(s.racers) do payload.me = src TriggerClientEvent('kartbahn:result', src, payload) end
    payload.me = -1
    for src in pairs(s.spectators) do TriggerClientEvent('kartbahn:result', src, payload) end
    local delay = Config.Race.CleanupDelay * 1000
    if Config.Podium.Enabled then delay = math.max(delay, Config.Podium.Duration + 1000) end
    SetTimeout(delay, function() cleanupSession(s) end)
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

-- ===== 8) Ausscheidung =====
local function activeList(s)
    local list = {}
    for _, r in ipairs(computeOrder(s)) do if isActive(r) then list[#list + 1] = r end end
    return list
end

local function declareElimWinner(s)
    local act = activeList(s)
    if #act == 1 and count(s.racers) > 1 then
        local w = act[1]
        w.finished = true
        w.finishTime = now() - s.startTime
        TriggerClientEvent('kartbahn:finished', w.src, 1)
    end
end

local function eliminateLast(s)
    local act = activeList(s)
    if #act < 2 then return end
    local last = act[#act]
    last.fixedPlace = #act
    last.finishTime = now() - s.startTime
    deleteKart(last)
    TriggerClientEvent('kartbahn:stopDriving', last.src)
    Notify(last.src, KB.T('you_eliminated', last.fixedPlace), 'error')
    sendAll(s, 'kartbahn:banner', KB.T('eliminated', last.name), 'error')
    declareElimWinner(s)
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
        if not r.pb or lapTime < r.pb then
            r.pb = lapTime
            isPB = true
            -- 7) Ghost-Aufzeichnung dieser Runde annehmen (nur Zeitfahren)
            if s.type == 'tt' and Config.Ghost.Enabled then
                PendingGhost[r.src] = { time = lapTime, identifier = r.cid, track = s.trackId, name = r.name }
            end
        end
        isRecord = Records.Submit(s.trackId, r.cid, r.name, lapTime)
        DB.InsertLap(r.cid, r.name, s.trackId, lapTime, s.type == 'tt' and 'tt' or s.mode)
        if isRecord then
            Features.Unlock(r.cid, 'record', r.src)
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
    if s.type == 'race' then
        if s.mode == 'elim' then
            local completed = r.lap - 1
            if completed >= Config.Elimination.FirstElimAfterLap and completed > (s.elimDone or 0) then
                s.elimDone = completed
                eliminateLast(s)
            end
            finished = r.finished
        elseif r.lap > s.laps then
            finished = true
            r.finished = true
            r.finishTime = t - s.startTime
            if not s.firstFinish then
                s.firstFinish = t
                sendAll(s, 'kartbahn:notify', KB.T('first_finish', r.name, Config.Race.FinishTimeout), 'info')
            end
        end
    end

    TriggerClientEvent('kartbahn:lap', r.src, {
        lap = r.lap, time = lapTime, valid = valid, pb = isPB, record = isRecord,
        best = r.bestLap, pbTime = r.pb, recordTime = (Records.Get(s.trackId) or {}).time,
        finished = finished, ghost = isPB and s.type == 'tt'
    })
    if finished and s.mode ~= 'elim' then
        TriggerClientEvent('kartbahn:finished', r.src, positionOf(s, r))
    end
end

-- ===== Checkpoint-Meldung vom Client =====
RegisterNetEvent('kartbahn:cp', function(sid, idx)
    local src = source
    local s = Sessions[PlayerSession[src] or -1]
    if not s or s.id ~= sid or s.state ~= 'running' then return end
    local r = s.racers[src]
    if not r or not isActive(r) then return end
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
        TriggerClientEvent('kartbahn:cpOk', src, r.nextCp, t - r.lapStart)
    end
end)

-- ===== 1) Boost (serverseitige Ladung) =====
local function boostCharge(r)
    local t = now()
    r.boost = math.min(100.0, r.boost + (t - r.boostT) / 1000.0 * Config.Boost.RechargeRate)
    r.boostT = t
    return r.boost
end

local function sessionOf(src)
    local s = Sessions[PlayerSession[src] or -1]
    if not s or s.state ~= 'running' then return nil end
    local r = s.racers[src]
    if not r or not isActive(r) then return nil end
    return s, r
end

RegisterNetEvent('kartbahn:boostReq', function()
    local src = source
    local s, r = sessionOf(src)
    if not s or not s.boost then return end
    if boostCharge(r) < Config.Boost.Cost then
        return TriggerClientEvent('kartbahn:boostState', src, r.boost, false)
    end
    r.boost = r.boost - Config.Boost.Cost
    TriggerClientEvent('kartbahn:boostGo', src, Config.Boost.Duration, Config.Boost.Power)
    TriggerClientEvent('kartbahn:boostState', src, r.boost, true)
end)

-- ===== Zurücksetzen auf den letzten Checkpoint (Absturz von der Plattform / festgefahren) =====
RegisterNetEvent('kartbahn:resetReq', function()
    local src = source
    local s, r = sessionOf(src)
    if not s then return end
    local t = now()
    if t - (r.lastReset or 0) < 3000 then return end
    r.lastReset = t
    r.lapInvalid = true -- Runde zählt nicht mehr
    local cps = s.track.checkpoints
    local n = #cps
    local idx = (r.nextCp == 1) and n or (r.nextCp - 1)
    local cp = cps[idx]
    local dx, dy = KB.CpDirection(cps, idx)
    TriggerClientEvent('kartbahn:resetTo', src, { x = cp.x, y = cp.y, z = cp.z + 0.6, h = math.deg(math.atan(-dx, dy)) })
end)

-- ===== 6) Items =====
local function rollItem(s, r)
    local pos = positionOf(s, r)
    local pool = (pos <= math.ceil(count(s.racers) / 2)) and Config.Items.Pool.front or Config.Items.Pool.back
    local total = 0
    for _, w in pairs(pool) do total = total + w end
    local roll = math.random() * total
    for item, w in pairs(pool) do
        roll = roll - w
        if roll <= 0 then return item end
    end
    return 'boost'
end

RegisterNetEvent('kartbahn:itemPick', function(idx)
    local src = source
    local s, r = sessionOf(src)
    if not s or not s.items or r.item then return end
    idx = tonumber(idx)
    local box = s.itemBoxes[idx or -1]
    if not box then return end
    local t = now()
    if (r.boxCd[idx] or 0) > t then return end
    local pc = GetEntityCoords(GetPlayerPed(src))
    if KB.Dist2D(pc.x, pc.y, box.x, box.y) > Config.Items.Radius + Config.AntiCheat.CpTolerance then return end
    r.boxCd[idx] = t + Config.Items.Respawn
    r.item = rollItem(s, r)
    TriggerClientEvent('kartbahn:itemGot', src, r.item, idx, Config.Items.Respawn)
end)

RegisterNetEvent('kartbahn:itemUse', function()
    local src = source
    local s, r = sessionOf(src)
    if not s or not r.item then return end
    local item = r.item
    r.item = nil
    if item == 'boost' then
        TriggerClientEvent('kartbahn:boostGo', src, Config.Boost.Duration, Config.Boost.Power)
    elseif item == 'oil' then
        local ped = GetPlayerPed(src)
        local pc = GetEntityCoords(ped)
        local h = math.rad(GetEntityHeading(ped))
        s.hazardId = (s.hazardId or 0) + 1
        sendSession(s, 'kartbahn:hazard', {
            id = s.hazardId, owner = src, ttl = Config.Items.OilTime,
            x = pc.x + math.sin(h) * 3.5, y = pc.y - math.cos(h) * 3.5, z = pc.z
        })
    elseif item == 'shield' then
        TriggerClientEvent('kartbahn:shield', src, Config.Items.ShieldTime)
    end
    TriggerClientEvent('kartbahn:itemGot', src, nil)
end)

-- ===== 2) Windschatten lädt den Boost (serverseitig geprüft) =====
local function slipstreamTick(s)
    if not s.boost or not Config.Slipstream.Enabled then return end
    local list = {}
    for _, r in pairs(s.racers) do
        if isActive(r) then
            local ped = GetPlayerPed(r.src)
            if ped ~= 0 then list[#list + 1] = { r = r, c = GetEntityCoords(ped), h = math.rad(GetEntityHeading(ped)) } end
        end
    end
    for _, a in ipairs(list) do
        local fx, fy = -math.sin(a.h), math.cos(a.h)
        for _, b in ipairs(list) do
            if a ~= b then
                local dx, dy = b.c.x - a.c.x, b.c.y - a.c.y
                local d = math.sqrt(dx * dx + dy * dy)
                if d > Config.Slipstream.MinDist and d < Config.Slipstream.MaxDist then
                    local cos = (dx * fx + dy * fy) / d
                    if cos > math.cos(math.rad(Config.Slipstream.MaxAngle)) then
                        boostCharge(a.r)
                        a.r.boost = math.min(100.0, a.r.boost + Config.Slipstream.BoostCharge)
                        TriggerClientEvent('kartbahn:boostState', a.r.src, a.r.boost, false)
                        break
                    end
                end
            end
        end
    end
end

-- ===== Ablauf einer Session (Spawn, Countdown, Rennen) =====
local function runSession(s)
    s.state = 'preparing'
    broadcastLobbies()
    local order = {}
    for _, r in pairs(s.racers) do order[#order + 1] = r end
    -- Startaufstellung: niedrigstes Rating vorne, die Besten starten hinten
    table.sort(order, function(a, b)
        if a.rating ~= b.rating then return a.rating < b.rating end
        return a.src < b.src
    end)
    if s.mode == 'elim' then s.laps = math.max(1, #order - 1) end

    for i, r in ipairs(order) do
        local slot = s.track.grid[i] or s.track.grid[#s.track.grid]
        r.pb = DB.GetPB(r.cid, s.trackId)
        -- 9) Teams abwechselnd nach Startplatz (ausgeglichen nach Rating)
        if s.mode == 'team' then
            r.team = ((i - 1) % #Config.Teams.List) + 1
            Notify(r.src, KB.T('team_assigned', Config.Teams.List[r.team].name), 'info')
        end
        -- 16) Kart-Design
        local custom = Features.GetCustom(r.cid)
        local color = r.team and Config.Teams.List[r.team].color or Features.PaintColor(custom.paint)
        local number = (custom.number and custom.number > 0) and custom.number or i
        local veh, netId = spawnKart(r.src, slot)
        if not veh then
            Notify(r.src, KB.T('spawn_failed'), 'error')
            if s.type == 'race' then r.dnf = true else return endTimeTrial(s) end
        else
            r.veh, r.netId = veh, netId
            local rec = Records.Get(s.trackId)
            local ghost = nil
            if s.type == 'tt' then ghost = Features.GetGhost(r.cid, s.trackId, s.ghostTarget or Config.Ghost.DefaultTarget) end
            TriggerLatentClientEvent('kartbahn:prepare', r.src, 50000, {
                sid = s.id, type = s.type, mode = s.mode, modeLabel = s.modeDef.label, trackId = s.trackId,
                netId = netId, slot = i, laps = s.laps, pb = r.pb, record = rec and rec.time or nil,
                recordName = rec and rec.name or nil, count = #order, boost = s.boost, items = s.items,
                charge = r.boost, color = color, number = number, team = r.team, ghost = ghost
            })
        end
    end

    Wait(Config.Race.PrepareTime * 1000)
    if s.state == 'finished' then return end
    s.state = 'countdown'
    sendAll(s, 'kartbahn:countdown', Config.Race.CountdownTime)
    Wait(Config.Race.CountdownTime * 1000)
    if s.state == 'finished' then return end

    s.startTime = now()
    s.state = 'running'
    for _, r in pairs(s.racers) do
        r.lap, r.nextCp, r.lapStart, r.lastCp, r.boostT = 1, 2, s.startTime, 0, s.startTime
        if r.veh then FreezeEntityPosition(r.veh, false) end
    end
    sendAll(s, 'kartbahn:go')

    -- Server-Tick: Kart-Kontrolle, Platzierung, Windschatten, Rennende
    while s.state == 'running' do
        Wait(1000)
        local t = now()
        local active = 0
        for src, r in pairs(s.racers) do
            if isActive(r) then
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
            slipstreamTick(s)
            if s.mode == 'elim' then declareElimWinner(s) end
            sendStandings(s)
            active = #activeList(s)
            if active == 0 then
                endRace(s)
            elseif s.firstFinish and s.mode ~= 'elim' and t - s.firstFinish >= Config.Race.FinishTimeout * 1000 then
                for _, r in pairs(s.racers) do if isActive(r) then r.dnf = true end end
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
                Features.RefundAllBets(s.id)
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
                        PlayerSession[src] = nil
                    end
                    Features.RefundAllBets(s.id)
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

local function createSession(kind, trackId, track, mode)
    nextId = nextId + 1
    local modeDef = kind == 'tt' and { id = 'tt', label = 'Zeitfahren', ranked = false,
        boost = Config.TimeTrialMode.boost, items = Config.TimeTrialMode.items } or KB.GetMode(mode)
    local s = {
        id = nextId, type = kind, trackId = trackId, track = track, state = 'lobby', racers = {}, spectators = {},
        mode = modeDef.id, modeDef = modeDef, boost = modeDef.boost, items = modeDef.items,
        itemBoxes = modeDef.items and KB.GetItemBoxes(track) or {}
    }
    Sessions[s.id] = s
    return s
end

function Race.JoinRace(src, trackId, laps, mode)
    local track = Tracks.Get(trackId)
    if not track then return false, KB.T('track_unknown') end
    if PlayerSession[src] then return false, KB.T('already_in') end
    local s = Sessions[Lobbies[trackId] or -1]
    if s and s.state ~= 'lobby' then return false, KB.T('race_running') end
    local created = false
    if not s then
        s = createSession('race', trackId, track, mode)
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
        TriggerClientEvent('kartbahn:notify', -1, KB.T('lobby_new', track.name, Config.Race.LobbyTime) .. ' (' .. s.modeDef.label .. ')', 'info')
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
    PlayerSession[src] = nil
    Features.RefundBetsOn(s.id, src)
    broadcastLobbies()
    return true, KB.T('lobby_left')
end

function Race.StartTimeTrial(src, trackId, ghostTarget)
    local track = Tracks.Get(trackId)
    if not track then return false, KB.T('track_unknown') end
    if PlayerSession[src] then return false, KB.T('already_in') end
    local fee = Bridge.IsFree() and 0 or Config.TimeTrial.Fee
    if fee > 0 and not Bridge.RemoveMoney(src, fee) then return false, KB.T('no_money', fee) end
    local s = createSession('tt', trackId, track)
    s.ghostTarget = (ghostTarget == 'record' or ghostTarget == 'none') and ghostTarget or 'pb'
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

-- ===== 13) Zuschauen =====
RegisterCallback('spectateJoin', function(src, sid)
    local s = Sessions[tonumber(sid) or -1]
    if not Config.Spectate.Enabled or not s or s.type ~= 'race' or s.state == 'finished' or PlayerSession[src] then return nil end
    Spectating[src] = s.id
    s.spectators[src] = true
    local racers = {}
    for rsrc, r in pairs(s.racers) do racers[#racers + 1] = { src = rsrc, name = r.name } end
    local first = s.track.grid[1]
    return { sid = s.id, trackId = s.trackId, racers = racers, spot = first }
end)

RegisterNetEvent('kartbahn:spectateLeave', function()
    local src = source
    local s = Sessions[Spectating[src] or -1]
    if s then s.spectators[src] = nil end
    Spectating[src] = nil
end)

-- ===== Callbacks =====
RegisterCallback('joinRace', function(src, trackId, laps, mode)
    local ok, msg = Race.JoinRace(src, trackId, laps, mode)
    return { ok = ok, msg = msg }
end)
RegisterCallback('leaveLobby', function(src)
    local ok, msg = Race.LeaveLobby(src)
    return { ok = ok, msg = msg }
end)
RegisterCallback('startTT', function(src, trackId, ghost)
    local ok, msg = Race.StartTimeTrial(src, trackId, ghost)
    return { ok = ok, msg = msg }
end)

-- /kartleave (Client) -> Session verlassen
RegisterNetEvent('kartbahn:stopRequest', function()
    Race.Stop(source)
end)

-- ===== Aufräumen =====
AddEventHandler('playerDropped', function()
    local src = source
    PendingGhost[src] = nil
    local sp = Sessions[Spectating[src] or -1]
    if sp then sp.spectators[src] = nil end
    Spectating[src] = nil
    local s = Sessions[PlayerSession[src] or -1]
    if not s then return end
    local r = s.racers[src]
    if s.state == 'lobby' then
        s.racers[src] = nil -- Startgebühr verfällt beim Verlassen des Servers
        Features.RefundBetsOn(s.id, src)
    elseif s.type == 'tt' then
        endTimeTrial(s, 'drop')
    elseif r then
        r.dnf = true
        deleteKart(r)
    end
    PlayerSession[src] = nil
    broadcastLobbies()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, s in pairs(Sessions) do
        for src, r in pairs(s.racers) do
            deleteKart(r)
            if s.state == 'lobby' and r.paid > 0 then Bridge.AddMoney(src, r.paid) end
        end
        Features.RefundAllBets(s.id)
    end
end)
