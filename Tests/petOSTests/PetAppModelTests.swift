import Foundation
import Testing
@testable import petOS

struct PetAppModelTests {
    @MainActor
    @Test
    func preferenceSettersUpdateModelAndPersistence() {
        let fileURL = PetTestSupport.temporaryFileURL()
        let persistence = PetPersistence(fileURL: fileURL)
        let model = PetAppModel(arguments: [], persistence: persistence)

        model.setSoundEnabled(true)
        model.setSwipeSoundEnabled(false)
        model.setReactionServerEnabled(false)
        model.setAlwaysOnTop(false)

        #expect(model.soundEnabled == true)
        #expect(model.swipeSoundEnabled == false)
        #expect(model.reactionServerEnabled == false)
        #expect(model.alwaysOnTop == false)
        #expect(PetPersistence(fileURL: fileURL).currentSnapshot.preferences == PetPreferences(
            soundEnabled: true,
            swipeSoundEnabled: false,
            reactionServerEnabled: false,
            alwaysOnTop: false
        ))
    }

    @MainActor
    @Test
    func reactionServerDisabledPreferenceDoesNotStartServerWhileStopped() {
        let persistence = PetPersistence(fileURL: PetTestSupport.temporaryFileURL())
        let model = PetAppModel(arguments: [], persistence: persistence)

        model.setReactionServerEnabled(false)

        #expect(model.reactionServerEnabled == false)
        #expect(model.isReactionServerRunning == false)
    }

    @MainActor
    @Test
    func enqueueReactionCapsEventHistory() {
        let persistence = PetPersistence(fileURL: PetTestSupport.temporaryFileURL())
        let model = PetAppModel(arguments: [], persistence: persistence)

        for index in 0 ..< 60 {
            model.enqueueReaction(type: "event-\(index)")
        }

        #expect(model.worldState.events.count == AppConstants.reactionHistoryLimit)
        #expect(model.worldState.events.first?.type == "event-10")
        #expect(model.worldState.events.last?.type == "event-59")
    }

    @MainActor
    @Test
    func sleepFocusUpdateImmediatelyChangesCurrentMood() {
        let persistence = PetPersistence(fileURL: PetTestSupport.temporaryFileURL())
        let model = PetAppModel(arguments: [], persistence: persistence)

        model.updateWorldState { state in
            state.hour = 14
            state.focus = .default
            state.music.playing = true
        }

        #expect(model.currentMood == .dancing)

        model.updateWorldState { state in
            state.focus = FocusState(
                active: true,
                authorized: true,
                modeIdentifier: "com.apple.focus.sleep",
                modeName: "Sleep",
                source: "named-mode"
            )
        }

        #expect(model.currentMood == .sleeping)
    }

    @MainActor
    @Test
    func descriptorlessActiveFocusUpdateChangesCurrentMoodToSleeping() {
        let persistence = PetPersistence(fileURL: PetTestSupport.temporaryFileURL())
        let model = PetAppModel(arguments: [], persistence: persistence)

        model.updateWorldState { state in
            state.hour = 14
            state.focus = .default
            state.music.playing = true
        }

        #expect(model.currentMood == .dancing)

        model.updateWorldState { state in
            state.focus = FocusState(
                active: true,
                authorized: true,
                modeIdentifier: nil,
                modeName: nil,
                source: "status"
            )
        }

        #expect(model.currentMood == .sleeping)
    }

    @MainActor
    @Test
    func midnightTimeUpdateDoesNotTriggerSleepingWithoutFocusMode() {
        let persistence = PetPersistence(fileURL: PetTestSupport.temporaryFileURL())
        let model = PetAppModel(arguments: [], persistence: persistence)
        let midnight = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_777_777_777))

        model.updateWorldState { state in
            state.hour = 23
            state.focus = .default
            state.music.playing = true
        }

        #expect(model.currentMood == .dancing)

        model.updateTimeOfDay(now: midnight)

        #expect(model.worldState.hour == 0)
        #expect(model.currentMood == .dancing)
    }

    @MainActor
    @Test
    func notificationAlertClearsAfterWindow() async {
        let persistence = PetPersistence(fileURL: PetTestSupport.temporaryFileURL())
        let model = PetAppModel(arguments: [], persistence: persistence, notificationAlertWindow: 0.01)
        let delivery = NotificationDelivery(
            bundleID: "com.apple.MobileSMS",
            deliveryState: "delivered",
            timestamp: .now
        )

        model.applyNotificationDelivery(delivery)
        #expect(model.worldState.notifications.alertUntil != nil)
        #expect(model.notificationToken != nil)
        #expect(model.worldState.notifications.source == "usernoted-delivered")

        let didClearAlert = await PetTestSupport.waitUntil {
            model.worldState.notifications.alertUntil == nil
        }
        #expect(didClearAlert)
    }
}
