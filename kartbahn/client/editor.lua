-- In-Game-Strecken-Editor (Ace "kart.admin", Prüfung serverseitig)
local E = nil       -- { track = {...}, history = {}, objs = {} }

function IsEditing() return E ~= nil end

local function msg(key, ...) Notify(KB.T(key, ...), 'info') end

local function groundZ(c)
    local ok, z = GetGroundZFor_3dCoord(c.x, c.y, c.z + 2.0, false)
    return ok and z or c.z - 1.0
end

-- Vorschau-Objekte (Absperrungen + Props) neu bauen
local function rebuildPreview()
    if not E then return end
    DeleteObjectList(E.objs)
    E.objs = SpawnObjectList(KB.BuildObjectList(E.track))
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
    elseif last == 'prop' then table.remove(E.track.props) end
    msg('ed_undo', last)
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
    TriggerEvent('chat:addSuggestion', '/kartleave', 'Rennen / Zeitfahren verlassen')
end)
