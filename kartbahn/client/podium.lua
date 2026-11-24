-- 14) Siegerpodest: Top 3 auf Stufen, Konfetti, Kamerafahrt (alles lokal, nicht vernetzt)
local function loadModel(hash)
    RequestModel(hash)
    local t = GetGameTimer()
    while not HasModelLoaded(hash) and GetGameTimer() - t < 3000 do Wait(10) end
    return HasModelLoaded(hash)
end

-- Figur für einen Fahrer: Klon des echten Spielers, sonst Ersatzmodell
local function makePed(src, x, y, z, h)
    local pl = GetPlayerFromServerId(src)
    local real = pl ~= -1 and GetPlayerPed(pl) or 0
    local ped
    if real ~= 0 and DoesEntityExist(real) then
        ped = ClonePed(real, false, false, true)
        SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    else
        local m = joaat('a_m_y_motox_01')
        if not loadModel(m) then return nil end
        ped = CreatePed(4, m, x, y, z, h, false, false)
        SetModelAsNoLongerNeeded(m)
    end
    SetEntityHeading(ped, h)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    return ped
end

local function confetti(x, y, z)
    RequestNamedPtfxAsset('scr_xs_celebration')
    local t = GetGameTimer()
    while not HasNamedPtfxAssetLoaded('scr_xs_celebration') and GetGameTimer() - t < 2000 do Wait(10) end
    if not HasNamedPtfxAssetLoaded('scr_xs_celebration') then return end
    UseParticleFxAsset('scr_xs_celebration')
    StartParticleFxNonLoopedAtCoord('scr_xs_confetti_burst', x, y, z, 0.0, 0.0, 0.0, 1.5, false, false, false)
end

function PlayPodium(d)
    local track = TrackList[d.trackId]
    if not track then return end
    local top = {}
    for _, r in ipairs(d.results) do
        if not r.dnf and r.place <= 3 then top[r.place] = r end
    end
    if not top[1] then return end

    local p = KB.GetPodium(track)
    if not track.podium and track.platform then
        local ok, gz = GetGroundZFor_3dCoord(p.x, p.y, p.z + 5.0, false)
        p = { x = p.x, y = p.y, z = ok and gz or p.z, h = p.h }
    end
    local h = math.rad(p.h)
    local rx, ry = math.cos(h), math.sin(h)        -- seitliche Achse des Podests
    local fx, fy = -math.sin(h), math.cos(h)       -- Blickrichtung
    local stands = {
        [1] = { off = 0.0,  height = 1.2, col = { 255, 204, 0 } },
        [2] = { off = -1.8, height = 0.8, col = { 192, 199, 208 } },
        [3] = { off = 1.8,  height = 0.5, col = { 205, 127, 50 } }
    }
    local peds = {}
    for place, r in pairs(top) do
        local s = stands[place]
        local x, y = p.x + rx * s.off, p.y + ry * s.off
        local ped = makePed(r.src, x, y, p.z + s.height, p.h)
        if ped then
            peds[#peds + 1] = ped
            TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CHEERING', 0, true)
        end
    end

    -- Kamerafahrt von weit nach nah
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, p.x + fx * 14.0 + rx * 6.0, p.y + fy * 14.0 + ry * 6.0, p.z + 5.0)
    PointCamAtCoord(cam, p.x, p.y, p.z + 1.5)
    local cam2 = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam2, p.x + fx * 6.0, p.y + fy * 6.0, p.z + 2.6)
    PointCamAtCoord(cam2, p.x, p.y, p.z + 1.8)
    SetCamActiveWithInterp(cam2, cam, Config.Podium.Duration - 1500, 1, 1)
    RenderScriptCams(true, true, 800, true, true)
    PlaySoundFrontend(-1, 'FIRST_PLACE', 'HUD_MINI_GAME_SOUNDSET', true)
    SendNUIMessage({ action = 'podium', on = true, names = {
        top[1] and top[1].name, top[2] and top[2].name, top[3] and top[3].name } })

    local endT = GetGameTimer() + Config.Podium.Duration
    local nextConfetti = 0
    while GetGameTimer() < endT do
        -- Podeststufen als Marker
        for place in pairs(top) do
            local s = stands[place]
            DrawMarker(1, p.x + rx * s.off, p.y + ry * s.off, p.z - 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, p.h, 1.6, 1.6, s.height,
                s.col[1], s.col[2], s.col[3], 255, false, false, 2, false, nil, nil, false)
        end
        if GetGameTimer() > nextConfetti then
            nextConfetti = GetGameTimer() + 1500
            confetti(p.x, p.y, p.z + 3.5)
        end
        Wait(0)
    end

    RenderScriptCams(false, true, 800, true, true)
    DestroyCam(cam, false)
    DestroyCam(cam2, false)
    for _, ped in ipairs(peds) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
    RemoveNamedPtfxAsset('scr_xs_celebration')
    SendNUIMessage({ action = 'podium', on = false })
end
