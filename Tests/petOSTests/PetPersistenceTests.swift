import Foundation
import Testing
@testable import petOS

struct PetPersistenceTests {
    @Test
    func defaultPreferencesAreLoaded() {
        let fileURL = PetTestSupport.temporaryFileURL()
        let persistence = PetPersistence(fileURL: fileURL)

        #expect(persistence.currentSnapshot.preferences == .default)
        #expect(persistence.currentSnapshot.soundEnabled == false)
    }

    @Test
    func syncAgeAdvancesByElapsedDays() {
        let fileURL = PetTestSupport.temporaryFileURL()
        let persistence = PetPersistence(fileURL: fileURL)
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(persistence.syncAge(now: baseDate) == 0)
        #expect(persistence.syncAge(now: baseDate.addingTimeInterval(2 * 24 * 60 * 60)) == 2)
    }

    @Test
    func saveCachedTopAppsFallsBackToDefaults() {
        let fileURL = PetTestSupport.temporaryFileURL()
        let persistence = PetPersistence(fileURL: fileURL)

        #expect(persistence.saveCachedTopApps([]) == AppConstants.defaultTopApps)
    }

    @Test
    func toggleSoundEnabledPersistsValue() {
        let fileURL = PetTestSupport.temporaryFileURL()
        let persistence = PetPersistence(fileURL: fileURL)

        #expect(persistence.currentSnapshot.soundEnabled == false)
        #expect(persistence.toggleSoundEnabled() == true)
        #expect(persistence.currentSnapshot.soundEnabled == true)
    }

    @Test
    func preferenceSettersPersistValues() {
        let fileURL = PetTestSupport.temporaryFileURL()
        let persistence = PetPersistence(fileURL: fileURL)

        #expect(persistence.setSoundEnabled(true) == true)
        #expect(persistence.setSwipeSoundEnabled(false) == false)
        #expect(persistence.setReactionServerEnabled(false) == false)
        #expect(persistence.setAlwaysOnTop(false) == false)

        let reloadedPersistence = PetPersistence(fileURL: fileURL)
        #expect(reloadedPersistence.currentSnapshot.preferences == PetPreferences(
            soundEnabled: true,
            swipeSoundEnabled: false,
            reactionServerEnabled: false,
            alwaysOnTop: false
        ))
    }

    @Test
    func legacySoundEnabledMigratesIntoPreferences() throws {
        let fileURL = PetTestSupport.temporaryFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let legacyJSON = """
        {
          "age" : 4,
          "soundEnabled" : true,
          "cachedTopApps" : ["Xcode"],
          "reactionHistory" : []
        }
        """
        try Data(legacyJSON.utf8).write(to: fileURL, options: .atomic)

        let persistence = PetPersistence(fileURL: fileURL)
        #expect(persistence.currentSnapshot.age == 4)
        #expect(persistence.currentSnapshot.preferences == PetPreferences(
            soundEnabled: true,
            swipeSoundEnabled: true,
            reactionServerEnabled: true,
            alwaysOnTop: true
        ))
    }

    @Test
    func recordReactionTruncatesHistory() {
        let fileURL = PetTestSupport.temporaryFileURL()
        let persistence = PetPersistence(fileURL: fileURL)

        for index in 0 ..< 60 {
            _ = persistence.recordReaction(PetEvent(type: "event-\(index)"))
        }

        #expect(persistence.currentSnapshot.reactionHistory.count == AppConstants.reactionHistoryLimit)
        #expect(persistence.currentSnapshot.reactionHistory.first?.type == "event-10")
        #expect(persistence.currentSnapshot.reactionHistory.last?.type == "event-59")
    }
}
