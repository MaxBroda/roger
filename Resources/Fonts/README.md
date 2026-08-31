# Schriften

Beide Familien stehen unter der SIL Open Font License 1.1; die Lizenztexte
liegen daneben.

| Datei | Familie | Rolle im Design-System |
|---|---|---|
| `ShareTechMono-Regular.ttf` | Share Tech Mono | Beschriftungen, Status, Knöpfe, Zähler |
| `IBMPlexMono-Regular.ttf` | IBM Plex Mono | Fließtext, Transkripte, Zeitstempel, Eingabefelder |

Registriert werden sie über `ATSApplicationFontsPath` in der `Info.plist` — das
gilt nur im gebündelten `Roger.app`. Ein nackter `swift run` fällt auf die
Festbreitenschrift des Systems zurück; `Design.Families` sucht der Reihe nach
und kippt nie in eine Proportionalschrift.
