import Testing
@testable import PetNative

struct PetLaunchPreflightTests {
    @Test
    func bundledExecutionRequiresAppBundlePath() {
        #expect(PetLaunchPreflight.isBundledExecution(bundlePath: "/tmp/PetNative.app"))
        #expect(PetLaunchPreflight.isBundledExecution(bundlePath: "/Applications/PetNative.app"))
        #expect(!PetLaunchPreflight.isBundledExecution(bundlePath: "/tmp/PetNative"))
        #expect(!PetLaunchPreflight.isBundledExecution(bundlePath: "/tmp/.build/debug/PetNative"))
    }
}
