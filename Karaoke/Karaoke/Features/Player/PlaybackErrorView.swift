// T060, T125 — PlaybackErrorView.
//
// T060: Words content-side failures as the singer's situation and mechanism-side
//       failures distinctly, per FR-008.
// T125: When no network and the song is unsaved, fail clearly within 3 s —
//       never hang (FR-032). The .offlineUnsaved case is distinct from .offline
//       so the singer knows exactly what to do: save the song first.
//
// Satisfies: FR-008, FR-032

import SwiftUI

// MARK: - PlaybackErrorView

/// Presents a playback error to the singer.
///
/// Content-side and mechanism-side failures have deliberately different visual
/// layouts and colour treatments (FR-008):
/// - **Content-side** (`Theme.Palette.contentIssue`, warm amber): the upload or
///   network condition prevents playing *this* song, so nothing in the app is
///   broken. The card is calm and makes **Pick Another Song** the primary
///   one-handed action so the party keeps moving.
/// - **Mechanism-side** (`Theme.Palette.mechanismIssue`, red): our resolution
///   or audio pipeline failed. It is explicitly badged as an app fault with a
///   diagnostic callout, and makes **Try Again** the primary action.
struct PlaybackErrorView: View {

    let error: PlaybackError
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            VStack {
                Spacer()

                if isMechanismSide {
                    mechanismErrorCard
                } else {
                    contentErrorCard
                }

                Spacer()
            }
            .padding(Theme.Space.lg)
        }
    }

    // MARK: - Content-Side Card (Amber, Calm, Action = Pick Another Song)

    private var contentErrorCard: some View {
        VStack(spacing: Theme.Space.lg) {
            Text("SONG ISSUE")
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(Theme.Palette.contentIssue)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, Theme.Space.xs)
                .background(Theme.Palette.contentIssue.opacity(0.16), in: Capsule())

            ZStack {
                Circle()
                    .fill(Theme.Palette.contentIssue.opacity(0.15))
                    .frame(width: 72, height: 72)

                Image(systemName: iconName)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Theme.Palette.contentIssue)
            }

            VStack(spacing: Theme.Space.sm) {
                Text(errorTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.center)

                Text(errorMessage)
                    .font(.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Theme.Space.sm) {
                if let dismiss = onDismiss {
                    Button(action: dismiss) {
                        HStack(spacing: Theme.Space.sm) {
                            Image(systemName: "magnifyingglass")
                            Text("Pick Another Song")
                        }
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Hit.control)
                        .background(
                            Theme.Palette.contentIssue,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let retry = onRetry {
                    Button(action: retry) {
                        Text("Try Again")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: Theme.Hit.minimum)
                            .card(Theme.Palette.surfaceRaised)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: 400)
        .card(Theme.Palette.surface, radius: Theme.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.Palette.contentIssue.opacity(0.45), lineWidth: 1.5)
        )
    }

    // MARK: - Mechanism-Side Card (Red, App Fault, Action = Retry)

    private var mechanismErrorCard: some View {
        VStack(spacing: Theme.Space.lg) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.caption2.weight(.bold))
                Text("APP FAULT")
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
            }
            .foregroundStyle(Theme.Palette.mechanismIssue)
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.xs)
            .background(Theme.Palette.mechanismIssue.opacity(0.18), in: Capsule())

            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Palette.mechanismIssue.opacity(0.16))
                    .frame(width: 72, height: 72)

                Image(systemName: iconName)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Theme.Palette.mechanismIssue)
            }

            VStack(spacing: Theme.Space.sm) {
                Text(errorTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.center)

                Text(errorMessage)
                    .font(.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }

            mechanismSideNote

            VStack(spacing: Theme.Space.sm) {
                if let retry = onRetry {
                    Button(action: retry) {
                        HStack(spacing: Theme.Space.sm) {
                            Image(systemName: "arrow.clockwise")
                            Text("Try Again")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Hit.control)
                        .background(
                            Theme.Palette.mechanismIssue,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let dismiss = onDismiss {
                    Button(action: dismiss) {
                        Text("Dismiss")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: Theme.Hit.minimum)
                            .card(Theme.Palette.surfaceRaised)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: 400)
        .card(Theme.Palette.surface, radius: Theme.Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.Palette.mechanismIssue.opacity(0.75), lineWidth: 2)
        )
    }

    // MARK: Icon & Classification

    private var iconName: String {
        switch error {
        case .contentUnavailable: return "nosign"
        case .mechanismFailed:    return "wrench.and.screwdriver"
        case .offline:            return "wifi.slash"
        case .offlineUnsaved:     return "arrow.down.circle.dotted"
        case .unsupportedFormat:  return "waveform.slash"
        case .audioError:         return "speaker.slash"
        }
    }

    private var errorTitle: String {
        switch error {
        case .contentUnavailable:
            return "Song Not Available"
        case .mechanismFailed:
            return "Playback Unavailable"
        case .offline:
            return "No Connection"
        case .offlineUnsaved:
            return "Song Not Saved"
        case .unsupportedFormat:
            return "Format Not Supported"
        case .audioError:
            return "Playback Error"
        }
    }

    private var errorMessage: String {
        switch error {
        case .contentUnavailable(let reason):
            return reason
        case .mechanismFailed:
            return "The resolution mechanism is temporarily unavailable. This is a technical issue, not a problem with the song."
        case .offline:
            return "Check your network connection and try again."
        case .offlineUnsaved:
            return "This song hasn't been saved for offline use. Connect to the internet, or save the song first."
        case .unsupportedFormat(let codec, let container):
            return "This song uses \(codec) in \(container), which this device cannot play. The app will try a different quality."
        case .audioError(let detail):
            return detail
        }
    }

    /// Distinguishes app/pipeline faults from song/environment conditions so the UI
    /// directs the user to either retry/inspect diagnostics or pick another song.
    private var isMechanismSide: Bool {
        switch error {
        case .mechanismFailed, .audioError:
            return true
        case .contentUnavailable, .offline, .offlineUnsaved, .unsupportedFormat:
            return false
        }
    }

    // MARK: Mechanism-side note

    private var mechanismSideNote: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Theme.Palette.mechanismIssue)
            Text("This is a technical issue. Check the diagnostic log for details.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.md)
        .card(Theme.Palette.surfaceRaised, radius: Theme.Radius.sm)
    }
}
