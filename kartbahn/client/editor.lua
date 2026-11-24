-- In-Game-Strecken-Editor (Ace "kart.admin", Prüfung serverseitig)
local E = nil       -- { track = {...}, history = {}, objs = {} }

function IsEditing() return E ~= nil end

local function msg(key, ...) Notify(KB.T(key, ...), 'info') end

local function groundZ(c)
    -- auf angehobenen Strecken: Höhe der eigenen Position (Fahrbahn = lokale Objekte)
    if E and E.track.platform and E.track.platform.enabled then
        return IsPedInAnyVehicle(PlayerPedId(), false) and c.z - 0.4 or c.z - 1.0
    end
    local ok, z = GetGroundZFor_3dCoord(c.x, c.y, c.z + 2.0, false)
    return ok and z or c.z - 1.0
end

-- Vorschau-Objekte (Absperrungen + Props) neu bauen
local function rebuildPreview()
    if not E then return end
    DeleteObjectList(E.objs)
    E.objs = SpawnTrackObjects(E.track)
end

local function finishEditor()
    if E then DeleteObjectList(E.objs) end
    E = nil
end

RegisterNetEvent('kartbahn:editorStart', function(existing, id)
    finishEditor()
    local t = existing and json.decode(json.encode(existing)) or {
        id = id ~= '' and id or nil, name = id ~= '' and id or 'Neue Strecke', laps = 3,
        minLap = Config.AntiCheat.MinLapTime, autoBarriers = true, checkpoints = {}, grid = {}, props = {}
    }
    t.boostPads, t.itemBoxes = t.boostPads or {}, t.itemBoxes or {}
    E = { track = t, history = {}, objs = {} }
    msg('ed_start', t.name or id)
    rebuildPreview()
    CreateThread(function()
        while E do
            local tr = E.track
            local cps = tr.checkpoints
            for i, cp in ipairs(cps) do
                local col = i == 1 and { 255, 255, 255 } or { 255, 204, 0 }
                DrawMarker(1, cp.x, cp.y, cp.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, cp.w, cp.w, 1.0,
                    col[1], col[2], col[3], 70, false, false, 2, false, nil, nil, false)
                local nxt = cps[i == #cps and 1 or i + 1]
                if #cps > 1 then
                    DrawLine(cp.x, cp.y, cp.z + 0.5, nxt.x, nxt.y, nxt.z + 0.5, 255, 204, 0, 255)
                end
                if #cps >= 3 then
                    -- Kanten-Linien als Vorschau der Begrenzung
                    local l1, r1 = KB.CpEdges(cps, i, 0.0)
                    local l2, r2 = KB.CpEdges(cps, i == #cps and 1 or i + 1, 0.0)
                    DrawLine(l1.x, l1.y, l1.z + 0.3, l2.x, l2.y, l2.z + 0.3, 255, 80, 80, 255)
                    DrawLine(r1.x, r1.y, r1.z + 0.3, r2.x, r2.y, r2.z + 0.3, 255, 80, 80, 255)
                end
            end
            for _, g in ipairs(tr.grid) do
                DrawMarker(0, g.x, g.y, g.z + 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.8, 0.8, 0.8,
                    80, 200, 255, 160, false, false, 2, false, nil, nil, false)
                local rad = math.rad(g.h)
                DrawLine(g.x, g.y, g.z + 0.5, g.x - math.sin(rad) * 3.0, g.y + math.cos(rad) * 3.0, g.z + 0.5, 80, 200, 255, 255)
            end
            -- Boost-Felder, Item-Boxen, Podest
            for _, b in ipairs(tr.boostPads) do
                DrawMarker(30, b.x, b.y, b.z + 0.05, 0.0, 0.0, 0.0, -90.0, 0.0, b.h, 3.0, 3.0, 3.0,
                    0, 200, 255, 160, false, false, 2, false, nil, nil, false)
            end
            for _, b in ipairs(tr.itemBoxes) do
                DrawMarker(32, b.x, b.y, b.z + 1.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.4, 1.4, 1.4,
                    255, 204, 0, 200, true, true, 2, true, nil, nil, false)
            end
            if tr.podium then
                DrawMarker(1, tr.podium.x, tr.podium.y, tr.podium.z - 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 5.0, 2.0, 1.2,
                    255, 204, 0, 120, false, false, 2, false, nil, nil, false)
            end
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(KB.T('ed_help', #cps, #tr.grid, #tr.props, tr.laps,
                tr.autoBarriers and KB.T('on') or KB.T('off')))
            EndTextCommandDisplayHelp(0, false, false, -1)
            Wait(0)
        end
    end)
end)

RegisterNetEvent('kartbahn:editorSaved', function()
    finishEditor()
end)

-- ===== Befehle =====
RegisterCommand('kartedit', function(_, args)
    TriggerServerEvent('kartbahn:editorRequest', args[1] or '')
end, false)

RegisterCommand('kartcp', function(_, args)
    if not E then return msg('ed_not_active') end
    local w = tonumber(args[1]) or Config.Editor.DefaultWidth
    w = math.max(Config.Editor.MinWidth, math.min(Config.Editor.MaxWidth, w))
    local c = GetEntityCoords(PlayerPedId())
    table.insert(E.track.checkpoints, { x = c.x, y = c.y, z = groundZ(c), w = w })
    table.insert(E.history, 'cp')
    msg('ed_cp', #E.track.checkpoints, w)
    if E.track.autoBarriers and #E.track.checkpoints >= 3 then rebuildPreview() end
end, false)

RegisterCommand('kartgrid', function()
    if not E then return msg('ed_not_active') end
    if #E.track.grid >= Config.Editor.MaxGrid then return msg('ed_grid_max', Config.Editor.MaxGrid) end
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    local ent = veh ~= 0 and veh or ped
    local c = GetEntityCoords(ent)
    table.insert(E.track.grid, { x = c.x, y = c.y, z = groundZ(c), h = GetEntityHeading(ent) })
    table.insert(E.history, 'grid')
    msg('ed_grid', #E.track.grid)
end, false)

RegisterCommand('kartprop', function(_, args)
    if not E then return msg('ed_not_active') end
    local model = args[1]
    if not model or not IsModelInCdimage(joaat(model)) then return msg('ed_bad_model', tostring(model)) end
    local ped = PlayerPedId()
    local c = GetOffsetFromEntityInWorldCoords(ped, 0.0, 3.0, 0.0)
    table.insert(E.track.props, { model = model, x = c.x, y = c.y, z = groundZ(c), h = GetEntityHeading(ped) })
    table.insert(E.history, 'prop')
    msg('ed_prop', model)
    rebuildPreview()
end, false)

RegisterCommand('kartundo', function()
    if not E then return msg('ed_not_active') end
    local last = table.remove(E.history)
    if not last then return msg('ed_nothing') end
    if last == 'cp' then table.remove(E.track.checkpoints)
    elseif last == 'grid' then table.remove(E.track.grid)
    elseif last == 'prop' then table.remove(E.track.props)
    elseif last == 'boost' then table.remove(E.track.boostPads)
    elseif last == 'item' then table.remove(E.track.itemBoxes)
    elseif last == 'podium' then E.track.podium = E.podiumPrev end
    msg('ed_undo', last)
    rebuildPreview()
end, false)

-- Boost-Feld in Blickrichtung
RegisterCommand('kartboost', function()
    if not E then return msg('ed_not_active') end
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    local ent = veh ~= 0 and veh or ped
    local c = GetEntityCoords(ent)
    table.insert(E.track.boostPads, { x = c.x, y = c.y, z = groundZ(c), h = GetEntityHeading(ent) })
    table.insert(E.history, 'boost')
    msg('ed_boost', #E.track.boostPads)
end, false)

-- Item-Box (nur im Item-Modus aktiv; ohne eigene Boxen werden sie automatisch verteilt)
RegisterCommand('kartitem', function()
    if not E then return msg('ed_not_active') end
    local c = GetEntityCoords(PlayerPedId())
    table.insert(E.track.itemBoxes, { x = c.x, y = c.y, z = groundZ(c) })
    table.insert(E.history, 'item')
    msg('ed_item', #E.track.itemBoxes)
end, false)

-- Siegerpodest (Blickrichtung = Richtung, in die die Fahrer schauen)
RegisterCommand('kartpodium', function()
    if not E then return msg('ed_not_active') end
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    E.podiumPrev = E.track.podium
    E.track.podium = { x = c.x, y = c.y, z = groundZ(c), h = GetEntityHeading(ped) }
    table.insert(E.history, 'podium')
    msg('ed_podium')
end, false)

-- Angehobene Strecke an/aus: verschiebt alle Punkte um die Höhe
RegisterCommand('kartplatform', function(_, args)
    if not E then return msg('ed_not_active') end
    local tr = E.track
    local on = not (tr.platform and tr.platform.enabled)
    local raise = on and (tonumber(args[1]) or Config.Platform.DefaultRaise) or tr.platform.raise
    local dz = on and raise or -raise
    for _, key in ipairs({ 'checkpoints', 'grid', 'boostPads', 'itemBoxes', 'props' }) do
        for _, o in ipairs(tr[key] or {}) do o.z = o.z + dz end
    end
    tr.platform = on and { enabled = true, raise = raise } or nil
    msg('ed_platform', on and (raise .. ' m') or KB.T('off'))
    rebuildPreview()
end, false)

RegisterCommand('kartlaps', function(_, args)
    if not E then return msg('ed_not_active') end
    local n = math.floor(tonumber(args[1]) or 3)
    E.track.laps = math.max(Config.Race.MinLaps, math.min(Config.Race.MaxLaps, n))
    msg('ed_laps', E.track.laps)
end, false)

RegisterCommand('kartbarriers', function()
    if not E then return msg('ed_not_active') end
    E.track.autoBarriers = not E.track.autoBarriers
    msg('ed_barriers', E.track.autoBarriers and KB.T('on') or KB.T('off'))
    rebuildPreview()
end, false)

RegisterCommand('kartsave', function(_, args)
    if not E then return msg('ed_not_active') end
    local id = args[1] or E.track.id
    if not id then return msg('usage_save') end
    E.track.id = id
    if #args > 1 then E.track.name = table.concat(args, ' ', 2) end
    if #E.track.checkpoints < 3 or #E.track.grid < 1 then return msg('ed_invalid') end
    TriggerServerEvent('kartbahn:editorSave', E.track)
end, false)

RegisterCommand('kartcancel', function()
    if not E then return msg('ed_not_active') end
    finishEditor()
    msg('ed_cancel')
end, false)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then finishEditor() end
end)

-- Chat-Vorschläge
CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/kartedit', 'Kart-Editor starten', { { name = 'id', help = 'Strecken-ID (optional, bestehende laden)' } })
    TriggerEvent('chat:addSuggestion', '/kartcp', 'Checkpoint setzen', { { name = 'breite', help = 'Breite in Metern' } })
    TriggerEvent('chat:addSuggestion', '/kartgrid', 'Startplatz an aktueller Position setzen')
    TriggerEvent('chat:addSuggestion', '/kartprop', 'Prop setzen', { { name = 'model', help = 'Modellname' } })
    TriggerEvent('chat:addSuggestion', '/kartundo', 'Letzte Aktion rückgängig')
    TriggerEvent('chat:addSuggestion', '/kartlaps', 'Rundenzahl setzen', { { name = 'anzahl', help = 'Runden' } })
    TriggerEvent('chat:addSuggestion', '/kartbarriers', 'Automatische Begrenzung an/aus')
    TriggerEvent('chat:addSuggestion', '/kartsave', 'Strecke speichern', { { name = 'id', help = 'Strecken-ID' }, { name = 'name', help = 'Anzeigename' } })
    TriggerEvent('chat:addSuggestion', '/kartcancel', 'Editor abbrechen')
    TriggerEvent('chat:addSuggestion', '/kartboost', 'Boost-Feld setzen')
    TriggerEvent('chat:addSuggestion', '/kartitem', 'Item-Box setzen')
    TriggerEvent('chat:addSuggestion', '/kartpodium', 'Siegerpodest setzen')
    TriggerEvent('chat:addSuggestion', '/kartplatform', 'Angehobene Strecke an/aus', { { name = 'höhe', help = 'Meter (Standard 3)' } })
    TriggerEvent('chat:addSuggestion', '/kartreset', 'Kart auf den letzten Checkpoint zurücksetzen')
    TriggerEvent('chat:addSuggestion', '/kartleave', 'Rennen / Zeitfahren verlassen')
end)
