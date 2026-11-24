# kartbahn – Kartbahn für FiveM (Standalone / ESX / QBCore)

Rennen mit Lobby, Zeitfahren, Elo-Ranking mit Stufen, Bestzeiten, serverseitiges Anti-Cheat,
automatische Streckenbegrenzung und In-Game-Strecken-Editor. NUI ohne externe Libraries.

## Voraussetzungen
- FiveM-Server mit **OneSync** (Lua 5.4, `fx_version cerulean`)
- [oxmysql](https://github.com/overextended/oxmysql)
- Optional: `es_extended` **oder** `qb-core` (wird automatisch erkannt; ohne Framework ist alles kostenlos)

## Installation
1. Ordner `kartbahn` nach `resources/` kopieren.
2. SQL aus `sql/kartbahn.sql` importieren (die Tabellen werden beim Start zusätzlich automatisch angelegt).
3. In der `server.cfg` (nach oxmysql und ggf. dem Framework):
   ```cfg
   ensure oxmysql
   # ensure es_extended   oder   ensure qb-core
   ensure kartbahn

   # Editor-Rechte
   add_ace group.admin kart.admin allow
   # oder für einen einzelnen Spieler:
   # add_principal identifier.license:DEINE_LICENSE group.admin
   ```
4. Server starten. Der Blip „Kartbahn“ erscheint am LSIA-Vorfeld. Mit **E** am Marker öffnet sich das Menü.

> Der Server muss Schreibrechte auf `data/tracks/` haben, damit der Editor Strecken speichern kann.

## Spielmodi
- **Rennen**: Lobby mit Countdown (Standard 45 s, bei voller Lobby 5 s), 2–8 Fahrer. Wer die Lobby eröffnet,
  wählt die Rundenzahl. Startgebühr wird beim Beitritt abgezogen und bei Absage erstattet.
  Preisgeld für Platz 1–3. Startaufstellung nach Rating – die Besten starten hinten.
  Wer das Kart länger als 10 s verlässt, bekommt ein DNF. Rennende, wenn alle im Ziel sind oder 60 s nach dem ersten Zieleinlauf.
- **Zeitfahren**: allein, unbegrenzt viele Runden; jede gültige Runde zählt für die Bestzeiten.
  Verlassen mit `/kartleave` oder durch Aussteigen (> 10 s).

## Ranking
- Elo für mehrere Fahrer (jeder gegen jeden, K = 32, Start 1000; DNFs teilen sich den letzten Platz)
- Stufen: Bronze, Silber, Gold, Platin, Diamant, Legende (Grenzen und Farben in `config.lua`)
- Rangliste Top 50, Bestzeiten je Strecke, letzte 10 Rennen, Profil mit Statistik
- Neuer Streckenrekord wird allen Spielern angezeigt

## Anti-Cheat (serverseitig)
- Checkpoints nur in der richtigen Reihenfolge
- Positionsprüfung mit `GetEntityCoords` auf dem Server (halbe CP-Breite + Toleranz)
- Mindestabstand zwischen Checkpoints, Mindestrundenzeit (`minLap` pro Strecke)
- Rundenzeiten werden ausschließlich vom Server gemessen
- Bei ungültiger Meldung schickt der Server dem Client den korrekten Stand (`kartbahn:sync`)
- Kart-Kontrolle serverseitig (`GetVehiclePedIsIn`); Runde wird ungültig, wenn das Kart verlassen wurde

## Befehle
| Befehl | Beschreibung |
|---|---|
| `/kartleave` | Rennen/Zeitfahren/Lobby verlassen (im Rennen = DNF) |
| `/kartedit [id]` | Editor starten (mit `id` wird eine vorhandene Strecke geladen) – benötigt `kart.admin` |
| `/kartcp [breite]` | Checkpoint an der eigenen Position (Standard 12 m). **CP 1 = Start/Ziel** |
| `/kartgrid` | Startplatz an Position + Blickrichtung (bzw. Fahrzeug), max. 8. Platz 1 = Pole |
| `/kartprop <model>` | Prop 3 m vor dir setzen |
| `/kartundo` | Letzte Aktion rückgängig |
| `/kartlaps <n>` | Standard-Rundenzahl |
| `/kartbarriers` | Automatische Begrenzung an/aus |
| `/kartsave <id> [Anzeigename]` | Strecke speichern (`data/tracks/<id>.json`) |
| `/kartcancel` | Editor ohne Speichern beenden |

### Strecke bauen
1. `/kartedit meinestrecke`
2. Den Kurs abfahren und alle 20–40 m `/kartcp` setzen. Der erste Checkpoint ist die Start-/Ziellinie.
3. Startplätze **hinter** CP 1 in Fahrtrichtung mit `/kartgrid` setzen (Pole zuerst).
4. `/kartsave meinestrecke Meine Strecke`

Die Vorschau zeigt Checkpoints (gelb, Start weiß), Ideallinie, Begrenzungskanten (rot), Startplätze (blau)
und die echten Absperrungen.

## Streckenformat (`data/tracks/<id>.json`)
```json
{
  "id": "lsia", "name": "LSIA Vorfeld", "laps": 3, "minLap": 25000, "autoBarriers": true,
  "checkpoints": [ { "x": 0.0, "y": 0.0, "z": 0.0, "w": 14.0 } ],
  "grid":        [ { "x": 0.0, "y": 0.0, "z": 0.0, "h": 0.0 } ],
  "props":       [ { "model": "prop_flag_ls", "x": 0.0, "y": 0.0, "z": 0.0, "h": 0.0 } ]
}
```
Alle geladenen Strecken stehen in `data/tracks/_index.json` (pflegt der Editor automatisch).
Die Standardstrecke `lsia` ist ein ca. 620 m langer, geschlossener Rundkurs mit 25 Checkpoints und 8 Startplätzen
auf dem LSIA-Vorfeld. Falls auf deinem Server dort Mapping steht, einfach mit dem Editor neu aufnehmen.

## Performance & Aufräumen
- Leerlauf: Menü-Schleife 1×/s, Prop-Streaming alle 2 s → ~0.00 ms resmon
- Absperrungen/Pylonen/Props werden **lokal** und nur in der Nähe (350 m) gespawnt
- Karts werden serverseitig erstellt und bei Rennende, Spieler-Disconnect und Resource-Stop gelöscht;
  lokale Props, Blips und Editor-Objekte werden beim Resource-Stop entfernt

## Konfiguration
Alles in `config.lua`: Framework, Menüpunkte, Kart-Modelle, Lobby-Zeiten, Spielerzahl, Runden, Startgebühr,
Preisgelder, DNF-Zeit, Elo (K, Startwert), Stufen, Anti-Cheat-Toleranzen, Absperrungs-Modelle/Abstände,
Editor-Grenzen, Ranglisten-Größen und alle Texte.
