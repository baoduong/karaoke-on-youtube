import SwiftUI

/// The app's visual language.
///
/// Dark-first, because the room is dark: this is used at parties, often with
/// the lights down. Light mode exists but is the secondary case.
///
/// The accent is warm rather than the system blue. Blue reads as "utility
/// app"; this is meant to feel like a piece of party equipment, and a warm
/// accent also stays legible against the video thumbnails that dominate most
/// screens.
enum Theme {

    // MARK: Colour

    enum Palette {
        /// Near-black rather than pure black so elevated surfaces can be seen
        /// against it without borders.
        static let background = Color(red: 0.055, green: 0.055, blue: 0.067)
        static let surface = Color(red: 0.102, green: 0.106, blue: 0.125)
        static let surfaceRaised = Color(red: 0.145, green: 0.149, blue: 0.176)

        static let accent = Color(red: 1.0, green: 0.706, blue: 0.251)
        static let accentDim = Color(red: 0.631, green: 0.443, blue: 0.157)

        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.62)
        static let textTertiary = Color.white.opacity(0.38)

        /// Content-side problems: the song is unusable, the singer picks
        /// another. Red-orange, distinct in hue from `accent` (amber) so
        /// "selected" and "content problem" are not confused (FR-021).
        /// Previously `rgb(0.95, 0.64, 0.22)` — the same amber hue as `accent`
        /// — which made the two states look alike.
        static let contentIssue = Color(red: 1.0, green: 0.42, blue: 0.20)
        /// Mechanism-side problems: our code stopped working. Red, because
        /// someone has to fix it.
        ///
        /// Re-check against the new `contentIssue` (red-orange). If the two
        /// read alike, move this to `Color(red: 1.0, green: 0.27, blue: 0.33)`
        /// — a cooler red that sits clearly apart from the red-orange above.
        static let mechanismIssue = Color(red: 0.91, green: 0.33, blue: 0.33)
        /// The label colour for text and glyphs placed on a filled accent
        /// control. White on the amber accent measures about 1.9:1 and fails
        /// the 4.5:1 contrast floor (FR-023). This value equals `background`
        /// and measures about 10.9:1 against the accent.
        static let onAccent = Color(red: 0.055, green: 0.055, blue: 0.067)
        static let success = Color(red: 0.36, green: 0.78, blue: 0.52)
    }

    // MARK: Spacing

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
    }

    /// Minimum 44pt is Apple's floor; the primary transport control is larger
    /// because it is pressed one-handed while holding a microphone.
    enum Hit {
        static let minimum: CGFloat = 44
        static let control: CGFloat = 56
        static let primaryControl: CGFloat = 76
    }

    // MARK: Typography tokens

    /// A typographic role expressed as data rather than as a `Font`.
    ///
    /// Constraints (FR-015):
    /// - `baseSize` MUST be at least 13. Smaller text is unreadable in a dim
    ///   room at arm's length.
    /// - `weight` MUST NOT be lighter than `.regular`. Thin strokes disappear
    ///   in a dim room.
    ///
    /// Roles are resolved to a `Font` inside a `ViewModifier` via
    /// `@ScaledMetric(relativeTo:)` — see `Theme.Typography` and
    /// `TypographyModifier`. They MUST NOT be exposed as `static let Font`
    /// values because `@ScaledMetric` is a `DynamicProperty` and only resolves
    /// inside a view (contract C-T2).
    struct TypeToken: Sendable, Equatable {
        let baseSize: CGFloat
        let weight: Font.Weight
        let design: Font.Design
        let relativeTo: Font.TextStyle
        let maxDynamicTypeSize: DynamicTypeSize?

        init(
            baseSize: CGFloat,
            weight: Font.Weight,
            design: Font.Design = .default,
            relativeTo: Font.TextStyle,
            maxDynamicTypeSize: DynamicTypeSize? = nil
        ) {
            self.baseSize = baseSize
            self.weight = weight
            self.design = design
            self.relativeTo = relativeTo
            self.maxDynamicTypeSize = maxDynamicTypeSize
        }
    }

    // MARK: Named scale

    enum Typography {
        // Text roles
        static let displayTitle  = TypeToken(baseSize: 28, weight: .bold,     relativeTo: .title,      maxDynamicTypeSize: .xxxLarge)
        static let screenTitle   = TypeToken(baseSize: 22, weight: .bold,     relativeTo: .title2)
        static let rowTitle      = TypeToken(baseSize: 17, weight: .semibold,  relativeTo: .headline)
        static let body          = TypeToken(baseSize: 17, weight: .regular,   relativeTo: .body)
        static let bodyEmphasis  = TypeToken(baseSize: 17, weight: .semibold,  relativeTo: .body)
        static let secondary     = TypeToken(baseSize: 15, weight: .regular,   relativeTo: .subheadline)
        static let caption       = TypeToken(baseSize: 13, weight: .medium,    relativeTo: .caption)
        /// Monospaced so digits do not jitter as the timecode counts.
        static let timecode      = TypeToken(baseSize: 17, weight: .semibold,  design: .monospaced, relativeTo: .body)

        // Glyph roles
        static let glyphPrimary   = TypeToken(baseSize: 30, weight: .semibold, relativeTo: .title,      maxDynamicTypeSize: .xxxLarge)
        static let glyphTransport = TypeToken(baseSize: 26, weight: .semibold, relativeTo: .title2,     maxDynamicTypeSize: .xxxLarge)
        static let glyphStatus    = TypeToken(baseSize: 32, weight: .semibold, relativeTo: .title)
        static let glyphEmpty     = TypeToken(baseSize: 44, weight: .regular,  relativeTo: .largeTitle)
    }
}

