KB = {}

function KB.T(key, ...)
    local s = Config.Text[key] or key
    if select('#', ...) > 0 then return s:format(...) end
    return s
end

-- Millisekunden -> m:ss.mmm
function KB.FormatTime(ms)
    if not ms then return '--:--.---' end
    ms = math.floor(ms)
    return ('%d:%02d.%03d'):format(ms // 60000, (ms // 1000) % 60, ms % 1000)
end

function KB.GetTier(rating)
    local tier = Config.Tiers[1]
    for _, t in ipairs(Config.Tiers) do
        if rating >= t.min then tier = t end
    end
    return tier
end

function KB.Dist2D(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

-- Fahrtrichtung an einem Checkpoint (gemittelt aus Vorgänger und Nachfolger)
function KB.CpDirection(cps, i)
    local n = #cps
    local prev = cps[i == 1 and n or i - 1]
    local nxt = cps[i == n and 1 or i + 1]
    local dx, dy = nxt.x - prev.x, nxt.y - prev.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then return 0.0, 1.0 end
    return dx / len, dy / len
end

-- Linke/rechte Kante eines Checkpoints (extra = zusätzlicher Abstand)
function KB.CpEdges(cps, i, extra)
    local cp = cps[i]
    local dx, dy = KB.CpDirection(cps, i)
    local nx, ny = -dy, dx
    local half = (cp.w or 12.0) / 2 + (extra or 0.0)
    return { x = cp.x + nx * half, y = cp.y + ny * half, z = cp.z },
           { x = cp.x - nx * half, y = cp.y - ny * half, z = cp.z }
end

-- Liste aller lokal zu spawnenden Objekte einer Strecke
function KB.BuildObjectList(track)
    local list = {}
    local cps = track.checkpoints or {}
    local n = #cps
    if track.autoBarriers and n >= 3 then
        local lefts, rights = {}, {}
        for i = 1, n do
            lefts[i], rights[i] = KB.CpEdges(cps, i, Config.Track.BarrierOffset)
        end
        for _, side in ipairs({ lefts, rights }) do
            for i = 1, n do
                local a, b = side[i], side[i == n and 1 or i + 1]
                local dx, dy = b.x - a.x, b.y - a.y
                local len = math.sqrt(dx * dx + dy * dy)
                local count = math.max(1, math.floor(len / (track.barrierSpacing or Config.Track.BarrierSpacing)))
                -- Objekt-X-Achse entlang der Linie ausrichten
                local h = math.deg(math.atan(dy, dx))
                for k = 0, count - 1 do
                    local t = (k + 0.5) / count
                    list[#list + 1] = {
                        model = track.barrierModel or Config.Track.BarrierModel,
                        x = a.x + dx * t, y = a.y + dy * t, z = a.z + (b.z - a.z) * t, h = h
                    }
                end
            end
        end
        -- Pylonen an den Checkpoint-Kanten
        for i = 1, n do
            local l, r = KB.CpEdges(cps, i, 0.0)
            list[#list + 1] = { model = Config.Track.ConeModel, x = l.x, y = l.y, z = l.z, h = 0.0 }
            list[#list + 1] = { model = Config.Track.ConeModel, x = r.x, y = r.y, z = r.z, h = 0.0 }
        end
    end
    for _, p in ipairs(track.props or {}) do
        list[#list + 1] = { model = p.model, x = p.x, y = p.y, z = p.z, h = p.h or 0.0 }
    end
    while #list > Config.Track.MaxObjects do table.remove(list) end
    return list
end

function KB.TrackCenter(track)
    local sx, sy, sz, n = 0.0, 0.0, 0.0, 0
    for _, cp in ipairs(track.checkpoints or {}) do
        sx, sy, sz, n = sx + cp.x, sy + cp.y, sz + cp.z, n + 1
    end
    if n == 0 then return vector3(0.0, 0.0, 0.0) end
    return vector3(sx / n, sy / n, sz / n)
end

function KB.TrackLength(track)
    local cps, len = track.checkpoints or {}, 0.0
    for i = 1, #cps do
        local b = cps[i == #cps and 1 or i + 1]
        len = len + KB.Dist2D(cps[i].x, cps[i].y, b.x, b.y)
    end
    return math.floor(len)
end

-- Modus-Definition holen
function KB.GetMode(id)
    for _, m in ipairs(Config.Modes) do if m.id == id then return m end end
    return Config.Modes[1]
end

-- Item-Boxen: eigene aus der Strecke oder automatisch an jedem n-ten Checkpoint
function KB.GetItemBoxes(track)
    if track.itemBoxes and #track.itemBoxes > 0 then return track.itemBoxes end
    local list, cps = {}, track.checkpoints or {}
    for i = 3, #cps, Config.Items.AutoEvery do
        list[#list + 1] = { x = cps[i].x, y = cps[i].y, z = cps[i].z }
    end
    return list
end

-- Position des Siegerpodests (eigene oder seitlich von Start/Ziel)
function KB.GetPodium(track)
    if track.podium then return track.podium end
    local cps = track.checkpoints
    local dx, dy = KB.CpDirection(cps, 1)
    local o = Config.Podium.Offset
    local cp = cps[1]
    return { x = cp.x + dy * o, y = cp.y - dx * o, z = cp.z, h = math.deg(math.atan(dy, dx)) } -- Blick zur Strecke
end

-- Sektorgrenzen: Checkpoint-Index, an dem ein Sektor endet (letzter Sektor endet an CP 1)
function KB.SectorEnds(track)
    local n, c = #track.checkpoints, Config.Sectors.Count
    local ends = {}
    for k = 1, c - 1 do ends[#ends + 1] = math.floor(k * n / c) + 1 end
    ends[#ends + 1] = 1
    return ends
end
