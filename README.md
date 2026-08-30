# Roger

Push-to-Talk-Diktat für macOS. Taste halten, sprechen, loslassen — der Text
landet in der App, die gerade den Fokus hat. Die Erkennung läuft vollständig auf
dem Gerät: kein Konto, kein Netz, keine API-Kosten.

Eine gewöhnliche Mac-App mit Dock-Symbol, Hauptmenü und Einstellungsfenster auf
⌘, — auf Wunsch aber auch ein reines Menüleistenwerkzeug, das im Hintergrund
liegt.

## Was drin ist

- **Push-to-Talk** auf einer frei wählbaren Taste, systemweit
- **Wörterbuch** für Namen und Fachbegriffe, das die Erkennung vorher schubst
  und den Text hinterher korrigiert
- **Verlauf** mit Suche, Kopieren und der Angabe, welche Korrektur gegriffen hat
- **Pegelanzeige** während der Aufnahme, im Fenster und als Blase über allem
- **Wortzähler** über alle Diktate hinweg

## Voraussetzungen

| | |
|---|---|
| macOS | 26 oder neuer |
| Mac | Apple Silicon |
| Xcode Command Line Tools | für `swift` — `xcode-select --install` |

Kein Apple-Entwicklerkonto nötig, um Roger selbst zu benutzen. Für die
Weitergabe an andere schon; siehe [Weitergeben](#weitergeben).

## Einrichten, Schritt für Schritt

### 1. Holen und bauen

```bash
git clone https://github.com/<dein-account>/roger.git
cd roger
./scripts/bundle.sh
```

Das Skript baut Roger und legt `~/Applications/Roger.app` an. Der erste Lauf
dauert ein paar Minuten, danach nur noch Sekunden.

`swift build` allein genügt nicht: macOS knüpft die Berechtigungen für Mikrofon
und Bedienungshilfen an Bundle-Identität und Code-Signatur, und beides hat ein
nacktes SwiftPM-Binary nicht. Es braucht das `.app`.

### 2. Starten

```bash
open ~/Applications/Roger.app

```

Beim ersten Start kommt das Einrichtungsfenster mit zwei Freigaben:

| Freigabe | Wofür |
|---|---|
| **Mikrofon** | Aufnahme |
| **Bedienungshilfen** | Die Taste abfangen **und** den Text in die Zielanwendung einfügen |

Eingabeüberwachung braucht Roger **nicht** — auch wenn die Verwechslung
naheliegt. Sie gilt für rein mithörende Event-Taps; Rogers Tap darf Ereignisse
verändern, und dafür sind die Bedienungshilfen zuständig.

### 3. Neu starten

Nach dem Erteilen bietet das Fenster einen Neustart an. Das ist keine
Bequemlichkeit: Der Event-Tap für die Taste entsteht beim Programmstart, und ein
laufender Prozess bekommt nachträglich freigegebene Tastaturereignisse nicht mehr
zu sehen.

### 4. Diktieren

**Esc gedrückt halten**, sprechen, loslassen. Der Text erscheint dort, wo der
Cursor steht. Die Taste ist in den Einstellungen (⌘,) änderbar.

Beim ersten Diktat lädt macOS das Sprachmodell nach; den Fortschritt zeigt die
Menüleiste. Das passiert einmal.

### 5. Nach /Applications verschieben (optional)

```bash
cp -R ~/Applications/Roger.app /Applications/
```

Achtung: Die Berechtigungen hängen auch am Pfad. Nach dem Verschieben werden sie
einmal neu erfragt.

## Weitergeben

Drei Wege, jemandem Roger zu geben. Der Unterschied liegt nicht in der Technik,
sondern darin, was der andere zu sehen bekommt.

| Weg | Was der Empfänger tut | Gatekeeper |
|---|---|---|
| **Selbst bauen** | Repo klonen, `./scripts/bundle.sh` | keine Hürde — selbst gebaute Software ist nicht in Quarantäne |
| **ZIP aus einem Release oder von einer Domain** | herunterladen, nach `/Applications` ziehen | blockt, solange nicht notarisiert |
| **Notarisiertes ZIP oder DMG** | herunterladen, öffnen | keine Hürde |

Das Archiv baut:

```bash
./scripts/release.sh 0.2.0
# → dist/Roger-0.2.0.zip, samt SHA-256 zum Mitveröffentlichen
```

Das Skript packt mit `ditto` und nicht mit `zip`. Nur `ditto` legt die
Code-Signatur so ab, dass sie das Auspacken übersteht — ein mit `zip` gepacktes
Bundle kommt beim Empfänger als beschädigt an.

**Ob das ZIP beim anderen läuft, hängt allein an der Signatur.** Alles, was aus
einem Browser kommt, bekommt von macOS ein Quarantäne-Merkmal. Gatekeeper prüft
dann die Signatur:

- **Ohne Developer ID** (Rogers Voreinstellung: ad-hoc) meldet macOS *„Roger ist
  beschädigt und kann nicht geöffnet werden"* — irreführend, aber gemeint ist
  „nicht notarisiert". Der Empfänger muss die Quarantäne selbst entfernen:

  ```bash
  xattr -dr com.apple.quarantine /Applications/Roger.app
  ```

  Für einen Kumpel, dem man das erklärt, reicht das. Für einen Download-Knopf auf
  einer Domain ist es keine Lösung — dort verliert man an dieser Stelle jeden.

- **Mit Developer ID und Notarisierung** (Apple Developer Program, 99 €/Jahr)
  öffnet die App ohne Hürde. Der Weg dahin:

  ```bash
  # einmalig: Zertifikat im Schlüsselbund, bundle.sh findet es von allein
  ./scripts/release.sh 0.2.0
  xcrun notarytool submit dist/Roger-0.2.0.zip \
    --apple-id "…" --team-id "…" --password "…" --wait
  xcrun stapler staple dist/Roger.app   # Ticket ins Bundle heften
  ditto -c -k --sequesterRsrc --keepParent dist/Roger.app dist/Roger-0.2.0.zip
  ```

  Die Notarisierung ist ein automatischer Malware-Scan, keine Prüfung durch
  Menschen; sie dauert Minuten. Ein weiterer Vorteil: Eine Developer ID bleibt
  über Builds hinweg gleich, die Freigaben bleiben also erhalten — bei ad-hoc
  sind sie nach jedem Bauen weg.

**Die eigene Domain** ändert daran nichts. Ein Download-Knopf, der auf ein ZIP
zeigt, ist genau derselbe Fall wie ein GitHub-Release: Es entscheidet die
Signatur, nicht der Ort. Der einzige Unterschied — GitHub-Releases sind kostenlos
und liefern Versionsverlauf und Prüfsummen gratis mit.

**Empfehlung:** Solange es Kumpels sind, ein GitHub-Release mit dem ZIP und dem
`xattr`-Befehl in den Release-Notes. Wird daraus etwas, das Fremde installieren
sollen, ist die Developer ID die 99 € wert — vorher nicht.

## Zwei Betriebsarten

In den Einstellungen unter **Betrieb** umschaltbar:

| | App (Voreinstellung) | Nur Menüleiste |
|---|---|---|
| Dock-Symbol | ja | nein |
| Programmumschalter (⌘Tab) | ja | nein |
| Fenster beim Start | ja | nein |
| Push-to-Talk | ja | ja |

Im Hintergrundbetrieb ist Roger ein Werkzeug in der Menüleiste, sonst nichts.
Fenster und Einstellungen kommen über das Menüleistensymbol — und solange eines
offen steht, ist Roger wieder eine gewöhnliche App. Nicht aus Nachlässigkeit: Ein
Fenster ohne Dock-Symbol ist ein halber Zustand, der sich nicht über den
Programmumschalter zurückholen lässt und den Tastaturfokus nur mit Mühe bekommt.
Mit dem letzten geschlossenen Fenster geht Roger wieder in den Hintergrund.

Die Aktivierungsrichtlinie wird schon vor `NSApplication.run()` gesetzt
(`main.swift`), nicht erst im Delegate: Zwischen Programmstart und
`applicationDidFinishLaunching` zeigt macOS das Dock-Symbol bereits an, und das
wäre ein Aufblitzen, das nichts bedeutet.

## Wörterbuch

Der Ort, an dem Roger Wörter beigebracht bekommt: Namen, Fachbegriffe,
Produktnamen. Zwei Eintragstypen:

| Typ | Bedeutung | Beispiel |
|---|---|---|
| Begriff | Roger soll das Wort kennen | `Anthropic` |
| Korrekturpaar | Wenn Roger X hört, schreibt er Y | `cloud code` → `Claude Code` |

Beide Mechanismen greifen, weil keiner allein reicht:

1. **Vor der Erkennung** gehen die Begriffe als Kontext an das Sprachmodell
   (`AnalysisContext.contextualStrings`). Das ist ein Schubs, kein Versprechen —
   und die Liste bleibt kurz (60 Einträge, mehrteilige zuerst), weil langer
   Kontext diese Modelle in die Irre zieht: Sie fangen an, bei leisem Audio
   Wörter zu erfinden, statt zu schweigen.
2. **Nach der Erkennung** läuft der Korrekturlauf über den Text. Ganze Wörter,
   schreibungsunabhängig, längstes Muster zuerst. Das ist der verbindliche Weg.

Der Korrekturlauf findet auch, was das Modell zusammenschreibt: Ein Eintrag für
`Claude Code` trifft `CloudCode` und `Cloud-Code` genauso wie die getrennte Form.
Zugleich lässt er echte Wörter in Ruhe — `Cloudflare` und das gewöhnliche `cloud`
bleiben stehen, weil das vollständige Muster verlangt wird. Sieht ein Eintrag so
aus, als träfe er etwas Gewöhnliches, sagt die Oberfläche das beim Tippen.

Im Verlauf steht bei jedem Diktat, welche Korrektur gegriffen hat und was sie
geändert hat — sonst ließe sich nicht beurteilen, ob das Wörterbuch überhaupt
etwas tut.

Die Datei liegt unter `~/Library/Application Support/Roger/dictionary.json` und
ist von Hand bearbeitbar. `{"written": "Vercel"}` genügt als Eintrag; `id` und
`created` ergänzt Roger. Änderungen an der Datei kommen im Fenster an, ohne die
App neu zu starten.

Ausgeliefert wird ein Beispielwörterbuch mit 158 Einträgen aus dem
Entwickleralltag: 86 Begriffe wie `Pull Request` und `Repository`, 72 Korrekturen
wie `cloud code` → `Claude Code`. Im Wörterbuchfenster gibt es „Auf Beispiel
zurücksetzen".

## Warum die Taste eine Schwelle braucht

Esc ist eine gewöhnliche Taste mit einem bestehenden Job. Würde Roger sie beim
Halten einfach schlucken, wäre Esc systemweit tot.

Stattdessen hält `HoldKeyMonitor` jeden Tastendruck zurück und startet eine Uhr:

- Loslassen vor Ablauf → normaler Tastendruck, wird synthetisch nachgereicht.
- Uhr läuft ab → Push-to-Talk, der Tastendruck bleibt geschluckt.

Der Preis ist die Schwelle als Latenz auf jedem normalen Esc — voreingestellt
220 ms, in den Einstellungen änderbar. Wer das nicht will, belegt dort eine
Modifier-Taste wie die rechte Wahltaste: Sie tut allein nichts, wird nicht
zurückgehalten und kostet keine Latenz.

Buchstaben und Ziffern lassen sich nicht belegen. Wer `A` belegt, kann `A`
danach nicht mehr tippen, ohne die Haltezeit abzuwarten.

## Sprache

Die Diktatsprache wird in den Einstellungen oder im Menüleistenmenü gewählt und
in den `UserDefaults` gemerkt.

Ein Default aus `Locale.current` wäre falsch: Das ist die Sprache der
*Oberfläche*, nicht die, in der jemand spricht. Wer seinen Mac auf Englisch
stellt und auf Deutsch diktiert, bekäme Kauderwelsch. Beim ersten Start wählt
Roger deshalb die erste Sprache aus `Locale.preferredLanguages`, die das Backend
beherrscht — korrigierbar mit einem Klick.

## Signatur und Berechtigungen

`bundle.sh` signiert mit einer **Developer ID**, falls eine im Schlüsselbund
liegt, sonst ad-hoc.

Der Unterschied ist im Alltag spürbar: macOS merkt sich die Berechtigung anhand
der Signatur. Eine Developer ID bleibt über Builds hinweg gleich, eine
Ad-hoc-Signatur nicht — sie enthält nur den Hash des Binaries, und der ändert
sich bei jedem Build. Ohne Zertifikat sind die Freigaben nach jedem
`bundle.sh` also wieder weg.

Das ist ein bekanntes Ärgernis ohne saubere Umgehung. Roger fängt es ab, statt
mit einem kryptischen Fehler zu scheitern: Das Einrichtungsfenster kommt hoch,
zwei Klicks, neu starten, weiter.

Im App Sandbox ist nichts davon möglich — ein Event-Tap und systemweiter Zugriff
über die Bedienungshilfen sind darin beide ausgeschlossen. Roger würde per
Developer ID verteilt, nicht über den Mac App Store.

## Fehlersuche

```bash
swift run roger-doctor
```

Zeigt Berechtigungen, Sprachumgebung, welche Sprachmodelle das System kennt und
welche installiert sind. Beantwortet die Frage „warum versteht Roger mich nicht?"
ohne die App zu instrumentieren.

Der Berechtigungsteil gilt für das Diagnose-Binary selbst, nicht für
`Roger.app` — macOS entscheidet pro Bundle und Signatur.

```bash
./scripts/reset-permissions.sh
```

Verwirft Rogers Einträge in der Berechtigungsdatenbank, damit macOS sie neu
erfragt. Nötig genau dann, wenn die Signatur wechselt — etwa beim Umstieg von
ad-hoc auf ein Zertifikat.

## Design-System

Richtung: Feldfunkgerät. Alle Farben, Abstände, Radien, Schatten und
Bewegungsdauern liegen im Namensraum `Design`
(`Sources/Roger/Design/Design.swift`), die lesbare Fassung in
[`docs/design-tokens.md`](docs/design-tokens.md). **Kein Wert steht in einer
Ansicht.**

Eine Ausnahme: Das Einrichtungsfenster bleibt in der Systemoptik. Ein Dialog, der
um zwei Systemfreigaben bittet, soll aussehen wie ein Dialog von macOS — Rogers
Gehäuse beginnt danach.

Share Tech Mono und IBM Plex Mono reisen im Bundle mit (SIL OFL) und werden über
`ATSApplicationFontsPath` nur für Roger registriert — sie werden nicht
installiert. Fehlen sie, fällt `Design.Families` auf die Festbreitenschrift des
Systems zurück, nie in eine Proportionalschrift.

## Aufbau

`RogerCore` kennt fünf Ports und einen Zustandsautomaten; die Adapter dahinter
sind austauschbar.

```
DictationSession            idle → recording → transcribing → injecting
  ├─ HotkeyMonitoring       HoldKeyMonitor            CGEventTap
  ├─ AudioCapturing         MicrophoneCapture         AVAudioEngine
  ├─ Transcribing           SpeechAnalyzerTranscriber Speech (on-device, macOS 26)
  ├─ TextFormatting         DictionaryCorrector       Wörterbuch-Korrekturlauf
  └─ TextInjecting          PasteboardInjector        Zwischenablage + ⌘V
```

Darüber liegt `RogerApp`: der Anwendungsdienst, der den Diktatstapel besitzt und
das ist, was die Fenster sehen. Ohne ihn stünde der gemeinsame Zustand — welche
Sprachen es gibt, was gerade lädt, was zuletzt schiefging — im `AppDelegate`.

Persistenz sind zwei JSON-Dateien in `~/Library/Application Support/Roger/`:
`dictionary.json` und `history.json`. Eingerückt, mit sortierten Schlüsseln und
ISO-Datumsangaben, damit ein Mensch sie anfassen kann.

```bash
swift test    # 23 Tests, im Schwerpunkt der Korrekturlauf
```

## Was fehlt

- Weitere Aufbereitung des Rohtranskripts: Füllwörter, Interpunktion, Listen
- Wörterbuch, das sich selbst füllt, statt gepflegt zu werden
- Sprachbefehle (Textbausteine per Zuruf)
- Alternative ASR-Backends (Parakeet via MLX) — `Transcribing` ist dafür da
- Notarisierung, Updates

Ausführlich, mit Wegen und Gegenargumenten: [`docs/ideen.md`](docs/ideen.md).

## Lizenz

MIT, siehe [LICENSE](LICENSE). Die mitgelieferten Schriften stehen unter der SIL
Open Font License 1.1.
