import AppKit
import RogerCore
import SwiftUI

/// Records a key. Once armed it swallows every keystroke, or the Esc someone is
/// about to bind would close the window. A *local* monitor: it only applies
/// while Roger is frontmost.
struct HotkeyRecorder: View {
    let keyCode: UInt16
    /// The other hotkey's key code, if one exists — both monitors would
    /// otherwise race over the same physical key press.
    var excludedKeyCode: UInt16?
    let onCapture: (UInt16) -> Void

    @State private var isArmed = false
    @State private var monitor: Any?
    @State private var rejected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            HStack(spacing: Design.Space.md) {
                Text(isArmed ? "Taste drücken …" : KeyNames.name(of: keyCode))
                    .textStyle(Design.Typography.status)
                    .foregroundStyle(isArmed ? Design.Palette.accentAmber : Design.Palette.textPrimary)
                    .frame(minWidth: 150, alignment: .leading)
                    .padding(.horizontal, Design.Space.md)
                    .padding(.vertical, Design.Space.sm)
                    .background(Design.Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous)
                            .strokeBorder(
                                isArmed ? Design.Palette.accentAmber : Design.Palette.surfaceBorder,
                                lineWidth: Design.Border.hairline
                            )
                    }

                Button(isArmed ? "Abbrechen" : "Ändern") {
                    isArmed ? disarm() : arm()
                }
                .fieldButton(.secondary, compact: true)
            }

            if let rejected {
                HStack(alignment: .top, spacing: Design.Space.sm) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: Design.Icon.hint))
                    Text(rejected)
                        .textStyle(Design.Typography.timestamp)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Design.Palette.accentAmber)
            }
        }
        .onDisappear(perform: disarm)
    }

    private func arm() {
        rejected = nil
        isArmed = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            MainActor.assumeIsolated { capture(event) }
            return nil
        }
    }

    private func disarm() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isArmed = false
    }

    private func capture(_ event: NSEvent) {
        let code = event.keyCode
        if let reason = HotkeyBinding.unusableReason(keyCode: code) {
            rejected = rejectionMessage(for: reason, code: code)
            disarm()
            return
        }
        if let excludedKeyCode, code == excludedKeyCode {
            rejected = """
                \(KeyNames.name(of: code)) ist schon die andere Taste. Beide auf \
                dieselbe Taste zu legen lässt die beiden Diktat-Modi um denselben \
                Tastendruck konkurrieren.
                """
            disarm()
            return
        }
        rejected = nil
        disarm()
        onCapture(code)
    }

    private func rejectionMessage(for reason: HotkeyBinding.UnusableReason, code: UInt16) -> String {
        switch reason {
        case .typingKey:
            """
            \(KeyNames.name(of: code)) lässt sich nicht belegen. Roger hält die \
            Taste bis zum Ablauf der Haltezeit zurück — bei einer Schreibtaste \
            wäre danach das Tippen kaputt.
            """
        case .modifierOnly:
            """
            \(KeyNames.name(of: code)) lässt sich nicht belegen. Für sich allein \
            löst sie keinen Tastendruck aus und würde nie ein Diktat starten.
            """
        }
    }
}
