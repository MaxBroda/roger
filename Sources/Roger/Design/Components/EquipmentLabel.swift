import SwiftUI

/// A stencilled label: small, tracked, uppercase. It names a surface —
/// `SIGNAL LEVEL`, not "this is where you see the level".
struct EquipmentLabel: View {
    let text: String
    var color: Color = Design.Palette.textSecondary

    init(_ text: String, color: Color = Design.Palette.textSecondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .textStyle(Design.Typography.label)
            .foregroundStyle(color)
    }
}

/// A value that changes at runtime. Amber, like every live reading here.
struct Readout: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            EquipmentLabel(caption)
            Text(value)
                .textStyle(Design.Typography.readout)
                .foregroundStyle(Design.Palette.accentAmber)
                .monospacedDigit()
        }
    }
}
