import Foundation

enum PetMoodEngine {
    struct MoodResolution: Equatable {
        let mood: PetMood
        let reason: Reason
    }

    enum Reason: String, CaseIterable {
        case sleepFocusExplicit = "sleep_focus_explicit"
        case sleepWindow = "sleep_window"
        case unidentifiedFocusAssumedSleep = "unidentified_focus_assumed_sleep"
        case workFocus = "work_focus"
        case productivityApp = "productivity_app"
        case focusWithTopApp = "focus_with_top_app"
        case imminentCalendar = "imminent_calendar"
        case notificationAlert = "notification_alert"
        case sickCPU = "sick_cpu"
        case sickThermal = "sick_thermal"
        case sickBattery = "sick_battery"
        case musicPlaying = "music_playing"
        case idleDefault = "idle_default"
    }

    static func resolveBaseMood(for state: WorldState, now: Date = .now) -> PetMood {
        resolveBaseMoodWithReason(for: state, now: now).mood
    }

    static func resolveBaseMoodWithReason(for state: WorldState, now: Date = .now) -> MoodResolution {
        let topAppFrontmost = isTopAppFrontmost(state.activity)
        let productivityAppFrontmost = isProductivityApp(state.activity.frontApp)
        let sleepFocusActive = isFocusMode(
            state.focus,
            identifier: "com.apple.focus.sleep",
            fallbackNames: ["sleep", "sleeping"]
        )
        let workFocusActive = state.focus.active &&
            isFocusMode(
                state.focus,
                identifier: "com.apple.focus.work",
                fallbackNames: ["work", "working"]
            )
        let sleepModeActive = state.focus.active && sleepFocusActive
        let sleepWindowActive = isSleepWindow(hour: state.hour)
        let unidentifiedSleepFocus = isUnidentifiedFocusAssumedAsSleep(state.focus)

        if sleepModeActive {
            return MoodResolution(mood: .sleeping, reason: .sleepFocusExplicit)
        }

        if sleepWindowActive {
            return MoodResolution(mood: .sleeping, reason: .sleepWindow)
        }

        if unidentifiedSleepFocus {
            return MoodResolution(mood: .sleeping, reason: .unidentifiedFocusAssumedSleep)
        }

        if state.cpu > 0.9 {
            return MoodResolution(mood: .sick, reason: .sickCPU)
        }

        if ["serious", "critical"].contains(state.thermal.rawValue) {
            return MoodResolution(mood: .sick, reason: .sickThermal)
        }

        if (state.battery.level ?? 1) < 0.2 {
            return MoodResolution(mood: .sick, reason: .sickBattery)
        }

        if hasImminentCalendarEvent(state.calendar) {
            return MoodResolution(mood: .alert, reason: .imminentCalendar)
        }

        if hasActiveNotificationAlert(state.notifications, now: now) {
            return MoodResolution(mood: .alert, reason: .notificationAlert)
        }

        if workFocusActive {
            return MoodResolution(mood: .working, reason: .workFocus)
        }

        if productivityAppFrontmost {
            return MoodResolution(mood: .working, reason: .productivityApp)
        }

        if state.focus.active && topAppFrontmost {
            return MoodResolution(mood: .working, reason: .focusWithTopApp)
        }

        if state.music.playing {
            return MoodResolution(mood: .dancing, reason: .musicPlaying)
        }

        return MoodResolution(mood: .idle, reason: .idleDefault)
    }

    private static let productivityAppNames: Set<String> = [
        "logic pro",
        "final cut pro",
        "motion",
        "compressor",
        "mainstage",
        "garageband",
        "lightroom",
        "lightroom classic",
        "adobe lightroom",
        "adobe lightroom classic",
        "photoshop",
        "adobe photoshop",
        "illustrator",
        "adobe illustrator",
        "indesign",
        "adobe indesign",
        "premiere pro",
        "adobe premiere pro",
        "after effects",
        "adobe after effects",
        "audition",
        "adobe audition",
        "acrobat",
        "adobe acrobat",
        "adobe acrobat reader",
        "davinci resolve",
        "ableton live",
        "pro tools",
        "blender",
        "cinema 4d",
        "figma",
        "sketch",
        "xcode",
        "cursor",
        "visual studio code",
        "code",
        "android studio",
        "notion",
        "obsidian",
        "ulysses",
        "intellij idea",
        "pycharm",
        "webstorm",
        "phpstorm",
        "rubymine",
        "clion",
        "goland",
        "rider",
        "datagrip",
        "dataspell",
        "fleet",
        "microsoft word",
        "word",
        "microsoft excel",
        "excel",
        "microsoft powerpoint",
        "powerpoint",
        "pages",
        "numbers",
        "keynote"
    ]

