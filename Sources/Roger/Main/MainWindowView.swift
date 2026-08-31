import RogerCore
import SwiftUI

/// The front panel: control head on top, band switch between log and dictionary
/// below.
struct MainWindowView: View {
    let app: RogerApp

    enum Section: Hashable { case log, dictionary }

    @State private var section: Section = .log
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            VStack(spacing: Design.Space.xl) {
                ControlHeadView(app: app)
                selector
                content
            }
            .padding(Design.Space.xl)
        }
        .background(Design.Palette.background)
        .frame(minWidth: 780, minHeight: 540)
    }

    /// The left inset leaves room for the three system buttons — they sit on the
    /// transparent title bar.
    private var titleBar: some View {
        HStack(spacing: Design.Space.md) {
            Text("Roger · Felddiktiergerät")
                .textStyle(Design.Typography.windowTitle)
                .foregroundStyle(Design.Palette.textPrimary)
            Spacer()
            IndicatorLight(mode: app.isRecording ? .transmitting : (app.isRunning ? .active : .off))
        }
        .padding(.leading, 82)
        .padding(.trailing, Design.Space.xl)
        .frame(height: 38)
        .background(Design.Palette.titlebar)
        .overlay(alignment: .bottom) { FieldDivider() }
    }

    private var selector: some View {
        HStack(spacing: Design.Space.lg) {
            SegmentedSelector(
                options: [(.log, "Verlauf"), (.dictionary, "Wörterbuch")],
                selection: $section
            )
            .frame(width: 260)

            FieldTextField(
                placeholder: section == .log ? "Verlauf durchsuchen" : "Wörterbuch durchsuchen",
                text: $query,
                symbol: "magnifyingglass"
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .log:
            TranscriptLogView(history: app.history, query: query)
        case .dictionary:
            DictionaryPanelView(store: app.dictionary, query: query)
        }
    }
}
