import Testing
@testable import petOS

struct PetLaunchPreflightTests {
    @Test
    func bundledExecutionRequiresAppBundlePath() {
        #expect(PetLaunchPreflight.isBundledExecution(bundlePath: "/tmp/petOS.app"))
        #expect(PetLaunchPreflight.isBundledExecution(bundlePath: "/Applications/petOS.app"))
        #expect(!PetLaunchPreflight.isBundledExecution(bundlePath: "/tmp/petOS"))
        #expect(!PetLaunchPreflight.isBundledExecution(bundlePath: "/tmp/.build/debug/petOS"))
    }
}