    private static let productivityAppPrefixes = [
        "logic pro",
        "final cut pro",
        "adobe lightroom",
        "lightroom",
        "adobe photoshop",
        "photoshop",
        "adobe illustrator",
        "adobe indesign",
        "adobe premiere pro",
        "adobe after effects",
        "adobe audition",
        "adobe acrobat",
        "davinci resolve",
        "ableton live",
        "pro tools",
        "cinema 4d",
        "intellij idea",
        "pycharm",
        "webstorm",
        "phpstorm",
        "rubymine",
        "clion",
        "goland",
        "rider",
        "datagrip",
        "dataspell",
        "fleet"
    ]

    private static let nonSleepFocusIdentifiers: Set<String> = [
        "com.apple.focus.work",
        "com.apple.focus.personal",
        "com.apple.focus.gaming",
        "com.apple.focus.fitness",
        "com.apple.focus.mindfulness",
        "com.apple.focus.driving",
        "com.apple.donotdisturb.mode.driving",
        "com.apple.focus.reading",
        "com.apple.donotdisturb"
    ]

    private static let nonSleepFocusNames: Set<String> = [
        "work", "working",
        "personal",
        "gaming",
        "fitness",
        "mindfulness",
        "driving",
        "reading",
        "do not disturb", "dnd"
    ]

    static func reactionVariant(for event: PetEvent) -> ReactionVariant {
        let reactionType = event.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if reactionType.contains("sparkle") || reactionType.contains("clap") {
            return .sparkle
        }

        if reactionType.contains("heart") || reactionType.contains("love") {
            return .heart
        }

        if reactionType.contains("storm") || reactionType.contains("shock") || reactionType.contains("zap") {
            return .zap
        }

        return .pulse
    }

    private static func isTopAppFrontmost(_ activity: ActivityState) -> Bool {
        !activity.frontApp.isEmpty && activity.topApps.contains(activity.frontApp)
    }

    private static func isProductivityApp(_ appName: String) -> Bool {
        let normalizedAppName = normalizeAppName(appName)
        guard !normalizedAppName.isEmpty else {
            return false
        }

        if productivityAppNames.contains(normalizedAppName) {
            return true
        }

        return productivityAppPrefixes.contains { prefix in
            normalizedAppName.hasPrefix("\(prefix) ")
        }
    }

    private static func hasImminentCalendarEvent(_ calendar: CalendarState) -> Bool {
        guard let minutesAway = calendar.nextEvent?.minutesAway else {
            return false
        }

        return (0 ... 15).contains(minutesAway)
    }

    private static func hasActiveNotificationAlert(_ notifications: NotificationState, now: Date) -> Bool {
        guard let alertUntil = notifications.alertUntil else {
            return false
        }

        return alertUntil > now
    }

    private static func isSleepWindow(hour: Int) -> Bool {
        (0 ..< 6).contains(hour)
    }

    private static func isUnidentifiedFocusAssumedAsSleep(_ focus: FocusState) -> Bool {
        guard focus.active else { return false }
        let identifier = normalizeFocusModeIdentifier(focus.modeIdentifier)
        let name = normalizeFocusModeName(focus.modeName)

        if nonSleepFocusIdentifiers.contains(identifier) {
            return false
        }
        if nonSleepFocusNames.contains(name) {
            return false
        }
        return true
    }

    private static func isFocusMode(_ focus: FocusState, identifier: String, fallbackNames: Set<String>) -> Bool {
        let normalizedIdentifier = normalizeFocusModeIdentifier(focus.modeIdentifier)
        if !normalizedIdentifier.isEmpty {
            return normalizedIdentifier == identifier
        }

        return fallbackNames.contains(normalizeFocusModeName(focus.modeName))
    }

    private static func normalizeFocusModeIdentifier(_ modeIdentifier: String?) -> String {
        modeIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private static func normalizeFocusModeName(_ modeName: String?) -> String {
        modeName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private static func normalizeAppName(_ appName: String) -> String {
        appName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }
}
