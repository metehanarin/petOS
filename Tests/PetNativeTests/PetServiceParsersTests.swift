import Foundation
import Testing
@testable import PetNative

struct PetServiceParsersTests {
    @Test
    func weatherCodeMappingGroupsRainAndSnow() {
        #expect(WeatherService.mapWeatherCode(63) == .rain)
        #expect(WeatherService.mapWeatherCode(75) == .snow)
        #expect(WeatherService.mapWeatherCode(0) == .clear)
    }

    @Test
    func weatherURLUsesDefaultCoordinates() {
        let absoluteString = WeatherService.url()?.absoluteString ?? ""
        #expect(absoluteString.contains("latitude=41.02"))
        #expect(absoluteString.contains("longitude=28.58"))
    }

    @Test
    func calendarParserNormalizesUpcomingEvent() {
        let formatter = ISO8601DateFormatter()
        let now = formatter.date(from: "2024-04-23T12:00:00Z")!
        let state = CalendarEventParser.parse("Standup\t2024-04-23T12:15:00Z", now: now)

        #expect(state.nextEvent?.title == "Standup")
        #expect(state.nextEvent?.minutesAway == 15)
        #expect(state.source == "calendar")
    }

    @Test
    func focusModeResolverSupportsNestedPayloads() {
        let assertions: [String: Any] = [
            "data": [
                [
                    "storeAssertionRecords": [
                        [
                            "assertionDetails": [
                                "assertionDetailsModeIdentifier": "com.apple.focus.sleep"
                            ]
                        ]
                    ]
                ]
            ]
        ]
        let configurations: [String: Any] = [
            "data": [
                [
                    "mode": [
                        "identifier": "com.apple.focus.work",
                        "name": "Work"
                    ]
                ],
                [
                    "mode": [
                        "identifier": "com.apple.focus.sleep",
                        "name": "Sleep"
                    ]
                ]
            ]
        ]

        let mode = FocusModeNameResolver.resolveMode(assertions: assertions, configurations: configurations)
        #expect(mode?.identifier == "com.apple.focus.sleep")
        #expect(mode?.name == "Sleep")
        #expect(FocusModeNameResolver.resolveModeName(assertions: assertions, configurations: configurations) == "Sleep")
    }

