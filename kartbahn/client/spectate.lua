-- 13) Zuschauer-Modus: Kamera folgt einem Fahrer, mit Pfeiltasten umschalten
local S = nil

function IsSpectating() return S ~= nil end

function StopSpectate()
    if not S then return end
    local ped = PlayerPedId()
    RenderScriptCams(false, true, 500, true, true)
    if S.cam then DestroyCam(S.cam, false) end
    DoScreenFadeOut(300)
    Wait(350)
    SetEntityCoords(ped, S.back.x, S.back.y, S.back.z, false, false, false, false)
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, false)
    DoScreenFadeIn(400)
    TriggerServerEvent('kartbahn:spectateLeave')
    SendNUIMessage({ action = 'spectate', on = false })
    SendNUIMessage({ action = 'hud', show = false })
    S = nil
end

function SpectateStandings(rows)
    if not S then return end
    local list = {}
    for _, r in ipairs(rows) do
        if not r.dnf and not r.out then list[#list + 1] = { src = r.src, name = r.name } end
    end
    if #list > 0 then S.racers = list end
    S.rows = rows
    if S.idx > #S.racers then S.idx = 1 end
end

local function current()
    return S.racers[S.idx]
end

local function startSpectate(data)
    local ped = PlayerPedId()
    S = { sid = data.sid, racers = data.racers, idx = 1, back = GetEntityCoords(ped), trackId = data.trackId }
    if MenuOpen then CloseMenu() end
    DoScreenFadeOut(300)
    Wait(350)
    -- Eigene Figur unsichtbar an die Strecke stellen, damit die Karts gestreamt werden
    local spot = data.spot
    SetEntityCoords(ped, spot.x, spot.y, spot.z + 15.0, false, false, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    SetEntityInvincible(ped, true)
    S.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamFov(S.cam, 60.0)
    RenderScriptCams(true, true, 500, true, true)
    DoScreenFadeIn(400)
    local track = TrackList[data.trackId]
    local outline = {}
    for _, cp in ipairs(track.checkpoints) do outline[#outline + 1] = { cp.x, cp.y } end
    SendNUIMessage({ action = 'spectate', on = true, trackName = track.name, outline = outline })

    CreateThread(function()
        while S do
            local r = current()
            if r then
                local pl = GetPlayerFromServerId(r.src)
                local tp = pl ~= -1 and GetPlayerPed(pl) or 0
                if tp ~= 0 and DoesEntityExist(tp) then
                    local ent = IsPedInAnyVehicle(tp, false) and GetVehiclePedIsIn(tp, false) or tp
                    local c = GetOffsetFromEntityInWorldCoords(ent, 0.0, -7.0, 3.0)
                    SetCamCoord(S.cam, c.x, c.y, c.z)
                    PointCamAtEntity(S.cam, ent, 0.0, 0.0, 0.5, true)
                    SetFocusEntity(ent)
                end
                SendNUIMessage({ action = 'spectateName', name = r.name, idx = S.idx, total = #S.racers })
            end
            -- Minimap-Punkte für Zuschauer
            if GetGameTimer() - (S.dotT or 0) > 250 then
                S.dotT = GetGameTimer()
                local dots = {}
                local cur = current()
                for _, row in ipairs(S.rows or {}) do
                    if not row.dnf and not row.out then
                        local pl = GetPlayerFromServerId(row.src)
                        local op = pl ~= -1 and GetPlayerPed(pl) or 0
                        local x, y = row.x, row.y
                        if op ~= 0 and DoesEntityExist(op) then local c = GetEntityCoords(op) x, y = c.x, c.y end
                        if x then dots[#dots + 1] = { x, y, (cur and cur.src == row.src) and 1 or 0, row.team } end
                    end
                end
                SendNUIMessage({ action = 'dots', dots = dots })
            end
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(KB.T('spectate_help'))
            EndTextCommandDisplayHelp(0, false, false, -1)
            if IsControlJustPressed(0, Config.Spectate.Key_Next) then S.idx = S.idx % #S.racers + 1 end
            if IsControlJustPressed(0, Config.Spectate.Key_Prev) then S.idx = (S.idx - 2) % #S.racers + 1 end
            if IsControlJustPressed(0, Config.Spectate.Key_Exit) then
                ClearFocus()
                StopSpectate()
                return
            end
            Wait(0)
        end
        ClearFocus()
    end)
end

RegisterNetEvent('kartbahn:spectateEnd', function()
    if S then ClearFocus() StopSpectate() end
end)

RegisterNUICallback('spectate', function(d, cb)
    cb('ok')
    if S or IsRacing() then return end
    local data = ServerCallback('spectateJoin', d.id)
    if not data then return Notify(KB.T('spectate_none'), 'error') end
    startSpectate(data)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not S then return end
    RenderScriptCams(false, false, 0, true, true)
    ClearFocus()
    local ped = PlayerPedId()
    SetEntityCoords(ped, S.back.x, S.back.y, S.back.z, false, false, false, false)
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
end)
