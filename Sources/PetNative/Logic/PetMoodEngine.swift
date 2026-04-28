import Foundation

enum PetMoodEngine {
    struct MoodResolution: Equatable {
        let mood: PetMood
        let reason: Reason
    }

    enum Reason: String, CaseIterable {
        case sleepFocusExplicit = "sleep_focus_explicit"
        case doNotDisturbFocus = "do_not_disturb_focus"
        case sleepWindow = "sleep_window"
        case unidentifiedFocusAssumedSleep = "unidentified_focus_assumed_sleep"
        case workFocus = "work_focus"
        case productivityApp = "productivity_app"
        case focusWithTopApp = "focus_with_top_app"
        case attentionApp = "attention_app"
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
        let attentionAppFrontmost = isAttentionApp(state.activity.frontApp)
        let sleepFocusActive = isFocusMode(
            state.focus,
            identifiers: sleepFocusIdentifiers,
            fallbackNames: ["sleep", "sleeping"]
        )
        let doNotDisturbFocusActive = isFocusMode(
            state.focus,
            identifiers: doNotDisturbFocusIdentifiers,
            fallbackNames: ["do not disturb", "dnd"]
        )
        let workFocusActive = state.focus.active &&
            isFocusMode(
                state.focus,
                identifiers: ["com.apple.focus.work"],
                fallbackNames: ["work", "working"]
            )
        let sleepModeActive = state.focus.active && sleepFocusActive
        let doNotDisturbModeActive = state.focus.active && doNotDisturbFocusActive
        let unidentifiedFocusAssumedSleep = isUnidentifiedFocusAssumedAsSleep(state.focus)

        if sleepModeActive {
            return MoodResolution(mood: .sleeping, reason: .sleepFocusExplicit)
        }

        if doNotDisturbModeActive {
            return MoodResolution(mood: .sleeping, reason: .doNotDisturbFocus)
        }

        if unidentifiedFocusAssumedSleep {
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

        if attentionAppFrontmost {
            return MoodResolution(mood: .alert, reason: .attentionApp)
        }

        if workFocusActive && canFocusAppTriggerWorking(state.activity.frontApp) {
            return MoodResolution(mood: .working, reason: .workFocus)
        }

        if productivityAppFrontmost {
            return MoodResolution(mood: .working, reason: .productivityApp)
        }

        if state.focus.active && topAppFrontmost && canTopAppTriggerWorking(state.activity.frontApp) {
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
        "chatgpt",
        "claude",
        "claude by anthropic",
        "google gemini",
        "gemini",
        "perplexity",
        "perplexity: ask anything",
        "microsoft copilot",
        "microsoft 365",
        "microsoft 365 copilot",
        "copilot",
        "grammarly",
        "grammarly: ai writing app",
        "goodnotes",
        "goodnotes: ai notes, docs, pdf",
        "notability",
        "notability: ai notes & pdf app",
        "pdf reader",
        "pdf reader: pdf editor,convert",
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
        "microsoft onenote",
        "onenote",
        "google docs",
        "docs",
        "google sheets",
        "sheets",
        "google slides",
        "slides",
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
        "chatgpt",
        "claude",
        "google gemini",
        "gemini",
        "perplexity",
        "microsoft copilot",
        "microsoft 365",
        "grammarly",
        "goodnotes",
        "notability",
        "pdf reader",
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

    private static let musicAppNames: Set<String> = [
        "music",
        "spotify",
        "youtube music",
        "tidal",
        "deezer",
        "amazon music",
        "soundcloud"
    ]

    private static let attentionAppNames: Set<String> = [
        "calendar",
        "fantastical",
        "google calendar",
        "mail",
        "apple mail",
        "gmail",
        "mail for gmail",
        "mail+ for gmail",
        "microsoft outlook",
        "outlook",
        "yahoo mail",
        "messages",
        "facetime",
        "slack",
        "microsoft teams",
        "teams",
        "zoom",
        "zoom.us",
        "discord",
        "whatsapp",
        "telegram",
        "signal"
    ]

    private static let passiveAppNames: Set<String> = [
        "finder",
        "desktop",
        "launchpad",
        "mission control",
        "system settings",
        "system preferences",
        "settings",
        "app store",
        "google drive",
        "drive",
        "microsoft onedrive",
        "onedrive",
        "quicktime player",
        "preview",
        "image capture",
        "photos"
    ]

    private static let sleepFocusIdentifiers: Set<String> = [
        "com.apple.focus.sleep",
        "com.apple.donotdisturb.mode.sleep",
        "com.apple.sleep.sleep-mode"
    ]

    private static let doNotDisturbFocusIdentifiers: Set<String> = [
        "com.apple.donotdisturb",
        "com.apple.donotdisturb.mode.default",
        "com.apple.focus.do-not-disturb",
        "com.apple.focus.donotdisturb"
    ]

    private static let knownNonSleepFocusIdentifiers: Set<String> = [
        "com.apple.focus.work",
        "com.apple.focus.personal",
        "com.apple.focus.gaming",
        "com.apple.focus.fitness",
        "com.apple.focus.mindfulness",
        "com.apple.focus.driving",
        "com.apple.donotdisturb.mode.driving",
        "com.apple.focus.reading"
    ]

    private static let knownFocusIdentifiers: Set<String> = sleepFocusIdentifiers
        .union(doNotDisturbFocusIdentifiers)
        .union(knownNonSleepFocusIdentifiers)

    private static let focusStatusOnlySources: Set<String> = [
        "status",
        "protected-mode-status"
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

    private static func isMusicApp(_ appName: String) -> Bool {
        musicAppNames.contains(normalizeAppName(appName))
    }

    private static func isAttentionApp(_ appName: String) -> Bool {
        attentionAppNames.contains(normalizeAppName(appName))
    }

    private static func canTopAppTriggerWorking(_ appName: String) -> Bool {
        canFocusAppTriggerWorking(appName)
    }

    private static func canFocusAppTriggerWorking(_ appName: String) -> Bool {
        let normalizedAppName = normalizeAppName(appName)
        guard !normalizedAppName.isEmpty else {
            return false
        }

        return !musicAppNames.contains(normalizedAppName) &&
            !attentionAppNames.contains(normalizedAppName) &&
            !passiveAppNames.contains(normalizedAppName)
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

    private static func isUnidentifiedFocusAssumedAsSleep(_ focus: FocusState) -> Bool {
        guard focus.active, focusStatusOnlySources.contains(focus.source) else {
            return false
        }

        return normalizeFocusModeIdentifier(focus.modeIdentifier).isEmpty &&
            normalizeFocusModeName(focus.modeName).isEmpty
    }

    private static func isFocusMode(_ focus: FocusState, identifiers: Set<String>, fallbackNames: Set<String>) -> Bool {
        let normalizedIdentifier = normalizeFocusModeIdentifier(focus.modeIdentifier)
        if identifiers.contains(normalizedIdentifier) {
            return true
        }

        if knownFocusIdentifiers.contains(normalizedIdentifier) {
            return false
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
