import Testing
@testable import Karaoke

/// Phase 1 smoke tests. These prove the test target is wired to the app target
/// and that Swift Testing runs; the real suites arrive with Phase 3.
@Suite("Setup")
struct SetupSmokeTests {
    @Test("Test target links the app target")
    func appTargetIsLinked() {
        // Referencing an app-target symbol is the assertion: this fails to
        // compile if @testable import or the target dependency is broken.
        _ = RootView()
    }
}
