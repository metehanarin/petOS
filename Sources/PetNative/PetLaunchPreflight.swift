import Foundation
import Darwin

enum PetLaunchPreflight {
    /// Aborts with EX_CONFIG (78) if the binary is executed outside an .app bundle.
    static func enforceBundledExecution() {
        let path = Bundle.main.bundlePath
        if isBundledExecution(bundlePath: path) {
            return
        }

        fputs(
            """
            [PetNative] FATAL: this binary must be launched from an .app bundle.
            Use ./tools/run.sh (dev) or ./tools/build-release.sh (release).
            Detected bundle path: \(path)

            """,
            stderr
        )
        exit(78)
    }

    static func isBundledExecution(bundlePath: String) -> Bool {
        bundlePath.hasSuffix(".app")
    }
}
