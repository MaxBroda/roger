import SwiftUI

/// A band switch, not a tab bar: the active position sits lower and glows amber.
struct SegmentedSelector<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                segment(option)
                    // An overlay, not its own view: a `Rectangle` without height
                    // would stretch the switch to the full remaining height.
                    .overlay(alignment: .leading) {
                        if index > 0 {
                            Rectangle()
                                .fill(Design.Palette.surfaceBorder)
                                .frame(width: Design.Border.hairline)
                        }
                    }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Design.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Design.Radius.sm, style: .continuous)
                .strokeBorder(Design.Palette.surfaceBorder, lineWidth: Design.Border.hairline)
        }
    }

    private func segment(_ option: (value: Value, label: String)) -> some View {
        let isActive = option.value == selection
        return Button {
            selection = option.value
        } label: {
            Text(option.label)
                .textStyle(Design.Typography.label)
                .foregroundStyle(isActive ? Design.Palette.accentAmber : Design.Palette.textSecondary)
                .padding(.horizontal, Design.Space.lg)
                .padding(.vertical, Design.Space.sm)
                .frame(maxWidth: .infinity)
                .background(isActive ? Design.Palette.controlBackground : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
