import Foundation
import Testing
@testable import PetNative

struct PetMoodEngineTests {
    @Test
    func sleepingResolvesForSleepFocusModeDuringOvernightWindow() {
        let state = PetTestSupport.makeState {
            $0.hour = 2
            $0.focus.active = true
            $0.focus.modeIdentifier = "com.apple.focus.sleep"
            $0.focus.modeName = "Sleep"
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .sleeping)
    }

    @Test
    func overnightWindowWithoutSleepFocusModeDoesNotResolveSleeping() {
        let state = PetTestSupport.makeState {
            $0.hour = 2
            $0.music.playing = true
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .dancing)
    }

    @Test
    func midnightWithoutSleepFocusModeDoesNotResolveSleeping() {
        let state = PetTestSupport.makeState {
            $0.hour = 0
            $0.music.playing = true
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .dancing)
    }

    @Test
    func beforeSixAMWithoutSleepFocusModeDoesNotResolveSleeping() {
        let state = PetTestSupport.makeState {
            $0.hour = 5
            $0.music.playing = true
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .dancing)
    }

    @Test
    func overnightSleepWindowEndsAtSixAMWithoutSleepFocusMode() {
        let state = PetTestSupport.makeState {
            $0.hour = 6
            $0.music.playing = true
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .dancing)
    }

    @Test
    func sleepFocusModeResolvesToSleepingAtSixAM() {
        let state = PetTestSupport.makeState {
            $0.hour = 6
            $0.focus.active = true
            $0.focus.modeIdentifier = "com.apple.focus.sleep"
            $0.focus.modeName = "Sleep"
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .sleeping)
    }

    @Test
    func longIdleDoesNotResolveToSleepingOutsideOvernightWindowWithoutSleepFocus() {
        let state = PetTestSupport.makeState {
            $0.hour = 10
            $0.idle = 300
            $0.music.playing = true
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .dancing)
    }

    @Test
    func suspendedSystemDoesNotResolveToSleepingOutsideOvernightWindowWithoutSleepFocus() {
        let state = PetTestSupport.makeState {
            $0.hour = 10
            $0.system.suspended = true
            $0.music.playing = true
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .dancing)
    }

    @Test
    func sleepingResolvesForSleepFocusModeBeforeMidnightWindow() {
        let state = PetTestSupport.makeState {
            $0.hour = 23
            $0.focus.active = true
            $0.focus.modeIdentifier = "com.apple.focus.sleep"
            $0.focus.modeName = "Sleep"
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .sleeping)
    }

