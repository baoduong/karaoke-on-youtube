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
        /// another. Amber, because nothing is broken.
        static let contentIssue = Color(red: 0.95, green: 0.64, blue: 0.22)
        /// Mechanism-side problems: our code stopped working. Red, because
        /// someone has to fix it.
        static let mechanismIssue = Color(red: 0.91, green: 0.33, blue: 0.33)
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
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.subheadline)
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
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.Palette.textTertiary)
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.Palette.textSecondary)
            if let message {
                Text(message)
                    .font(.subheadline)
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
