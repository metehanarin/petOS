import Foundation
import SwiftUI

struct PetDebugSnapshot: Codable {
    var debugEnabled: Bool
    var worldState: WorldState
    var currentMood: PetMood
    var preferences: PetPreferences
    var age: Int
    var reactionHistory: [PetEvent]
}

@MainActor
final class PetAppModel: ObservableObject {
    @Published private(set) var worldState: WorldState
    @Published private(set) var currentMood: PetMood
    @Published private(set) var age: Int
    @Published var soundEnabled: Bool
    @Published private(set) var swipeMeowEnabled: Bool
    @Published private(set) var reactionServerEnabled: Bool
    @Published private(set) var alwaysOnTop: Bool
    @Published private(set) var latestReaction: PetEvent?
    @Published private(set) var reactionVariant: ReactionVariant = .pulse
    @Published private(set) var reactionToken: UUID?
    @Published private(set) var notificationToken: UUID?

    let debugEnabled: Bool

    private let persistence: PetPersistence
    private let windowManager: PetWindowManager
    private let notificationAlertWindow: TimeInterval
    private lazy var monitorCoordinator = PetMonitorCoordinator(model: self, persistence: persistence)
    private var notificationClearTask: Task<Void, Never>?
    private var debugLogTask: Task<Void, Never>?
    private var reactionServer: ReactionServer?
    private var debugMoodOverride: PetMood?
    private var started = false
    private static var globalStarted = false
    private let audioService = PetAudioService()
    private lazy var gestureMonitor = PetGestureMonitor { [weak self] in
        self?.handleMeowGesture()
    }
    private var lastMeowAt: Date?

    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        persistence: PetPersistence = PetPersistence(),
        notificationAlertWindow: TimeInterval = AppConstants.notificationAlertWindow
    ) {
        self.persistence = persistence
        windowManager = PetWindowManager(persistence: persistence)
        self.notificationAlertWindow = notificationAlertWindow

        let snapshot = persistence.currentSnapshot
        let preferences = snapshot.preferences
        let worldState = WorldState.default
        self.worldState = worldState
        currentMood = PetMoodEngine.resolveBaseMood(for: worldState)
        age = snapshot.age
        soundEnabled = preferences.soundEnabled
        swipeMeowEnabled = preferences.swipeMeowEnabled
        reactionServerEnabled = preferences.reactionServerEnabled
        alwaysOnTop = preferences.alwaysOnTop
        debugEnabled = arguments.contains("--debug")
    }

    func start() {
        guard !started else {
            return
        }

        if Self.globalStarted {
            NSLog("[PetNative] PetAppModel.start() called but another instance already started monitors; skipping.")
            started = true
            return
        }

        started = true
        Self.globalStarted = true
        age = persistence.syncAge()
        updateTimeOfDay()
        monitorCoordinator.start()
        applyReactionServerPreference()
        applySwipeMeowPreference()
        startDebugLoggingIfNeeded()
        recomputeMood()
    }

    func stop() {
        monitorCoordinator.stop()
        gestureMonitor.stop()
        notificationClearTask?.cancel()
        debugLogTask?.cancel()
        reactionServer?.stop()
        reactionServer = nil
        persistence.saveLastSeen()
        started = false
    }

    func attachWindow(_ window: NSWindow) {
        windowManager.attach(window: window)
        windowManager.setAlwaysOnTop(alwaysOnTop)
    }

    func recenterWindow() {
        windowManager.recenter()
    }

    func resetPet() {
        persistence.reset()
        age = persistence.currentSnapshot.age
        let preferences = persistence.currentSnapshot.preferences
        soundEnabled = preferences.soundEnabled
        swipeMeowEnabled = preferences.swipeMeowEnabled
        reactionServerEnabled = preferences.reactionServerEnabled
        alwaysOnTop = preferences.alwaysOnTop
        notificationClearTask?.cancel()
        clearDebugMoodOverride()
        latestReaction = nil
        reactionToken = nil
        notificationToken = nil
        worldState = .default
        applyReactionServerPreference()
        applySwipeMeowPreference()
        windowManager.setAlwaysOnTop(alwaysOnTop)
        updateTimeOfDay()
        recomputeMood()
        recenterWindow()
    }

    func toggleSound() {
        soundEnabled = persistence.toggleSoundEnabled()
    }

    func setSoundEnabled(_ value: Bool) {
        soundEnabled = persistence.setSoundEnabled(value)
    }

    func setSwipeMeowEnabled(_ value: Bool) {
        swipeMeowEnabled = persistence.setSwipeMeowEnabled(value)
        applySwipeMeowPreference()
    }

    func setReactionServerEnabled(_ value: Bool) {
        reactionServerEnabled = persistence.setReactionServerEnabled(value)
        applyReactionServerPreference()
    }

    func setAlwaysOnTop(_ value: Bool) {
        alwaysOnTop = persistence.setAlwaysOnTop(value)
        windowManager.setAlwaysOnTop(alwaysOnTop)
    }

    func updateTimeOfDay(now: Date = .now) {
        let hour = Calendar.current.component(.hour, from: now)
        updateWorldState { state in
            state.hour = hour
            state.sunPhase = SunPhase.resolve(for: hour)
        }
    }

    func updateWorldState(_ mutation: (inout WorldState) -> Void) {
        mutation(&worldState)
        recomputeMood()
    }

    func enqueueReaction(type: String, priority: Int = 50, payload: [String: PetJSONValue] = [:]) {
        enqueueReaction(PetEvent(type: type, priority: priority, payload: payload))
    }

    func enqueueReaction(_ event: PetEvent) {
        worldState.events = Array((worldState.events + [event]).suffix(AppConstants.reactionHistoryLimit))
        persistence.recordReaction(event)
        latestReaction = event
        reactionVariant = PetMoodEngine.reactionVariant(for: event)
        reactionToken = UUID()
        recomputeMood()
    }

    func reloadSprites() {
        PetSpriteCatalog.clearCache()
        // Nudge UI by updating world state without changing semantics
        updateWorldState { state in
            state.hour = state.hour
        }
    }

    func cycleDebugMood() {
        guard debugEnabled else {
            return
        }

        let nextMood: PetMood?
        if let debugMoodOverride, let currentIndex = PetMood.allCases.firstIndex(of: debugMoodOverride) {
            let nextIndex = currentIndex + 1
            nextMood = PetMood.allCases.indices.contains(nextIndex) ? PetMood.allCases[nextIndex] : nil
        } else {
            nextMood = PetMood.allCases.first
        }

        debugMoodOverride = nextMood
        recomputeMood()
    }

    func clearDebugMoodOverride() {
        debugMoodOverride = nil
        recomputeMood()
    }

    var debugSnapshot: PetDebugSnapshot {
        let snapshot = persistence.currentSnapshot
        return PetDebugSnapshot(
            debugEnabled: debugEnabled,
            worldState: worldState,
            currentMood: currentMood,
            preferences: snapshot.preferences,
            age: age,
            reactionHistory: Array(snapshot.reactionHistory.suffix(20))
        )
    }

    var isReactionServerRunning: Bool {
        reactionServer != nil
    }

    func applyNotificationDelivery(_ delivery: NotificationDelivery) {
        let alertUntil = Date().addingTimeInterval(notificationAlertWindow)
        updateWorldState { state in
            state.notifications = NotificationState(
                alertUntil: alertUntil,
                lastBundleID: delivery.bundleID,
                lastDeliveredAt: delivery.timestamp,
                source: "usernoted-\(delivery.deliveryState)"
            )
        }
        notificationToken = UUID()

        notificationClearTask?.cancel()
        notificationClearTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(for: .seconds(self.notificationAlertWindow))

            self.updateWorldState { state in
                if state.notifications.alertUntil == alertUntil {
                    state.notifications.alertUntil = nil
                }
            }
        }
    }

    func handleMeowGesture() {
        NSLog("[PetNative] pet interaction received; soundEnabled=\(soundEnabled)")

        guard soundEnabled else {
            return
        }

        let now = Date()
        if let lastMeowAt, now.timeIntervalSince(lastMeowAt) < AppConstants.meowDebounceInterval {
            return
        }

        lastMeowAt = now
        audioService.playRandomSound()
    }

    private func recomputeMood() {
        currentMood = debugMoodOverride ?? PetMoodEngine.resolveBaseMood(for: worldState)
    }

    private func startReactionServer() {
        guard reactionServer == nil else {
            return
        }

        let reactionServer = ReactionServer { [weak self] event in
            Task { @MainActor [weak self] in
                self?.enqueueReaction(event)
            }
        }

        do {
            try reactionServer.start()
            self.reactionServer = reactionServer
        } catch {
            NSLog("[PetNative] reaction server failed to start: \(error.localizedDescription)")
        }
    }

    private func applyReactionServerPreference() {
        guard started else {
            return
        }

        if reactionServerEnabled {
            startReactionServer()
        } else {
            reactionServer?.stop()
            reactionServer = nil
        }
    }

    private func applySwipeMeowPreference() {
        guard started else {
            return
        }

        if swipeMeowEnabled {
            gestureMonitor.start()
        } else {
            gestureMonitor.stop()
        }
    }

    private func startDebugLoggingIfNeeded() {
        guard debugEnabled, debugLogTask == nil else {
            return
        }

        debugLogTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }

                self.logDebugSnapshot()

                do {
                    try await Task.sleep(for: .seconds(AppConstants.debugPollInterval))
                } catch {
                    return
                }
            }
        }
    }

    private func logDebugSnapshot() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(debugSnapshot), let json = String(data: data, encoding: .utf8) else {
            return
        }

        NSLog("[PetNative] debug snapshot: \(json)")
    }
}
