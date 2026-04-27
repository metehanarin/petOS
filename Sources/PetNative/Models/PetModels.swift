import CoreGraphics
import Foundation

enum PetMood: String, CaseIterable, Codable {
    case sick
    case idle
    case alert
    case sleeping
    case working
    case dancing
}

enum SunPhase: String, Codable {
    case dawn
    case day
    case golden
    case dusk
    case night

    static func resolve(for hour: Int) -> SunPhase {
        switch hour {
        case 5 ... 6:
            return .dawn
        case 7 ... 16:
            return .day
        case 17 ... 18:
            return .golden
        case 19 ... 20:
            return .dusk
        default:
            return .night
        }
    }
}

enum WeatherCondition: String, Codable {
    case clear
    case cloudy
    case rain
    case snow
    case storm
}

enum ThermalSeverity: String, Codable {
    case nominal
    case fair
    case serious
    case critical
}

enum PetJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([PetJSONValue])
    case object([String: PetJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([PetJSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: PetJSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(string):
            try container.encode(string)
        case let .number(number):
            try container.encode(number)
        case let .bool(bool):
            try container.encode(bool)
        case let .array(array):
            try container.encode(array)
        case let .object(object):
            try container.encode(object)
        case .null:
            try container.encodeNil()
        }
    }
}

struct PetPosition: Codable, Equatable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }

    var point: CGPoint {
        CGPoint(x: x, y: y)
    }
}

struct PetPreferences: Codable, Equatable {
    var soundEnabled: Bool
    var swipeMeowEnabled: Bool
    var reactionServerEnabled: Bool
    var alwaysOnTop: Bool

    static var `default`: PetPreferences {
        PetPreferences(
            soundEnabled: false,
            swipeMeowEnabled: true,
            reactionServerEnabled: true,
            alwaysOnTop: true
        )
    }

    init(
        soundEnabled: Bool = false,
        swipeMeowEnabled: Bool = true,
        reactionServerEnabled: Bool = true,
        alwaysOnTop: Bool = true
    ) {
        self.soundEnabled = soundEnabled
        self.swipeMeowEnabled = swipeMeowEnabled
        self.reactionServerEnabled = reactionServerEnabled
        self.alwaysOnTop = alwaysOnTop
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? Self.default.soundEnabled
        swipeMeowEnabled = try container.decodeIfPresent(Bool.self, forKey: .swipeMeowEnabled) ?? Self.default.swipeMeowEnabled
        reactionServerEnabled = try container.decodeIfPresent(Bool.self, forKey: .reactionServerEnabled) ?? Self.default.reactionServerEnabled
        alwaysOnTop = try container.decodeIfPresent(Bool.self, forKey: .alwaysOnTop) ?? Self.default.alwaysOnTop
    }
}

struct SystemState: Codable, Equatable {
    var idleState: String
    var locked: Bool
    var suspended: Bool

    static let `default` = SystemState(
        idleState: "active",
        locked: false,
        suspended: false
    )
}

struct BatteryState: Codable, Equatable {
    var level: Double?
    var charging: Bool
    var onBatteryPower: Bool
    var status: String

    static let `default` = BatteryState(
        level: 1,
        charging: true,
        onBatteryPower: false,
        status: "charged"
    )
}

struct CalendarEventState: Codable, Equatable {
    var title: String
    var startAt: Date
    var minutesAway: Int
}

struct CalendarState: Codable, Equatable {
    var nextEvent: CalendarEventState?
    var source: String

    static let `default` = CalendarState(
        nextEvent: nil,
        source: "calendar"
    )
}

struct FocusState: Codable, Equatable {
    var active: Bool
    var authorized: Bool
    var modeIdentifier: String?
    var modeName: String?
    var source: String

    static let `default` = FocusState(
        active: false,
        authorized: false,
        modeIdentifier: nil,
        modeName: nil,
        source: "status"
    )
}

struct ActivityState: Codable, Equatable {
    var frontApp: String
    var runningApps: [String]
    var topApps: [String]
    var source: String

    static let `default` = ActivityState(
        frontApp: "",
        runningApps: [],
        topApps: [],
        source: "fallback"
    )
}

struct WeatherState: Codable, Equatable {
    var condition: WeatherCondition
    var tempC: Double?

    static let `default` = WeatherState(
        condition: .clear,
        tempC: nil
    )
}

struct MusicState: Codable, Equatable {
    var source: String?
    var playing: Bool
    var track: String
    var artist: String
    var status: String

    static let `default` = MusicState(
        source: nil,
        playing: false,
        track: "",
        artist: "",
        status: "stopped"
    )
}

struct NotificationState: Codable, Equatable {
    var alertUntil: Date?
    var lastBundleID: String?
    var lastDeliveredAt: Date?
    var source: String?

    static let `default` = NotificationState(
        alertUntil: nil,
        lastBundleID: nil,
        lastDeliveredAt: nil,
        source: nil
    )
}

struct PetEvent: Codable, Equatable, Identifiable {
    var id: UUID
    var timestamp: Date
    var type: String
    var priority: Int
    var payload: [String: PetJSONValue]

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        type: String,
        priority: Int = 50,
        payload: [String: PetJSONValue] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.priority = priority
        self.payload = payload
    }
}

struct WorldState: Codable, Equatable {
    var idle: TimeInterval
    var hour: Int
    var sunPhase: SunPhase
    var system: SystemState
    var battery: BatteryState
    var calendar: CalendarState
    var focus: FocusState
    var activity: ActivityState
    var weather: WeatherState
    var music: MusicState
    var notifications: NotificationState
    var events: [PetEvent]
    var cpu: Double
    var thermal: ThermalSeverity

    static var `default`: WorldState {
        let hour = Calendar.current.component(.hour, from: .now)
        return WorldState(
            idle: 0,
            hour: hour,
            sunPhase: SunPhase.resolve(for: hour),
            system: .default,
            battery: .default,
            calendar: .default,
            focus: .default,
            activity: .default,
            weather: .default,
            music: .default,
            notifications: .default,
            events: [],
            cpu: 0,
            thermal: .nominal
        )
    }
}

enum ReactionVariant: String {
    case pulse
    case sparkle
    case heart
    case zap
}

enum AppConstants {
    static let appName = "petOS"
    static let petName = "Lumi"
    static let windowSize = CGSize(width: 240, height: 240)
    static let spriteSize = CGSize(width: 160, height: 160)
    static let windowMargin: CGFloat = 20
    static let reactionServerPort: UInt16 = 7893
    static let reactionHistoryLimit = 50
    static let debugPollInterval: TimeInterval = 1
    static let timeOfDayPollInterval: TimeInterval = 1
    static let focusPollInterval: TimeInterval = 1
    static let topAppsRefreshInterval: TimeInterval = 15 * 60
    static let notificationMonitorRestartDelay: TimeInterval = 2
    static let notificationDelayedFallbackDeduplicationWindow: TimeInterval = 7
    static let weatherLatitude = 41.02
    static let weatherLongitude = 28.58
    static let notificationAlertWindow: TimeInterval = 8
    static let meowDebounceInterval: TimeInterval = 0.5
    static let defaultTopApps = [
        "Cursor",
        "Visual Studio Code",
        "Xcode",
        "Terminal",
        "iTerm2",
        "Safari",
        "Google Chrome",
        "Arc",
        "Slack",
        "Figma"
    ]
}
