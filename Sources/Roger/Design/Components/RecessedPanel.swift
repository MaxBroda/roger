import SwiftUI

/// A recessed surface from two flat tones and a hairline — a punched sheet
/// metal window, not a gradient.
struct RecessedPanel<Content: View>: View {
    private let label: String?
    private let padding: CGFloat
    private let content: Content

    init(
        _ label: String? = nil,
        padding: CGFloat = Design.Space.lg,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label {
                // The label keeps its own inset: with `padding: 0` — lists that
                // scroll to the edge — it would stick to the frame.
                EquipmentLabel(label)
                    .padding(.horizontal, Design.Space.lg)
                    .padding(.top, Design.Space.md)
                    .padding(.bottom, Design.Space.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            content
                .padding(padding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous)
                .strokeBorder(Design.Palette.surfaceBorder, lineWidth: Design.Border.hairline)
        }
    }
}

struct FieldDivider: View {
    var body: some View {
        Rectangle()
            .fill(Design.Palette.surfaceBorder)
            .frame(height: Design.Border.hairline)
    }
}
