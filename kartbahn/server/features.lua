-- Zusatz-Features: Meisterschaft, Erfolge, Kart-Design, Wetten, Ghosts, Auszahlungen
Features = {}

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS kart_season (
            season VARCHAR(16) NOT NULL, identifier VARCHAR(64) NOT NULL, name VARCHAR(64) NOT NULL DEFAULT '',
            points INT NOT NULL DEFAULT 0, races INT NOT NULL DEFAULT 0, wins INT NOT NULL DEFAULT 0,
            PRIMARY KEY (season, identifier), INDEX idx_points (season, points)
        )]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS kart_season_winners (
            season VARCHAR(16) NOT NULL PRIMARY KEY, results LONGTEXT NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS kart_payouts (
            id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, identifier VARCHAR(64) NOT NULL,
            amount INT NOT NULL, reason VARCHAR(64) NOT NULL DEFAULT '', INDEX idx_ident (identifier)
        )]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS kart_achievements (
            identifier VARCHAR(64) NOT NULL, code VARCHAR(32) NOT NULL,
            unlocked_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (identifier, code)
        )]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS kart_custom (
            identifier VARCHAR(64) NOT NULL PRIMARY KEY, paint VARCHAR(16) NOT NULL DEFAULT 'yellow',
            number INT NOT NULL DEFAULT 0
        )]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS kart_ghosts (
            identifier VARCHAR(64) NOT NULL, track VARCHAR(64) NOT NULL, name VARCHAR(64) NOT NULL DEFAULT '',
            lap_time INT NOT NULL, data LONGTEXT NOT NULL, PRIMARY KEY (identifier, track), INDEX idx_track_time (track, lap_time)
        )]])
    Features.CheckSeasonRollover()
end)

-- ===================== 10) Meisterschaft =====================
function Features.SeasonId()
    return os.date('%Y-W%V')
end

local function addPayout(identifier, amount, reason)
    MySQL.insert('INSERT INTO kart_payouts (identifier, amount, reason) VALUES (?, ?, ?)', { identifier, amount, reason })
end

-- Saisonwechsel: Sieger der letzten Saison festhalten und Preisgeld vormerken
function Features.CheckSeasonRollover()
    if not Config.Season.Enabled then return end
    local cur = Features.SeasonId()
    local old = MySQL.query.await([[SELECT DISTINCT s.season FROM kart_season s
        LEFT JOIN kart_season_winners w ON w.season = s.season WHERE s.season <> ? AND w.season IS NULL]], { cur }) or {}
    for _, row in ipairs(old) do
        local top = MySQL.query.await('SELECT identifier, name, points FROM kart_season WHERE season = ? ORDER BY points DESC, wins DESC LIMIT 3',
            { row.season }) or {}
        for i, p in ipairs(top) do
            local prize = Bridge.IsFree() and 0 or (Config.Season.Prizes[i] or 0)
            if prize > 0 then addPayout(p.identifier, prize, 'season') end
            if i == 1 then Features.Unlock(p.identifier, 'season_champ', nil) end
        end
        MySQL.insert.await('INSERT INTO kart_season_winners (season, results) VALUES (?, ?)', { row.season, json.encode(top) })
    end
end

function Features.AddSeasonPoints(identifier, name, place, win)
    if not Config.Season.Enabled then return 0 end
    local pts = Config.Season.Points[place] or 0
    MySQL.insert([[INSERT INTO kart_season (season, identifier, name, points, races, wins) VALUES (?, ?, ?, ?, 1, ?)
        ON DUPLICATE KEY UPDATE name = VALUES(name), points = points + VALUES(points), races = races + 1, wins = wins + VALUES(wins)]],
        { Features.SeasonId(), identifier, name, pts, win and 1 or 0 })
    return pts
end

-- Offene Auszahlungen (z. B. Saison-Preisgeld) beim Menü-Öffnen gutschreiben
function Features.PayPending(src, identifier)
    local rows = MySQL.query.await('SELECT id, amount FROM kart_payouts WHERE identifier = ?', { identifier }) or {}
    for _, r in ipairs(rows) do
        local deleted = MySQL.update.await('DELETE FROM kart_payouts WHERE id = ?', { r.id })
        if deleted and deleted > 0 then
            Bridge.AddMoney(src, r.amount)
            Notify(src, KB.T('season_payout', r.amount), 'success')
        end
    end
