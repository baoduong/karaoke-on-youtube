import SwiftUI

/// Throwaway measurement app for spikes S5 and S0.
///
/// Not part of the Karaoke target. It exists to turn two `[prior]` findings in
/// research.md into measurements, per Constitution Principle III, and should be
/// deleted once both are recorded.
@main
struct RouteProbeApp: App {
    var body: some Scene {
        WindowGroup {
            ProbeView()
        }
    }
}