// MARK: - Typography resolver

/// Resolves a `Theme.TypeToken` to a scaled `Font` using `@ScaledMetric`.
///
/// `@ScaledMetric` reads `@Environment(\.dynamicTypeSize)` and applies the
/// same non-linear curve Apple uses internally, so the resulting font honours
/// `.dynamicTypeSize(...)`, Xcode previews, and subtree clamping.
/// `Font.system(size:weight:design:)` alone does NOT scale — it is only
/// correct here because `@ScaledMetric` supplies an already-scaled size.
private struct TypographyModifier: ViewModifier {
    let token: Theme.TypeToken

    @ScaledMetric private var scaledSize: CGFloat

    init(token: Theme.TypeToken) {
        self.token = token
        _scaledSize = ScaledMetric(wrappedValue: token.baseSize, relativeTo: token.relativeTo)
    }

    func body(content: Content) -> some View {
        if let cap = token.maxDynamicTypeSize {
            content
                .font(.system(size: scaledSize, weight: token.weight, design: token.design))
                .dynamicTypeSize(...cap)
        } else {
            content
                .font(.system(size: scaledSize, weight: token.weight, design: token.design))
        }
    }
}

extension View {
    /// Applies a typographic role from `Theme.Typography`.
    ///
    /// Usage: `.font(Theme.Typography.rowTitle)`
    func font(_ token: Theme.TypeToken) -> some View {
        modifier(TypographyModifier(token: token))
    }
}

// MARK: - Reusable surfaces

/// A raised content block. Used instead of plain list rows so screens read as
/// panels rather than settings tables.
struct CardBackground: ViewModifier {
    var color: Color = Theme.Palette.surface
    var radius: CGFloat = Theme.Radius.md

    func body(content: Content) -> some View {
        content
            .background(color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func card(_ color: Color = Theme.Palette.surface, radius: CGFloat = Theme.Radius.md) -> some View {
        modifier(CardBackground(color: color, radius: radius))
    }
}

// MARK: - Section heading

struct SectionHeading: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
    }
}

// MARK: - Empty state

/// Every empty state in the app uses this, so absence looks deliberate rather
/// than broken. A new install has no history and an unplayed queue is
/// install genuinely has no history — those are normal, not faults.
struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: icon)
                .font(Theme.Typography.glyphEmpty)
                .foregroundStyle(Theme.Palette.textTertiary)
            Text(title)
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Palette.textSecondary)
            if let message {
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 320)
        .padding(Theme.Space.xl)
    }
}

// MARK: - Duration formatting

extension Int {
    /// Seconds as m:ss, the form every music interface uses.
    var asDurationLabel: String {
        let minutes = self / 60
        let seconds = self % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

extension Double {
    var asDurationLabel: String {
        guard isFinite, self >= 0 else { return "0:00" }
        return Int(self).asDurationLabel
    }
}
