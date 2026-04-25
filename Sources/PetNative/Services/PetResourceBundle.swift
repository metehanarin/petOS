import Foundation

enum PetResourceBundle {
    private static let bundleName = "PetNative_PetNative.bundle"

    static var bundle: Bundle {
        if
            let resourceURL = Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            let bundle = Bundle(url: resourceURL)
        {
            return bundle
        }

        let legacyURL = Bundle.main.bundleURL.appendingPathComponent(bundleName)
        if let bundle = Bundle(url: legacyURL) {
            return bundle
        }

        return Bundle.module
    }
}
