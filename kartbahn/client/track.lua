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
function SpawnObjectList(list)
    local objs, loaded = {}, {}
    for _, o in ipairs(list) do
        local hash = joaat(o.model)
        if loaded[hash] == nil then loaded[hash] = loadModel(hash) end
        if loaded[hash] then
            local obj = CreateObjectNoOffset(hash, o.x, o.y, o.z, false, false, false)
            SetEntityHeading(obj, o.h or 0.0)
            PlaceObjectOnGroundProperly(obj)
            FreezeEntityPosition(obj, true)
            SetEntityInvincible(obj, true)
            objs[#objs + 1] = obj
        end
    end
    for hash, ok in pairs(loaded) do if ok then SetModelAsNoLongerNeeded(hash) end end
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
                spawned[id] = { objs = SpawnObjectList(KB.BuildObjectList(TrackList[id])) }
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
