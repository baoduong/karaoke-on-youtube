// T132 — SigningValidityView.
//
// Shows remaining code-signature validity and how to restore it (FR-036).
// Sideloaded apps expire after 7 days (AltStore free) or 365 days (paid/developer).
// The singer must know in advance so expiry is a scheduled chore, not a mystery
// failure in front of guests.
//
// Satisfies: FR-036

import SwiftUI

// MARK: - SigningValidityView

struct SigningValidityView: View {

    // MARK: Computed validity

    private var expiryDate: Date? { Self.readExpiryDate() }

    private var daysRemaining: Int? {
        guard let expiry = expiryDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
        return max(0, days)
    }

    var body: some View {
        List {
            Section {
                validityRow
            }

            Section("How to restore") {
                restoreInstructions
            }
        }
        .navigationTitle("App Signing")
    }

    // MARK: Validity row

    private var validityRow: some View {
        HStack {
            Label("Validity", systemImage: "signature")
            Spacer()
            validityBadge
        }
    }

    @ViewBuilder
    private var validityBadge: some View {
        if let days = daysRemaining {
            if days <= 3 {
                Text("\(days)d remaining")
                    .foregroundStyle(.red)
                    .fontWeight(.semibold)
            } else if days <= 7 {
                Text("\(days)d remaining")
                    .foregroundStyle(.orange)
            } else {
                Text("\(days)d remaining")
                    .foregroundStyle(.green)
            }
        } else {
            Text("Unknown")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Restore instructions

    private var restoreInstructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This app is sideloaded and its signature expires periodically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                instructionStep(number: 1, text: "Open AltStore on your iPhone.")
                instructionStep(number: 2, text: "Tap \"My Apps\" and find Karaoke.")
                instructionStep(number: 3, text: "Tap \"Refresh\" to re-sign the app.")
                instructionStep(number: 4, text: "Your data and settings are preserved.")
            }

            Text("AltStore refreshes automatically when your iPhone and Mac are on the same Wi-Fi network.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number).")
                .fontWeight(.semibold)
                .frame(width: 20, alignment: .leading)
            Text(text)
        }
        .font(.subheadline)
    }

    // MARK: Expiry reading

    /// Reads the provisioning profile's expiry date from the embedded profile.
    ///
    /// The profile is a CMS-signed plist embedded in the app bundle. We read
    /// the raw bytes, find the plist payload between the CMS wrapper, and parse
    /// `ExpirationDate`. Returns nil when running in the simulator (no profile)
    /// or when the profile cannot be parsed.
    static func readExpiryDate() -> Date? {
        guard let profileURL = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: profileURL) else {
            return nil
        }

        // The plist is embedded between the CMS header and footer.
        // Find the plist start marker.
        guard let plistStart = data.range(of: Data("<?xml".utf8)),
              let plistEnd = data.range(of: Data("</plist>".utf8)) else {
            return nil
        }

        let plistRange = plistStart.lowerBound ..< plistEnd.upperBound
        let plistData = data.subdata(in: plistRange)

        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let expiry = plist["ExpirationDate"] as? Date else {
            return nil
        }

        return expiry
    }
}
