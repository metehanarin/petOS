import Foundation

enum ShellCommandError: LocalizedError {
    case failedToLaunch(String)
    case nonZeroExit(code: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case let .failedToLaunch(message):
            return message
        case let .nonZeroExit(code, stderr):
            if stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Command exited with code \(code)."
            }

            return "Command exited with code \(code): \(stderr)"
        }
    }
}

enum ShellCommand {
    static func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval? = nil
    ) throws -> String {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ShellCommandError.failedToLaunch(error.localizedDescription)
        }

        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
                }
            }
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(decoding: stdoutData, as: UTF8.self)
        let stderr = String(decoding: stderrData, as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw ShellCommandError.nonZeroExit(code: process.terminationStatus, stderr: stderr)
        }

        return stdout
    }
}
