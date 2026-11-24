-- Datenbank-Zugriff über oxmysql
DB = {}

-- Tabellen automatisch anlegen (identisch zu sql/kartbahn.sql)
MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS kart_profiles (
            identifier VARCHAR(64) NOT NULL PRIMARY KEY,
            name VARCHAR(64) NOT NULL DEFAULT '',
            rating INT NOT NULL DEFAULT 1000,
            peak_rating INT NOT NULL DEFAULT 1000,
            races INT NOT NULL DEFAULT 0,
            wins INT NOT NULL DEFAULT 0,
            podiums INT NOT NULL DEFAULT 0,
            dnfs INT NOT NULL DEFAULT 0,
            laps INT NOT NULL DEFAULT 0,
            prize_money INT NOT NULL DEFAULT 0,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_rating (rating)
        )]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS kart_laps (
            id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            identifier VARCHAR(64) NOT NULL,
            name VARCHAR(64) NOT NULL DEFAULT '',
            track VARCHAR(64) NOT NULL,
            lap_time INT NOT NULL,
            mode VARCHAR(8) NOT NULL DEFAULT 'tt',
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_track_time (track, lap_time),
            INDEX idx_ident_track (identifier, track)
        )]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS kart_races (
            id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
            track VARCHAR(64) NOT NULL,
            laps INT NOT NULL DEFAULT 0,
            results LONGTEXT NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )]])
    if Records then Records.LoadAll() end
end)

function DB.GetProfile(identifier, name)
    local row = MySQL.single.await('SELECT * FROM kart_profiles WHERE identifier = ?', { identifier })
    if not row then
        MySQL.insert.await('INSERT INTO kart_profiles (identifier, name, rating, peak_rating) VALUES (?, ?, ?, ?)',
            { identifier, name, Config.Elo.Start, Config.Elo.Start })
        row = { identifier = identifier, name = name, rating = Config.Elo.Start, peak_rating = Config.Elo.Start,
                races = 0, wins = 0, podiums = 0, dnfs = 0, laps = 0, prize_money = 0 }
    elseif name and row.name ~= name then
        MySQL.update('UPDATE kart_profiles SET name = ? WHERE identifier = ?', { name, identifier })
        row.name = name
    end
    return row
end

-- Statistik nach einem Rennen
function DB.UpdateAfterRace(identifier, d)
    MySQL.update.await([[
        UPDATE kart_profiles SET rating = ?, peak_rating = GREATEST(peak_rating, ?), races = races + 1,
            wins = wins + ?, podiums = podiums + ?, dnfs = dnfs + ?, prize_money = prize_money + ?
        WHERE identifier = ?]],
        { d.rating, d.rating, d.win and 1 or 0, d.podium and 1 or 0, d.dnf and 1 or 0, d.prize or 0, identifier })
end

function DB.InsertLap(identifier, name, track, ms, mode)
    MySQL.insert('INSERT INTO kart_laps (identifier, name, track, lap_time, mode) VALUES (?, ?, ?, ?, ?)',
        { identifier, name, track, ms, mode })
    MySQL.update('UPDATE kart_profiles SET laps = laps + 1 WHERE identifier = ?', { identifier })
end

function DB.GetPB(identifier, track)
    return MySQL.scalar.await('SELECT MIN(lap_time) FROM kart_laps WHERE identifier = ? AND track = ?',
        { identifier, track })
end

function DB.GetAllPBs(identifier)
    local rows = MySQL.query.await('SELECT track, MIN(lap_time) AS best FROM kart_laps WHERE identifier = ? GROUP BY track',
        { identifier }) or {}
    local out = {}
    for _, r in ipairs(rows) do out[r.track] = r.best end
    return out
end

function DB.GetTrackRecord(track)
    return MySQL.single.await('SELECT identifier, name, lap_time FROM kart_laps WHERE track = ? ORDER BY lap_time ASC, id ASC LIMIT 1',
        { track })
end

function DB.GetLeaderboard(limit)
    return MySQL.query.await([[SELECT identifier, name, rating, peak_rating, races, wins, podiums, dnfs
        FROM kart_profiles WHERE races > 0 ORDER BY rating DESC LIMIT ?]], { limit }) or {}
end

function DB.GetTrackTimes(track, limit)
    return MySQL.query.await([[
        SELECT l.identifier, MAX(l.name) AS name, MIN(l.lap_time) AS best, COUNT(*) AS laps
        FROM kart_laps l WHERE l.track = ? GROUP BY l.identifier ORDER BY best ASC LIMIT ?]], { track, limit }) or {}
end

function DB.GetRecentRaces(limit)
    local rows = MySQL.query.await('SELECT id, track, laps, results, UNIX_TIMESTAMP(created_at) AS ts FROM kart_races ORDER BY id DESC LIMIT ?',
        { limit }) or {}
    for _, r in ipairs(rows) do r.results = json.decode(r.results) or {} end
    return rows
end

function DB.InsertRace(track, laps, results)
    MySQL.insert('INSERT INTO kart_races (track, laps, results) VALUES (?, ?, ?)', { track, laps, json.encode(results) })
end
