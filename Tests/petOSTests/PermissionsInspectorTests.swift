import Foundation
import Testing
@testable import petOS

struct PermissionsInspectorTests {
    @Test
    func snapshotProducesAllThreeStatusFields() {
        let snapshot = PermissionsInspector.snapshot()

        // We can't assert specific values (depends on host TCC state) - just
        // verify the snapshot returns plausible enum cases for all three.
        let validStatuses: Set<PermissionsSnapshot.Status> = [.granted, .denied, .notDetermined, .unknown]
        #expect(validStatuses.contains(snapshot.focusStatus))
        #expect(validStatuses.contains(snapshot.accessibility))
        #expect(validStatuses.contains(snapshot.fullDiskAccess))
    }

    @Test
    func paneURLsMatchExpectedSystemSettingsRoutes() {
        #expect(
            PermissionsInspector.systemSettingsURL(for: .focus)?.absoluteString ==
                "x-apple.systempreferences:com.apple.Focus-Settings.extension"
        )
        #expect(
            PermissionsInspector.systemSettingsURL(for: .accessibility)?.absoluteString ==
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        #expect(
            PermissionsInspector.systemSettingsURL(for: .fullDiskAccess)?.absoluteString ==
                "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        )
    }
}
