-- Fahr-Features: 1) Boost, 2) Windschatten, 3) Perfekter Start, 4) Drift-Boost, 5) Boost-Felder, 6) Items
local F = nil

local function banner(key, kind) SendNUIMessage({ action = 'banner', text = KB.T(key), kind = kind }) end

function FeatOnPrepare(d)
    F = {
        boostAllowed = d.boost, itemsAllowed = d.items, charge = d.charge or 0,
        boostUntil = 0, boostPower = 1.0, penaltyUntil = 0, falseStart = false, startChecked = false,
        driftTime = 0.0, padCd = 0, item = nil, boxCd = {}, hazards = {}, shieldUntil = 0, spinUntil = 0,
        slip = false, lastSlipMsg = false, fxOn = false,
        boxes = d.items and KB.GetItemBoxes(TrackList[d.trackId]) or {},
        pads = Config.BoostPads.Enabled and (TrackList[d.trackId].boostPads or {}) or {}
    }
    SendNUIMessage({ action = 'boost', charge = F.charge, enabled = F.boostAllowed })
    SendNUIMessage({ action = 'item', item = nil, enabled = F.itemsAllowed })
end

function FeatOnGo()
    if not F then return end
    if F.falseStart then
        F.penaltyUntil = GetGameTimer() + Config.PerfectStart.FalseStartPenalty
        banner('false_start', 'error')
    end
end

function FeatOnStop()
    if F and F.fxOn then AnimpostfxStop('RaceTurbo') end
    F = nil
    SendNUIMessage({ action = 'slip', on = false })
end

