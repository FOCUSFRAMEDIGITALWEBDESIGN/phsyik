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
Config.KartModels = { 'veto2' }   -- ein Modell = gleiche Bedingungen für alle
Config.KartPlate = 'KART'

-- Eigenes Kart "KB-1": diese Werte setzt das Skript beim Spawn direkt auf jedes Kart.
-- Damit gilt die Physik auch dann, wenn die handling.meta nicht greift.
Config.Kart = {
    Enabled   = true,
    Name      = 'KB-1 Rennkart',
    MaxSpeed  = 95.0,          -- km/h Höchstgeschwindigkeit (für alle gleich = faire Rennen)
    Handling  = {              -- CHandlingData-Werte (float)
        fMass                     = 230.0,
        fInitialDragCoeff         = 6.0,
        fInitialDriveForce        = 0.32,
        fInitialDriveMaxFlatVel   = 118.0,
        fDriveInertia             = 1.4,
        fBrakeForce               = 0.9,
        fBrakeBiasFront           = 0.4,
        fSteeringLock             = 38.0,
        fTractionCurveMax         = 2.65,
        fTractionCurveMin         = 2.35,
        fTractionCurveLateral     = 20.0,
        fLowSpeedTractionLossMult = 0.25,
        fTractionLossMult         = 0.6,
        fSuspensionForce          = 3.6,
        fAntiRollBarForce         = 1.6,
        fCollisionDamageMult      = 0.2,
        fDeformationDamageMult    = 0.1
    },
    -- Optik: Farben (GTA-Farbindex), Startnummern-Kennzeichen
    Colors    = { primary = 89, secondary = 0, pearl = 89, wheels = 0 }, -- Racing-Gelb / Schwarz
    NumberPlates = true         -- Kennzeichen zeigt "KB-<Startplatz>"
}

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
    MaxObjects      = 800,   -- Bande (~480) + Pylonen + Deko passen hinein
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

-- =====================================================================
-- FEATURES
-- =====================================================================

-- Renn-Modi (wählt, wer die Lobby eröffnet)
-- ranked = zählt für Elo/Meisterschaft, boost = Boost-Knopf + Drift-Boost, items = Item-Boxen
Config.Modes = {
    { id = 'ranked', label = 'Ranked',        ranked = true,  boost = false, items = false },
    { id = 'fun',    label = 'Fun-Rennen',    ranked = false, boost = true,  items = true  },
    { id = 'elim',   label = 'Ausscheidung',  ranked = false, boost = false, items = false },
    { id = 'team',   label = 'Teamrennen',    ranked = false, boost = false, items = false }
}
Config.TimeTrialMode = { boost = false, items = false }  -- Zeitfahren: ohne Boost (faire Bestzeiten)

-- 1) Boost-Knopf
Config.Boost = {
    Key          = 21,      -- INPUT_SPRINT (Shift / A)
    Duration     = 2500,    -- ms pro Boost
    Cost         = 50,      -- Ladung pro Boost (max. 100)
    RechargeRate = 6,       -- Ladung pro Sekunde
    StartCharge  = 50,
    Power        = 2.2,     -- Motorleistungs-Multiplikator
    ExtraSpeed   = 20.0     -- km/h über dem Tempolimit während des Boosts
}

-- 2) Windschatten
Config.Slipstream = { Enabled = true, MinDist = 2.5, MaxDist = 14.0, MaxAngle = 12.0, Power = 1.25, BoostCharge = 4 }

-- 3) Perfekter Start
Config.PerfectStart = { Enabled = true, Window = 300, BoostTime = 1500, Power = 2.0, FalseStartPenalty = 1200 }

-- 4) Drift-Boost (nur in Modi mit boost = true)
Config.DriftBoost = { Enabled = true, MinAngle = 15.0, MinSpeed = 25.0, MinTime = 1.2, MaxBoost = 1500, Power = 1.8 }

-- 5) Boost-Felder (pro Strecke im Editor mit /kartboost)
Config.BoostPads = { Enabled = true, Radius = 3.0, Duration = 1200, Power = 2.0, Cooldown = 2000 }

-- 6) Item-Modus
Config.Items = {
    Key         = 47,       -- INPUT_DETONATE (G) Item benutzen
    Radius      = 3.0,
    Respawn     = 5000,     -- ms bis eine Box für denselben Fahrer wieder verfügbar ist
    AutoEvery   = 5,        -- ohne eigene Boxen: automatisch an jedem 5. Checkpoint
    OilTime     = 20000,    -- Lebensdauer einer Ölpfütze
    OilRadius   = 2.5,
    SpinTime    = 1500,
    ShieldTime  = 8000,
    -- Gewichtung nach Platz (vorne eher Öl, hinten eher Boost)
    Pool = {
        front = { boost = 2, oil = 5, shield = 3 },
        back  = { boost = 6, oil = 2, shield = 2 }
    },
    Labels = { boost = 'Turbo', oil = 'Ölpfütze', shield = 'Schutzschild' }
}

-- 7) Ghost im Zeitfahren
Config.Ghost = { Enabled = true, Interval = 100, Alpha = 120, DefaultTarget = 'pb' } -- 'pb' oder 'record'

-- 8) Ausscheidungsrennen: Runden = Fahrer - 1, nach jeder Runde fliegt der Letzte raus
Config.Elimination = { FirstElimAfterLap = 1 }

-- 9) Teamrennen
Config.Teams = {
    Points = { 10, 8, 6, 5, 4, 3, 2, 1 },
    List = {
        { name = 'Team Rot',  color = 27, hex = '#ef4444' },
        { name = 'Team Blau', color = 64, hex = '#3b82f6' }
    },
    WinBonus = 500           -- Bonus-Bargeld für jedes Mitglied des Siegerteams
}

