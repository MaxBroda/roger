import SwiftUI

/// A button with travel instead of effect: pressing moves the face down by
/// exactly the shadow height and the shadow disappears.
struct FieldButtonStyle: ButtonStyle {
    enum Role {
        case primary
        case secondary
        case destructive
    }

    let role: Role
    var isCompact = false

    func makeBody(configuration: Configuration) -> some View {
        let depth = Design.Elevation.buttonDepth
        let pressed = configuration.isPressed

        return configuration.label
            .textStyle(Design.Typography.button)
            .foregroundStyle(foreground)
            .padding(.horizontal, isCompact ? Design.Space.md : Design.Space.xxl)
            .padding(.vertical, isCompact ? Design.Space.buttonVerticalCompact : Design.Space.buttonVertical)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Design.Radius.sm, style: .continuous)
                    .strokeBorder(border, lineWidth: Design.Border.hairline)
            }
            .offset(y: pressed ? depth : 0)
            .background(alignment: .bottom) {
                // A second, lower body in the dark variant of the button colour —
                // not a blurred drop shadow.
                RoundedRectangle(cornerRadius: Design.Radius.sm, style: .continuous)
                    .fill(shadow)
                    .padding(.top, depth)
                    .offset(y: pressed ? 0 : depth)
            }
            .animation(Design.Motion.indicate, value: pressed)
            .contentShape(Rectangle())
    }

    private var background: Color {
        switch role {
        case .primary, .destructive: Design.Palette.accentRed
        case .secondary: Design.Palette.controlBackground
        }
    }

    private var foreground: Color {
        switch role {
        case .primary, .destructive: .white
        case .secondary: Design.Palette.controlText
        }
    }

    private var border: Color {
        switch role {
        case .primary, .destructive: Design.Palette.accentRedDark
        case .secondary: Design.Palette.controlBorder
        }
    }

    private var shadow: Color {
        switch role {
        case .primary, .destructive: Design.Palette.accentRedDark
        case .secondary: Design.Palette.surfaceBorder
        }
    }
}

extension View {
    func fieldButton(_ role: FieldButtonStyle.Role, compact: Bool = false) -> some View {
        buttonStyle(FieldButtonStyle(role: role, isCompact: compact))
    }
}

/// A button without a housing, where a full one would overwhelm the row.
struct GhostButtonStyle: ButtonStyle {
    var tint: Color = Design.Palette.controlText

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(Design.Typography.label)
            .foregroundStyle(configuration.isPressed ? Design.Palette.textPrimary : tint)
            .padding(.horizontal, Design.Space.sm)
            .padding(.vertical, Design.Space.xs)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.sm, style: .continuous)
                    .fill(Design.Palette.controlBackground.opacity(configuration.isPressed ? 1 : 0))
            )
            .contentShape(Rectangle())
    }
}
