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
            lobby = Race.GetLobbyInfo(id)
        }
    end
    table.sort(tracks, function(a, b) return a.name < b.name end)
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
            framework = Bridge.fw
        }
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
    end
    return { rows = rows }
end)
