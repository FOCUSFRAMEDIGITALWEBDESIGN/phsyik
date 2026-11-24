Config = {}

-- 'auto' erkennt es_extended bzw. qb-core automatisch, 'esx' | 'qb' | 'none' erzwingt einen Modus
Config.Framework = 'auto'
Config.Debug = false

-- Menüpunkte (Blip + Marker, Menü mit E)
Config.Locations = {
    { coords = vector3(-1310.54, -3101.65, 13.94), blip = true }
}
Config.Blip = { sprite = 315, color = 5, scale = 0.85, name = 'Kartbahn' }
Config.InteractKey = 38        -- E
Config.InteractDistance = 2.0
Config.MarkerDrawDistance = 25.0

-- Kart-Modelle (zufällig gewählt)
Config.KartModels = { 'veto2', 'veto' }
Config.KartPlate = 'KART'

-- Rennen
Config.Race = {
    LobbyTime     = 45,     -- Sekunden Lobby-Countdown
    FullLobbyTime = 5,      -- Rest-Countdown, sobald die Lobby voll ist
    MinPlayers    = 2,
    MaxPlayers    = 8,
    MinLaps       = 1,
    MaxLaps       = 10,
    EntryFee      = 500,    -- Startgebühr (Bargeld)
    Prizes        = { 2500, 1500, 750 }, -- Preisgeld Platz 1-3
    PrepareTime   = 4,      -- Sekunden zwischen Spawn und Countdown
    CountdownTime = 3,      -- 3-2-1-GO
    FinishTimeout = 60,     -- Sekunden nach erstem Zieleinlauf
    ExitDnfTime   = 10,     -- Sekunden außerhalb des Karts bis DNF
    CleanupDelay  = 4       -- Sekunden bis Karts nach Rennende gelöscht werden
}

-- Zeitfahren
Config.TimeTrial = {
    Fee = 0,                -- Gebühr pro Session
    ExitEndTime = 10        -- Sekunden außerhalb des Karts bis die Session endet
}

-- Elo
Config.Elo = { Start = 1000, K = 32 }

-- Stufen (min = Mindest-Rating)
Config.Tiers = {
    { name = 'Bronze',  min = 0,    color = '#cd7f32' },
    { name = 'Silber',  min = 1100, color = '#c0c7d0' },
    { name = 'Gold',    min = 1250, color = '#ffcc00' },
    { name = 'Platin',  min = 1400, color = '#5eead4' },
    { name = 'Diamant', min = 1600, color = '#60a5fa' },
    { name = 'Legende', min = 1800, color = '#f43f5e' }
}

-- Anti-Cheat (serverseitig)
Config.AntiCheat = {
    CpTolerance   = 10.0,   -- zusätzliche Meter zur halben Checkpoint-Breite (Latenz)
    MinCpInterval = 250,    -- ms zwischen zwei Checkpoints
    MinLapTime    = 20000   -- Standard-Mindestrundenzeit in ms (pro Strecke über "minLap" überschreibbar)
}

-- Strecken-Darstellung (lokal pro Client)
Config.Track = {
    StreamDistance  = 350.0,
    BarrierModel    = 'prop_mp_barrier_02b',
    BarrierSpacing  = 3.0,
    BarrierOffset   = 1.0,   -- Abstand der Absperrung zur Checkpoint-Kante
    ConeModel       = 'prop_roadcone02a',
    MaxObjects      = 500,
    CpMarkerColor   = { 255, 204, 0, 90 },
    FinishColor     = { 255, 255, 255, 110 },
    ArrowColor      = { 255, 204, 0, 200 },
    GpsColor        = 5
}

-- Editor
Config.Editor = {
    Ace          = 'kart.admin',
    DefaultWidth = 12.0,
    MinWidth     = 4.0,
    MaxWidth     = 40.0,
    MaxGrid      = 8
}

-- Rangliste
Config.Leaderboard = { Top = 50, TrackTop = 20, RecentRaces = 10 }

-- Texte
Config.Text = {
    open_menu      = '~INPUT_CONTEXT~ Kartbahn öffnen',
    no_money       = 'Du hast nicht genug Bargeld (%s $).',
    paid           = 'Startgebühr bezahlt: %s $',
    refunded       = 'Startgebühr erstattet: %s $',
    already_in     = 'Du bist bereits in einem Rennen oder einer Lobby.',
    race_running   = 'Auf dieser Strecke läuft bereits ein Rennen.',
    lobby_full     = 'Die Lobby ist voll.',
    lobby_joined   = 'Lobby beigetreten (%s/%s Fahrer).',
    lobby_left     = 'Du hast die Lobby verlassen.',
    lobby_cancel   = 'Rennen abgesagt: zu wenige Fahrer.',
    lobby_new      = 'Kart-Rennen auf %s startet in %s s! Melde dich an der Kartbahn an.',
    track_unknown  = 'Unbekannte Strecke.',
    spawn_failed   = 'Kart konnte nicht gespawnt werden.',
    out_of_kart    = 'Zurück ins Kart! DNF in %s s',
    dnf            = 'DNF – du warst zu lange außerhalb des Karts.',
    tt_end         = 'Zeitfahren beendet.',
    first_finish   = '%s ist im Ziel! Rennen endet in %s s.',
    finished       = 'Ziel! Platz %s',
    record_all     = 'Neuer Streckenrekord auf %s: %s von %s',
    prize          = 'Preisgeld erhalten: %s $',
    no_perm        = 'Keine Berechtigung.',
    ed_start       = 'Editor gestartet: %s',
    ed_cp          = 'Checkpoint %s gesetzt (Breite %s m)',
    ed_grid        = 'Startplatz %s gesetzt',
    ed_grid_max    = 'Maximal %s Startplätze.',
    ed_prop        = 'Prop %s gesetzt',
    ed_bad_model   = 'Ungültiges Modell: %s',
    ed_undo        = 'Rückgängig: %s',
    ed_nothing     = 'Nichts rückgängig zu machen.',
    ed_laps        = 'Rundenzahl: %s',
    ed_barriers    = 'Automatische Begrenzung: %s',
    ed_saved       = 'Strecke "%s" gespeichert.',
    ed_invalid     = 'Strecke ungültig: mind. 3 Checkpoints und 1 Startplatz nötig.',
    ed_cancel      = 'Editor beendet, nichts gespeichert.',
    ed_not_active  = 'Der Editor ist nicht aktiv.',
    ed_help        = '~y~Kart-Editor~s~ CP: %s | Grid: %s | Props: %s | Runden: %s | Begrenzung: %s~n~/kartcp /kartgrid /kartprop /kartundo /kartlaps /kartbarriers /kartsave /kartcancel',
    on             = 'an',
    off            = 'aus',
    usage_save     = 'Benutzung: /kartsave <id> [Anzeigename]'
}
