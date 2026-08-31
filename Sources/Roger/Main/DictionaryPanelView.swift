import AppKit
import RogerCore
import SwiftUI

/// The dictionary: add, edit, delete, search. Both entry kinds share one form —
/// they differ in a single field.
struct DictionaryPanelView: View {
    let store: DictionaryStore
    let query: String

    @State private var draft = Draft()

    var body: some View {
        RecessedPanel("Wörterbuch", padding: 0) {
            VStack(spacing: 0) {
                editor
                FieldDivider()
                list
                FieldDivider()
                footer
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            HStack(spacing: Design.Space.lg) {
                SegmentedSelector(
                    options: [(DictionaryEntry.Kind.term, "Begriff"), (.correction, "Korrektur")],
                    selection: $draft.kind
                )
                .frame(width: 220)
                .disabled(draft.editingID != nil)

                EquipmentLabel(draft.editingID == nil ? "Neuer Eintrag" : "Eintrag ändern")
                Spacer()
            }

            HStack(spacing: Design.Space.md) {
                if draft.kind == .correction {
                    FieldTextField(placeholder: "Gehört, z. B. cloud code", text: $draft.heard) { commit() }
                    Text("→")
                        .textStyle(Design.Typography.status)
                        .foregroundStyle(Design.Palette.textSecondary)
                }
                FieldTextField(
                    placeholder: draft.kind == .correction ? "Geschrieben, z. B. Claude Code" : "Begriff, z. B. Anthropic",
                    text: $draft.written
                ) { commit() }

                Button(draft.editingID == nil ? "Hinzufügen" : "Speichern") { commit() }
                    .fieldButton(.secondary, compact: true)
                    .disabled(provisional == nil)
                    .opacity(provisional == nil ? Design.Emphasis.disabled : 1)

                if draft.editingID != nil {
                    Button("Abbrechen") { draft = Draft() }
                        .buttonStyle(GhostButtonStyle())
                }
            }

            hints
        }
        .padding(Design.Space.lg)
    }

    /// While typing — after saving the warning would come too late.
    @ViewBuilder
    private var hints: some View {
        if let provisional {
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                ForEach(provisional.risks, id: \.self) { risk in
                    warning(risk.message)
                }
                if let existing = store.dictionary.conflict(with: provisional) {
                    warning("Für dieses Muster gibt es schon einen Eintrag: »\(existing.written.text)«. Er wird ersetzt.")
                }
            }
        }
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Design.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: Design.Icon.hint))
            Text(text)
                .textStyle(Design.Typography.timestamp)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Design.Palette.accentAmber)
    }

    @ViewBuilder
    private var list: some View {
        let entries = store.dictionary.search(query)
        if entries.isEmpty {
            EmptyPanelHint(text: query.isEmpty ? "Das Wörterbuch ist leer." : "Kein Eintrag passt zur Suche.")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { FieldDivider() }
                        DictionaryRow(
                            entry: entry,
                            isEditing: draft.editingID == entry.id,
                            onToggle: { store.setEnabled(!entry.isEnabled, for: entry.id) },
                            onEdit: { draft = Draft(entry: entry) },
                            onDelete: {
                                if draft.editingID == entry.id { draft = Draft() }
                                store.remove(id: entry.id)
                            }
                        )
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var footer: some View {
        HStack(spacing: Design.Space.md) {
            EquipmentLabel("Datei")
            Text(store.fileURL.path(percentEncoded: false))
                .textStyle(Design.Typography.timestamp)
                .foregroundStyle(Design.Palette.textDim)
                .truncationMode(.head)
                .lineLimit(1)
            Spacer(minLength: Design.Space.md)
            Button("Im Finder zeigen") {
                NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
            }
            .buttonStyle(GhostButtonStyle())
            Button("Neu laden") { store.reloadFromDisk() }
                .buttonStyle(GhostButtonStyle())
            Button("Auf Beispiel zurücksetzen") { store.resetToSeed() }
                .buttonStyle(GhostButtonStyle(tint: Design.Palette.textSecondary))
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.vertical, Design.Space.sm)
    }

    /// The entry as the form currently stands; `nil` means not saveable yet.
    private var provisional: DictionaryEntry? { draft.entry() }

    private func commit() {
        guard let entry = provisional else { return }
        store.upsert(entry)
        draft = Draft()
    }

    struct Draft {
        var kind: DictionaryEntry.Kind = .term
        var written = ""
        var heard = ""
        var editingID: UUID?
        private var createdAt = Date()

        init() {}

        init(entry: DictionaryEntry) {
            kind = entry.kind
            written = entry.written.text
            heard = entry.heard?.text ?? ""
            editingID = entry.id
            createdAt = entry.createdAt
        }

        /// Keeps identity and creation date — an edited entry is the same entry.
        func entry() -> DictionaryEntry? {
            guard let written = Phrase(written) else { return nil }
            let heard = kind == .correction ? Phrase(heard) : nil
            if kind == .correction, heard == nil { return nil }
            return DictionaryEntry(
                written: written,
                heard: heard,
                id: editingID ?? UUID(),
                createdAt: createdAt
            )
        }
    }
}

private struct DictionaryRow: View {
    let entry: DictionaryEntry
    let isEditing: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Design.Space.md) {
            FieldCheckbox(isOn: .init(get: { entry.isEnabled }, set: { _ in onToggle() }))

            EquipmentLabel(entry.kind == .term ? "Begriff" : "Korrektur")
                .frame(width: 66, alignment: .leading)

            HStack(spacing: Design.Space.sm) {
                if let heard = entry.heard {
                    Text(heard.text)
                        .textStyle(Design.Typography.body)
                        .foregroundStyle(Design.Palette.textDim)
                    Text("→")
                        .textStyle(Design.Typography.timestamp)
                        .foregroundStyle(Design.Palette.textSecondary)
                }
                Text(entry.written.text)
                    .textStyle(Design.Typography.body)
                    .foregroundStyle(Design.Palette.textPrimary)
            }
            .opacity(entry.isEnabled ? 1 : Design.Emphasis.disabled)

            if let risk = entry.risks.first {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: Design.Icon.hint))
                    .foregroundStyle(Design.Palette.accentAmber)
                    .help(risk.message)
            }

            Spacer(minLength: Design.Space.md)

            Button("Bearbeiten", action: onEdit)
                .buttonStyle(GhostButtonStyle(tint: isEditing ? Design.Palette.accentAmber : Design.Palette.controlText))
            Button("Löschen", action: onDelete)
                .buttonStyle(GhostButtonStyle(tint: Design.Palette.textSecondary))
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.vertical, Design.Space.sm)
        .background(isEditing ? Design.Palette.controlBackground.opacity(Design.Emphasis.highlight) : .clear)
    }
}
