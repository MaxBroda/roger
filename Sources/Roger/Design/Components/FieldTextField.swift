import SwiftUI

/// A recessed text field: `TextField` brings a light rounded well on macOS,
/// switched off (`.plain`) and replaced by the surface used everywhere else.
struct FieldTextField: View {
    let placeholder: String
    @Binding var text: String
    var symbol: String?
    var onSubmit: (() -> Void)?

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Design.Space.sm) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: Design.Icon.field, weight: .medium))
                    .foregroundStyle(Design.Palette.textSecondary)
            }
            TextField("", text: $text, prompt: prompt)
                .textFieldStyle(.plain)
                .textStyle(Design.Typography.field)
                .foregroundStyle(Design.Palette.textPrimary)
                .focused($isFocused)
                .onSubmit { onSubmit?() }
        }
        .padding(.horizontal, Design.Space.md)
        .padding(.vertical, Design.Space.sm)
        .background(Design.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Design.Radius.md, style: .continuous)
                .strokeBorder(
                    isFocused ? Design.Palette.accentAmber.opacity(0.7) : Design.Palette.surfaceBorder,
                    lineWidth: Design.Border.hairline
                )
        }
        .animation(Design.Motion.indicate, value: isFocused)
    }

    private var prompt: Text {
        Text(placeholder)
            .font(Design.Typography.field.font)
            .foregroundColor(Design.Palette.textSecondary)
    }
}

/// A checkbox without system chrome: a box that is filled or not.
struct FieldCheckbox: View {
    @Binding var isOn: Bool
    var label: String?

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: Design.Space.sm) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isOn ? Design.Palette.accentAmber : .clear)
                    .frame(width: Design.Icon.field + 2, height: Design.Icon.field + 2)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(
                                isOn ? Design.Palette.accentAmber : Design.Palette.controlBorder,
                                lineWidth: Design.Border.hairline
                            )
                    }
                if let label {
                    Text(label)
                        .textStyle(Design.Typography.button)
                        .foregroundStyle(isOn ? Design.Palette.textPrimary : Design.Palette.controlText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Design.Motion.indicate, value: isOn)
    }
}
