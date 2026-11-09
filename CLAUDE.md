# Oathbreaker

Zygor-Begleiter für WoW Forever, Zmash gibt ihn über Discord an Freunde weiter. Oberfläche Englisch im echten EllesmereUI-Stil. Abhängigkeiten: ZygorGuidesViewerForever, EllesmereUI. QuestieDB ist optional, das Addon muss ohne laufen.

## Dateien

- `Oathbreaker.lua`: Aufräumliste, Einstellungen, Minimap-Button, Knopf in Zygors Titelleiste, Smart Skip, gemeinsame Helfer
- `Assistant.lua`: Dungeon-Angebot, Hinweise in der Nähe, Lupe im Questlog mit Questroute
- `SideQuests.lua`: bis zu 2 Side Guides, Abstecher-Hinweise, Auswahlfenster
- `GuideCheck.lua`: Empfehlung des nächsten Leveling-Guides beim Überleveln

Einstellungen laufen über das Menü (Rechtsklick aufs Minimap-Icon), keine weiteren Slash-Befehle außer `/oathbreaker`. SavedVariablesPerCharacter: `OathbreakerDB`.

## Verhalten, das bewusst so ist

- Fraktion: Flugpunkt-Hinweise überspringen Knoten der Gegenseite (`node.faction` A/H, B = beide, Neutral sieht alle). Quests der Gegenseite gelten über QuestieDB `requiredRaces` als nicht verfügbar (`ns.isOtherFactionQuest`). Zygor lädt ohnehin nur die Guides der eigenen Fraktion.
- Aufräumen bricht nur Quests ab, die kein kommender Zygor-Guide braucht. Quests aus Dungeon-Guides sind geschützt.
- Lupe: zeigt nur den Guide des aktuellen Questschritts (offene Ziele, sonst Hilfsschritte, sonst Abgabe) und zusätzlich die Abgabe, falls sie in einem anderen Guide liegt. Nur die Abgabe ist beschriftet (`Turn in`). Rechts der Abstand entlang `guide.next`, auf dem Icon `+n`, wenn der nächste Schritt später kommt.
- Guide Check per Knopf (Einstellungen, „Check guide now"): läuft ohne Levelbedingung, ignoriert „Stay here" und „Later", vergleicht den aktuellen Leveling-Guide mit den folgenden und zeigt immer ein Fenster.
- Side Guides: standardmäßig an, ohne markierten Guide passiert nichts. Hinweis bei höchstens 350 yd Entfernung und 200 yd Umweg zum nächsten Zygor-Punkt, ohne Pfeilziel im Umkreis von 120 yd. Luftlinie. Nur Annahmen und Abgaben, die jetzt machbar sind. `Collect` im Dungeon-Angebot legt einen Side Guide an, bei ausgeschaltetem Modus einen Tab.
- Guide Check: nur bei `LEVELING\...(a-b)`, ab b+2. Ziel ist der erste Guide der Kette, für den man nicht zu hoch ist, geprüft werden die 3 Guides ab dort. Mehr als 5 Pflichtquests: kein Fenster, nur eine Chat-Zeile. Ketten mit mehr als 3 Quests pro freigeschalteter Quest entfallen.

## Zygor-Interna

- Globale `ZGV`. Titel werden zur Laufzeit umgeschrieben: `Leveling Guides\X` wird `LEVELING\X`, `Dungeon Guides\X` wird `DUNGEONS\X`. Immer mit den umgeschriebenen Titeln arbeiten, `ZGV:GetGuideByTitle` bereinigt selbst.
- `guide.rawdata` bleibt erhalten und ist die verlässliche Quelle für nicht geladene Guides. `guide.steps` gibt es nur bei geladenen Guides.
- Rohtext: `accept Name##id`, `turnin Name##id`, `|q id/n` (Zielnummer wie `C_QuestLog.GetQuestObjectives`), `|q id` Hilfsschritt, `|instant`, `|only Klasse`, `|only if Bedingung`, `|ding n`.
- `ZGV.Parser.MakeCondition(text, true)`, `ZGV:RaceClassMatch(liste)`, `guide.condition_visible()` für Rassenfilter, `guide:GetStatus()` (INVALID, OUTLEVELED, COMPLETE, SUGGESTED, VALID).
- `ZGV.Quest_Cache` und `ZGV.Quest_Cache_Accept` nach Titel, `pack.ids` ist anfangs ein Komma-String.
- Vorquests: `ZGV.Chains[id]` ist eine Zahl oder `{ "AND"|"OR", id, ... }` (ohne Marker gilt OR). `ZGV.ChainsBreadcrumbs`, `ZGV.ChainsSiblings`, `ZGV.RevChains`.
- `ZGV.QuestDB:IsQuestPossible` prüft Ketten nur bei `db.char.SISstarted` oder `SISdestination`. Smart Skip und `ns.isQuestAvailable` setzen das kurzzeitig.
- Pfeil: `ZGV.Pointer:SetWaypoint(m,x,y,data,arrow)` mit x,y 0 bis 1, `ClearWaypoints("manual")`, danach `ZGV:ShowWaypoints()` zurück zum Guide. Route: `Pointer.DestinationWaypoint`.
- Tabs: `ZGV.Tabs:LoadGuideToTab(guide, step)`, `ZGV:FocusStep(n, true)`. Positionen über `ZGV.HBD`, `ZGV.Parser.ParseMapXYDist(text)`, Flugpunkte `ZGV.LibTaxi.taxipoints`.

## WoW und QuestieDB

- Quest-Details liegen in `QuestMapFrame.QuestsFrame.DetailsFrame`, Auswahl über `C_QuestLog.GetSelectedQuest()`. Die Lupe pollt alle 0,25 s, weil Karten-Addons wie OpenMap eigene Wege öffnen.
- QuestieDB: `LibQuestieDB.RequireContract(3)`, `.Quest.Exists/Get(id, "preQuestSingle"|"preQuestGroup"|"exclusiveTo"|"breadcrumbs"|"requiredLevel")`.

## EllesmereUI-Stil

`EUI.MakeFont`, `MakeBorder`, `AttachSmoothScrollbar(sf, {child, step})`, `COGS_ICON`, Hintergrund 0.077/0.068/0.058 bei 0.97, Close-Icon `eui-close.png`, Toggle-Spur 34x16.

## Tests

`pip install lupa`, dann `python tests\run.py`. Sie laufen mit Lua-Mocks und lesen Zygors echte Horde-Guides. Anderer Zygor-Pfad über Umgebungsvariable `ZYGOR_DIR`. Nichts davon ersetzt einen Test im Spiel.

## Offene Punkte und Entscheidungen

- Noch nie im Spiel geprüft: Optik und Verhalten von Side Guides und Guide Check.
- Offen: fertige Side Guides automatisch freigeben, Unterstützung für das Detailfenster des Ellesmere Quest Trackers, feste „Follow the path“-Wegpunkte optional überspringen.
- Abgelehnt, nicht wieder vorschlagen: Routen bündeln, Hearth-Logik, XP-Balken, Unterwegs-Ideen, Dungeon-Reisekoordinator. Zwei Guides echt zu einer Route zu verschmelzen ist bewusst nicht das Ziel.
