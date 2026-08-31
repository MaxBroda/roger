import SwiftUI

/// The level meter as an LED ladder, fed from the spectrum analysis. At rest a
/// row of base dots stays lit so the panel reads as powered, not crashed.
struct LevelMeter: View {
    /// Level per band, 0…1 — finer than the ladder has bars.
    let bands: [Float]
    var isLive: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: Design.Meter.barGap) {
            ForEach(0..<Design.Meter.barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: Design.Radius.bar, style: .continuous)
                    .fill(Design.Meter.color(at: index).opacity(isLive ? 1 : 0.5))
                    .frame(width: Design.Meter.barWidth, height: height(at: index))
            }
        }
        .frame(height: Design.Meter.maxHeight, alignment: .bottom)
        .animation(Design.Motion.meter, value: bands)
        .animation(Design.Motion.indicate, value: isLive)
    }

    private func height(at index: Int) -> CGFloat {
        guard isLive, let level = folded(index) else { return Design.Meter.minHeight }
        return max(Design.Meter.minHeight, Design.Meter.maxHeight * CGFloat(level))
    }

    /// Peak per group, not mean: a mean smooths away the very peak you look for.
    private func folded(_ index: Int) -> Float? {
        guard !bands.isEmpty else { return nil }
        let lower = index * bands.count / Design.Meter.barCount
        let upper = max(lower + 1, (index + 1) * bands.count / Design.Meter.barCount)
        guard lower < bands.count else { return nil }
        return bands[lower..<min(upper, bands.count)].max()
    }
}
