# Roger — Design-Tokens

Richtung: **Feldfunkgerät**. Tragbares Funkgerät aus dem Kalten Krieg — PRC-77,
AN/PRC-152, Clansman. Robust, zweckgebaut, ohne Zierde. Die Oberfläche soll wie
Ausrüstung wirken, nicht wie ein Thema, das über eine Oberfläche gelegt wurde.

Die verbindliche Fassung ist `Sources/Roger/Design/Design.swift`. Diese Datei
ist die lesbare Ansicht derselben Werte. **Kein Wert steht in einer Ansicht** —
wer einen braucht, den es nicht gibt, legt ihn im Namensraum `Design` an.

Wo die Regel endet: Farbe, Schrift, Abstand, Radius, Kante, Schatten, Bewegung
und Deckkraft kommen ausnahmslos aus den Tokens. Die Maße *eines bestimmten
Fensters* — 560 × 740 für die Einstellungen, 780 × 540 als Mindestmaß des
Hauptfensters, 82 pt Einzug für die drei Systemknöpfe — stehen bei diesem
Fenster. Sie beschreiben kein wiederverwendbares Verhältnis, und als Token
hießen sie `settingsWidth` und wären nur ein Umweg.

**Das Einrichtungsfenster ist ganz ausgenommen.** Es benutzt Systemschriften,
`.secondary`, `Divider` und Standard-Knöpfe — absichtlich. Es ist das erste
Fenster, das jemand sieht, und es bittet um zwei Systemfreigaben. Genau dieser
Dialog soll aussehen wie ein Dialog von macOS; das wirkt vertrauenswürdiger als
ein eigenes Gehäuse um eine Berechtigungsanfrage. Rogers Optik beginnt danach.

## Farben — `Design.Palette`

| Token | Hex | Verwendung |
|---|---|---|
| `background` | `#2A2E22` | Fensterhintergrund — dunkles Oliv |
| `surface` | `#1E2218` | Versenkte Flächen (Meter, Transkript, Listen) |
| `surfaceBorder` | `#3A4030` | Blechkante, Rahmen, Trennlinien |
| `titlebar` | `#232820` | Titelleiste |
| `textPrimary` | `#C8D4A8` | Fließtext — blasses Salbeigrün |
| `textSecondary` | `#5A6A48` | Beschriftungen, Bildunterschriften |
| `textDim` | `#6A7A58` | Drittrangiges, Deaktiviertes |
| `accentRed` | `#C04030` | Sendeanzeige, zerstörende Aktionen |
| `accentRedDark` | `#802820` | Knopfschatten unter Rot |
| `accentAmber` | `#D4A030` | Statusanzeige, Zähler, Cursor |
| `levelGreen` | `#6A8A30` | Pegelbalken 1–7 |
| `levelGreenBright` | `#8AA040` | Pegelbalken 8–10 |
| `levelAmber` | `#D4A030` | Pegelbalken 11–12 |
| `levelRed` | `#C04030` | Pegelbalken 13–14 |
| `controlBackground` | `#3A4030` | Sekundärer Knopf |
| `controlText` | `#8A9A78` | Sekundärer Knopf, Text |
| `controlBorder` | `#4A5A40` | Sekundärer Knopf, Kante |

Ein einziger festgelegter Satz, kein Hell/Dunkel-Umschalter. Das Hauptfenster
erzwingt deshalb `NSAppearance(named: .darkAqua)`.

## Schrift — `Design.Typography`

| Rolle | Familie | Größe | Laufweite | Schreibung |
|---|---|---|---|---|
| `windowTitle` | IBM Plex Mono | 11 | 0.10 em | Großbuchstaben |
| `label` | Share Tech Mono | 9 | 0.15 em | Großbuchstaben |
| `status` | Share Tech Mono | 12 | 0.12 em | Großbuchstaben |
| `body` | IBM Plex Mono | 13 | 0 | wie geschrieben |
| `button` | Share Tech Mono | 11 | 0.10 em | Großbuchstaben |
| `timestamp` | IBM Plex Mono | 10 | 0.06 em | wie geschrieben |
| `readout` | Share Tech Mono | 22 | 0.10 em | Großbuchstaben |
| `field` | IBM Plex Mono | 12 | 0 | wie geschrieben |

