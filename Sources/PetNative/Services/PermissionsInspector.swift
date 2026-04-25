import AppKit
import Foundation
import Intents
import ApplicationServices

struct PermissionsSnapshot: Equatable {
    enum Status: Equatable {
        case granted
        case denied
        case notDetermined
        case unknown
    }

    let focusStatus: Status
    let accessibility: Status
    let fullDiskAccess: Status
}

enum PermissionsInspector {
    enum Pane {
        case focus
        case accessibility
        case fullDiskAccess
    }

    static func snapshot() -> PermissionsSnapshot {
        PermissionsSnapshot(
            focusStatus: focusStatus(),
            accessibility: accessibilityStatus(),
            fullDiskAccess: fullDiskAccessStatus()
        )
    }

    static func openSystemSettings(for pane: Pane) {
        guard let url = systemSettingsURL(for: pane) else { return }
        NSWorkspace.shared.open(url)
    }

    static func systemSettingsURL(for pane: Pane) -> URL? {
        switch pane {
        case .focus:
            return URL(string: "x-apple.systempreferences:com.apple.preference.notifications?Focus")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .fullDiskAccess:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        }
    }

    private static func focusStatus() -> PermissionsSnapshot.Status {
        switch INFocusStatusCenter.default.authorizationStatus {
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .unknown
        }
    }

    private static func accessibilityStatus() -> PermissionsSnapshot.Status {
        // AXIsProcessTrusted does NOT prompt; safe to call from a status query.
        AXIsProcessTrusted() ? .granted : .denied
    }

    private static func fullDiskAccessStatus() -> PermissionsSnapshot.Status {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/DoNotDisturb/DB/Assertions.json")
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            _ = try handle.read(upToCount: 1)
            return .granted
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoPermissionError {
                return .denied
            }
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoSuchFileError {
                return .unknown
            }
            let message = error.localizedDescription.lowercased()
            if message.contains("operation not permitted") || message.contains("permission denied") {
                return .denied
            }
            return .unknown
        }
    }
}
