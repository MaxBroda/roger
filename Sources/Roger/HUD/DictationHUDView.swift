import RogerCore
import SwiftUI

/// The bubble that floats above everything while dictating. It shows exactly
/// one thing: that Roger is listening, and how loud.
struct DictationHUDView: View {
    let model: HUDModel

    var body: some View {
        bubble
            // Fills the panel; the bubble keeps its natural size, centred.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bubble: some View {
        Group {
            switch model.state {
            case .transcribing, .injecting:
                SweepingBars()
            default:
                Bars(levels: model.bands)
            }
        }
        .padding(.horizontal, Design.Bubble.horizontalPadding)
        .padding(.vertical, Design.Bubble.verticalPadding)
        .background { shell }
        .shadow(
            color: .black.opacity(Design.Elevation.bubbleOpacity),
            radius: Design.Elevation.bubbleRadius,
            y: Design.Elevation.bubbleOffset
        )
        // Two axes, two springs: width leads, height follows. One spring for
        // both would just be growing.
        .scaleEffect(
            x: model.isExpanded ? 1 : Design.Bubble.collapsedWidthScale,
            y: 1,
            anchor: .center
        )
        .animation(
            model.isExpanded ? Design.Bubble.openWidth : Design.Bubble.closeWidth,
            value: model.isExpanded
        )
        .scaleEffect(
            x: 1,
            y: model.isExpanded ? 1 : Design.Bubble.collapsedHeightScale,
            anchor: .center
        )
        .animation(
            model.isExpanded ? Design.Bubble.openHeight : Design.Bubble.closeHeight,
            value: model.isExpanded
        )
        .opacity(model.isExpanded ? 1 : 0)
        .animation(model.isExpanded ? Design.Bubble.fadeIn : Design.Bubble.fadeOut, value: model.isExpanded)
    }

    /// Opaque black with a hairline: an object lying on the screen, not a window
    /// into it.
    private var shell: some View {
        Capsule(style: .continuous)
            .fill(Design.Bubble.fill)
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Design.Bubble.rim, lineWidth: Design.Border.hairline)
            }
    }
}

/// The deflection as thin bars, growing from the centre in both directions.
private struct Bars: View {
    let levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: Design.Bubble.barSpacing) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Bar(level: level)
            }
        }
        .frame(height: Design.Bubble.barMaxHeight)
        .animation(Design.Bubble.bars, value: levels)
    }
}

/// No audio arrives while transcribing, so a wave runs through the same bars —
/// otherwise the bubble looks frozen.
private struct SweepingBars: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: Design.Bubble.barSpacing) {
                ForEach(0..<HUDModel.barCount, id: \.self) { index in
                    Bar(level: level(index: index, time: time), opacity: Design.Bubble.sweepOpacity)
                }
            }
            .frame(height: Design.Bubble.barMaxHeight)
        }
    }

    private func level(index: Int, time: TimeInterval) -> Float {
        let travel = time * 3.6 - Double(index) * 0.32
        return Float(0.1 + (sin(travel) + 1) / 2 * 0.45)
    }
}

private struct Bar: View {
    let level: Float
    var opacity: Double = 1

    var body: some View {
        Capsule(style: .circular)
            .fill(Design.Bubble.bar.opacity(opacity))
            .frame(width: Design.Bubble.barWidth, height: height)
    }

    private var height: CGFloat {
        let clamped = CGFloat(max(0, min(1, level)))
        let span = Design.Bubble.barMaxHeight - Design.Bubble.barMinHeight
        return Design.Bubble.barMinHeight + span * clamped
    }
}
