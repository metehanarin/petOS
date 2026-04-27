import AppKit
import Foundation

struct ActivityBundleRanking: Equatable {
    var bundleID: String
    var count: Int
}

struct ActivityPollerDependencies {
    var getCachedTopApps: () -> [String]
    var saveCachedTopApps: ([String]) -> [String]
    var queryFrontmostApp: () async throws -> String
    var queryRunningApps: () async throws -> [String]
    var queryTopApps: () async throws -> [String]
    var now: () -> Date
    var fallbackTopApps: [String]
    var refreshInterval: TimeInterval
    var logWarning: (String) -> Void
}

@MainActor
final class ActivityPoller {
    private let dependencies: ActivityPollerDependencies
    private var topApps: [String]
    private var source: String
    private var lastRefreshAt: Date?
    private var usageStoreAvailable = true

    init(dependencies: ActivityPollerDependencies) {
        self.dependencies = dependencies

        let cachedTopApps = ActivityPoller.normalizedTopApps(
            dependencies.getCachedTopApps(),
            fallbackTopApps: dependencies.fallbackTopApps
        )
        topApps = cachedTopApps
        source = Self.inferSource(topApps: cachedTopApps, fallbackTopApps: dependencies.fallbackTopApps)
    }

    convenience init(persistence: PetPersistence) {
        self.init(
            dependencies: ActivityPollerDependencies(
                getCachedTopApps: { persistence.currentSnapshot.cachedTopApps },
                saveCachedTopApps: { persistence.saveCachedTopApps($0) },
                queryFrontmostApp: {
                    try await ActivityQueries.queryFrontmostApp()
                },
                queryRunningApps: {
                    try await ActivityQueries.queryRunningApps()
                },
                queryTopApps: {
                    try await ActivityQueries.queryTopApps(fallbackTopApps: AppConstants.defaultTopApps)
                },
                now: { .now },
                fallbackTopApps: AppConstants.defaultTopApps,
                refreshInterval: AppConstants.topAppsRefreshInterval,
                logWarning: { message in
                    NSLog("%@", "[PetNative] \(message)")
                }
            )
        )
    }

    func poll() async -> ActivityState {
        var frontApp = ""
        var runningApps: [String] = []

        do {
            frontApp = try await dependencies.queryFrontmostApp()
        } catch {
            dependencies.logWarning("[activity] frontmost app query failed: \(error.localizedDescription)")
        }

        do {
            runningApps = try await dependencies.queryRunningApps()
        } catch {
            dependencies.logWarning("[activity] running apps query failed: \(error.localizedDescription)")
        }

        let now = dependencies.now()
        if usageStoreAvailable, shouldRefreshTopApps(at: now) {
            lastRefreshAt = now

            do {
                let resolvedTopApps = try await dependencies.queryTopApps()
                if !resolvedTopApps.isEmpty {
                    topApps = resolvedTopApps
                    source = "system"
                    _ = dependencies.saveCachedTopApps(resolvedTopApps)
                }
            } catch {
                if Self.isUsageStoreUnavailable(error) {
                    usageStoreAvailable = false
                } else {
                    dependencies.logWarning("[activity] usage store query failed: \(error.localizedDescription)")
                }

                let cachedTopApps = Self.normalizedTopApps(
                    dependencies.getCachedTopApps(),
                    fallbackTopApps: dependencies.fallbackTopApps
                )
                topApps = cachedTopApps
                source = Self.inferSource(topApps: cachedTopApps, fallbackTopApps: dependencies.fallbackTopApps)
            }
        }

        return ActivityState(
            frontApp: frontApp,
            runningApps: runningApps,
            topApps: topApps,
            source: source
        )
    }

    private func shouldRefreshTopApps(at date: Date) -> Bool {
        guard let lastRefreshAt else {
            return true
        }

        return date.timeIntervalSince(lastRefreshAt) >= dependencies.refreshInterval
    }

    private static func normalizedTopApps(_ topApps: [String], fallbackTopApps: [String]) -> [String] {
        topApps.isEmpty ? fallbackTopApps : topApps
    }

    private static func inferSource(topApps: [String], fallbackTopApps: [String]) -> String {
        topApps == fallbackTopApps ? "fallback" : "cache"
    }

    private static func isUsageStoreUnavailable(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain,
           [Int(EACCES), Int(ENOENT), Int(EPERM)].contains(nsError.code)
        {
            return true
        }

        let message = error.localizedDescription.lowercased()
        return message.contains("no readable app usage store was available") ||
            message.contains("operation not permitted") ||
            message.contains("permission denied") ||
            message.contains("no such file")
    }
}

