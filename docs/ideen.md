# Roger — Ideen

Was Roger noch werden könnte. Sortiert nach Verhältnis von Nutzen zu Aufwand,
nicht nach Reihenfolge der Einfälle. Nichts davon ist beschlossen.

Jeder Punkt nennt auch, was daran schiefgehen kann — eine Ideenliste, die nur
Vorteile aufzählt, ist eine Wunschliste.

---

## 1. Textaufbereitung nach der Erkennung

**Das mit Abstand größte Fehlende.** Rogers Rohtranskript ist genau das: roh.
Gesprochene Sprache hat Füllwörter, keine Absätze und keine Listen.

Drei Stufen, die sich unabhängig voneinander bauen lassen:

### 1a. Füllwörter und Selbstkorrekturen (regelbasiert, klein)

Eine Streichliste, die nach demselben Muster arbeitet wie der Korrekturlauf:
`äh`, `ähm`, `also`, `sozusagen`, `im Prinzip`, `quasi`, `halt` — und, wichtiger,
das **Neuansetzen**: „ich wollte — ich meine also, dass" wird „ich meine, dass".

| Vorteil | Nachteil |
|---|---|
| `TextCorrector` kann das schon, es braucht nur eine zweite Regelliste | „also" ist manchmal ein echtes Wort. Ohne Kontext wird es falsch gestrichen |
| Kein Modell, kein Zeitverlust, testbar | Die Streichliste ist Geschmackssache und gehört damit in die Einstellungen |

**Empfehlung:** ja, aber abschaltbar und mit einer eigenen, bearbeitbaren Datei —
wie das Wörterbuch. Und mit derselben Anzeige im Verlauf: *was* wurde gestrichen.

### 1b. Struktur aus Aufzählungswörtern (regelbasiert, mittel)

Das genannte Beispiel: „erstens … zweitens … drittens" wird eine Liste.

```
erstens den Cache leeren zweitens neu bauen drittens testen
→
1. Den Cache leeren
2. Neu bauen
3. Testen
```

Ebenso „Punkt eins / Punkt zwei", „zum einen / zum anderen", „erster Punkt".

| Vorteil | Nachteil |
|---|---|
| Deterministisch, ohne Modell, schnell | Die Grenze zwischen zwei Punkten ist raterei — wo endet „erstens"? |
| Spart die meiste Nacharbeit von allen Ideen hier | Falsch geschnitten ist schlimmer als nicht geschnitten |

Ehrlicher Weg: Nur auslösen, wenn **mindestens zwei** Aufzählungswörter in Folge
auftreten. Ein einzelnes „erstens" bleibt Text. Und die Schnittstelle vor dem
nächsten Aufzählungswort setzen, nicht raten.

### 1c. LLM-Durchlauf (groß, mit echtem Nachteil)

