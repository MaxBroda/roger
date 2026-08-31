import AppKit
import RogerCore
import SwiftUI

/// Records a key. Once armed it swallows every keystroke, or the Esc someone is
/// about to bind would close the window. A *local* monitor: it only applies
/// while Roger is frontmost.
struct HotkeyRecorder: View {
    let keyCode: UInt16
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
        guard HotkeyBinding.isUsable(keyCode: code) else {
            rejected = """
                \(KeyNames.name(of: code)) lässt sich nicht belegen. Roger hält die \
                Taste bis zum Ablauf der Haltezeit zurück — bei einer Schreibtaste \
                wäre danach das Tippen kaputt.
                """
            disarm()
            return
        }
        rejected = nil
        disarm()
        onCapture(code)
    }
}
