import Foundation
import Testing
@testable import PetNative

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
    func paneURLsAreNonNil() {
        #expect(PermissionsInspector.systemSettingsURL(for: .focus) != nil)
        #expect(PermissionsInspector.systemSettingsURL(for: .accessibility) != nil)
        #expect(PermissionsInspector.systemSettingsURL(for: .fullDiskAccess) != nil)
    }
}
