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
/// Content-side failures are worded as the singer's situation — they can act
/// on them by choosing a different song. Mechanism-side failures are worded
/// distinctly — they require the maintainer to fix something (FR-008).
struct PlaybackErrorView: View {

    let error: PlaybackError
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            errorIcon

            VStack(spacing: 8) {
                Text(errorTitle)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(errorMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            if isMechanismSide {
                mechanismSideNote
            }

            actionButtons

            Spacer()
        }
        .padding()
    }

    // MARK: Icon

    private var errorIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: 56))
            .foregroundStyle(isMechanismSide ? .orange : .secondary)
    }

    private var iconName: String {
        switch error {
        case .contentUnavailable: return "nosign"
        case .mechanismFailed: return "wrench.and.screwdriver"
        case .offline: return "wifi.slash"
        case .offlineUnsaved: return "arrow.down.circle.dotted"
        case .unsupportedFormat: return "waveform.slash"
        case .audioError: return "speaker.slash"
        }
    }

    // MARK: Text

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

    private var isMechanismSide: Bool {
        if case .mechanismFailed = error { return true }
        return false
    }

    // MARK: Mechanism-side note

    private var mechanismSideNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.orange)
            Text("This is a technical issue. Check the diagnostic log for details.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    // MARK: Action buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if let retry = onRetry {
                Button("Try Again") {
                    retry()
                }
                .buttonStyle(.borderedProminent)
            }

            if let dismiss = onDismiss {
                Button("Dismiss") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
