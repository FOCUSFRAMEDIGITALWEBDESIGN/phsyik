-- Lokale (nicht vernetzte) Streckenobjekte: Absperrungen, Pylonen, Props
local spawned = {}   -- [trackId] = { objs = {}, center = vector3 }
local centers = {}

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

local function spawnPlatform(track)
    local objs = {}
    local hash = pickPlatformModel()
    if not hash then
        print('[kartbahn] Kein Plattform-Modell gefunden – Strecke ohne Plattform.')
        return objs
    end
    -- Maße des Modells: Fahrbahn läuft entlang der längeren Achse
    local mn, mx = GetModelDimensions(hash)
    local sx, sy = mx.x - mn.x, mx.y - mn.y
    local alongX = sx > sy
    local tileLen = math.max(alongX and sx or sy, 1.0)
    local tileW = math.max(alongX and sy or sx, 1.0)
    local step = math.max(tileLen - Config.Platform.Overlap, 0.5)
    local cps = track.checkpoints
    local n = #cps
    for i = 1, n do
        local a, b = cps[i], cps[i == n and 1 or i + 1]
        local dx, dy = b.x - a.x, b.y - a.y
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0.1 then
            local ux, uy = dx / len, dy / len
            local nx, ny = -uy, ux
            local W = math.max(a.w, b.w) + Config.Platform.Margin * 2
            -- über die Enden hinaus verlängern, damit Kurven geschlossen sind
            local ext = W / 2
            local total = len + ext * 2
            local count = math.max(1, math.ceil(total / step))
            local lanes = math.max(1, math.ceil(W / tileW))
            local h = math.deg(math.atan(-ux, uy))
            if alongX then h = h + 90.0 end
            -- winziger Höhenversatz je Segment gegen Flackern überlappender Platten
            local zOff = (i % 2) * 0.01
            for k = 0, count - 1 do
                local along = -ext + (k + 0.5) * (total / count)
                local t = math.max(0.0, math.min(1.0, along / len))
                local surfZ = a.z + (b.z - a.z) * t
                for l = 0, lanes - 1 do
                    local lat = (l - (lanes - 1) / 2) * tileW
                    local x = a.x + ux * along + nx * lat
                    local y = a.y + uy * along + ny * lat
                    local obj = CreateObjectNoOffset(hash, x, y, surfZ - mx.z + zOff, false, false, false)
                    SetEntityHeading(obj, h)
                    FreezeEntityPosition(obj, true)
                    SetEntityInvincible(obj, true)
                    SetEntityLodDist(obj, 500)
                    objs[#objs + 1] = obj
                end
            end
        end
    end
    SetModelAsNoLongerNeeded(hash)
    return objs
end

-- komplette Strecke spawnen (Plattform zuerst, dann Bande/Props)
function SpawnTrackObjects(track)
    local objs = {}
    local raised = track.platform and track.platform.enabled
    if raised and #(track.checkpoints or {}) >= 3 then objs = spawnPlatform(track) end
    for _, o in ipairs(SpawnObjectList(KB.BuildObjectList(track), raised)) do objs[#objs + 1] = o end
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

function RespawnTrack(id)
    despawnTrack(id)
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
            if d < Config.Track.StreamDistance and not spawned[id] and TrackList[id] then
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
