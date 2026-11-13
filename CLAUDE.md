# Oathbreaker

Zygor-Begleiter für WoW Forever, Zmash gibt ihn über Discord an Freunde weiter. Oberfläche Englisch im echten EllesmereUI-Stil. Abhängigkeiten: ZygorGuidesViewerForever, EllesmereUI. QuestieDB ist optional, das Addon muss ohne laufen.

## Dateien

- `Oathbreaker.lua`: Aufräumliste, Einstellungen, Minimap-Button, Knopf in Zygors Titelleiste, Smart Skip, gemeinsame Helfer
- `Assistant.lua`: Dungeon-Angebot, Hinweise in der Nähe, Lupe im Questlog mit Questroute
- `SideQuests.lua`: bis zu 2 Side Guides, Abstecher-Hinweise, Auswahlfenster
- `Update.lua`: Update-Hinweis: Spieler tauschen ihre Version per Addon-Nachricht (Gilde, Gruppe, verstecktes temporäres Chat-Kanal `OathbreakerSync`). Wer eine neuere hört, bekommt ein Fenster mit kopierbarem Link auf die neueste GitHub-Release-Seite, wer eine ältere hört, antwortet per Flüstern. Schalter „Update notice". Im Spiel geprüft, funktioniert.
- `GuideCheck.lua`: Empfehlung des nächsten Leveling-Guides beim Überleveln

Einstellungen laufen über das Menü (Rechtsklick aufs Minimap-Icon), keine weiteren Slash-Befehle außer `/oathbreaker`. SavedVariablesPerCharacter: `OathbreakerDB`.

## Verhalten, das bewusst so ist

