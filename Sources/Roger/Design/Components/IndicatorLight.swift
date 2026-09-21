import SwiftUI

/// An indicator lamp — the only lit and the only round shape in the device.
struct IndicatorLight: View {
    enum Mode {
        case transmitting
        case active
        case off
    }

    let mode: Mode

    /// The blink hangs off a branch of its own rather than off a state flag:
    /// `repeatForever` never ends, and setting the flag back does not end it
    /// either — SwiftUI merges the next one onto the still-running one, and a
    /// stack of them costs a frame's work for as long as Roger runs. Leaving the
    /// branch destroys the view, and the animation dies with it.
    var body: some View {
        if mode == .transmitting {
            lamp.modifier(Blink())
        } else {
            lamp
        }
    }

    private var lamp: some View {
        Circle()
            .fill(color)
            .frame(width: Design.Indicator.size, height: Design.Indicator.size)
            .shadow(color: color.opacity(glows ? 0.9 : 0), radius: Design.Indicator.glowRadius)
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

private struct Blink: ViewModifier {
    @State private var isDimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(isDimmed ? 0.3 : 1)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: Design.Motion.blinkPeriod / 2).repeatForever()
                ) { isDimmed = true }
            }
    }
}
