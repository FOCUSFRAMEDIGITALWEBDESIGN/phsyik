-- Strecken-Editor (serverseitige Berechtigungsprüfung und Speichern)
local function allowed(src)
    return IsPlayerAceAllowed(src, Config.Editor.Ace)
end

RegisterNetEvent('kartbahn:editorRequest', function(id)
    local src = source
    if not allowed(src) then return Notify(src, KB.T('no_perm'), 'error') end
    id = type(id) == 'string' and id:lower():gsub('[^%w_%-]', '') or ''
    TriggerClientEvent('kartbahn:editorStart', src, id ~= '' and Tracks.Get(id) or nil, id)
end)

RegisterNetEvent('kartbahn:editorSave', function(data)
    local src = source
    if not allowed(src) then return Notify(src, KB.T('no_perm'), 'error') end
    local t = Tracks.Sanitize(data)
    if not t then return Notify(src, KB.T('ed_invalid'), 'error') end
    Tracks.Save(t)
    if not Records.Get(t.id) then
        local r = DB.GetTrackRecord(t.id)
        if r then Records.data[t.id] = { time = r.lap_time, name = r.name, identifier = r.identifier } end
    end
    TriggerClientEvent('kartbahn:editorSaved', src, t.id)
    Notify(src, KB.T('ed_saved', t.name), 'success')
end)