-- 10) Wöchentliche Meisterschaft (nur Ranked-Rennen)
Config.Season = {
    Enabled = true,
    Points  = { 25, 18, 15, 12, 10, 8, 6, 4 },
    Prizes  = { 25000, 15000, 7500 },   -- Saison-Preisgeld Platz 1-3 (wird beim nächsten Menü-Öffnen ausgezahlt)
    Top     = 20
}

-- 11) Sektorzeiten
Config.Sectors = { Count = 3 }

-- 12) Minimap im HUD
Config.Minimap = { Enabled = true }

-- 13) Zuschauer-Modus
Config.Spectate = { Enabled = true, Key_Next = 175, Key_Prev = 174, Key_Exit = 177 } -- Pfeil rechts/links, Backspace

-- 14) Siegerpodest
Config.Podium = { Enabled = true, Duration = 9000, Offset = 22.0 } -- Abstand seitlich von Start/Ziel, falls die Strecke kein "podium" hat

-- 15) Startampel
Config.StartLights = { Enabled = true, Height = 5.0, Spacing = 1.4 }

-- 16) Kart-Design (min = Mindest-Rating zum Freischalten)
Config.KartPaints = {
    { id = 'yellow', name = 'Racing-Gelb',  color = 89,  min = 0 },
    { id = 'black',  name = 'Schwarz',      color = 12,  min = 0 },
    { id = 'white',  name = 'Weiß',         color = 111, min = 0 },
    { id = 'red',    name = 'Rot',          color = 27,  min = 0 },
    { id = 'blue',   name = 'Blau',         color = 64,  min = 0 },
    { id = 'green',  name = 'Grün',         color = 53,  min = 0 },
    { id = 'silver', name = 'Silber',       color = 4,   min = 1100 },
    { id = 'gold',   name = 'Gold',         color = 158, min = 1250 },
    { id = 'teal',   name = 'Platin-Türkis',color = 74,  min = 1400 },
    { id = 'chrome', name = 'Diamant-Chrom',color = 120, min = 1600 },
    { id = 'purple', name = 'Legenden-Lila',color = 145, min = 1800 }
}

-- 17) Erfolge
Config.Achievements = {
    { code = 'first_race',   name = 'Erste Runde',     desc = 'Erstes Rennen beendet' },
    { code = 'first_win',    name = 'Sieger',          desc = 'Erstes Rennen gewonnen' },
    { code = 'wins_10',      name = 'Seriensieger',    desc = '10 Rennen gewonnen' },
    { code = 'podiums_10',   name = 'Stammgast',       desc = '10 Podestplätze' },
    { code = 'races_50',     name = 'Dauerbrenner',    desc = '50 Rennen gefahren' },
    { code = 'laps_100',     name = 'Kilometerfresser',desc = '100 gültige Runden' },
    { code = 'record',       name = 'Rekordhalter',    desc = 'Einen Streckenrekord aufgestellt' },
    { code = 'tier_gold',    name = 'Goldjunge',       desc = 'Stufe Gold erreicht' },
    { code = 'tier_legend',  name = 'Legende',         desc = 'Stufe Legende erreicht' },
    { code = 'elim_win',     name = 'Letzter Überlebender', desc = 'Ein Ausscheidungsrennen gewonnen' },
    { code = 'team_win',     name = 'Teamplayer',      desc = 'Mit dem Team gewonnen' },
    { code = 'season_champ', name = 'Meister',         desc = 'Eine Wochenmeisterschaft gewonnen' }
}

-- 18) Wetten (nur mit ESX/QBCore)
Config.Bets = { Enabled = true, Min = 100, Max = 10000, HouseCut = 0.05 }

-- Texte der Features
Config.Text.boost_empty    = 'Boost leer!'
Config.Text.perfect_start  = 'PERFEKTER START!'
Config.Text.false_start    = 'Frühstart!'
Config.Text.slipstream     = 'Windschatten'
Config.Text.drift_boost    = 'Drift-Boost!'
Config.Text.item_got       = 'Item: %s (G zum Benutzen)'
Config.Text.item_oil_hit   = 'Ausgerutscht!'
Config.Text.item_shield    = 'Schild aktiv'
Config.Text.eliminated     = '%s ist ausgeschieden!'
Config.Text.you_eliminated = 'Du bist ausgeschieden! Platz %s'
Config.Text.team_assigned  = 'Du fährst für %s'
Config.Text.team_won       = '%s gewinnt mit %s Punkten!'
Config.Text.season_payout  = 'Meisterschafts-Preisgeld erhalten: %s $'
Config.Text.achievement    = 'Erfolg freigeschaltet: %s'
Config.Text.paint_locked   = 'Diese Lackierung ist noch gesperrt.'
Config.Text.paint_saved    = 'Kart-Design gespeichert.'
Config.Text.bet_placed     = 'Wette platziert: %s $ auf %s'
Config.Text.bet_invalid    = 'Wette nicht möglich.'
Config.Text.bet_won        = 'Wette gewonnen: %s $'
Config.Text.bet_refund     = 'Wetteinsatz erstattet: %s $'
Config.Text.spectate_help  = '~INPUT_CELLPHONE_RIGHT~ / ~INPUT_CELLPHONE_LEFT~ Fahrer wechseln  ~INPUT_CELLPHONE_CANCEL~ Beenden'
Config.Text.spectate_none  = 'Kein laufendes Rennen.'
Config.Text.ed_boost       = 'Boost-Feld %s gesetzt'
Config.Text.ed_item        = 'Item-Box %s gesetzt'
Config.Text.ed_podium      = 'Siegerpodest gesetzt'
