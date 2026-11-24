-- Callbacks, Menüdaten, Benachrichtigungen
local Callbacks = {}

function RegisterCallback(name, fn) Callbacks[name] = fn end

RegisterNetEvent('kartbahn:cb', function(name, id, ...)
    local src = source
    local fn = Callbacks[name]
    if type(fn) ~= 'function' then return end
    local ok, res = pcall(fn, src, ...)
    if not ok then print(('[kartbahn] Callback-Fehler %s: %s'):format(name, res)) res = nil end
    TriggerClientEvent('kartbahn:cbResp', src, id, res)
end)

function Notify(src, msg, kind)
    TriggerClientEvent('kartbahn:notify', src, msg, kind or 'info')
end

local function tiersForUi()
    return Config.Tiers
end

-- Daten für den Tab "Fahren" und "Profil"
RegisterCallback('getMenu', function(src)
    local ident = Bridge.GetIdentifier(src)
    local profile = DB.GetProfile(ident, Bridge.GetName(src))
    local pbs = DB.GetAllPBs(ident)
    local tracks = {}
    for id, t in pairs(Tracks.list) do
        local rec = Records.Get(id)
        tracks[#tracks + 1] = {
            id = id, name = t.name, laps = t.laps, length = KB.TrackLength(t), grid = #t.grid,
            record = rec and { time = rec.time, name = rec.name } or nil,
            pb = pbs[id],
            lobby = Race.GetLobbyInfo(id, src),
            outline = (function()
                local o = {}
                for _, cp in ipairs(t.checkpoints) do o[#o + 1] = { math.floor(cp.x), math.floor(cp.y) } end
                return o
            end)(),
            start = { math.floor(t.checkpoints[1].x), math.floor(t.checkpoints[1].y) },
            raised = t.platform ~= nil
        }
    end
    table.sort(tracks, function(a, b) return a.name < b.name end)
    Features.PayPending(src, ident)
    local custom = Features.GetCustom(ident)
    return {
        tracks = tracks,
        profile = profile,
        tiers = tiersForUi(),
        session = Race.GetPlayerSessionInfo(src),
        settings = {
            fee = Bridge.IsFree() and 0 or Config.Race.EntryFee,
            ttFee = Bridge.IsFree() and 0 or Config.TimeTrial.Fee,
            prizes = Bridge.IsFree() and { 0, 0, 0 } or Config.Race.Prizes,
            minLaps = Config.Race.MinLaps, maxLaps = Config.Race.MaxLaps,
            minPlayers = Config.Race.MinPlayers, maxPlayers = Config.Race.MaxPlayers,
            framework = Bridge.fw,
            bets = Features.BetsEnabled(), betMin = Config.Bets.Min, betMax = Config.Bets.Max,
            ghost = Config.Ghost.Enabled, spectate = Config.Spectate.Enabled, season = Config.Season.Enabled
        },
        modes = Config.Modes,
        custom = custom,
        paints = Config.KartPaints,
        achievements = Config.Achievements,
        unlocked = Features.GetAchievements(ident),
        running = Race.GetRunningRaces(),
        me = src
    }
end)

RegisterCallback('getLeaderboard', function()
    return { rows = DB.GetLeaderboard(Config.Leaderboard.Top), tiers = tiersForUi() }
end)

RegisterCallback('getTrackTimes', function(_, trackId)
    if type(trackId) ~= 'string' or not Tracks.Get(trackId) then return { rows = {} } end
    return { rows = DB.GetTrackTimes(trackId, Config.Leaderboard.TrackTop) }
end)

RegisterCallback('getRecent', function()
    local rows = DB.GetRecentRaces(Config.Leaderboard.RecentRaces)
    for _, r in ipairs(rows) do
        local t = Tracks.Get(r.track)
        r.trackName = t and t.name or r.track
        -- neues Format: { mode, results, teams }
        if type(r.results) == 'table' and r.results.results then
            local m = KB.GetMode(r.results.mode)
            r.modeLabel = m and m.label or nil
            r.results = r.results.results
        end
    end
    return { rows = rows }
end)