end

-- ===================== 17) Erfolge =====================
local achNames = {}
for _, a in ipairs(Config.Achievements) do achNames[a.code] = a.name end

function Features.Unlock(identifier, code, src)
    if not achNames[code] then return end
    local ok = MySQL.update.await('INSERT IGNORE INTO kart_achievements (identifier, code) VALUES (?, ?)', { identifier, code }) -- affectedRows
    if ok and ok > 0 and src and GetPlayerPing(src) > 0 then
        Notify(src, KB.T('achievement', achNames[code]), 'record')
        TriggerClientEvent('kartbahn:achievement', src, code)
    end
end

function Features.GetAchievements(identifier)
    local rows = MySQL.query.await('SELECT code FROM kart_achievements WHERE identifier = ?', { identifier }) or {}
    local out = {}
    for _, r in ipairs(rows) do out[r.code] = true end
    return out
end

-- Prüfung nach einem Rennen anhand des Profils
function Features.CheckProfileAchievements(identifier, src)
    local p = MySQL.single.await('SELECT * FROM kart_profiles WHERE identifier = ?', { identifier })
    if not p then return end
    if p.races >= 1 then Features.Unlock(identifier, 'first_race', src) end
    if p.wins >= 1 then Features.Unlock(identifier, 'first_win', src) end
    if p.wins >= 10 then Features.Unlock(identifier, 'wins_10', src) end
    if p.podiums >= 10 then Features.Unlock(identifier, 'podiums_10', src) end
    if p.races >= 50 then Features.Unlock(identifier, 'races_50', src) end
    if p.laps >= 100 then Features.Unlock(identifier, 'laps_100', src) end
    if p.rating >= 1250 then Features.Unlock(identifier, 'tier_gold', src) end
    if p.rating >= 1800 then Features.Unlock(identifier, 'tier_legend', src) end
end

-- ===================== 16) Kart-Design =====================
function Features.GetCustom(identifier)
    local row = MySQL.single.await('SELECT paint, number FROM kart_custom WHERE identifier = ?', { identifier })
    return row or { paint = 'yellow', number = 0 }
end

function Features.PaintColor(id)
    for _, p in ipairs(Config.KartPaints) do if p.id == id then return p.color end end
    return Config.KartPaints[1].color
end

RegisterCallback('saveCustom', function(src, paint, number)
    local ident = Bridge.GetIdentifier(src)
    local prof = DB.GetProfile(ident, Bridge.GetName(src))
    local def
    for _, p in ipairs(Config.KartPaints) do if p.id == paint then def = p end end
    -- Freischaltung über das Höchst-Rating
    if not def or (prof.peak_rating or prof.rating) < def.min then return { ok = false, msg = KB.T('paint_locked') } end
    number = math.max(0, math.min(99, math.floor(tonumber(number) or 0)))
    MySQL.insert.await('INSERT INTO kart_custom (identifier, paint, number) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE paint = VALUES(paint), number = VALUES(number)',
        { ident, paint, number })
    return { ok = true, msg = KB.T('paint_saved') }
end)

-- ===================== 7) Ghosts =====================
function Features.GetGhost(identifier, track, target)
    if not Config.Ghost.Enabled then return nil end
    local row
    if target == 'record' then
        row = MySQL.single.await('SELECT name, lap_time, data FROM kart_ghosts WHERE track = ? ORDER BY lap_time ASC LIMIT 1', { track })
    else
        row = MySQL.single.await('SELECT name, lap_time, data FROM kart_ghosts WHERE identifier = ? AND track = ?', { identifier, track })
    end
    if not row then return nil end
    return { name = row.name, time = row.lap_time, data = json.decode(row.data) }
end

-- Der Server merkt sich die zuletzt gemessene PB; nur dazu passende Ghost-Daten werden angenommen
RegisterNetEvent('kartbahn:ghostSave', function(lapTime, data)
    local src = source
    local pending = Race.TakePendingGhost(src)
    if not pending or pending.time ~= lapTime or type(data) ~= 'table' or #data < 10 or #data > 15000 then return end
    for i = 1, #data do
        if type(data[i]) ~= 'number' then return end
    end
    MySQL.insert([[INSERT INTO kart_ghosts (identifier, track, name, lap_time, data) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE name = VALUES(name), data = IF(VALUES(lap_time) < lap_time, VALUES(data), data),
        lap_time = LEAST(lap_time, VALUES(lap_time))]],
        { pending.identifier, pending.track, pending.name, lapTime, json.encode(data) })
end)