Nur Festbreitenschriften. Share Tech Mono und IBM Plex Mono liegen nicht auf
jedem Mac; `Design.Families` sucht sie der Reihe nach und fällt am Ende auf die
Festbreitenschrift des Systems zurück, statt in eine Proportionalschrift zu
kippen. Sind die Schriften installiert, greift Roger sie ohne Zutun.

## Abstände — `Design.Space`

| Token | Wert | Verwendung |
|---|---|---|
| `xs` | 4 | Lücken innerhalb einer Zeile |
| `sm` | 8 | Zwischen zusammengehörenden Elementen |
| `md` | 12 | Zwischen Bedienelementen, Listeneinträgen |
| `lg` | 16 | Innenabstand einer engen Fläche |
| `xl` | 20 | Innenabstand einer normalen Fläche |
| `xxl` | 24 | Innenabstand eines Abschnitts |
| `buttonVertical` | 10 | Knopfhöhe, senkrecht |
| `buttonVerticalCompact` | 6 | Knopfhöhe in der engen Variante |

## Ecken — `Design.Radius`

| Token | Wert | Verwendung |
|---|---|---|
| `sm` | 4 | Knöpfe, kleine Bedienelemente |
| `md` | 8 | Flächen, Karten, Eingabefelder |
| `bar` | 1 | Pegelbalken |

Keine Pillenformen. Nichts vollständig Rundes außer den Anzeigelämpchen.

## Kanten und Flächen — `Design.Border`

| Token | Wert |
|---|---|
| `hairline` | 1 |

Versenkte Fläche: `hairline` in `surfaceBorder` auf `surface`. Keine doppelten
Rahmen, kein Relief, keine Verläufe.

Eine eigene Fensterkante gibt es nicht: Sie gehört macOS. Ein selbstgezeichneter
Rahmen bricht an der gerundeten Systemecke ab und sieht dort aus wie ein Fehler.

## Schatten — `Design.Elevation`

| Token | Wert | Verwendung |
|---|---|---|
| `buttonDepth` | 2 | Höhe des harten Knopfschattens |
| `bubbleRadius` / `bubbleOffset` / `bubbleOpacity` | 14 / 5 / 0.5 | Der Schatten unter der Blase |

Schatten sind Tiefenhinweise an drückbaren Dingen, nie Zierde. Kein innerer
Schein. Fenster bekommen ihren Schatten vom System; der Blasenschatten ist der
einzige, den Roger selbst wirft — sie schwebt über fremdem Inhalt und braucht
eine Kante zu ihm.

## Bewegung — `Design.Motion`

| Token | Wert | Verwendung |
|---|---|---|
| `meter` | `easeInOut` 0.09 s | Pegel folgt dem Ton |
| `indicate` | `easeInOut` 0.15 s | Knöpfe, Lämpchen, Fokus |
| `blinkPeriod` | 1.5 s | Sendeanzeige |

Keine Federn, kein Nachwippen, keine Auftrittsanimationen. Ausrüstung animiert
nicht, sie zeigt an. Die einzige Ausnahme ist die Blase über fremden Fenstern —
siehe `Design.Bubble` weiter unten.

## Hervorhebung — `Design.Emphasis`

| Token | Wert | Verwendung |
|---|---|---|
| `disabled` | 0.4 | Ein Bedienelement, das gerade nichts zu tun hat |
| `highlight` | 0.5 | Unterlegte Fläche der Zeile, an der gearbeitet wird |

Ausrüstung nimmt ihre Knöpfe nicht weg, wenn sie nichts tun — sie sind nur nicht
dran. Deshalb 0.4 und nicht 0.15.

## Sinnbilder — `Design.Icon`

| Token | Wert | Verwendung |
|---|---|---|
| `hint` | 9 | Warndreieck an einem Eintrag |
| `field` | 10 | Lupe im Suchfeld, Häkchenkästchen (+2) |

SF Symbols kommen als Schrift ins Layout, nicht als Bild — ihre Größe gehört
deshalb hierher und nicht zu den Abständen.

## Pegelmesser — `Design.Meter`

14 senkrechte Balken, 6 breit, 3 Abstand, Radius 1, höchstens 48 hoch,
mindestens 3 — ein völlig leeres Raster liest sich als abgestürzt, nicht als
still. Farbe nach Position über `Design.Meter.color(at:)`. Sitzt in einer
versenkten Fläche mit der Beschriftung `PEGEL`.

