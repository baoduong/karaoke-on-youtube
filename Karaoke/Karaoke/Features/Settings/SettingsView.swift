// T082, T132, T135 — SettingsView.
//
// T132: Link to SigningValidityView (FR-036).
// T135: Companion service address field and provider-preference control (T134).
//
// Satisfies: FR-020, FR-022, FR-024, FR-036

import SwiftUI
import SwiftData

struct SettingsView: View {

    @Bindable var settings: PerformanceSettings
    @AppStorage(CompanionSourceProvider.addressKey) private var companionAddress: String = ""
    @AppStorage("companionPreferred") private var companionPreferred: Bool = false

    @State private var companionReachability: CompanionReachability = .notConfigured

    private let companionProvider = CompanionSourceProvider()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                                    volumeSection
                        companionSection
                        appSection
                    }
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.bottom, Theme.Space.xl)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Theme.Palette.background, for: .navigationBar)
            .task(id: companionAddress) {
                await checkCompanionReachability()
            }
        }
    }


    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeading(title: "Volume")

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    Text("Output Volume")
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Spacer()
                    Text(String(format: "%.0f%%", settings.outputVolume * 100))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .monospacedDigit()
                }

                Slider(
                    value: $settings.outputVolume,
                    in: PerformanceSettings.outputVolumeRange
                )
                .tint(Theme.Palette.accent)
                .frame(minHeight: Theme.Hit.minimum)
            }
            .padding(Theme.Space.md)
            .card(Theme.Palette.surface)
        }
    }

    // MARK: 4. Companion Service Section

    private var companionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeading(title: "Companion Service")
                reachabilityIndicator
            }

            VStack(alignment: .leading, spacing: Theme.Space.md) {
                TextField(
                    "",
                    text: $companionAddress,
                    prompt: Text("http://192.168.1.x:7979")
                        .foregroundStyle(Theme.Palette.textTertiary)
                )
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.horizontal, Theme.Space.md)
                .frame(height: Theme.Hit.minimum)
                .card(Theme.Palette.surfaceRaised, radius: Theme.Radius.sm)

                Toggle("Prefer companion over on-device", isOn: $companionPreferred)
                    .tint(Theme.Palette.accent)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .frame(minHeight: Theme.Hit.minimum)
                    .onChange(of: companionPreferred) { _, preferred in
                        NotificationCenter.default.post(
                            name: .companionPreferenceChanged,
                            object: preferred
                        )
                    }

                Text("The companion service resolves audio server-side. Use it when on-device resolution breaks.")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .padding(Theme.Space.md)
            .card(Theme.Palette.surface)

            Text("Run Tools/companion-service/run.sh on your Mac. Enter the Mac's local IP address above.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .padding(.horizontal, Theme.Space.xs)
        }
    }

    private var reachabilityIndicator: some View {
        HStack(spacing: Theme.Space.xs) {
            Circle()
                .fill(companionReachability.dotColor)
                .frame(width: 8, height: 8)
            Text(companionReachability.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(companionReachability.textColor)
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, Theme.Space.xs)
        .background(Theme.Palette.surface, in: Capsule())
    }

    private func checkCompanionReachability() async {
        let trimmed = companionAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            companionReachability = .notConfigured
            return
        }
        companionReachability = .checking
        let health = await companionProvider.healthCheck()
        guard !Task.isCancelled else { return }
        switch health {
        case .healthy:
            companionReachability = .reachable
        case .unhealthy:
            companionReachability = .unreachable
        }
    }

    // MARK: 5. App Section

    /// Sideloaded signatures expire after 7 days on free developer accounts;
    /// surfacing a warning directly on the Settings row when few days remain
    /// prevents a surprise launch failure during a party (FR-036).
    private var appSection: some View {
        let remainingDays = signingDaysRemaining
        let isExpiringSoon = (remainingDays ?? 999) <= 7
        let isCritical = (remainingDays ?? 999) <= 3

        return VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeading(title: "App")

            NavigationLink {
                SigningValidityView()
            } label: {
                HStack(spacing: Theme.Space.md) {
                    if isExpiringSoon {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(isCritical ? Theme.Palette.mechanismIssue : Theme.Palette.contentIssue)
                    }

                    Text("Signing Validity")
                        .foregroundStyle(Theme.Palette.textPrimary)

                    Spacer()

                    if let days = remainingDays {
                        Text("\(days)d remaining")
                            .font(.subheadline.weight(isExpiringSoon ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(signingBadgeColor(days: days))
                            .padding(.horizontal, Theme.Space.sm)
                            .padding(.vertical, Theme.Space.xs)
                            .background(signingBadgeColor(days: days).opacity(0.16), in: Capsule())
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                .padding(Theme.Space.md)
                .frame(minHeight: Theme.Hit.control)
                .card(Theme.Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(
                            isExpiringSoon
                                ? (isCritical ? Theme.Palette.mechanismIssue.opacity(0.6) : Theme.Palette.contentIssue.opacity(0.6))
                                : .clear,
                            lineWidth: isExpiringSoon ? 1.5 : 0
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var signingDaysRemaining: Int? {
        guard let expiry = SigningValidityView.readExpiryDate() else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
        return max(0, days)
    }

    private func signingBadgeColor(days: Int) -> Color {
        if days <= 3 {
            return Theme.Palette.mechanismIssue
        } else if days <= 7 {
            return Theme.Palette.contentIssue
        } else {
            return Theme.Palette.success
        }
    }
}

// MARK: - CompanionReachability

private enum CompanionReachability: Equatable {
    case notConfigured
    case checking
    case reachable
    case unreachable

    var label: String {
        switch self {
        case .notConfigured: return "Not configured"
        case .checking:      return "Checking…"
        case .reachable:     return "Reachable"
        case .unreachable:   return "Unreachable"
        }
    }

    var dotColor: Color {
        switch self {
        case .notConfigured: return Theme.Palette.textTertiary
        case .checking:      return Theme.Palette.accent
        case .reachable:     return Theme.Palette.success
        case .unreachable:   return Theme.Palette.mechanismIssue
        }
    }

    var textColor: Color {
        switch self {
        case .notConfigured: return Theme.Palette.textTertiary
        case .checking:      return Theme.Palette.textSecondary
        case .reachable:     return Theme.Palette.success
        case .unreachable:   return Theme.Palette.mechanismIssue
        }
    }
}

extension Notification.Name {
    static let companionPreferenceChanged = Notification.Name("companionPreferenceChanged")
}