-- ===================== 18) Wetten =====================
-- Bets[sessionId] = { [bettorSrc] = { target = src, amount = n, identifier = ... } }
local Bets = {}

function Features.BetsEnabled()
    return Config.Bets.Enabled and not Bridge.IsFree()
end

RegisterCallback('placeBet', function(src, trackId, target, amount)
    if not Features.BetsEnabled() then return { ok = false, msg = KB.T('bet_invalid') } end
    local s = Race.GetLobbySession(trackId)
    amount = math.floor(tonumber(amount) or 0)
    target = tonumber(target)
    if not s or s.state ~= 'lobby' or not target or not s.racers[target] or s.racers[src]
        or amount < Config.Bets.Min or amount > Config.Bets.Max then
        return { ok = false, msg = KB.T('bet_invalid') }
    end
    Bets[s.id] = Bets[s.id] or {}
    if Bets[s.id][src] then return { ok = false, msg = KB.T('bet_invalid') } end
    if not Bridge.RemoveMoney(src, amount) then return { ok = false, msg = KB.T('no_money', amount) } end
    Bets[s.id][src] = { target = target, amount = amount }
    return { ok = true, msg = KB.T('bet_placed', amount, s.racers[target].name) }
end)

function Features.GetBetInfo(sessionId, src)
    local list = Bets[sessionId]
    if not list then return { pool = 0 } end
    local pool = 0
    for _, b in pairs(list) do pool = pool + b.amount end
    return { pool = pool, mine = list[src] }
end

-- Spieler verlässt die Lobby: Wetten auf ihn erstatten
function Features.RefundBetsOn(sessionId, target)
    local list = Bets[sessionId]
    if not list then return end
    for bettor, b in pairs(list) do
        if b.target == target then
            Bridge.AddMoney(bettor, b.amount)
            Notify(bettor, KB.T('bet_refund', b.amount), 'info')
            list[bettor] = nil
        end
    end
end

function Features.RefundAllBets(sessionId)
    local list = Bets[sessionId]
    Bets[sessionId] = nil
    if not list then return end
    for bettor, b in pairs(list) do
        Bridge.AddMoney(bettor, b.amount)
        Notify(bettor, KB.T('bet_refund', b.amount), 'info')
    end
end

-- Totalisator: Gewinner teilen sich den Topf (abzüglich Hausanteil) im Verhältnis ihrer Einsätze
function Features.SettleBets(sessionId, winnerSrc)
    local list = Bets[sessionId]
    Bets[sessionId] = nil
    if not list then return end
    local pool, winStake = 0, 0
    for _, b in pairs(list) do
        pool = pool + b.amount
        if b.target == winnerSrc then winStake = winStake + b.amount end
    end
    if winStake == 0 then
        for bettor, b in pairs(list) do
            Bridge.AddMoney(bettor, b.amount)
            Notify(bettor, KB.T('bet_refund', b.amount), 'info')
        end
        return
    end
    local payoutPool = math.floor(pool * (1.0 - Config.Bets.HouseCut))
    for bettor, b in pairs(list) do
        if b.target == winnerSrc then
            local win = math.floor(payoutPool * b.amount / winStake)
            Bridge.AddMoney(bettor, win)
            Notify(bettor, KB.T('bet_won', win), 'success')
        end
    end
end

-- ===================== Callbacks für das Menü =====================
RegisterCallback('getSeason', function()
    local rows = MySQL.query.await('SELECT identifier, name, points, races, wins FROM kart_season WHERE season = ? ORDER BY points DESC, wins DESC LIMIT ?',
        { Features.SeasonId(), Config.Season.Top }) or {}
    local last = MySQL.single.await('SELECT season, results FROM kart_season_winners ORDER BY created_at DESC LIMIT 1')
    if last then last.results = json.decode(last.results) end
    return { season = Features.SeasonId(), rows = rows, last = last, prizes = Bridge.IsFree() and {} or Config.Season.Prizes }
end)

RegisterCallback('spectateList', function()
    return Race.GetRunningRaces()
end)
