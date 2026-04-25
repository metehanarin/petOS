import Darwin
import Foundation

struct NotificationDelivery: Equatable, Sendable {
    var bundleID: String
    var deliveryState: String
    var timestamp: Date
}

enum WeatherService {
    static func url() -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(AppConstants.weatherLatitude)),
            URLQueryItem(name: "longitude", value: String(AppConstants.weatherLongitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code")
        ]
        return components?.url
    }

    static func mapWeatherCode(_ code: Int) -> WeatherCondition {
        switch code {
        case 0 ... 1:
            return .clear
        case 2, 3, 45, 48:
            return .cloudy
        case 51 ... 67, 80 ... 82:
            return .rain
        case 71 ... 77, 85, 86:
            return .snow
        case 95, 96, 99:
            return .storm
        default:
            return .clear
        }
    }

    static func parseCurrentWeather(from data: Data) -> WeatherState? {
        guard
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let current = payload["current"] as? [String: Any]
        else {
            return nil
        }

        let code = current["weather_code"] as? Int ?? 0
        let tempC = current["temperature_2m"] as? Double
        return WeatherState(condition: mapWeatherCode(code), tempC: tempC)
    }
}

enum CalendarEventParser {
    static func parse(_ output: String, now: Date = .now) -> CalendarState {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .default
        }

        let parts = trimmed.components(separatedBy: "\t")
        guard parts.count >= 2, let startAt = parseDate(parts[1]) else {
            return .default
        }

        let minutesAway = max(0, Int(ceil(startAt.timeIntervalSince(now) / 60)))
        return CalendarState(
            nextEvent: CalendarEventState(
                title: parts[0],
                startAt: startAt,
                minutesAway: minutesAway
            ),
            source: "calendar"
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        let iso8601WithFractionalSeconds = ISO8601DateFormatter()
        iso8601WithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601WithFractionalSeconds.date(from: value) {
            return date
        }

        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime]
        if let date = iso8601.date(from: value) {
            return date
        }

        let localFormatter = DateFormatter()
        localFormatter.locale = Locale(identifier: "en_US_POSIX")
        localFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return localFormatter.date(from: value)
    }
}

enum MusicStateParser {
    static func parse(_ output: String, source: String) -> MusicState {
        let raw = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = raw.components(separatedBy: "|")
        let track = parts.indices.contains(0) ? parts[0] : ""
        let artist = parts.indices.contains(1) ? parts[1] : ""
        let status = parts.indices.contains(2) ? parts[2] : "stopped"
        let playing = status == "playing"

        return MusicState(
            source: playing ? source : nil,
            playing: playing,
            track: track,
            artist: artist,
            status: status
        )
    }
}

struct FocusModeDescriptor: Equatable {
    var identifier: String
    var name: String?
}

