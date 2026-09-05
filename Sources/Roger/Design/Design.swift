import AppKit
import SwiftUI

/// Roger's design system: field radio — olive drab, matte black, stencilled
/// lettering. Red transmits, amber indicates.
///
/// No value belongs in a view. If one is missing, add it here. Tables in
/// `docs/design-tokens.md`.
public enum Design {}

public extension Design {
    /// One fixed set — no light/dark switch.
    enum Palette {
        public static let background = Color(hex: 0x2A2E22)
        public static let surface = Color(hex: 0x1E2218)
        public static let surfaceBorder = Color(hex: 0x3A4030)
        public static let titlebar = Color(hex: 0x232820)

        public static let textPrimary = Color(hex: 0xC8D4A8)
        public static let textSecondary = Color(hex: 0x5A6A48)
        public static let textDim = Color(hex: 0x6A7A58)

        public static let accentRed = Color(hex: 0xC04030)
        public static let accentRedDark = Color(hex: 0x802820)
        public static let accentAmber = Color(hex: 0xD4A030)

        public static let levelGreen = Color(hex: 0x6A8A30)
        public static let levelGreenBright = Color(hex: 0x8AA040)
        public static let levelAmber = Color(hex: 0xD4A030)
        public static let levelRed = Color(hex: 0xC04030)

        public static let controlBackground = Color(hex: 0x3A4030)
        public static let controlText = Color(hex: 0x8A9A78)
        public static let controlBorder = Color(hex: 0x4A5A40)
    }
}

public extension Design {
    /// Font, tracking and casing belong together — a stencilled label without
    /// its tracking is no longer one.
    struct TextStyle: Sendable {
        public let font: Font
        public let tracking: CGFloat
        public let isUppercase: Bool
    }

    /// Monospaced only.
    enum Typography {
        public static let windowTitle = TextStyle(
            font: Families.body(11), tracking: 1.1, isUppercase: true
        )
        public static let label = TextStyle(
            font: Families.stencil(9), tracking: 1.35, isUppercase: true
        )
        public static let status = TextStyle(
            font: Families.stencil(12), tracking: 1.44, isUppercase: true
        )
        public static let body = TextStyle(
            font: Families.body(13), tracking: 0, isUppercase: false
        )
        public static let button = TextStyle(
            font: Families.stencil(11), tracking: 1.1, isUppercase: true
        )
        public static let timestamp = TextStyle(
            font: Families.body(10), tracking: 0.6, isUppercase: false
        )
        public static let readout = TextStyle(
            font: Families.stencil(22), tracking: 2.2, isUppercase: true
        )
        public static let field = TextStyle(
            font: Families.body(12), tracking: 0, isUppercase: false
        )
    }

    /// Share Tech Mono and IBM Plex Mono are not on every Mac. Rather than
    /// falling back to a proportional face, the list is tried in order and ends
    /// at the system monospace.
    enum Families {
        static func stencil(_ size: CGFloat) -> Font {
            font(named: stencilName, size: size)
        }

        static func body(_ size: CGFloat) -> Font {
            font(named: bodyName, size: size)
        }

        private static func font(named name: String?, size: CGFloat) -> Font {
            guard let name else { return .system(size: size, design: .monospaced) }
            return .custom(name, size: size)
        }

        /// `nil` means none found — the system takes over.
        static let stencilName: String? = firstAvailable([
            "Share Tech Mono", "ShareTechMono-Regular",
            "IBM Plex Mono", "IBMPlexMono-Regular",
        ])

        static let bodyName: String? = firstAvailable([
            "IBM Plex Mono", "IBMPlexMono-Regular",
            "Menlo",
        ])

        private static func firstAvailable(_ names: [String]) -> String? {
            names.first { NSFont(name: $0, size: 12) != nil }
        }
    }
}

public extension Design {
    enum Space {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 20
        public static let xxl: CGFloat = 24

        /// Its own value: a button has to be graspable, not as tall as the gap
        /// beside it.
        public static let buttonVertical: CGFloat = 10
        public static let buttonVerticalCompact: CGFloat = 6
    }

    enum Radius {
        public static let sm: CGFloat = 4
        public static let md: CGFloat = 8
        public static let bar: CGFloat = 1
    }

    /// The window edge is deliberately absent — it belongs to macOS. Our own
    /// frame breaks off at the rounded system corner.
    enum Border {
        public static let hairline: CGFloat = 1
    }