Ein Modell schreibt das Transkript um: Interpunktion, Absätze, Groß- und
Kleinschreibung, auf Wunsch Ton („sachlich", „knapp", „E-Mail").

| Weg | Vorteil | Nachteil |
|---|---|---|
| **Apple Foundation Models** (on-device, macOS 26) | bleibt auf dem Gerät, kein Konto, keine Kosten | kleines Modell, deutsche Prosa wird mittelmäßig |
| **API** (Claude, GPT) | deutlich bessere Ergebnisse | Netz, Konto, Kosten, Diktat verlässt das Gerät |

Beides bricht Rogers Versprechen an unterschiedlichen Stellen: Das erste kostet
Qualität, das zweite kostet Vertraulichkeit und Latenz — ein LLM-Durchlauf
verdoppelt bis verdreifacht die Zeit bis zum Text.

**Empfehlung:** als **zweite Taste** bauen, nicht als Voreinstellung. Ein
Standarddiktat bleibt schnell und lokal; wer aufbereiten will, hält die andere
Taste. Und im Verlauf beide Fassungen behalten — Roh und aufbereitet —, weil ein
Modell manchmal Inhalt verliert und man das dann sehen muss.

---

## 2. Wörterbuch, das sich selbst füllt

Der zweite genannte Punkt: nicht pflegen müssen, sondern lernen lassen.

Das Problem daran ist scharf umrissen: **Roger sieht nie, was richtig gewesen
wäre.** Er sieht nur, was er gehört hat. Ein Modell, das aus sich selbst lernt,
verstärkt seine eigenen Fehler. Es braucht also eine Quelle für Wahrheit, und
dafür gibt es genau vier — in dieser Reihenfolge tragfähig:

### 2a. Aus Korrekturen im Verlauf lernen (die beste Quelle)

Der Verlauf liegt schon vor. Was fehlt, ist eine Bearbeitungsmöglichkeit: Text im
Verlauf anfassen, richtigstellen, und Roger vergleicht Vorher/Nachher.

```
Roher Text:   "wir mergen den pull rikwest nach mein"
Korrigiert:   "wir mergen den Pull Request nach main"
                                ^^^^^^^^^^^^  ^^^^
→ Vorschlag: "pull rikwest" → "Pull Request"
             "mein" → "main"   (verdächtig: häufiges Wort, nur mit Bestätigung)
```

| Vorteil | Nachteil |
|---|---|
| Echte Wahrheit — ein Mensch hat es hingeschrieben | Setzt voraus, dass man im Verlauf korrigiert, statt in der Ziel-App |
| Ein Wortabstand (Levenshtein) auf Wortebene reicht als Verfahren | Einmalige Tippfehler dürfen nicht zur Regel werden |

**Regel dagegen:** Nur vorschlagen, was **dreimal gleich** korrigiert wurde. Und
niemals stillschweigend übernehmen — als Vorschlagsliste im Wörterbuchfenster,
mit „übernehmen" und „nie wieder vorschlagen". Ein Wörterbuch, das sich hinter
dem Rücken ändert, ist nicht mehr überprüfbar.

### 2b. Aus dem eigenen Wortschatz lesen (breit, aber ungenau)

Namen und Fachbegriffe aus Quellen, die schon da sind: Namen der eigenen
Git-Repos, Ordnernamen unter `~/dev`, Kontakte, Kalendertitel, Verzeichnisse im
Projekt.

| Vorteil | Nachteil |
|---|---|
| Trifft genau die Wörter, an denen es scheitert — eigene Projektnamen | Zugriff auf Kontakte und Kalender braucht neue Freigaben |
| Läuft einmalig, ohne Lernphase | Liefert viel Müll; die Kontextliste ist auf 60 begrenzt und wird verwässert |

**Empfehlung:** ja für Git-Repos und Ordnernamen (kein neuer Zugriff nötig, wenn
man den Ordner selbst auswählt), nein für Kontakte, solange es keinen Weg gibt,
die Auswahl vorher zu sehen.

### 2c. Aus der Erkennung selbst (Konfidenzwerte)

`SpeechTranscriber` liefert Alternativen und Konfidenz. Wörter, bei denen das
Modell unsicher war, sind Kandidaten für das Wörterbuch.

| Vorteil | Nachteil |
|---|---|
| Kostenlos, kommt mit dem Transkript | Zeigt nur *wo* es unsicher war, nie *was* richtig ist |

Alleine also nutzlos. Sinnvoll nur als Verstärker für 2a: eine Korrektur an einer
Stelle, an der das Modell ohnehin unsicher war, ist eher eine Regel als ein
Tippfehler.

### 2d. Aus einem LLM (bequem, schwer prüfbar)

Ein Modell durchsucht das Transkript nach Wörtern, die verhört klingen. Praktisch
und mit dem Fehler behaftet, dass es Regeln erfindet, die niemand gesagt hat.
Nur mit Bestätigung pro Eintrag, wenn überhaupt.

**Zusammengefasst:** 2a bauen, mit 2c gewichten, 2b für den Einstieg. Nie ohne
Bestätigung.

---

## 3. Themes

Die genannte Idee: die Optik in den Einstellungen umschaltbar machen.

Technisch ist der Weg schon gelegt — das ganze Design geht durch `Design.Palette`
und die Ansichten kennen keine eigenen Werte. Was fehlt: `Palette` von einem
`enum` mit statischen Konstanten in ein injizierbares `Theme` verwandeln und über
die `Environment` verteilen. Etwa ein halber Tag Arbeit, und ein Umbau, der jede
Ansicht anfasst.

Kandidaten, wenn:

| Theme | Farben |
|---|---|
| **Feldfunk** (heute) | Oliv, Bernstein, Rot |
| **Terminal** | Schwarz, Phosphorgrün, ein Bernstein |
| **Blueprint** | Preußischblau, Weiß, dünne Linien |
| **Grau** | Neutrale Grautöne, ein einziger Akzent — für Leute, die das Thema nicht wollen |

**Ehrlich dazu:** Die Idee ist verführerisch und steht deshalb hier unten. Der
Nutzen ist nahe null — man wählt einmal und schaut nie wieder hin —, und der
Preis ist hoch: Jeder Token wird verhandelbar, jede neue Ansicht muss in vier
Farbwelten funktionieren, und der Kommentar „zwei Akzentfarben, und beide bedeuten
etwas" gilt dann nicht mehr überall. Der Charakter der App kommt gerade daraus,
dass sie *eine* Lackierung hat.

Wenn, dann als **zwei** Themes, nicht vier, und mit derselben Bedeutungszuweisung
(Rot sendet, Bernstein zeigt an) in beiden.

---

## 4. Kleineres, das sich lohnt

| Idee | Warum | Aufwand |
|---|---|---|
| **Sprachbefehle** — „neue Zeile", „Punkt", „Komma", „Absatz" | Interpunktion diktieren, ohne LLM | klein, gleiche Mechanik wie das Wörterbuch |
| **Textbausteine per Zuruf** — „Signatur einfügen" | Wiederkehrender Text ohne Snippet-Werkzeug | klein |
| **Verlaufseintrag erneut einfügen** | Etwas verlorenes Diktat nachschieben, ohne Kopieren | sehr klein |
| **Pro-App-Verhalten** — im Terminal nie Großschreibung, in Slack keine Anrede | Der Zielkontext ist bekannt (`frontmostApplication`) | mittel |
| **Diktat abbrechen** mit Esc während der Aufnahme | Verklickt sich jeder mal | sehr klein |
| **Automatischer Start bei Anmeldung** (`SMAppService`) | Ein Hintergrundwerkzeug, das man von Hand starten muss, ist keines | klein |
| **Updates** (Sparkle) | Sonst muss jeder Empfänger von Hand nachladen | mittel, setzt Notarisierung voraus |
| **Audio behalten** (optional, mit Verfallsdatum) | Ohne Aufnahme lässt sich kein Erkennungsfehler nachvollziehen | mittel, und heikel: Sprachaufnahmen auf der Platte |
| **Statistik** — Wörter pro Tag, häufigste Korrekturen | Zeigt, ob das Wörterbuch etwas bringt | klein, die Daten liegen vor |

## 5. Wovon ich abraten würde

| Idee | Warum nicht |
|---|---|
| **Cloud-Sync des Wörterbuchs** | Ein Konto und ein Server für eine Datei, die in iCloud Drive liegen könnte |
| **Live-Transkription während des Sprechens** | Sieht beeindruckend aus, hilft nicht: Man liest nicht mit, während man spricht — und `SpeechAnalyzer` müsste dauerlaufen |
| **Mehrere Sprachen gleichzeitig** | Das Speech-Framework reserviert pro Sprache; automatisches Umschalten rät und rät falsch |
| **iOS-Fassung** | Kein systemweites Einfügen, kein Event-Tap. Es wäre eine andere App |
