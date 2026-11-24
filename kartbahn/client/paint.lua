-- Fahrbahn-Markierungen (Randlinien, Curbs, Start-/Ziel-Karo, Startboxen) und Flutlicht bei Nacht
-- Alles wird nur gezeichnet, wenn man in der Nähe der Strecke ist.
local cache = {}  -- [trackId] = { chunks = { { cx, cy, tris = {...} } }, lights = {...}, center = vector3 }

local function col(name) return Config.Paint.Colors[name] end

-- Viereck (a, b, c, d im Umlauf) als zwei Dreiecke
local function quad(list, a, b, c, d, color)
    list[#list + 1] = { a, b, c, color }
    list[#list + 1] = { a, c, d, color }
end

local function P(x, y, z) return { x, y, z + Config.Paint.Lift } end

local function turnAngle(cps, i)
    local n = #cps
    local a, b, c = cps[i == 1 and n or i - 1], cps[i], cps[i == n and 1 or i + 1]
    local v1x, v1y, v2x, v2y = b.x - a.x, b.y - a.y, c.x - b.x, c.y - b.y
    local l1, l2 = math.sqrt(v1x * v1x + v1y * v1y), math.sqrt(v2x * v2x + v2y * v2y)
    if l1 < 0.01 or l2 < 0.01 then return 0, 0 end
    local cos = math.max(-1, math.min(1, (v1x * v2x + v1y * v2y) / (l1 * l2)))
    return math.deg(math.acos(cos)), v1x * v2y - v1y * v2x
end

-- Streifen entlang einer Kante: von p nach q, nach innen (zur Strecke) um width versetzt
local function stripe(list, p, q, inward, width, colors, segLen)
    local dx, dy = q.x - p.x, q.y - p.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.05 then return end
    local ux, uy = dx / len, dy / len
    local ix, iy = -uy * inward, ux * inward -- Normale zur Streckenmitte
    local segs = segLen and math.max(1, math.floor(len / segLen + 0.5)) or 1
    for k = 0, segs - 1 do
        local t0, t1 = k / segs, (k + 1) / segs
        local ax, ay, az = p.x + dx * t0, p.y + dy * t0, p.z + (q.z - p.z) * t0
        local bx, by, bz = p.x + dx * t1, p.y + dy * t1, p.z + (q.z - p.z) * t1
        quad(list, P(ax, ay, az), P(bx, by, bz), P(bx + ix * width, by + iy * width, bz), P(ax + ix * width, ay + iy * width, az),
            colors[(k % #colors) + 1])
    end
end

local function lerp(a, b, t) return { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t, z = a.z + (b.z - a.z) * t } end

local function build(track)
    local cps = track.checkpoints or {}
    local n = #cps
    if n < 3 then return nil end
    local C = Config.Paint
    local L, R = {}, {}
    for i = 1, n do L[i], R[i] = KB.CpEdges(cps, i, 0.0) end
    local chunks = {}
    for i = 1, n do chunks[i] = { cx = cps[i].x, cy = cps[i].y, tris = {} } end

    for i = 1, n do
        local j = i == n and 1 or i + 1
        local tris = chunks[i].tris
        -- weiße Randlinien (links: nach rechts innen = -1, rechts: +1)
        stripe(tris, L[i], L[j], -1, C.EdgeWidth, { col('edge') })
        stripe(tris, R[i], R[j], 1, C.EdgeWidth, { col('edge') })
        -- Curbs an der Kurveninnenseite (halbe Strecke davor und danach)
        local ang, cross = turnAngle(cps, i)
        if ang >= C.CurbAngle then
            local E = cross > 0 and L or R            -- Linkskurve: innen = links
            local inward = cross > 0 and -1 or 1
            local prev = i == 1 and n or i - 1
            local a, b, c = lerp(E[prev], E[i], 0.45), E[i], lerp(E[i], E[j], 0.55)
            local rw = { col('red'), col('white') }
            stripe(tris, a, b, inward, C.CurbWidth, rw, C.CurbSegment)
            stripe(tris, b, c, inward, C.CurbWidth, rw, C.CurbSegment)
        end
    end

    -- Karierte Start-/Ziellinie an CP 1 (zwei Reihen)
    do
        local cp = cps[1]
        local ux, uy = KB.CpDirection(cps, 1)
        local nx, ny = -uy, ux
        local s = C.CheckerSize
        local cols = math.max(2, math.floor(cp.w / s + 0.5))
        local cw = cp.w / cols
        for row = 0, 1 do
            for k = 0, cols - 1 do
                local lat0, lat1 = -cp.w / 2 + k * cw, -cp.w / 2 + (k + 1) * cw
                local f0, f1 = (row - 1) * s, row * s
                local function pt(f, l) return P(cp.x + ux * f + nx * l, cp.y + uy * f + ny * l, cp.z) end
                quad(chunks[1].tris, pt(f0, lat0), pt(f1, lat0), pt(f1, lat1), pt(f0, lat1),
                    ((row + k) % 2 == 0) and col('white') or col('black'))
            end
        end
    end

    -- Startboxen (Rahmen) an den Startplätzen
    for _, g in ipairs(track.grid or {}) do
        local h = math.rad(g.h)
        local fx, fy = -math.sin(h), math.cos(h)   -- Fahrtrichtung
        local rx, ry = fy, -fx                     -- rechts
        local B = C.GridBox
        local function pt(f, r) return P(g.x + fx * f + rx * r, g.y + fy * f + ry * r, g.z) end
        local hw, hl, t = B.w / 2 + 0.3, B.l / 2 + 0.3, B.line
        local tris = chunks[1].tris
        quad(tris, pt(-hl, -hw), pt(-hl, hw), pt(-hl + t, hw), pt(-hl + t, -hw), col('grid'))      -- hinten
        quad(tris, pt(-hl, -hw), pt(hl, -hw), pt(hl, -hw + t), pt(-hl, -hw + t), col('grid'))      -- links
        quad(tris, pt(-hl, hw - t), pt(hl, hw - t), pt(hl, hw), pt(-hl, hw), col('grid'))          -- rechts
        quad(tris, pt(hl - t, -hw), pt(hl - t, -hw + 0.6), pt(hl, -hw + 0.6), pt(hl, -hw), col('grid')) -- Ecke vorne links
        quad(tris, pt(hl - t, hw - 0.6), pt(hl - t, hw), pt(hl, hw), pt(hl, hw - 0.6), col('grid'))     -- Ecke vorne rechts
    end
    return { chunks = chunks, lights = KB.LightSpots(track), center = KB.TrackCenter(track) }
end

local function getCache(id)
    local t = TrackList[id]
    if not t then return nil end
    if cache[id] == nil then cache[id] = build(t) or false end
    return cache[id] or nil
end

-- Bei neuen Streckendaten neu berechnen
RegisterNetEvent('kartbahn:tracks', function() cache = {} end)

local function draw(tri)
    local a, b, c, k = tri[1], tri[2], tri[3], tri[4]
    -- beide Seiten zeichnen (Umlaufrichtung egal)
    DrawPoly(a[1], a[2], a[3], b[1], b[2], b[3], c[1], c[2], c[3], k[1], k[2], k[3], k[4])
    DrawPoly(c[1], c[2], c[3], b[1], b[2], b[3], a[1], a[2], a[3], k[1], k[2], k[3], k[4])
end

local function isNight()
    local h = GetClockHours()
    return h >= Config.Lights.NightFrom or h < Config.Lights.NightTo
end

CreateThread(function()
    if not Config.Paint.Enabled and not Config.Lights.Enabled then return end
    while true do
        local sleep = 1000
        local pc = GetEntityCoords(PlayerPedId())
        for id, t in pairs(TrackList) do
            local data = getCache(id)
            if data and #(pc - data.center) < Config.Track.StreamDistance then
                sleep = 0
                local dd = Config.Paint.DrawDistance
                if Config.Paint.Enabled then
                    for _, ch in ipairs(data.chunks) do
                        if KB.Dist2D(pc.x, pc.y, ch.cx, ch.cy) < dd then
                            for _, tri in ipairs(ch.tris) do draw(tri) end
                        end
                    end
                end
                if Config.Lights.Enabled and isNight() then
                    local c = Config.Lights.Color
                    for _, l in ipairs(data.lights) do
                        if KB.Dist2D(pc.x, pc.y, l.x, l.y) < 200.0 then
                            -- Licht zwischen Lampe und Streckenmitte
                            DrawLightWithRange((l.x + l.tx) / 2, (l.y + l.ty) / 2, l.z + 6.0, c[1], c[2], c[3],
                                Config.Lights.Range, Config.Lights.Intensity)
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)