    @Test
    func focusModeResolverRecognizesSleepModeIdentifierUsedByMacOS() {
        let assertions: [String: Any] = [
            "data": [
                [
                    "storeAssertionRecords": [
                        [
                            "assertionDetails": [
                                "assertionDetailsModeIdentifier": "com.apple.sleep.sleep-mode"
                            ]
                        ]
                    ]
                ]
            ]
        ]
        let configurations: [String: Any] = [
            "data": [
                [
                    "modeConfigurations": [
                        "com.apple.sleep.sleep-mode": [
                            "mode": [
                                "modeIdentifier": "com.apple.sleep.sleep-mode",
                                "name": "Sleep"
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let mode = FocusModeNameResolver.resolveMode(assertions: assertions, configurations: configurations)
        #expect(mode?.identifier == "com.apple.sleep.sleep-mode")
        #expect(mode?.name == "Sleep")
    }

    @Test
    func focusModeResolverIgnoresInvalidatedAssertionHistory() {
        let assertions: [String: Any] = [
            "data": [
                [
                    "storeInvalidationRecords": [
                        [
                            "invalidationAssertion": [
                                "assertionDetails": [
                                    "assertionDetailsModeIdentifier": "com.apple.sleep.sleep-mode"
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        let configurations: [String: Any] = [
            "data": [
                [
                    "modeConfigurations": [
                        "com.apple.sleep.sleep-mode": [
                            "mode": [
                                "modeIdentifier": "com.apple.sleep.sleep-mode",
                                "name": "Sleep"
                            ]
                        ]
                    ]
                ]
            ]
        ]

        #expect(FocusModeNameResolver.resolveMode(assertions: assertions, configurations: configurations) == nil)
    }

    @Test
    func focusModeResolverSupportsKeyedConfigurationPayloads() {
        let assertions: [String: Any] = [
            "data": [
                "sources": [
                    [
                        "assertionDetails": [
                            "modeIdentifier": "com.apple.focus.work"
                        ]
                    ]
                ]
            ]
        ]
        let configurations: [String: Any] = [
            "data": [
                "modeConfigurationsByModeIdentifier": [
                    "com.apple.focus.work": [
                        "mode": [
                            "modeIdentifier": "com.apple.focus.work",
                            "displayName": "Work"
                        ]
                    ]
                ]
            ]
        ]

        let mode = FocusModeNameResolver.resolveMode(assertions: assertions, configurations: configurations)
        #expect(mode?.identifier == "com.apple.focus.work")
        #expect(mode?.name == "Work")
        #expect(FocusModeNameResolver.resolveModeName(assertions: assertions, configurations: configurations) == "Work")
    }

    @Test
    func controlCenterFocusSignalParserRecognizesSleepFocusStatus() {
        let mode = ControlCenterFocusSignalParser.resolveMode(from: [
            "com.apple.menuextra.clock",
            "Sleep Focus, status menu",
            "Control Center"
        ])

        #expect(mode?.identifier == "com.apple.focus.sleep")
        #expect(mode?.name == "Sleep")
    }

    @Test
    func controlCenterFocusSignalParserRecognizesSelectedSleepFocusLabels() {
        let mode = ControlCenterFocusSignalParser.resolveMode(from: [
            "Control Center",
            "Focus",
            "Sleep",
            "selected sleep focus"
        ])

        #expect(mode?.identifier == "com.apple.focus.sleep")
        #expect(mode?.name == "Sleep")
    }

    @Test
    func controlCenterFocusSignalParserRecognizesDoNotDisturbFocusStatus() {
        let mode = ControlCenterFocusSignalParser.resolveMode(from: [
            "com.apple.menuextra.clock",
            "Do Not Disturb Focus, status menu",
            "Control Center"
        ])

        #expect(mode?.identifier == "com.apple.donotdisturb")
        #expect(mode?.name == "Do Not Disturb")
    }

    @Test
    func controlCenterFocusSignalParserIgnoresUnselectedSleepRow() {
        let mode = ControlCenterFocusSignalParser.resolveMode(from: [
            "Focus",
            "On",
            "Do Not Disturb",
            "Personal",
            "Work",
            "Sleep",
            "Home",
            "Reduce Interruptions"
        ])

        #expect(mode == nil)
    }

    @Test
    func controlCenterFocusSignalParserIgnoresUnrelatedSleepText() {
        let mode = ControlCenterFocusSignalParser.resolveMode(from: [
            "Sleep Timer",
            "Now Playing",
            "Control Center"
        ])

        #expect(mode == nil)
    }

    @Test
    func notificationLogParserExtractsDeliveryAndTimestamp() throws {
        let line = """
        {"eventMessage":"com.apple.ScriptEditor2 performing delayed database write (delivered)","timestamp":"2026-04-23 20:44:31.856073+0300"}
        """

        let delivery = try #require(NotificationLogParser.parseDelivery(from: line))
        #expect(delivery.bundleID == "com.apple.ScriptEditor2")
        #expect(delivery.deliveryState == "delivered")

        let components = Calendar.current.dateComponents([.year, .month, .day], from: delivery.timestamp)
        #expect(components.year == 2026)
        #expect(components.month == 4)
        #expect(components.day == 23)
    }

    @Test
    func notificationLogParserExtractsImmediatePresentation() throws {
        let line = #"""
        {"eventMessage":"Presenting <NotificationRecord app:\"com.apple.MobileSMS\" ident:\"DA39-A3EE\" req:\"\" uuid:\"983F6945\" source:\"D435C375\" staticCategory:\"<LEGACY>\"> as banner ([\"badge\", \"sound\", \"alert\"])","timestamp":"2026-04-23 20:44:31.856073+0300"}
        """#

        let delivery = try #require(NotificationLogParser.parseDelivery(from: line))
        #expect(delivery.bundleID == "com.apple.MobileSMS")
        #expect(delivery.deliveryState == "presented")
    }

    @Test
    func calendarPresentationNotificationsAreIgnored() {
        let line = #"""
        {"eventMessage":"Presenting <NotificationRecord app:\"com.apple.iCal\" ident:\"DA39-A3EE\"> as banner ([\"badge\", \"sound\", \"alert\"])","timestamp":"2026-04-23 20:44:31.856073+0300"}
        """#

        #expect(NotificationLogParser.parseDelivery(from: line) == nil)
    }

    @Test
    func calendarNotificationBundlesAreIgnored() {
        #expect(NotificationLogParser.isCalendarNotificationBundleID("com.apple.iCal"))
        #expect(NotificationLogParser.isCalendarNotificationBundleID("com.apple.iCal.CalendarNotificationContentExtention-OSX"))
        #expect(!NotificationLogParser.isCalendarNotificationBundleID("com.apple.MobileSMS"))
    }

    @Test
    func activityPollerUsesSystemTopAppsWhenUsageStoreResolves() async {
        let poller = await MainActor.run {
            ActivityPoller(
                dependencies: ActivityPollerDependencies(
                    getCachedTopApps: { AppConstants.defaultTopApps },
                    saveCachedTopApps: { $0 },
                    queryFrontmostApp: { "Safari" },
                    queryRunningApps: { ["Safari", "Finder"] },
                    queryTopApps: { ["Safari", "Terminal"] },
                    now: { Date(timeIntervalSince1970: 1_000_000) },
                    fallbackTopApps: AppConstants.defaultTopApps,
                    refreshInterval: AppConstants.topAppsRefreshInterval,
                    logWarning: { _ in }
                )
            )
        }

        let activity = await poller.poll()
        #expect(activity.frontApp == "Safari")
        #expect(activity.runningApps == ["Safari", "Finder"])
        #expect(activity.topApps == ["Safari", "Terminal"])
        #expect(activity.source == "system")
    }

    @Test
    func activityPollerFallsBackWhenUsageStoreUnavailable() async {
        let poller = await MainActor.run {
            ActivityPoller(
                dependencies: ActivityPollerDependencies(
                    getCachedTopApps: { AppConstants.defaultTopApps },
                    saveCachedTopApps: { $0 },
                    queryFrontmostApp: { "Cursor" },
                    queryRunningApps: { ["Cursor", "Terminal"] },
                    queryTopApps: { throw ActivityQueryError.noReadableUsageStore },
                    now: { Date(timeIntervalSince1970: 1_000_000) },
                    fallbackTopApps: AppConstants.defaultTopApps,
                    refreshInterval: AppConstants.topAppsRefreshInterval,
                    logWarning: { _ in }
                )
            )
        }

        let firstActivity = await poller.poll()
        let secondActivity = await poller.poll()

        #expect(firstActivity.source == "fallback")
        #expect(firstActivity.topApps == AppConstants.defaultTopApps)
        #expect(secondActivity.source == "fallback")
        #expect(secondActivity.topApps == AppConstants.defaultTopApps)
    }
}
