import RogerCore
import SwiftUI

/// The control head: what Roger is doing, how loud it comes in, and the two
/// buttons that drive it by hand.
struct ControlHeadView: View {
    let app: RogerApp

    var body: some View {
        VStack(spacing: Design.Space.lg) {
            HStack(alignment: .top, spacing: Design.Space.lg) {
                statusPanel
                meterPanel
            }
            controlRow
        }
    }

    private var statusPanel: some View {
        RecessedPanel("Status") {
            VStack(alignment: .leading, spacing: Design.Space.md) {
                HStack(spacing: Design.Space.sm) {
                    IndicatorLight(mode: indicatorMode)
                    Text(app.statusLine)
                        .textStyle(Design.Typography.status)
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
                HStack(spacing: Design.Space.lg) {
                    detail("Taste", KeyNames.description(of: app.hotkey))
                    detail("Sprache", app.activeLocale?.nativeDisplayName ?? "—")
                }
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            EquipmentLabel(label)
            Text(value)
                .textStyle(Design.Typography.timestamp)
                .foregroundStyle(Design.Palette.textDim)
                .lineLimit(1)
        }
    }

    private var indicatorMode: IndicatorLight.Mode {
        if app.isRecording { return .transmitting }
        return app.isRunning ? .active : .off
    }

    private var statusColor: Color {
        if case .failed = app.state { return Design.Palette.accentRed }
        if app.isRecording { return Design.Palette.accentRed }
        return Design.Palette.accentAmber
    }

    private var meterPanel: some View {
        MeterPanel(app: app)
    }

    private var controlRow: some View {
        HStack(spacing: Design.Space.md) {
            Button {
                app.startDictation()
            } label: {
                Text("● Aufnahme")
            }
            .fieldButton(.primary)
            .disabled(!app.canRecord)
            .opacity(app.canRecord ? 1 : Design.Emphasis.disabled)

            Button {
                app.stopDictation()
            } label: {
                Text("■ Stopp")
            }
            .fieldButton(.secondary)
            .disabled(!app.isRecording)
            .opacity(app.isRecording ? 1 : Design.Emphasis.disabled)

            Spacer()

            Readout(value: app.history.lifetimeWords.formatted(), caption: "Wörter")
            Readout(value: app.history.records.count.formatted(), caption: "Diktate")
            Readout(value: app.dictionary.dictionary.entries.count.formatted(), caption: "Einträge")
        }
    }
}

/// Its own view because the bands arrive some fifty times a second: if the
/// control head read them, SwiftUI would re-evaluate buttons, status line and
/// counter just as often.
private struct MeterPanel: View {
    let app: RogerApp

    var body: some View {
        RecessedPanel("Pegel") {
            LevelMeter(bands: app.bands, isLive: app.isRecording)
        }
        .frame(width: width)
    }

    /// Fixed width — a level meter that rescales when you drag the window is none.
    private var width: CGFloat {
        let bars = CGFloat(Design.Meter.barCount) * Design.Meter.barWidth
        let gaps = CGFloat(Design.Meter.barCount - 1) * Design.Meter.barGap
        return bars + gaps + Design.Space.lg * 2 + 2
    }
}
