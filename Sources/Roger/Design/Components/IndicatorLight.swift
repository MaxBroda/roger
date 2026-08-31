import SwiftUI

/// An indicator lamp — the only lit and the only round shape in the device.
struct IndicatorLight: View {
    enum Mode {
        case transmitting
        case active
        case off
    }

    let mode: Mode
    @State private var isDimmed = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: Design.Indicator.size, height: Design.Indicator.size)
            .shadow(color: color.opacity(glows ? 0.9 : 0), radius: Design.Indicator.glowRadius)
            .opacity(mode == .transmitting && isDimmed ? 0.3 : 1)
            .onChange(of: mode, initial: true) { _, newMode in
                // Re-armed on state change: an endless animation on a hidden lamp
                // keeps the view awake.
                guard newMode == .transmitting else {
                    withAnimation(.linear(duration: 0)) { isDimmed = false }
                    return
                }
                isDimmed = false
                withAnimation(
                    .easeInOut(duration: Design.Motion.blinkPeriod / 2).repeatForever()
                ) { isDimmed = true }
            }
    }

    private var color: Color {
        switch mode {
        case .transmitting: Design.Palette.accentRed
        case .active: Design.Palette.accentAmber
        case .off: Design.Palette.surfaceBorder
        }
    }

    private var glows: Bool { mode != .off }
}
