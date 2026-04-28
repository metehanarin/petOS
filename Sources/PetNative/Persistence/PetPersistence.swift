import Foundation

struct PersistedPetState: Codable {
    var age: Int
    var position: PetPosition?
    var lastSeen: Date?
    var preferences: PetPreferences
    var cachedTopApps: [String]
    var reactionHistory: [PetEvent]

    var soundEnabled: Bool {
        get {
            preferences.soundEnabled
        }
        set {
            preferences.soundEnabled = newValue
        }
    }

    static var `default`: PersistedPetState {
        PersistedPetState(
            age: 0,
            position: nil,
            lastSeen: nil,
            preferences: .default,
            cachedTopApps: AppConstants.defaultTopApps,
            reactionHistory: []
        )
    }

    init(
        age: Int,
        position: PetPosition?,
        lastSeen: Date?,
        preferences: PetPreferences,
        cachedTopApps: [String],
        reactionHistory: [PetEvent]
    ) {
        self.age = age
        self.position = position
        self.lastSeen = lastSeen
        self.preferences = preferences
        self.cachedTopApps = cachedTopApps
        self.reactionHistory = reactionHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        age = try container.decodeIfPresent(Int.self, forKey: .age) ?? Self.default.age
        position = try container.decodeIfPresent(PetPosition.self, forKey: .position)
        lastSeen = try container.decodeIfPresent(Date.self, forKey: .lastSeen)

        if let decodedPreferences = try container.decodeIfPresent(PetPreferences.self, forKey: .preferences) {
            preferences = decodedPreferences
        } else {
            var migratedPreferences = PetPreferences.default
            if let legacySoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) {
                migratedPreferences.soundEnabled = legacySoundEnabled
            }
            preferences = migratedPreferences
        }

        cachedTopApps = try container.decodeIfPresent([String].self, forKey: .cachedTopApps) ?? Self.default.cachedTopApps
        reactionHistory = try container.decodeIfPresent([PetEvent].self, forKey: .reactionHistory) ?? Self.default.reactionHistory
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(age, forKey: .age)
        try container.encodeIfPresent(position, forKey: .position)
        try container.encodeIfPresent(lastSeen, forKey: .lastSeen)
        try container.encode(preferences, forKey: .preferences)
        try container.encode(cachedTopApps, forKey: .cachedTopApps)
        try container.encode(reactionHistory, forKey: .reactionHistory)
    }

    private enum CodingKeys: String, CodingKey {
        case age
        case position
        case lastSeen
        case soundEnabled
        case preferences
        case cachedTopApps
        case reactionHistory
    }
}

final class PetPersistence {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager
    private let fileURL: URL
    private var snapshot: PersistedPetState
    private var debouncedFlushWorkItem: DispatchWorkItem?

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        if let fileURL {
            self.fileURL = fileURL
        } else {
            let applicationSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
                URL(fileURLWithPath: NSTemporaryDirectory())
            let containerURL = applicationSupportDirectory
                .appendingPathComponent("PetNative", isDirectory: true)
            self.fileURL = containerURL.appendingPathComponent("state.json")
        }

        let loadedSnapshot: PersistedPetState
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? decoder.decode(PersistedPetState.self, from: data)
        {
            loadedSnapshot = decoded
        } else {
            loadedSnapshot = .default
        }

        snapshot = loadedSnapshot
    }

    var currentSnapshot: PersistedPetState {
        snapshot
    }

    @discardableResult
    func syncAge(now: Date = .now) -> Int {
        let currentAge = snapshot.age

        guard let lastSeen = snapshot.lastSeen else {
            snapshot.lastSeen = now
            flush()
            return currentAge
        }

        let calendar = Calendar.current
        let lastSeenStart = calendar.startOfDay(for: lastSeen)
        let nowStart = calendar.startOfDay(for: now)
        let elapsedDays = max(0, calendar.dateComponents([.day], from: lastSeenStart, to: nowStart).day ?? 0)

        if elapsedDays > 0 {
            snapshot.age = currentAge + elapsedDays
        }

        snapshot.lastSeen = now
        flush()
        return snapshot.age
    }

    func savePosition(_ position: CGPoint) {
        snapshot.position = PetPosition(position)
        debouncedFlush()
    }

    func saveLastSeen(_ date: Date = .now) {
        snapshot.lastSeen = date
        flush()
    }

    @discardableResult
    func toggleSoundEnabled() -> Bool {
        snapshot.preferences.soundEnabled.toggle()
        flush()
        return snapshot.preferences.soundEnabled
    }

    @discardableResult
    func setSoundEnabled(_ value: Bool) -> Bool {
        snapshot.preferences.soundEnabled = value
        flush()
        return value
    }

    @discardableResult
    func setSwipeSoundEnabled(_ value: Bool) -> Bool {
        snapshot.preferences.swipeSoundEnabled = value
        flush()
        return value
    }

    @discardableResult
    func setReactionServerEnabled(_ value: Bool) -> Bool {
        snapshot.preferences.reactionServerEnabled = value
        flush()
        return value
    }

    @discardableResult
    func setAlwaysOnTop(_ value: Bool) -> Bool {
        snapshot.preferences.alwaysOnTop = value
        flush()
        return value
    }

    @discardableResult
    func saveCachedTopApps(_ topApps: [String]) -> [String] {
        let normalizedTopApps = topApps.isEmpty ? AppConstants.defaultTopApps : topApps
        snapshot.cachedTopApps = normalizedTopApps
        flush()
        return normalizedTopApps
    }

    @discardableResult
    func recordReaction(_ reaction: PetEvent) -> [PetEvent] {
        snapshot.reactionHistory = Array((snapshot.reactionHistory + [reaction]).suffix(AppConstants.reactionHistoryLimit))
        flush()
        return snapshot.reactionHistory
    }

    func reset() {
        snapshot = .default
        snapshot.lastSeen = .now
        flush()
    }

    /// Coalesces rapid writes (e.g. window drag) into a single disk write
    /// after the specified delay. If a new debounced flush arrives before the
    /// previous fires, the previous is cancelled.
    private func debouncedFlush(delay: TimeInterval = 0.3) {
        debouncedFlushWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.flush()
        }
        debouncedFlushWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func flush() {
        debouncedFlushWorkItem?.cancel()
        debouncedFlushWorkItem = nil

        let directoryURL = fileURL.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[PetNative] persistence write failed: \(error.localizedDescription)")
        }
    }
}