enum ActivityQueries {
    private static let usageStorePaths = [
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Knowledge/knowledgeC.db")
            .path,
        "/private/var/db/CoreDuet/Knowledge/knowledgeC.db"
    ]
    private static let commandTimeout: TimeInterval = 3

    static func queryFrontmostApp() async throws -> String {
        await MainActor.run {
            NSWorkspace.shared.frontmostApplication?.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    static func queryRunningApps() async throws -> [String] {
        await MainActor.run {
            NSWorkspace.shared.runningApplications
                .filter { !$0.isTerminated && $0.activationPolicy != .prohibited }
                .compactMap(\.localizedName)
        }
    }

    static func queryTopApps(
        usageStorePaths: [String] = usageStorePaths,
        fallbackTopApps: [String]
    ) async throws -> [String] {
        try await Task.detached(priority: .utility) {
            try queryTopAppsSync(usageStorePaths: usageStorePaths, fallbackTopApps: fallbackTopApps)
        }.value
    }

    static func parseBundleRankingOutput(_ output: String) -> [ActivityBundleRanking] {
        parsePipeRows(output)
            .compactMap { line in
                let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
                guard parts.count == 2, let count = Int(parts[1]) else {
                    return nil
                }

                let bundleID = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !bundleID.isEmpty else {
                    return nil
                }

                return ActivityBundleRanking(bundleID: bundleID, count: count)
            }
    }

    private static func queryTopAppsSync(
        usageStorePaths: [String],
        fallbackTopApps: [String]
    ) throws -> [String] {
        let fileManager = FileManager.default

        for candidatePath in usageStorePaths where fileManager.isReadableFile(atPath: candidatePath) {
            do {
                let columns = try candidateUsageColumns(databasePath: candidatePath)
                guard !columns.isEmpty else {
                    continue
                }

                let unionQuery = columns.map { column in
                    let identifier = quoteSQLIdentifier(column)
                    return "SELECT \(identifier) AS bundle_id FROM ZOBJECT WHERE typeof(\(identifier)) = 'text'"
                }.joined(separator: " UNION ALL ")

                let rankingQuery = """
                WITH candidates AS (\(unionQuery))
                SELECT bundle_id, COUNT(*) AS usage_count
                FROM candidates
                WHERE bundle_id LIKE 'com.%'
                GROUP BY bundle_id
                ORDER BY usage_count DESC
                LIMIT 50;
                """

                let rankings = parseBundleRankingOutput(try runSQLite(databasePath: candidatePath, query: rankingQuery))
                guard !rankings.isEmpty else {
                    continue
                }

                var resolvedTopApps: [String] = []
                for ranking in rankings {
                    let appName = try resolveAppName(for: ranking.bundleID)
                    guard !appName.isEmpty, !resolvedTopApps.contains(appName) else {
                        continue
                    }

                    resolvedTopApps.append(appName)
                    if resolvedTopApps.count == fallbackTopApps.count {
                        break
                    }
                }

                if !resolvedTopApps.isEmpty {
                    return resolvedTopApps
                }
            } catch {
                continue
            }
        }

        throw ActivityQueryError.noReadableUsageStore
    }

    private static func candidateUsageColumns(databasePath: String) throws -> [String] {
        parsePipeRows(try runSQLite(databasePath: databasePath, query: "PRAGMA table_info(ZOBJECT);"))
            .compactMap { line in
                let columns = line.split(separator: "|").map(String.init)
                guard columns.indices.contains(1) else {
                    return nil
                }

                let columnName = columns[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = columnName.lowercased()
                guard normalized.contains("bundle") || normalized.contains("value") || normalized.contains("string") || normalized.contains("identifier") else {
                    return nil
                }

                return columnName
            }
    }

    private static func resolveAppName(for bundleID: String) throws -> String {
        let query = "kMDItemCFBundleIdentifier == \"\(bundleID.replacingOccurrences(of: "\"", with: "\\\""))\""
        let output = try ShellCommand.run("/usr/bin/mdfind", arguments: [query], timeout: commandTimeout)
        guard let path = parsePipeRows(output).first else {
            return ""
        }

        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func runSQLite(databasePath: String, query: String) throws -> String {
        try ShellCommand.run("/usr/bin/sqlite3", arguments: [databasePath, query], timeout: commandTimeout)
    }

    private static func parsePipeRows(_ output: String) -> [String] {
        output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func quoteSQLIdentifier(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

enum ActivityQueryError: LocalizedError {
    case noReadableUsageStore

    var errorDescription: String? {
        switch self {
        case .noReadableUsageStore:
            return "No readable app usage store was available."
        }
    }
}