- Fraktion: Flugpunkt-Hinweise überspringen Knoten der Gegenseite (`node.faction` A/H, B = beide, Neutral sieht alle). Quests der Gegenseite gelten über QuestieDB `requiredRaces` als nicht verfügbar (`ns.isOtherFactionQuest`). Zygor lädt ohnehin nur die Guides der eigenen Fraktion.
- Aufräumen bricht nur Quests ab, die kein kommender Zygor-Guide braucht. Quests aus Dungeon-Guides sind geschützt.
- Lupe: zeigt nur den Guide des aktuellen Questschritts (offene Ziele, sonst Hilfsschritte, sonst Abgabe) und zusätzlich die Abgabe, falls sie in einem anderen Guide liegt. Nur die Abgabe ist beschriftet (`Turn in`). Rechts der Abstand entlang `guide.next`, auf dem Icon `+n`, wenn der nächste Schritt später kommt.
- Guide Check per Knopf (Einstellungen, „Check guide now"): läuft ohne Levelbedingung, ignoriert „Stay here" und „Later", vergleicht den aktuellen Leveling-Guide mit den folgenden und zeigt immer ein Fenster.
- Low-Level-Markierung: Zygors `ZGV.GoalProto.GetText` ist gehookt, Annahme- und Abgabezeilen grauer Quests (Quest-Stufe aus QuestieDB `questLevel` kleiner als Spielerstufe minus `GetQuestGreenRange()`, Rückfall 8) bekommen `(low level)`. Nicht beim Teilen (nocolor). `turninany`-Zeilen bleiben unmarkiert. Auch in Side-Quest-Hinweisen. Schalter „Mark low-level quests".
- Side-Guide-Hinweis: Radius einstellbar (Standard 450 yd, Schritte 50, 150 bis 1000), Umweg und Umkreis ohne Pfeilziel skalieren mit (4/7 und 12/35). Bei mehreren Quests am selben NPC listet das Fenster jede Quest als eigene Zeile, Klick setzt den Pfeil auf genau diese. Icon ist Blizzards `QuestNormal`/`QuestTurnin`, nicht das durchgestrichene Addon-Icon.
- Side Guides: standardmäßig an, ohne markierten Guide passiert nichts. Hinweis bei höchstens 350 yd Entfernung und 200 yd Umweg zum nächsten Zygor-Punkt, ohne Pfeilziel im Umkreis von 120 yd. Luftlinie. Nur Annahmen und Abgaben, die jetzt machbar sind. `Collect` im Dungeon-Angebot legt einen Side Guide an, bei ausgeschaltetem Modus einen Tab.
- Guide Check: nur bei `LEVELING\...(a-b)`, ab b+2. Ziel ist der erste Guide der Kette, für den man nicht zu hoch ist, geprüft werden die 3 Guides ab dort. Mehr als 5 Pflichtquests: kein Fenster, nur eine Chat-Zeile. Ketten mit mehr als 3 Quests pro freigeschalteter Quest entfallen.

## Zygor-Interna

- Globale `ZGV`. Titel werden zur Laufzeit umgeschrieben: `Leveling Guides\X` wird `LEVELING\X`, `Dungeon Guides\X` wird `DUNGEONS\X`. Immer mit den umgeschriebenen Titeln arbeiten, `ZGV:GetGuideByTitle` bereinigt selbst.
- `guide.rawdata` bleibt erhalten und ist die verlässliche Quelle für nicht geladene Guides. `guide.steps` gibt es nur bei geladenen Guides.
- Rohtext: `accept Name##id`, `turnin Name##id`, `|q id/n` (Zielnummer wie `C_QuestLog.GetQuestObjectives`), `|q id` Hilfsschritt, `|instant`, `|only Klasse`, `|only if Bedingung`, `|ding n`.
- `ZGV.Parser.MakeCondition(text, true)`, `ZGV:RaceClassMatch(liste)`, `guide.condition_visible()` für Rassenfilter, `guide:GetStatus()` (INVALID, OUTLEVELED, COMPLETE, SUGGESTED, VALID).
- `ZGV.Quest_Cache` und `ZGV.Quest_Cache_Accept` nach Titel, `pack.ids` ist anfangs ein Komma-String.
- Vorquests: `ZGV.Chains[id]` ist eine Zahl oder `{ "AND"|"OR", id, ... }` (ohne Marker gilt OR). `ZGV.ChainsBreadcrumbs`, `ZGV.ChainsSiblings`, `ZGV.RevChains`.
- `ZGV.QuestDB:IsQuestPossible` prüft Ketten nur bei `db.char.SISstarted` oder `SISdestination`. Smart Skip und `ns.isQuestAvailable` setzen das kurzzeitig. Auf Forever legt Zygor die Option `beta_use_chains` nie an (nur IsClassic/TBC/WOTLK), das Profilfeld ist nil und `IsQuestPossible` meldet sofort "chains disabled" = möglich. `possibleWithChains` setzt deshalb auch `profile.beta_use_chains` kurzzeitig auf true (seit 2.11.2; vorher griff Smart Skip nur über den Questie-Zweig, Zygor-Ketten wie Elder Crone -> Forsaken Aid wirkten nicht). Im Spiel noch ungeprüft.
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

- Schritt-Skipper (`ns.SkipImpossibleStep`, 2.11.3): Zygor überspringt Schritte mit nur unmöglichen Quest-Zielen nur im `fastforward`, ein Talk-Ziel hält den Schritt zusätzlich offen. Der Skipper hängt an `TryToCompleteStep`, überspringt nur vorwärts und nur Schritte aus talk/goto/gossip/text/accept/turnin mit mindestens einem unmöglichen Quest-Ziel. Im Spiel noch ungeprüft.

- Bewertungsfenster (`skipRating`, 2.11.4, Standard an): setzt `ZGV.db.profile.ratings = false`. Dann ruft Zygors `GuideRating:ShowGuideRating` direkt `NextRatingGuide` auf und wechselt ohne Umfrage zur nächsten Guide. Schalter aus stellt `ratings` auf true zurück. Im Spiel noch ungeprüft.

- Schritt-Skipper seit 2.11.5: kill/collect/click zählen mit, solange mindestens ein Ziel eine Quest-ID hat und alle Quest-Ziele unmöglich sind (Zygor hängt "kill X" oft ohne `|q` an ein `collect ... |q`). Im Spiel noch ungeprüft.

- 2.11.6: Zygor setzt bei `collect` intern `goal.action = "get"` (`cmd` bleibt "collect"); der Skipper kennt deshalb `get`. Im Spiel noch ungeprüft.

- 2.11.7: Ein laufender Side-Quest-Umweg (`detour`) zählt nur Stopps von Guides, die noch in `db.sideGuides` stehen und solange `db.sideQuests` an ist (`stop.guideTitle`). Guide abwählen beendet den Umweg sofort, vorher blieb der Pfeil bis /reload auf der alten Quest. Im Spiel noch ungeprüft.

- 2.12.0: Guide Check listet zusätzlich fertige Quests (im Log, Ziele erfüllt), deren Abgabe in einem übersprungenen Guide liegt (`handIn`, dritter Rückgabewert von `Analyze`, höchstens 8, `MAX_HAND_IN`). Quests, die ein folgender Guide (die 3 ab dem Ziel) abgibt, fehlen bewusst. Die Zeilen stehen nach den Pflichtquests, Klick lädt den Guide und springt zum Abgabeschritt (`stage = "turnin"`); das Fenster bleibt dabei offen (mehrere Abgaben nacheinander), die Zeile wird grau („handed in"), sobald die Quest abgegeben ist (1-s-Takt in `OnUpdate`). Pflichtquest-Zeilen schließen das Fenster wie bisher. Die Liste löst allein kein Fenster aus: es kommt nur im üblichen Ablauf (Überlevelt) oder per Knopf, zählt aber für „Later" mit. Im Spiel noch ungeprüft.

- 2.11.8: Zygor löscht manuelle Pfeile bei jedem `ZGV_STEP_CHANGED` (Pointer.lua:138). Der Side-Quest-Umweg setzt seinen Pfeil deshalb selbst wieder (`ns.SetWaypoint`, höchstens `MAX_REASSERTS` = 5 je Umweg, damit ein bewusst gewählter Zygor-Schritt gewinnt). Eine fehlgeschlagene Positionsmessung beendet den Umweg nicht mehr, erst zwei in Folge. Im Spiel noch ungeprüft.