enum ControlCenterFocusSignalParser {
    static func resolveMode(from values: [String]) -> FocusModeDescriptor? {
        let normalizedValues = values.map(normalize).filter { !$0.isEmpty }
        let hasSleepFocusSignal = normalizedValues.contains { value in
            value.contains("sleep focus") ||
                value.contains("focus sleep") ||
                (value.contains("sleep") && (value.contains("selected") || value.contains("active") || value.contains("current") || value.contains("on")))
        }

        guard hasSleepFocusSignal else {
            return nil
        }

        return FocusModeDescriptor(identifier: "com.apple.focus.sleep", name: "Sleep")
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum FocusModeNameResolver {
    static func resolveMode(assertionsData: Data, configurationsData: Data) -> FocusModeDescriptor? {
        guard
            let assertions = try? JSONSerialization.jsonObject(with: assertionsData),
            let configurations = try? JSONSerialization.jsonObject(with: configurationsData)
        else {
            return nil
        }

        return resolveMode(assertions: assertions, configurations: configurations)
    }

    static func resolveModeName(assertionsData: Data, configurationsData: Data) -> String? {
        resolveMode(assertionsData: assertionsData, configurationsData: configurationsData)?.name
    }

    static func resolveMode(assertions: Any, configurations: Any) -> FocusModeDescriptor? {
        guard let activeModeIdentifier = extractActiveModeIdentifier(from: assertions) else {
            return nil
        }

        return FocusModeDescriptor(
            identifier: activeModeIdentifier,
            name: collectModeNames(from: configurations)[activeModeIdentifier]
        )
    }

    static func resolveModeName(assertions: Any, configurations: Any) -> String? {
        resolveMode(assertions: assertions, configurations: configurations)?.name
    }

    private static func extractActiveModeIdentifier(from root: Any) -> String? {
        var activeModeIdentifier: String?

        walkJSONObject(root) { entry in
            guard let dictionary = entry as? [String: Any] else {
                return true
            }

            if let assertionDetails = dictionary["assertionDetails"] as? [String: Any] {
                let candidate = normalizeString(
                    assertionDetails["assertionDetailsModeIdentifier"] ??
                        assertionDetails["modeIdentifier"]
                )
                if let candidate {
                    activeModeIdentifier = candidate
                    return false
                }
            }

            let candidate = normalizeString(dictionary["assertionDetailsModeIdentifier"] ?? dictionary["modeIdentifier"])
            if let candidate {
                activeModeIdentifier = candidate
                return false
            }

            return true
        }

        return activeModeIdentifier
    }

    private static func collectModeNames(from root: Any) -> [String: String] {
        var modeNames: [String: String] = [:]

        func addModeName(identifier: Any?, displayName: Any?) {
            guard
                let identifier = normalizeString(identifier),
                let displayName = normalizeString(displayName),
                modeNames[identifier] == nil
            else {
                return
            }

            modeNames[identifier] = displayName
        }

        walkJSONObject(root) { entry in
            guard let dictionary = entry as? [String: Any] else {
                return true
            }

            if let mode = dictionary["mode"] as? [String: Any] {
                addModeName(
                    identifier: mode["identifier"] ?? mode["modeIdentifier"] ?? dictionary["identifier"] ?? dictionary["modeIdentifier"],
                    displayName: mode["name"] ?? mode["displayName"] ?? dictionary["name"] ?? dictionary["displayName"]
                )
            }

            if let nestedModes = dictionary["modeConfigurationsByModeIdentifier"] as? [String: Any] {
                for (identifier, configuration) in nestedModes {
                    guard let configDictionary = configuration as? [String: Any] else {
                        continue
                    }

                    let mode = configDictionary["mode"] as? [String: Any]
                    addModeName(
                        identifier: mode?["identifier"] ?? mode?["modeIdentifier"] ?? configDictionary["identifier"] ?? configDictionary["modeIdentifier"] ?? identifier,
                        displayName: mode?["name"] ?? mode?["displayName"] ?? configDictionary["name"] ?? configDictionary["displayName"]
                    )
                }
            }

            return true
        }

        return modeNames
    }

    private static func normalizeString(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }

        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    @discardableResult
    private static func walkJSONObject(_ root: Any, visitor: (Any) -> Bool) -> Bool {
        if !visitor(root) {
            return false
        }

        if let array = root as? [Any] {
            for value in array where !walkJSONObject(value, visitor: visitor) {
                return false
            }
        } else if let dictionary = root as? [String: Any] {
            for value in dictionary.values where !walkJSONObject(value, visitor: visitor) {
                return false
            }
        }

        return true
    }
}

enum NotificationLogParser {
    private static let usernotedDelayedDeliveryPattern = try? NSRegularExpression(
        pattern: #"^([A-Za-z0-9.-]+)\s+performing delayed database write \(([^)]+)\)$"#
    )
    private static let usernotedPresentationPattern = try? NSRegularExpression(
        pattern: #"^Presenting <NotificationRecord app:"([^"]+)""#
    )

    static func isCalendarNotificationBundleID(_ bundleID: String) -> Bool {
        let normalized = bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return false
        }

        return normalized.hasPrefix("com.apple.ical") || normalized.hasPrefix("com.apple.calendar")
    }

    static func parseTimestamp(_ value: String) -> Date? {
        for formatter in timestampFormatters {
            if let date = formatter.date(from: value) {
                return date
            }
        }

        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601.date(from: value) {
            return date
        }

        iso8601.formatOptions = [.withInternetDateTime]
        return iso8601.date(from: value)
    }

    static func parseDelivery(from line: String) -> NotificationDelivery? {
        guard
            let payload = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
            let eventMessage = payload["eventMessage"] as? String,
            let timestampString = payload["timestamp"] as? String,
            let timestamp = parseTimestamp(timestampString)
        else {
            return nil
        }

        if let presentation = parsePresentation(eventMessage: eventMessage, timestamp: timestamp) {
            return presentation
        }

        return parseDelayedDelivery(eventMessage: eventMessage, timestamp: timestamp)
    }

    private static func parsePresentation(eventMessage: String, timestamp: Date) -> NotificationDelivery? {
        guard
            let regex = usernotedPresentationPattern,
            let match = regex.firstMatch(in: eventMessage, range: NSRange(eventMessage.startIndex..., in: eventMessage)),
            let bundleRange = Range(match.range(at: 1), in: eventMessage)
        else {
            return nil
        }

        let bundleID = String(eventMessage[bundleRange])
        guard !isCalendarNotificationBundleID(bundleID) else {
            return nil
        }

        return NotificationDelivery(
            bundleID: bundleID,
            deliveryState: "presented",
            timestamp: timestamp
        )
    }

    private static func parseDelayedDelivery(eventMessage: String, timestamp: Date) -> NotificationDelivery? {
        guard
            let regex = usernotedDelayedDeliveryPattern,
            let match = regex.firstMatch(in: eventMessage, range: NSRange(eventMessage.startIndex..., in: eventMessage)),
            let bundleRange = Range(match.range(at: 1), in: eventMessage),
            let stateRange = Range(match.range(at: 2), in: eventMessage)
        else {
            return nil
        }

        let bundleID = String(eventMessage[bundleRange])
        let deliveryState = String(eventMessage[stateRange]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard deliveryState == "delivered", !isCalendarNotificationBundleID(bundleID) else {
            return nil
        }

        return NotificationDelivery(
            bundleID: bundleID,
            deliveryState: deliveryState,
            timestamp: timestamp
        )
    }

    private static let timestampFormatters: [DateFormatter] = [
        makeTimestampFormatter("yyyy-MM-dd HH:mm:ss.SSSSSSZ"),
        makeTimestampFormatter("yyyy-MM-dd HH:mm:ss.SSSZ"),
        makeTimestampFormatter("yyyy-MM-dd HH:mm:ssZ")
    ]

    private static func makeTimestampFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
}

final class CPUSampler {
    private var previousTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    func sample() -> Double? {
        var cpuInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &cpuInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        let currentTicks = (
            user: cpuInfo.cpu_ticks.0,
            system: cpuInfo.cpu_ticks.1,
            idle: cpuInfo.cpu_ticks.2,
            nice: cpuInfo.cpu_ticks.3
        )

        defer {
            previousTicks = currentTicks
        }

        guard let previousTicks else {
            return nil
        }

        let user = Double(currentTicks.user - previousTicks.user)
        let system = Double(currentTicks.system - previousTicks.system)
        let idle = Double(currentTicks.idle - previousTicks.idle)
        let nice = Double(currentTicks.nice - previousTicks.nice)
        let total = user + system + idle + nice

        guard total > 0 else {
            return nil
        }

        return (user + system + nice) / total
    }
}
