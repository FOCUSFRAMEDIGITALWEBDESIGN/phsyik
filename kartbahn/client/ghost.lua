-- 7) Ghost im Zeitfahren: Runde aufzeichnen, Bestzeit-Runde als durchsichtiges Kart abspielen
local G = nil
local STRIDE = 5 -- t, x, y, z, h

local function r2(v) return math.floor(v * 100 + 0.5) / 100 end

local function deleteGhostVeh()
    if G and G.veh and DoesEntityExist(G.veh) then DeleteEntity(G.veh) end
    if G then G.veh = nil end
end

local function spawnGhostVeh()
    local model = joaat(Config.KartModels[1])
    RequestModel(model)
    local t = GetGameTimer()
    while not HasModelLoaded(model) and GetGameTimer() - t < 3000 do Wait(10) end
    if not HasModelLoaded(model) then return end
    local d = G.play
    -- lokales, nicht vernetztes Fahrzeug ohne Kollision
    local veh = CreateVehicle(model, d[2], d[3], d[4], d[5], false, false)
    SetModelAsNoLongerNeeded(model)
    SetEntityCollision(veh, false, false)
    SetEntityAlpha(veh, Config.Ghost.Alpha, false)
    SetEntityInvincible(veh, true)
    FreezeEntityPosition(veh, true)
    SetVehicleDoorsLocked(veh, 2)
    SetVehicleColours(veh, 111, 111)
    G.veh = veh
end

function GhostPrepare(ghost)
    G = nil
    if not Config.Ghost.Enabled or not RaceState or RaceState.type ~= 'tt' then return end
    G = { rec = {}, lastRec = 0, play = ghost and ghost.data or nil, playName = ghost and ghost.name, playTime = ghost and ghost.time }
    if G.play and #G.play >= STRIDE * 2 then
        CreateThread(spawnGhostVeh)
        SendNUIMessage({ action = 'ghost', name = G.playName, time = G.playTime })
    end
end

function GhostLapStart()
    if not G then return end
    G.rec = {}
    G.lastRec = -Config.Ghost.Interval
end

function GhostLapDone(d)
    if not G then return end
    -- neue persönliche Bestzeit: an den Server senden und ab jetzt dagegen fahren
    if d.ghost and #G.rec >= STRIDE * 10 then
        TriggerLatentServerEvent('kartbahn:ghostSave', 50000, d.time, G.rec)
        G.play, G.playTime = G.rec, d.time
        if not G.veh then CreateThread(spawnGhostVeh) end
    end
    G.rec = {}
    G.lastRec = -Config.Ghost.Interval
end

function GhostStop()
    deleteGhostVeh()
    G = nil
end

-- aktuelle Ghost-Position (für die Minimap)
function GhostPos()
    if G and G.veh and DoesEntityExist(G.veh) then
        local c = GetEntityCoords(G.veh)
        return c.x, c.y
    end
    return nil
end

function GhostTick(R, ped, veh)
    if not G or not R.started or R.finished or not R.lapLocal then return end
    local el = GetGameTimer() - R.lapLocal
    -- Aufzeichnung
    if veh ~= 0 and el - G.lastRec >= Config.Ghost.Interval then
        G.lastRec = el
        local c = GetEntityCoords(veh)
        local n = #G.rec
        G.rec[n + 1], G.rec[n + 2], G.rec[n + 3], G.rec[n + 4], G.rec[n + 5] = el, r2(c.x), r2(c.y), r2(c.z), r2(GetEntityHeading(veh))
    end
    -- Wiedergabe mit Interpolation
    local p = G.play
    if not p or not G.veh or not DoesEntityExist(G.veh) then return end
    local samples = #p // STRIDE
    local i = G.cursor or 1
    if i > samples or p[(i - 1) * STRIDE + 1] > el then i = 1 end
    while i < samples and p[i * STRIDE + 1] <= el do i = i + 1 end
    G.cursor = i
    local a = (i - 1) * STRIDE
    if i >= samples then
        SetEntityVisible(G.veh, false, false) -- Ghost ist schon im Ziel
        return
    end
    SetEntityVisible(G.veh, true, false)
    local b = i * STRIDE
    local span = p[b + 1] - p[a + 1]
    local f = span > 0 and math.max(0.0, math.min(1.0, (el - p[a + 1]) / span)) or 0.0
    local h1, h2 = p[a + 5], p[b + 5]
    local dh = ((h2 - h1 + 540) % 360) - 180
    SetEntityCoordsNoOffset(G.veh, p[a + 2] + (p[b + 2] - p[a + 2]) * f, p[a + 3] + (p[b + 3] - p[a + 3]) * f,
        p[a + 4] + (p[b + 4] - p[a + 4]) * f, false, false, false)
    SetEntityHeading(G.veh, h1 + dh * f)
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then deleteGhostVeh() end
end)
