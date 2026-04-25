import Foundation

enum PetResourceBundle {
    private static let bundleName = "PetNative_PetNative.bundle"

    static var bundle: Bundle {
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent(bundleName),
           let bundle = bundleIfPresent(at: resourceURL)
        {
            return bundle
        }

        let legacyURL = Bundle.main.bundleURL.appendingPathComponent(bundleName)
        if let bundle = bundleIfPresent(at: legacyURL) {
            return bundle
        }

        if Bundle.main.bundlePath.hasSuffix(".app") {
            NSLog("[PetNative] missing packaged resource bundle: \(bundleName)")
            return Bundle.main
        }

        return Bundle.module
    }

    private static func bundleIfPresent(at url: URL) -> Bundle? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return nil
        }

        return Bundle(url: url)
    }
}
