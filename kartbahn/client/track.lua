-- Lokale (nicht vernetzte) Streckenobjekte: Absperrungen, Pylonen, Props
local spawned = {}   -- [trackId] = { objs = {}, center = vector3 }
local centers = {}
local hidden = {}    -- [trackId] = true, solange der Editor die Strecke bearbeitet

local function loadModel(hash)
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    local t = GetGameTimer()
    while not HasModelLoaded(hash) do
        if GetGameTimer() - t > 5000 then return false end
        Wait(10)
    end
    return true
end

-- Objektliste erzeugen (wird auch vom Editor für die Vorschau genutzt)
-- exactZ = true: Höhe nicht auf den Boden anpassen (angehobene Strecke)
function SpawnObjectList(list, exactZ)
    local objs, loaded = {}, {}
    for _, o in ipairs(list) do
        local hash = joaat(o.model)
        if loaded[hash] == nil then loaded[hash] = loadModel(hash) end
        if loaded[hash] then
            local obj = CreateObjectNoOffset(hash, o.x, o.y, o.z, false, false, false)
            SetEntityHeading(obj, o.h or 0.0)
            if not exactZ then PlaceObjectOnGroundProperly(obj) end
            FreezeEntityPosition(obj, true)
            SetEntityInvincible(obj, true)
            objs[#objs + 1] = obj
        end
    end
    for hash, ok in pairs(loaded) do if ok then SetModelAsNoLongerNeeded(hash) end end
    return objs
end

-- ===== Angehobene Strecke: Fahrbahn aus gleichen Platten =====
local function pickPlatformModel()
    for _, m in ipairs(Config.Platform.Models) do
        local h = joaat(m)
        if loadModel(h) then return h end
    end
    return nil
end

-- Abstand Punkt -> Strecke (Mittellinie) und Höhe dort
local function nearestOnTrack(cps, px, py)
    local best, bz = math.huge, cps[1].z
    local n = #cps
    for i = 1, n do
        local a, b = cps[i], cps[i == n and 1 or i + 1]
        local dx, dy = b.x - a.x, b.y - a.y
        local l2 = dx * dx + dy * dy
        local t = l2 > 0 and math.max(0, math.min(1, ((px - a.x) * dx + (py - a.y) * dy) / l2)) or 0
        local qx, qy = a.x + dx * t, a.y + dy * t
        local d = math.sqrt((px - qx) ^ 2 + (py - qy) ^ 2) - math.max(a.w, b.w) / 2
        if d < best then best, bz = d, a.z + (b.z - a.z) * t end
    end
    return best, bz
end

-- Fahrbahn als exaktes Raster gleicher Platten (Kante an Kante, keine Überlappung),
-- ausgerichtet an der Start-/Ziel-Geraden
local function spawnPlatform(track)
    local objs = {}
    local hash = pickPlatformModel()
    if not hash then
        print('[kartbahn] Kein Plattform-Modell gefunden – Strecke ohne Plattform.')
        return objs
    end
    local mn, mx = GetModelDimensions(hash)
    local sx, sy = mx.x - mn.x, mx.y - mn.y
    local cps = track.checkpoints
    local ux, uy = KB.CpDirection(cps, 1)
    local vx, vy = -uy, ux
    -- Kachelmaße entlang u (Fahrtrichtung der Start-Geraden) und v (quer); Modell-Y = Längsachse
    local tu, tv = sy, sx
    local h = math.deg(math.atan(-ux, uy))
    -- Bounding-Box im lokalen Raster
    local o = cps[1]
    local minU, maxU, minV, maxV = math.huge, -math.huge, math.huge, -math.huge
    for _, c in ipairs(cps) do
        local du, dv = (c.x - o.x) * ux + (c.y - o.y) * uy, (c.x - o.x) * vx + (c.y - o.y) * vy
        minU, maxU, minV, maxV = math.min(minU, du), math.max(maxU, du), math.min(minV, dv), math.max(maxV, dv)
    end
    local pad = 25.0
    -- Raster so legen, dass eine Kachelkante genau auf der Start-/Ziellinie liegt
    local i0, i1 = math.floor((minU - pad) / tu), math.ceil((maxU + pad) / tu)
    local j0, j1 = math.floor((minV - pad) / tv), math.ceil((maxV + pad) / tv)
    local margin = Config.Platform.Margin
    for i = i0, i1 do
        for j = j0, j1 do
            local cu, cv = (i + 0.5) * tu, (j + 0.5) * tv
            local px, py = o.x + ux * cu + vx * cv, o.y + uy * cu + vy * cv
            -- Kachel nehmen, wenn sie die Fahrbahn + Rand berührt
            local d, z = nearestOnTrack(cps, px, py)
            if d <= margin + math.max(tu, tv) * 0.35 then
                local obj = CreateObjectNoOffset(hash, px, py, z - mx.z, false, false, false)
                SetEntityHeading(obj, h)
                FreezeEntityPosition(obj, true)
                SetEntityInvincible(obj, true)
                SetEntityLodDist(obj, 500)
                objs[#objs + 1] = obj
            end
        end
        if i % 4 == 0 then Wait(0) end
    end
    SetModelAsNoLongerNeeded(hash)
    return objs
end

-- komplette Strecke spawnen (Plattform zuerst, dann Bande/Props)
function SpawnTrackObjects(track)
    local objs = {}
    local raised = track.platform and track.platform.enabled
    if raised and #(track.checkpoints or {}) >= 3 then objs = spawnPlatform(track) end
    -- Banden-Modell vermessen, damit die Teile genau aneinanderstoßen
    local opts = {}
    local bh = joaat(track.barrierModel or Config.Track.BarrierModel)
    if track.autoBarriers and loadModel(bh) then
        local mn, mx = GetModelDimensions(bh)
        local bx, by = mx.x - mn.x, mx.y - mn.y
        opts.barrierLen = math.max(bx, by)
        opts.barrierAlongY = by > bx
    end
    for _, o in ipairs(SpawnObjectList(KB.BuildObjectList(track, opts), raised)) do objs[#objs + 1] = o end
    return objs
end

function DeleteObjectList(objs)
    for _, obj in ipairs(objs or {}) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
end

local function despawnTrack(id)
    if spawned[id] then
        DeleteObjectList(spawned[id].objs)
        spawned[id] = nil
    end
end

-- Editor: gestreamte Fassung ausblenden, damit nichts doppelt übereinander liegt
function SetTrackHidden(id, state)
    if not id then return end
    hidden[id] = state or nil
    if state then despawnTrack(id) end
end

-- Neue Streckendaten: alles neu aufbauen
function OnTracksUpdated()
    for id in pairs(spawned) do despawnTrack(id) end
    centers = {}
    for id, t in pairs(TrackList) do centers[id] = KB.TrackCenter(t) end
end

-- Streaming nach Entfernung (alle 2 s)
CreateThread(function()
    while true do
        Wait(2000)
        local pc = GetEntityCoords(PlayerPedId())
        for id, c in pairs(centers) do
            local d = #(pc - c)
            if d < Config.Track.StreamDistance and not spawned[id] and not hidden[id] and TrackList[id] then
                spawned[id] = { objs = SpawnTrackObjects(TrackList[id]) }
            elseif d > Config.Track.StreamDistance + 50.0 and spawned[id] then
                despawnTrack(id)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(spawned) do despawnTrack(id) end
end)