-- lokaler Schub (Server hat Boost/Item bereits geprüft)
local function startBoost(ms, power)
    if not F then return end
    local t = GetGameTimer()
    F.boostUntil = math.max(F.boostUntil, t + ms)
    F.boostPower = math.max(power, F.boostUntil > t and F.boostPower or 1.0)
    PlaySoundFrontend(-1, 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET', true)
end

RegisterNetEvent('kartbahn:boostGo', function(ms, power) startBoost(ms, power) end)

RegisterNetEvent('kartbahn:boostState', function(charge, used)
    if not F then return end
    F.charge = charge
    SendNUIMessage({ action = 'boost', charge = charge, enabled = F.boostAllowed })
    if not used and charge < Config.Boost.Cost and F.requested then banner('boost_empty', 'error') end
    F.requested = false
end)

RegisterNetEvent('kartbahn:itemGot', function(item, boxIdx, cd)
    if not F then return end
    F.item = item
    if boxIdx then F.boxCd[boxIdx] = GetGameTimer() + (cd or Config.Items.Respawn) end
    if item then
        Notify(KB.T('item_got', Config.Items.Labels[item] or item), 'info')
        PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    end
    SendNUIMessage({ action = 'item', item = item and Config.Items.Labels[item] or nil, key = item, enabled = F.itemsAllowed })
end)

RegisterNetEvent('kartbahn:hazard', function(h)
    if not F then return end
    h.untilT = GetGameTimer() + h.ttl
    F.hazards[h.id] = h
end)

RegisterNetEvent('kartbahn:shield', function(ms)
    if not F then return end
    F.shieldUntil = GetGameTimer() + ms
    SendNUIMessage({ action = 'shield', ms = ms })
    banner('item_shield')
end)

-- Winkel zwischen Fahrtrichtung und Bewegungsrichtung (Drift)
local function slipAngle(veh)
    local v = GetEntityVelocity(veh)
    local sp = math.sqrt(v.x * v.x + v.y * v.y)
    if sp < 1.0 then return 0.0, sp end
    local f = GetEntityForwardVector(veh)
    local cos = (v.x * f.x + v.y * f.y) / sp
    return math.deg(math.acos(math.max(-1.0, math.min(1.0, cos)))), sp
end

-- Windschatten lokal (Leistung); die Boost-Ladung vergibt der Server
local function checkSlipstream(R, veh, pc)
    if not Config.Slipstream.Enabled or R.type ~= 'race' then return false end
    local f = GetEntityForwardVector(veh)
    local me = GetPlayerServerId(PlayerId())
    for _, row in ipairs(R.standings or {}) do
        if row.src ~= me then
            local pl = GetPlayerFromServerId(row.src)
            if pl ~= -1 then
                local op = GetPlayerPed(pl)
                if op ~= 0 and IsPedInAnyVehicle(op, false) then
                    local oc = GetEntityCoords(op)
                    local dx, dy = oc.x - pc.x, oc.y - pc.y
                    local d = math.sqrt(dx * dx + dy * dy)
                    if d > Config.Slipstream.MinDist and d < Config.Slipstream.MaxDist then
                        if (dx * f.x + dy * f.y) / d > math.cos(math.rad(Config.Slipstream.MaxAngle)) then return true end
                    end
                end
            end
        end
    end
    return false
end

-- wird jeden Frame aus der Renn-Schleife aufgerufen
function FeatTick(R, ped, veh, pc)
    if not F then return end
    local t = GetGameTimer()

    -- 3) Frühstart erkennen (Gas in der letzten Countdown-Sekunde)
    if not R.started then
        if Config.PerfectStart.Enabled and R.lights and R.lightsMax and R.lights >= R.lightsMax and IsDisabledControlPressed(0, 71) then
            F.falseStart = true
        end
        return
    end
    if R.finished or veh == 0 then return end

    -- 3) Perfekter Start: Gas innerhalb des Zeitfensters nach GO
    if Config.PerfectStart.Enabled and not F.startChecked and not F.falseStart then
        if IsControlPressed(0, 71) then
            F.startChecked = true
            if t - (R.goAt or t) <= Config.PerfectStart.Window then
                startBoost(Config.PerfectStart.BoostTime, Config.PerfectStart.Power)
                banner('perfect_start')
            end
        elseif t - (R.goAt or t) > Config.PerfectStart.Window then
            F.startChecked = true
        end
    end

    -- 1) Boost-Knopf
    if F.boostAllowed and IsControlJustPressed(0, Config.Boost.Key) then
        F.requested = true
        TriggerServerEvent('kartbahn:boostReq')
    end

    -- 4) Drift-Boost
    if F.boostAllowed and Config.DriftBoost.Enabled then
        local ang, sp = slipAngle(veh)
        if sp * 3.6 > Config.DriftBoost.MinSpeed and ang > Config.DriftBoost.MinAngle and ang < 90.0 then
            F.driftTime = F.driftTime + GetFrameTime()
        else
            if F.driftTime >= Config.DriftBoost.MinTime then
                startBoost(math.min(Config.DriftBoost.MaxBoost, math.floor(F.driftTime * 600)), Config.DriftBoost.Power)
                banner('drift_boost')
            end
            F.driftTime = 0.0
        end
    end

    -- 5) Boost-Felder
    for _, p in ipairs(F.pads) do
        local d = KB.Dist2D(pc.x, pc.y, p.x, p.y)
        if d < 60.0 then
            DrawMarker(30, p.x, p.y, p.z + 0.05, 0.0, 0.0, 0.0, -90.0, 0.0, p.h, 3.0, 3.0, 3.0,
                0, 200, 255, 160, false, false, 2, false, nil, nil, false)
            if d < Config.BoostPads.Radius and t > F.padCd then
                F.padCd = t + Config.BoostPads.Cooldown
                startBoost(Config.BoostPads.Duration, Config.BoostPads.Power)
            end
        end
    end

    -- 6) Item-Boxen, Benutzen, Ölpfützen
    if F.itemsAllowed then
        for i, b in ipairs(F.boxes) do
            if (F.boxCd[i] or 0) < t then
                local d = KB.Dist2D(pc.x, pc.y, b.x, b.y)
                if d < 80.0 then
                    DrawMarker(32, b.x, b.y, b.z + 1.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.4, 1.4, 1.4,
                        255, 204, 0, 220, true, true, 2, true, nil, nil, false)
                    if d < Config.Items.Radius and not F.item then
                        F.boxCd[i] = t + 1000 -- Doppelmeldung vermeiden; echte Sperre setzt der Server
                        TriggerServerEvent('kartbahn:itemPick', i)
                    end
                end
            end
        end
        if F.item and IsControlJustPressed(0, Config.Items.Key) then
            TriggerServerEvent('kartbahn:itemUse')
        end
    end
    local me = GetPlayerServerId(PlayerId())
    for id, h in pairs(F.hazards) do
        if h.untilT < t then
            F.hazards[id] = nil
        else
            DrawMarker(27, h.x, h.y, h.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, Config.Items.OilRadius * 2, Config.Items.OilRadius * 2, 1.0,
                15, 15, 15, 220, false, false, 2, false, nil, nil, false)
            -- eigene Pfütze trifft den Werfer nicht in den ersten 2 s
            local own = h.owner == me and (h.untilT - h.ttl + 2000) > t
            if not own and KB.Dist2D(pc.x, pc.y, h.x, h.y) < Config.Items.OilRadius and t > F.shieldUntil and t > F.spinUntil then
                F.spinUntil = t + Config.Items.SpinTime
                F.hazards[id] = nil
                SetVehicleReduceGrip(veh, true)
                SetVehicleForwardSpeed(veh, GetEntitySpeed(veh) * 0.6)
                banner('item_oil_hit', 'error')
                PlaySoundFrontend(-1, 'LOSER', 'HUD_AWARDS', true)
            end
        end
    end
    if F.spinUntil > 0 and t > F.spinUntil then
        F.spinUntil = 0
        SetVehicleReduceGrip(veh, false)
    end

    -- 2) Windschatten-Anzeige (alle 250 ms prüfen)
    if t - (F.slipCheck or 0) > 250 then
        F.slipCheck = t
        F.slip = checkSlipstream(R, veh, pc)
        if F.slip ~= F.lastSlipMsg then
            F.lastSlipMsg = F.slip
            SendNUIMessage({ action = 'slip', on = F.slip })
        end
    end

    -- Leistung anwenden (muss jeden Frame gesetzt werden)
    local power = 1.0
    local maxSpeed = Config.Kart.MaxSpeed
    if t < F.penaltyUntil then
        power = 0.25
    elseif t < F.boostUntil then
        power = F.boostPower
        maxSpeed = maxSpeed + Config.Boost.ExtraSpeed
    elseif F.slip then
        power = Config.Slipstream.Power
    end
    SetVehicleCheatPowerIncrease(veh, power)
    if F.lastMax ~= maxSpeed then
        F.lastMax = maxSpeed
        SetVehicleMaxSpeed(veh, maxSpeed / 3.6)
    end
    -- Boost-Bildeffekt
    local boosting = t < F.boostUntil
    if boosting ~= F.fxOn then
        F.fxOn = boosting
        if boosting then AnimpostfxPlay('RaceTurbo', 0, false) else AnimpostfxStop('RaceTurbo') end
        SendNUIMessage({ action = 'boostActive', on = boosting })
    end
    -- Boost-Leiste lokal weiterladen (Anzeige; maßgeblich ist der Server)
    if F.boostAllowed and t - (F.chargeTick or 0) > 250 then
        F.chargeTick = t
        F.charge = math.min(100.0, F.charge + Config.Boost.RechargeRate * 0.25)
        SendNUIMessage({ action = 'boost', charge = F.charge, enabled = true })
    end
end
