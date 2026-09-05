import AppKit
import RogerCore
import SwiftUI

/// Settings: the key and the language model. Everything else lives in the main
/// window or in the dictionary file.
struct SettingsView: View {
    let app: RogerApp

    /// A list instead of a slider, because only a narrow band makes sense: below
    /// 150 ms normal typing starts a recording, above 400 ms the key feels slow.
    private static let thresholds = [150, 200, 220, 280, 350, 450]

    var body: some View {
        ScrollView {
            VStack(spacing: Design.Space.xl) {
                hotkeyPanel
                languagePanel
                microphonePanel
                modePanel
                filesPanel
            }
            .padding(Design.Space.xl)
        }
        .frame(width: 560, height: 640)
        .background(Design.Palette.background)
    }

    private var hotkeyPanel: some View {
        RecessedPanel("Push-to-Talk") {
            VStack(alignment: .leading, spacing: Design.Space.lg) {
                HotkeyRecorder(keyCode: app.hotkey.keyCode) { code in
                    app.rebindHotkey(
                        to: HotkeyBinding(
                            keyCode: code,
                            holdThreshold: app.hotkey.holdThreshold,
                            replaysShortPress: HotkeyBinding.needsReplay(keyCode: code)
                        )
                    )
                }

                VStack(alignment: .leading, spacing: Design.Space.sm) {
                    EquipmentLabel("Haltezeit")
                    HStack(spacing: Design.Space.xs) {
                        ForEach(Self.thresholds, id: \.self) { milliseconds in
                            thresholdButton(milliseconds)
                        }
                    }
                    Text(explanation)
                        .textStyle(Design.Typography.timestamp)
                        .foregroundStyle(Design.Palette.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func thresholdButton(_ milliseconds: Int) -> some View {
        let isActive = Int(app.hotkey.holdThreshold.timeInterval * 1000) == milliseconds
        return Button {
            app.rebindHotkey(
                to: HotkeyBinding(
                    keyCode: app.hotkey.keyCode,
                    holdThreshold: .milliseconds(milliseconds),
                    replaysShortPress: app.hotkey.replaysShortPress
                )
            )
        } label: {
            Text("\(milliseconds)")
                .textStyle(Design.Typography.label)
                .foregroundStyle(isActive ? Design.Palette.accentAmber : Design.Palette.controlText)
                .frame(width: 44, height: 24)
                .background(isActive ? Design.Palette.controlBackground : Design.Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Design.Radius.sm, style: .continuous)
                        .strokeBorder(
                            isActive ? Design.Palette.accentAmber : Design.Palette.controlBorder,
                            lineWidth: Design.Border.hairline
                        )
                }
        }
        .buttonStyle(.plain)
    }

    private var explanation: String {
        app.hotkey.replaysShortPress
        ? """
          \(KeyNames.name(of: app.hotkey.keyCode)) hat schon eine Aufgabe. Roger hält jeden \
          Druck bis zum Ablauf der Haltezeit zurück und reicht ihn danach als echten \
          Tastendruck nach — die Haltezeit ist also die Verzögerung, die ein normales \
          \(KeyNames.name(of: app.hotkey.keyCode)) bekommt.
          """
        : """
          \(KeyNames.name(of: app.hotkey.keyCode)) ist eine Modifier-Taste und tut allein \
          nichts. Sie wird nicht zurückgehalten, die Haltezeit kostet hier keine Latenz.
          """
    }

    private var languagePanel: some View {
        RecessedPanel("Sprachmodell") {
            VStack(alignment: .leading, spacing: Design.Space.sm) {
                if app.languages.isEmpty {
                    Text("Noch keine Sprache gemeldet.")
                        .textStyle(Design.Typography.timestamp)
                        .foregroundStyle(Design.Palette.textDim)
                }
                ForEach(app.languages) { choice in
                    languageRow(choice)
                }
                Text("""
                    Erkennung läuft vollständig auf diesem Mac. Eine noch nicht geladene \
                    Sprache zieht das System beim Umschalten nach; der Fortschritt steht in \
                    der Menüleiste.
                    """)
                    .textStyle(Design.Typography.timestamp)
                    .foregroundStyle(Design.Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Design.Space.xs)
            }
        }
    }

    private func languageRow(_ choice: RogerApp.LanguageChoice) -> some View {
        let isActive = app.activeLocale.map { choice.locale.matches($0) } == true
        return Button {
            app.select(language: choice.locale)
        } label: {
            HStack(spacing: Design.Space.md) {
                Circle()
                    .fill(isActive ? Design.Palette.accentAmber : Design.Palette.surfaceBorder)
                    .frame(width: Design.Indicator.size, height: Design.Indicator.size)
                Text(choice.name)
                    .textStyle(Design.Typography.body)
                    .foregroundStyle(Design.Palette.textPrimary)
                Spacer()
                EquipmentLabel(choice.isInstalled ? "Geladen" : "Nachladen")
            }
            .padding(.vertical, Design.Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Microphone

    /// Available input devices are queried each time the settings view is
    /// rendered — cheap, and picks up hot-plugged devices without observers.
    private var microphonePanel: some View {
        let devices = app.availableInputDevices()
        let hasBuiltIn = devices.contains { $0.transport == .builtIn }
        let selection = app.inputDeviceSelection

        return RecessedPanel("Mikrofon") {
            VStack(alignment: .leading, spacing: Design.Space.sm) {
                microphoneRow(
                    label: "Automatisch (System-Standard)",
                    detail: nil,
                    warning: nil,
                    isActive: selection == .automatic,
                    action: { app.selectInputDevice(.automatic) }
                )
                if hasBuiltIn {
                    microphoneRow(
                        label: "Eingebautes Mikrofon (empfohlen)",
                        detail: nil,
                        warning: nil,
                        isActive: selection == .builtIn,
                        action: { app.selectInputDevice(.builtIn) }
                    )
                }
                ForEach(devices.filter { $0.transport != .builtIn }) { device in
                    microphoneRow(
                        label: device.name,
                        detail: transportLabel(for: device),
                        warning: device.transport == .bluetooth ? bluetoothWarning : nil,
                        isActive: selection == .explicit(uid: device.uid),
                        action: { app.selectInputDevice(.explicit(uid: device.uid)) }
                    )
                }

                Text(microphoneExplanation)
                    .textStyle(Design.Typography.timestamp)
                    .foregroundStyle(Design.Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Design.Space.xs)

                FieldDivider()
                    .padding(.vertical, Design.Space.xs)

                FieldCheckbox(
                    isOn: .init(
                        get: { app.pausesMusicWhileDictating },
                        set: { app.setPausesMusicWhileDictating($0) }
                    ),
                    label: "Musik während der Aufnahme pausieren"
                )
                Text(musicPauseExplanation)
                    .textStyle(Design.Typography.timestamp)
                    .foregroundStyle(Design.Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func microphoneRow(
        label: String,
        detail: String?,
        warning: String?,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Design.Space.md) {
                Circle()
                    .fill(isActive ? Design.Palette.accentAmber : Design.Palette.surfaceBorder)
                    .frame(width: Design.Indicator.size, height: Design.Indicator.size)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .textStyle(Design.Typography.body)
                        .foregroundStyle(Design.Palette.textPrimary)
                    if let warning {
                        Text(warning)
                            .textStyle(Design.Typography.timestamp)
                            .foregroundStyle(Design.Palette.accentRed)
                    }
                }
                Spacer()
                if let detail {
                    EquipmentLabel(detail)
                }
            }
            .padding(.vertical, Design.Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func transportLabel(for device: InputDevice) -> String {
        switch device.transport {
        case .builtIn: return "Eingebaut"
        case .wired: return "Kabel"
        case .bluetooth: return "Bluetooth"
        case .continuity: return "iPhone / iPad"
        case .aggregate: return "Aggregat"
        case .virtual: return "Virtuell"
        case .unknown: return "Sonstige"
        }
    }

    private var bluetoothWarning: String {
        "Verzögerter Start, verringerte Musik-Qualität, mehr Erkennungsfehler."
    }

    private var microphoneExplanation: String {
        """
        Bluetooth-Kopfhörer schalten beim Aufnehmen auf einen Mono-Modus mit \
        geringer Qualität. Für das Diktat empfehlen wir das eingebaute \
        Mikrofon; die Musik bleibt in voller Qualität auf den Kopfhörern.
        """
    }

    private var musicPauseExplanation: String {
        """
        Beim Drücken geht ein Pause-Befehl an das, was gerade läuft, beim \
        Loslassen ein Play. Ist nichts zu hören, passiert nichts. Erreicht wird, \
        was sich bei der Mediensteuerung von macOS anmeldet — Musik, Spotify, \
        Videos im Browser. Mit Bluetooth-Kopfhörern fällt so der \
        Qualitätswechsel zum Aufnahmestart nicht auf.
        """
    }

    private var modePanel: some View {
        RecessedPanel("Betrieb") {
            VStack(alignment: .leading, spacing: Design.Space.sm) {
                FieldCheckbox(
                    isOn: .init(
                        get: { app.isMenuBarOnly },
                        set: { app.setMenuBarOnly($0) }
                    ),
                    label: "Nur in der Menüleiste"
                )
                Text(modeExplanation)
                    .textStyle(Design.Typography.timestamp)
                    .foregroundStyle(Design.Palette.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Describes the state Roger *is* in — not the one the switch leads to.
    private var modeExplanation: String {
        app.isMenuBarOnly
        ? """
          Roger liegt im Hintergrund: kein Dock-Symbol, kein Eintrag im \
          Programmumschalter, kein Fenster beim Start. Die Taste funktioniert \
          trotzdem, und Fenster wie Einstellungen kommen über das \
          Menüleistensymbol. Solange eines offen steht, ist Roger wieder eine \
          gewöhnliche App — sonst bekäme das Fenster keinen Tastaturfokus und \
          ließe sich nicht zurückholen.
          """
        : """
          Roger ist eine gewöhnliche App: Dock-Symbol, Programmumschalter, \
          Hauptfenster beim Start. Für den reinen Hintergrundbetrieb hier \
          einschalten — die Umstellung greift, sobald das letzte Fenster zu ist.
          """
    }

    private var filesPanel: some View {
        RecessedPanel("Dateien") {
            VStack(alignment: .leading, spacing: Design.Space.sm) {
                fileRow("Wörterbuch", app.dictionary.fileURL)
                fileRow("Verlauf", app.history.fileURL)
                FieldDivider()
                    .padding(.vertical, Design.Space.xs)
                clearHistoryRow
            }
        }
    }

    /// The log has to be clearable without editing the file. The word count stays
    /// — it is a tally, not a store.
    private var clearHistoryRow: some View {
        HStack(spacing: Design.Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                EquipmentLabel("Verlauf leeren")
                Text("Löscht alle \(app.history.records.count) Einträge. Der Wortzähler bleibt.")
                    .textStyle(Design.Typography.timestamp)
                    .foregroundStyle(Design.Palette.textDim)
            }
            Spacer(minLength: Design.Space.sm)
            Button("Löschen") { app.history.clear() }
                .buttonStyle(GhostButtonStyle(tint: Design.Palette.accentRed))
                .disabled(app.history.records.isEmpty)
                .opacity(app.history.records.isEmpty ? Design.Emphasis.disabled : 1)
        }
    }

    private func fileRow(_ label: String, _ url: URL) -> some View {
        HStack(spacing: Design.Space.md) {
            EquipmentLabel(label).frame(width: 90, alignment: .leading)
            Text(url.path(percentEncoded: false))
                .textStyle(Design.Typography.timestamp)
                .foregroundStyle(Design.Palette.textDim)
                .truncationMode(.head)
                .lineLimit(1)
            Spacer(minLength: Design.Space.sm)
            Button("Zeigen") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                .buttonStyle(GhostButtonStyle())
        }
    }
}