    @Test
    func sleepFocusModeBeatsOtherMoodSignalsOutsideOvernightWindow() {
        let now = Date(timeIntervalSince1970: 1_777_777_777)
        let state = PetTestSupport.makeState {
            $0.hour = 14
            $0.focus.active = true
            $0.focus.modeIdentifier = "com.apple.focus.sleep"
            $0.focus.modeName = "Sleep"
            $0.music.playing = true
            $0.cpu = 0.95
            $0.notifications.alertUntil = now.addingTimeInterval(5)
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state, now: now) == .sleeping)
    }

    @Test
    func resolutionExposesReasonForExplicitSleepFocus() {
        let state = PetTestSupport.makeState {
            $0.hour = 14
            $0.focus.active = true
            $0.focus.modeIdentifier = "com.apple.focus.sleep"
            $0.focus.modeName = "Sleep"
        }

        let resolution = PetMoodEngine.resolveBaseMoodWithReason(for: state)
        #expect(resolution.mood == .sleeping)
        #expect(resolution.reason == .sleepFocusExplicit)
    }

    @Test
    func sleepingResolvesWhenFocusActiveWithSleepNameOnly() {
        let state = PetTestSupport.makeState {
            $0.hour = 14
            $0.focus.active = true
            $0.focus.modeIdentifier = nil
            $0.focus.modeName = "Sleep"
        }

        let resolution = PetMoodEngine.resolveBaseMoodWithReason(for: state)
        #expect(resolution.mood == .sleeping)
        #expect(resolution.reason == .sleepFocusExplicit)
    }

    @Test
    func sleepingResolvesWhenFocusActiveWithUnknownIdentifierAndSleepName() {
        let state = PetTestSupport.makeState {
            $0.hour = 14
            $0.focus.active = true
            $0.focus.modeIdentifier = "com.apple.focus.mode.sleep"
            $0.focus.modeName = "Sleep"
        }

        let resolution = PetMoodEngine.resolveBaseMoodWithReason(for: state)
        #expect(resolution.mood == .sleeping)
        #expect(resolution.reason == .sleepFocusExplicit)
    }

    @Test
    func sleepingResolvesForMacOSSleepModeIdentifier() {
        let state = PetTestSupport.makeState {
            $0.hour = 14
            $0.focus.active = true
            $0.focus.modeIdentifier = "com.apple.sleep.sleep-mode"
            $0.focus.modeName = "Sleep"
            $0.music.playing = true
        }

        let resolution = PetMoodEngine.resolveBaseMoodWithReason(for: state)
        #expect(resolution.mood == .sleeping)
        #expect(resolution.reason == .sleepFocusExplicit)
    }

    @Test
    func workingResolvesWhenFocusActiveWithWorkNameOnly() {
        let state = PetTestSupport.makeState {
            $0.hour = 14
            $0.focus.active = true
            $0.focus.modeIdentifier = nil
            $0.focus.modeName = "Work"
            $0.activity.frontApp = "Cursor"
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .working)
    }

    @Test
    func customNamedFocusDoesNotResolveSleeping() {
        let state = PetTestSupport.makeState {
            $0.hour = 14
            $0.focus.active = true
            $0.focus.modeIdentifier = "com.example.custom.focus"
            $0.focus.modeName = "Deep Work"
        }

        let resolution = PetMoodEngine.resolveBaseMoodWithReason(for: state)
        #expect(resolution.mood == .idle)
        #expect(resolution.reason == .idleDefault)
    }

    @Test
    func idleResolvesWhenAllFocusSourcesFailAtMidday() {
        let state = PetTestSupport.makeState {
            $0.hour = 14
            $0.focus.active = false
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .idle)
    }

    @Test
    func drivingFocusDoesNotResolveToSleeping() {
        let state = PetTestSupport.makeState {
            $0.hour = 14
            $0.focus.active = true
            $0.focus.modeIdentifier = "com.apple.donotdisturb.mode.driving"
            $0.focus.modeName = "Driving"
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .idle)
    }

    @Test
    func unidentifiedProtectedFocusResolvesSleepingInLateEvening() {
        let state = PetTestSupport.makeState {
            $0.hour = 23
            $0.focus.active = true
            $0.focus.source = "protected-mode-status"
            $0.music.playing = true
        }

        let resolution = PetMoodEngine.resolveBaseMoodWithReason(for: state)
        #expect(resolution.mood == .sleeping)
        #expect(resolution.reason == .unidentifiedFocusAssumedSleep)
    }

    @Test
    func unidentifiedProtectedFocusResolvesSleepingDuringDaytime() {
        let state = PetTestSupport.makeState {
            $0.hour = 14
            $0.focus.active = true
            $0.focus.source = "protected-mode-status"
            $0.music.playing = true
        }

        let resolution = PetMoodEngine.resolveBaseMoodWithReason(for: state)
        #expect(resolution.mood == .sleeping)
        #expect(resolution.reason == .unidentifiedFocusAssumedSleep)
    }

    @Test
    func unidentifiedStatusFocusResolvesSleepingDuringDaytime() {
        let state = PetTestSupport.makeState {
            $0.hour = 14
            $0.focus.active = true
            $0.focus.source = "status"
            $0.music.playing = true
        }

        let resolution = PetMoodEngine.resolveBaseMoodWithReason(for: state)
        #expect(resolution.mood == .sleeping)
        #expect(resolution.reason == .unidentifiedFocusAssumedSleep)
    }

    @Test
    func doNotDisturbFocusResolvesToSleeping() {
        let state = PetTestSupport.makeState {
            $0.hour = 14
            $0.focus.active = true
            $0.focus.modeIdentifier = "com.apple.donotdisturb"
            $0.focus.modeName = "Do Not Disturb"
            $0.music.playing = true
        }

        let resolution = PetMoodEngine.resolveBaseMoodWithReason(for: state)
        #expect(resolution.mood == .sleeping)
        #expect(resolution.reason == .doNotDisturbFocus)
    }

    @Test
    func nonSleepFocusDoesNotResolveToSleepingOutsideOvernightWindow() {
        let state = PetTestSupport.makeState {
            $0.hour = 10
            $0.focus.active = true
            $0.focus.modeIdentifier = "com.apple.focus.work"
            $0.focus.modeName = "Sleep"
            $0.music.playing = true
            $0.activity.frontApp = "Cursor"
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .working)
    }

    @Test
    func sleepingDoesNotResolveBeforeMidnightWithoutSleepFocusMode() {
        let state = PetTestSupport.makeState {
            $0.hour = 23
            $0.music.playing = true
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .dancing)
    }

    @Test
    func workingResolvesForWorkFocusMode() {
        let state = PetTestSupport.makeState {
            $0.focus.active = true
            $0.focus.modeIdentifier = "com.apple.focus.work"
            $0.focus.modeName = "Work"
            $0.activity.frontApp = "Cursor"
            $0.activity.runningApps = ["Cursor"]
            $0.activity.topApps = ["Cursor", "Safari"]
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .working)
    }

    @Test
    func workFocusDoesNotForceWorkingForPassiveFrontmostApp() {
        let state = PetTestSupport.makeState {
            $0.focus.active = true
            $0.focus.modeIdentifier = "com.apple.focus.work"
            $0.focus.modeName = "Work"
            $0.activity.frontApp = "Finder"
            $0.activity.runningApps = ["Finder"]
            $0.activity.topApps = ["Finder", "Cursor"]
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .idle)
    }

    @Test
    func inactiveWorkFocusMetadataDoesNotResolveToWorking() {
        let state = PetTestSupport.makeState {
            $0.focus.active = false
            $0.focus.modeIdentifier = "com.apple.focus.work"
            $0.focus.modeName = "Work"
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .idle)
    }

    @Test
    func productivityAppsResolveToWorkingWhenFrontmost() {
        for appName in ["Logic Pro", "Final Cut Pro", "Lightroom"] {
            let state = PetTestSupport.makeState {
                $0.activity.frontApp = appName
                $0.activity.runningApps = [appName, "Finder"]
            }

            #expect(PetMoodEngine.resolveBaseMood(for: state) == .working)
        }
    }

    @Test
    func alertBeatsDancingWhenCalendarEventIsImminent() {
        let state = PetTestSupport.makeState {
            $0.music.playing = true
            $0.calendar.nextEvent = CalendarEventState(title: "Standup", startAt: .now, minutesAway: 15)
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .alert)
    }

    @Test
    func alertResolvesWhileNotificationIsActive() {
        let now = Date(timeIntervalSince1970: 1_777_777_777)
        let state = PetTestSupport.makeState {
            $0.notifications.alertUntil = now.addingTimeInterval(5)
            $0.notifications.lastBundleID = "com.apple.MobileSMS"
            $0.notifications.lastDeliveredAt = now
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state, now: now) == .alert)
    }

    @Test
    func expiredNotificationDoesNotKeepAlertMood() {
        let base = Date(timeIntervalSince1970: 1_777_777_777)
        let state = PetTestSupport.makeState {
            $0.notifications.alertUntil = base
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state, now: base.addingTimeInterval(1)) == .idle)
    }

    @Test
    func alertBeatsWorkingWhenProductivityAppIsFrontmost() {
        let now = Date(timeIntervalSince1970: 1_777_777_777)
        let state = PetTestSupport.makeState {
            $0.activity.frontApp = "Logic Pro"
            $0.notifications.alertUntil = now.addingTimeInterval(5)
            $0.notifications.lastBundleID = "com.apple.MobileSMS"
            $0.notifications.lastDeliveredAt = now
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state, now: now) == .alert)
    }

    @Test
    func workingBeatsDancingWhenFocusActiveAndTrackedAppFrontmost() {
        let state = PetTestSupport.makeState {
            $0.focus.active = true
            $0.focus.modeIdentifier = "com.apple.focus.personal"
            $0.focus.modeName = "Personal"
            $0.music.playing = true
            $0.activity.frontApp = "Safari"
            $0.activity.runningApps = ["Safari", "Finder"]
            $0.activity.topApps = ["Safari", "Terminal"]
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .working)
    }

    @Test
    func focusActiveWithTrackedAppOnlyInBackgroundDoesNotTriggerWorking() {
        let state = PetTestSupport.makeState {
            $0.focus.active = true
            $0.focus.modeIdentifier = "com.apple.focus.personal"
            $0.focus.modeName = "Personal"
            $0.activity.frontApp = "Codex"
            $0.activity.runningApps = ["Codex", "Safari", "Terminal"]
            $0.activity.topApps = ["Safari", "Terminal"]
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .idle)
    }

    @Test
    func frontmostProductivityAppBeatsDancing() {
        let state = PetTestSupport.makeState {
            $0.music.playing = true
            $0.activity.frontApp = "Final Cut Pro"
            $0.activity.runningApps = ["Final Cut Pro", "Music"]
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .working)
    }

    @Test
    func appStoreProductivityAppsResolveToWorkingOverMusic() {
        for appName in ["ChatGPT", "Google Docs", "Google Sheets", "Microsoft 365", "PowerPoint", "Perplexity", "Goodnotes"] {
            let state = PetTestSupport.makeState {
                $0.music.playing = true
                $0.activity.frontApp = appName
                $0.activity.runningApps = [appName, "Music"]
            }

            #expect(PetMoodEngine.resolveBaseMood(for: state) == .working)
        }
    }

    @Test
    func frontmostAttentionAppsResolveToAlertOverMusic() {
        for appName in ["Microsoft Outlook", "Gmail", "Google Calendar", "Slack", "Zoom"] {
            let state = PetTestSupport.makeState {
                $0.music.playing = true
                $0.activity.frontApp = appName
                $0.activity.runningApps = [appName, "Music"]
            }

            #expect(PetMoodEngine.resolveBaseMood(for: state) == .alert)
        }
    }

    @Test
    func frontmostMusicAppDoesNotUseFocusTopAppFallback() {
        for appName in ["Music", "Spotify"] {
            let state = PetTestSupport.makeState {
                $0.focus.active = true
                $0.focus.modeIdentifier = "com.apple.focus.personal"
                $0.focus.modeName = "Personal"
                $0.music.playing = true
                $0.activity.frontApp = appName
                $0.activity.runningApps = [appName]
                $0.activity.topApps = [appName]
            }

            #expect(PetMoodEngine.resolveBaseMood(for: state) == .dancing)
        }
    }

    @Test
    func frontmostPassiveAppsDoNotUseFocusTopAppFallback() {
        for appName in ["Finder", "System Settings", "Preview", "Photos", "Google Drive", "OneDrive"] {
            let state = PetTestSupport.makeState {
                $0.focus.active = true
                $0.focus.modeIdentifier = "com.apple.focus.personal"
                $0.focus.modeName = "Personal"
                $0.activity.frontApp = appName
                $0.activity.runningApps = [appName]
                $0.activity.topApps = [appName]
            }

            #expect(PetMoodEngine.resolveBaseMood(for: state) == .idle)
        }
    }

    @Test
    func backgroundProductivityAppDoesNotTriggerWorking() {
        let state = PetTestSupport.makeState {
            $0.activity.frontApp = "Finder"
            $0.activity.runningApps = ["Finder", "Logic Pro"]
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .idle)
    }

    @Test
    func productivityAppMatchingNormalizesCaseWhitespaceAndVersionSuffixes() {
        for appName in ["  ADOBE PHOTOSHOP 2026  ", "Lightroom Classic"] {
            let state = PetTestSupport.makeState {
                $0.activity.frontApp = appName
                $0.activity.runningApps = [appName]
            }

            #expect(PetMoodEngine.resolveBaseMood(for: state) == .working)
        }
    }

    @Test
    func focusWithoutTrackedWorkAppResolvesToIdle() {
        let state = PetTestSupport.makeState {
            $0.focus.active = true
            $0.focus.modeIdentifier = "com.apple.focus.personal"
            $0.focus.modeName = "Personal"
            $0.activity.frontApp = "Safari"
            $0.activity.runningApps = ["Safari"]
            $0.activity.topApps = []
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .idle)
    }

    @Test
    func musicPlaybackResolvesToDancing() {
        let state = PetTestSupport.makeState {
            $0.music.playing = true
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .dancing)
    }

    @Test
    func batteryBelowTwentyPercentResolvesToSick() {
        let state = PetTestSupport.makeState {
            $0.battery.level = 0.19
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .sick)
    }

    @Test
    func highCpuResolvesToSick() {
        let state = PetTestSupport.makeState {
            $0.cpu = 0.95
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .sick)
    }

    @Test
    func seriousThermalStateResolvesToSick() {
        let state = PetTestSupport.makeState {
            $0.thermal = .serious
        }

        #expect(PetMoodEngine.resolveBaseMood(for: state) == .sick)
    }
}
