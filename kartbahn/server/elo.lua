-- Elo für mehrere Fahrer: jeder gegen jeden, Ergebnis gemittelt über (n-1) Gegner
Elo = {}

-- entries: { { key = ..., rating = number, place = number } }  (gleicher Platz = Unentschieden, z. B. DNFs)
function Elo.Calculate(entries)
    local n, K = #entries, Config.Elo.K
    local deltas = {}
    if n < 2 then
        for _, e in ipairs(entries) do deltas[e.key] = 0 end
        return deltas
    end
    for i, a in ipairs(entries) do
        local sum = 0.0
        for j, b in ipairs(entries) do
            if i ~= j then
                local expected = 1.0 / (1.0 + 10 ^ ((b.rating - a.rating) / 400.0))
                local score = (a.place < b.place) and 1.0 or ((a.place == b.place) and 0.5 or 0.0)
                sum = sum + (score - expected)
            end
        end
        local d = K * sum / (n - 1)
        deltas[a.key] = d >= 0 and math.floor(d + 0.5) or -math.floor(-d + 0.5)
    end
    return deltas
end
