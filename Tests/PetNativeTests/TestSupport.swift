import Foundation
@testable import PetNative

enum PetTestSupport {
    static func makeState(_ update: (inout WorldState) -> Void = { _ in }) -> WorldState {
        var state = WorldState.default
        state.idle = 0
        state.system = .default
        state.battery = .default
        state.focus = .default
        state.activity = .default
        state.music = .default
        state.notifications = .default
        state.events = []
        state.cpu = 0
        state.thermal = .nominal
        update(&state)
        return state
    }

    static func temporaryFileURL(name: String = UUID().uuidString) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PetNativeTests", isDirectory: true)
            .appendingPathComponent("\(name).json")
    }

    @MainActor
    static func waitUntil(
        timeout: TimeInterval = 1,
        pollInterval: TimeInterval = 0.01,
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if condition() {
                return true
            }

            try? await Task.sleep(for: .seconds(pollInterval))
        }

        return condition()
    }
}