    enum Elevation {
        public static let buttonDepth: CGFloat = 2
        public static let bubbleRadius: CGFloat = 14
        public static let bubbleOffset: CGFloat = 5
        public static let bubbleOpacity: Double = 0.5
    }

    /// No springs, no bounce — equipment indicates, it does not animate.
    enum Motion {
        /// Linear and about three of the 33 ms analysis steps long: the bars
        /// glide through the steps instead of snapping and easing on every one.
        public static let meter = Animation.linear(duration: 0.11)
        public static let indicate = Animation.easeInOut(duration: 0.15)
        public static let blinkPeriod: Double = 1.5
    }

    enum Emphasis {
        public static let disabled: Double = 0.4
        public static let highlight: Double = 0.5
    }

    /// SF Symbols enter the layout as type, not as images — their size belongs
    /// here and not with the spacing.
    enum Icon {
        public static let hint: CGFloat = 9
        public static let field: CGFloat = 10
    }

    /// One resolution for both displays: the analysis runs once per audio buffer.
    /// It follows the finer of the two — the bubble — and the level meter folds
    /// it down to its bars.
    enum Spectrum {
        public static let bandCount = 20
    }

    enum Meter {
        public static let barCount = 14
        public static let barWidth: CGFloat = 6
        public static let barGap: CGFloat = 3
        public static let maxHeight: CGFloat = 48
        /// Not zero: an empty grid reads as crashed, not as silent.
        public static let minHeight: CGFloat = 3

        public static func color(at index: Int) -> Color {
            switch index {
            case ..<7: Palette.levelGreen
            case ..<10: Palette.levelGreenBright
            case ..<12: Palette.levelAmber
            default: Palette.levelRed
            }
        }
    }

    /// The bubble during dictation — the declared exception to the motion and
    /// colour rules. It appears unasked over other apps' windows and has to read
    /// as a bubble there, not as a glitch.
    enum Bubble {
        /// Opaque, not translucent: see-through over someone else's content reads
        /// as interference.
        public static let fill = Color(white: 0.05)
        /// Without an edge the bubble vanishes on a dark background.
        public static let rim = Color.white.opacity(0.13)
        public static let bar = Color.white
        /// The sweep while transcribing indicates work, not loudness.
        public static let sweepOpacity: Double = 0.75

        /// One dial for all of it, instead of six separate values.
        public static let scale: CGFloat = 0.92

        public static var barWidth: CGFloat { 2.5 * scale }
        public static var barSpacing: CGFloat { 2 * scale }
        public static var barMinHeight: CGFloat { 3 * scale }
        public static var barMaxHeight: CGFloat { 20 * scale }

        public static var horizontalPadding: CGFloat { 16 * scale }
        public static var verticalPadding: CGFloat { 11 * scale }

        /// Tight, no spring here — otherwise the deflection smears.
        public static let bars = Animation.easeOut(duration: 0.07)

        /// Opening: width leads, height follows. Two springs with different
        /// timings are what produces the squash.
        public static let openWidth = Animation.spring(response: 0.30, dampingFraction: 0.50)
        public static let openHeight = Animation.spring(response: 0.42, dampingFraction: 0.62)

        /// Closing: height drops first, width follows.
        public static let closeWidth = Animation.spring(response: 0.26, dampingFraction: 0.85)
        public static let closeHeight = Animation.spring(response: 0.18, dampingFraction: 0.90)

        /// Not zero: a remnant stays, otherwise closing looks like a crash.
        public static let collapsedWidthScale: CGFloat = 0.22
        public static let collapsedHeightScale: CGFloat = 0.28

        public static let fadeIn = Animation.easeOut(duration: 0.12)
        public static let fadeOut = Animation.easeOut(duration: 0.20)

        /// Must outlast the closing motion, or the bubble vanishes abruptly
        /// instead of folding away.
        public static let collapseDuration = Duration.milliseconds(420)
    }

    enum Indicator {
        public static let size: CGFloat = 8
        public static let glowRadius: CGFloat = 4
    }
}

public extension View {
    func textStyle(_ style: Design.TextStyle) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .textCase(style.isUppercase ? .uppercase : nil)
    }
}

extension Color {
    /// `sRGB` explicitly: the palette values are sRGB hex, and SwiftUI's default
    /// is not sRGB everywhere.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
