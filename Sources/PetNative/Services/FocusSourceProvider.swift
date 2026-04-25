import Foundation

@MainActor
protocol FocusSourceProvider: AnyObject {
    /// Returns a descriptor parsed from `~/Library/DoNotDisturb/DB/Assertions.json`,
    /// or `nil` if no active mode / unable to read. May mutate internal state to
    /// remember "permanently denied" so subsequent calls short-circuit.
    func readAssertionsFile() -> FocusModeDescriptor?

    /// Returns a descriptor parsed from Control Center via Accessibility, or `nil`.
    func scrapeControlCenter() -> FocusModeDescriptor?

    /// Returns `(authorized, isFocused)` from `INFocusStatusCenter`. May trigger
    /// the system authorization prompt on first call.
    func queryInFocusStatus() async -> (authorized: Bool, isFocused: Bool)
}

final class LiveFocusSourceProvider: FocusSourceProvider {
    weak var coordinator: PetMonitorCoordinator?

    init(coordinator: PetMonitorCoordinator? = nil) {
        self.coordinator = coordinator
    }

    func readAssertionsFile() -> FocusModeDescriptor? {
        coordinator?.liveReadAssertionsFile()
    }

    func scrapeControlCenter() -> FocusModeDescriptor? {
        coordinator?.liveScrapeControlCenter()
    }

    func queryInFocusStatus() async -> (authorized: Bool, isFocused: Bool) {
        await coordinator?.liveQueryInFocusStatus() ?? (false, false)
    }
}
