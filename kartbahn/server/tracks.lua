-- Strecken laden/speichern (data/tracks/*.json, Liste in data/tracks/_index.json)
Tracks = { list = {} }
Records = { data = {} }

local RES = GetCurrentResourceName()

local function num(v, d) v = tonumber(v) return v or d end

-- Validierung/Normalisierung einer Strecke
function Tracks.Sanitize(t)
    if type(t) ~= 'table' then return nil end
    local out = {
        id = tostring(t.id or ''):lower():gsub('[^%w_%-]', ''),
        name = tostring(t.name or t.id or 'Strecke'):sub(1, 40),
        laps = math.max(Config.Race.MinLaps, math.min(Config.Race.MaxLaps, math.floor(num(t.laps, 3)))),
        minLap = math.max(5000, math.floor(num(t.minLap, Config.AntiCheat.MinLapTime))),
        autoBarriers = t.autoBarriers ~= false,
        -- optional: eigenes Banden-Modell und Abstand pro Strecke
        barrierModel = type(t.barrierModel) == 'string' and #t.barrierModel < 64 and t.barrierModel or nil,
        barrierSpacing = tonumber(t.barrierSpacing) and math.max(1.0, tonumber(t.barrierSpacing)) or nil,
        checkpoints = {}, grid = {}, props = {}
    }
    if out.id == '' then return nil end
    for _, c in ipairs(t.checkpoints or {}) do
        out.checkpoints[#out.checkpoints + 1] = {
            x = num(c.x, 0.0), y = num(c.y, 0.0), z = num(c.z, 0.0),
            w = math.max(Config.Editor.MinWidth, math.min(Config.Editor.MaxWidth, num(c.w, Config.Editor.DefaultWidth)))
        }
    end
    for i, g in ipairs(t.grid or {}) do
        if i > Config.Editor.MaxGrid then break end
        out.grid[#out.grid + 1] = { x = num(g.x, 0.0), y = num(g.y, 0.0), z = num(g.z, 0.0), h = num(g.h, 0.0) }
    end
    for _, p in ipairs(t.props or {}) do
        if type(p.model) == 'string' and #p.model < 64 then
            out.props[#out.props + 1] = { model = p.model, x = num(p.x, 0.0), y = num(p.y, 0.0), z = num(p.z, 0.0), h = num(p.h, 0.0) }
        end
    end
    -- Boost-Felder, Item-Boxen, Siegerpodest
    out.boostPads, out.itemBoxes = {}, {}
    for _, b in ipairs(t.boostPads or {}) do
        out.boostPads[#out.boostPads + 1] = { x = num(b.x, 0.0), y = num(b.y, 0.0), z = num(b.z, 0.0), h = num(b.h, 0.0) }
    end
    for _, b in ipairs(t.itemBoxes or {}) do
        out.itemBoxes[#out.itemBoxes + 1] = { x = num(b.x, 0.0), y = num(b.y, 0.0), z = num(b.z, 0.0) }
    end
    if type(t.podium) == 'table' then
        out.podium = { x = num(t.podium.x, 0.0), y = num(t.podium.y, 0.0), z = num(t.podium.z, 0.0), h = num(t.podium.h, 0.0) }
    end
    if #out.checkpoints < 3 or #out.grid < 1 then return nil end
    return out
end

function Tracks.LoadAll()
    Tracks.list = {}
    local idx = json.decode(LoadResourceFile(RES, 'data/tracks/_index.json') or '[]') or {}
    for _, id in ipairs(idx) do
        local raw = LoadResourceFile(RES, ('data/tracks/%s.json'):format(id))
        local t = raw and Tracks.Sanitize(json.decode(raw))
        if t then
            Tracks.list[t.id] = t
        else
            print(('[kartbahn] Strecke "%s" konnte nicht geladen werden.'):format(id))
        end
    end
end

function Tracks.Get(id) return Tracks.list[id] end

function Tracks.Save(t)
    SaveResourceFile(RES, ('data/tracks/%s.json'):format(t.id), json.encode(t, { indent = true }), -1)
    Tracks.list[t.id] = t
    local ids = {}
    for id in pairs(Tracks.list) do ids[#ids + 1] = id end
    table.sort(ids)
    SaveResourceFile(RES, 'data/tracks/_index.json', json.encode(ids), -1)
    TriggerClientEvent('kartbahn:tracks', -1, Tracks.list)
end

-- Streckenrekorde im Speicher
function Records.LoadAll()
    for id in pairs(Tracks.list) do
        local r = DB.GetTrackRecord(id)
        Records.data[id] = r and { time = r.lap_time, name = r.name, identifier = r.identifier } or nil
    end
end

function Records.Get(id) return Records.data[id] end

-- true, wenn neuer Rekord
function Records.Submit(track, identifier, name, ms)
    local cur = Records.data[track]
    if not cur or ms < cur.time then
        Records.data[track] = { time = ms, name = name, identifier = identifier }
        return true
    end
    return false
end

Tracks.LoadAll()

-- Client fragt die Strecken beim Start an
RegisterNetEvent('kartbahn:requestTracks', function()
    TriggerClientEvent('kartbahn:tracks', source, Tracks.list)
end)
