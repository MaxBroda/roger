import AppKit
import RogerCore
import SwiftUI

/// The log: what was dictated, when, and what the dictionary changed. That last
/// line is the actual point — a text that is right looks exactly like one that
/// was never wrong.
struct TranscriptLogView: View {
    let history: HistoryStore
    let query: String

    var body: some View {
        RecessedPanel("Verlauf", padding: 0) {
            if records.isEmpty {
                EmptyPanelHint(
                    text: history.records.isEmpty
                        ? "Noch nichts diktiert. Halte die Taste, oder drücke Aufnahme."
                        : "Kein Eintrag passt zur Suche."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                            if index > 0 { FieldDivider() }
                            TranscriptRow(record: record) { history.remove(id: record.id) }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var records: [DictationRecord] {
        history.search(query)
    }
}

private struct TranscriptRow: View {
    let record: DictationRecord
    let onDelete: () -> Void

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            HStack(spacing: Design.Space.md) {
                Text(record.recordedAt.formatted(date: .abbreviated, time: .standard))
                    .textStyle(Design.Typography.timestamp)
                    .foregroundStyle(Design.Palette.textSecondary)
                EquipmentLabel("\(record.wordCount) Wörter")
                Spacer()
                Button(didCopy ? "Kopiert" : "Kopieren") { copy() }
                    .buttonStyle(GhostButtonStyle(tint: didCopy ? Design.Palette.accentAmber : Design.Palette.controlText))
                Button("Löschen", action: onDelete)
                    .buttonStyle(GhostButtonStyle(tint: Design.Palette.textSecondary))
            }

            Text(record.text)
                .textStyle(Design.Typography.body)
                .foregroundStyle(Design.Palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if !record.corrections.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(record.corrections, id: \.self) { correction in
                        HStack(spacing: Design.Space.xs) {
                            Text("▸")
                            Text(correction.description)
                        }
                        .textStyle(Design.Typography.timestamp)
                        .foregroundStyle(Design.Palette.accentAmber)
                    }
                }
            }
        }
        .padding(Design.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.text, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            didCopy = false
        }
    }
}

/// Deliberately faint: an empty list is a state, not an error.
struct EmptyPanelHint: View {
    let text: String

    var body: some View {
        Text(text)
            .textStyle(Design.Typography.body)
            .foregroundStyle(Design.Palette.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(Design.Space.xxl)
    }
}