Die Beschriftungen sind deutsch (`PEGEL`, `STATUS`, `VERLAUF`), nicht englisch
wie auf echtem Gerät: Die ganze Oberfläche ist deutsch, und ein englisches
Schild darin wäre Kostüm statt Beschriftung.

Die Analyse rechnet feiner (siehe `Design.Spectrum`); `LevelMeter` faltet ihre
Bänder auf diese vierzehn Balken.

## Die Blase — `Design.Bubble`

Die Anzeige, die während des Diktats über allem schwebt. **Die ausgewiesene
Ausnahme von zwei Regeln dieses Systems**, und beide aus demselben Grund: Sie
sitzt über fremden Fenstern, nicht über Rogers Frontplatte.

| Regel | Warum hier anders |
|---|---|
| Keine Federn, keine Auftritte | Sie erscheint ungefragt für zwei Sekunden. Etwas, das so auftritt, muss als Blase lesbar sein und nicht als Fehler im Bildaufbau. |
| Palette | Schwarz und Weiß statt Oliv, weil der Untergrund beliebig ist. |

| Token | Wert | Verwendung |
|---|---|---|
| `fill` | `#0D0D0D` deckend | Kapselfüllung — nicht durchscheinend |
| `rim` | Weiß 13 % | Haarlinie als Kante |
| `bar` | Weiß | Ausschlagstriche |
| `scale` | 0.92 | Gesamtmaßstab — ein Regler für alle Maße darunter |
| `barWidth` / `barSpacing` | 2.5 / 2 × `scale` | Striche mit runden Enden |
| `barMinHeight` / `barMaxHeight` | 3 / 20 × `scale` | Aus der Mitte nach beiden Seiten |
| `horizontalPadding` / `verticalPadding` | 16 / 11 × `scale` | Innenabstand der Kapsel |
| `sweepOpacity` | 0.75 | Die laufende Welle beim Transkribieren — blasser als ein echter Ausschlag |
| `bars` | `easeOut` 0.07 s | Striche folgen dem Ton — hier keine Feder, sonst schmiert der Ausschlag |
| `openWidth` / `openHeight` | Feder 0.30/0.50 · 0.42/0.62 | Breite läuft voraus und schwingt über |
| `closeWidth` / `closeHeight` | Feder 0.26/0.85 · 0.18/0.90 | Höhe fällt zuerst, die Blase legt sich flach |
| `collapsedWidthScale` / `collapsedHeightScale` | 0.22 / 0.28 | Nicht null — sonst wirkt es wie ein Absturz |
| `fadeIn` / `fadeOut` | `easeOut` 0.12 / 0.20 s | Deckkraft — da sein, bevor sie fertig aufgeploppt ist |
| `collapseDuration` | 420 ms | So lange bleibt das Panel im Fenstersystem |

Zwei Federn statt einer für beide Achsen: Genau daraus entsteht das Quetschen,
das die Bewegung wie einen Tropfen aussehen lässt. Eine Feder für beide Achsen
wäre nur ein Größerwerden.

## Frequenzanalyse — `Design.Spectrum`

`bandCount = 20`. Eine Zahl für alle: Die Analyse läuft einmal pro Audiopuffer,
zwei Anzeigen mit eigenem Raster hieße, sie zweimal zu rechnen. Die Auflösung
richtet sich nach der feineren Anzeige — der Blase —, und `LevelMeter` faltet
sie auf seine vierzehn Balken, mit dem Spitzenwert je Gruppe statt dem
Mittelwert: Ein Pegelmesser soll zeigen, wie laut es *wird*.

## Anzeigelämpchen — `Design.Indicator`

8 Durchmesser, Schein mit Radius 4. Rot blinkend beim Senden, bernsteinfarben
stehend bei aktivem Nichtsenden, dunkel im Ruhezustand.

## Bausteine

| Baustein | Datei |
|---|---|
| `EquipmentLabel`, `Readout` | `Design/Components/EquipmentLabel.swift` |
| `RecessedPanel`, `FieldDivider` | `Design/Components/RecessedPanel.swift` |
| `FieldButtonStyle`, `GhostButtonStyle` | `Design/Components/FieldButton.swift` |
| `LevelMeter` | `Design/Components/LevelMeter.swift` |
| `SegmentedSelector` | `Design/Components/SegmentedSelector.swift` |
| `IndicatorLight` | `Design/Components/IndicatorLight.swift` |
| `FieldTextField`, `FieldCheckbox` | `Design/Components/FieldTextField.swift` |
