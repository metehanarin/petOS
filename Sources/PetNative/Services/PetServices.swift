import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import Intents
import IOKit.ps
import os

@MainActor
final class PetMonitorCoordinator {
    private weak var model: PetAppModel?
    private let persistence: PetPersistence
    private lazy var activityPoller = ActivityPoller(persistence: persistence)
    private let cpuSampler = CPUSampler()

    private var tasks: [Task<Void, Never>] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var focusModeChangeSource: DispatchSourceFileSystemObject?
    private var notificationMonitor: NotificationLogMonitor?
    private var requestedFocusAuthorization = false
    private var requestedAccessibilityAuthorization = false
    private var canReadFocusModeFiles = true
    private let focusLog = Logger(subsystem: "com.petnative.focus", category: "pipeline")

    init(model: PetAppModel, persistence: PetPersistence) {
        self.model = model
        self.persistence = persistence
    }

    func start() {
        guard tasks.isEmpty else {
            return
        }

        observeWorkspaceNotifications()
        observeFocusModeChanges()

        addRepeatingTask(every: AppConstants.timeOfDayPollInterval) { [weak self] in
            await self?.refreshTimeOfDay()
        }
        addRepeatingTask(every: 5) { [weak self] in
            await self?.refreshActivity()
        }
        addRepeatingTask(every: 15) { [weak self] in
            await self?.refreshPower()
        }
        addRepeatingTask(every: 900) { [weak self] in
            await self?.refreshWeather()
        }
        addRepeatingTask(every: 60) { [weak self] in
            await self?.refreshCalendar()
        }
        addRepeatingTask(every: 1) { [weak self] in
            await self?.refreshMusic()
        }
        addRepeatingTask(every: AppConstants.focusPollInterval) { [weak self] in
            await self?.refreshFocus()
        }
        addRepeatingTask(every: 2) { [weak self] in
            await self?.refreshIdleTime()
        }

        let notificationMonitor = NotificationLogMonitor()
        notificationMonitor.onDelivery = { [weak self] delivery in
            Task { @MainActor in
                self?.model?.applyNotificationDelivery(delivery)
            }
        }
        notificationMonitor.start()
        self.notificationMonitor = notificationMonitor
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        stopFocusModeChangeObserver()
        notificationMonitor?.stop()
        notificationMonitor = nil

        let notificationCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(notificationCenter.removeObserver)
        workspaceObservers.removeAll()
    }

    private func addRepeatingTask(
        every seconds: TimeInterval,
        operation: @escaping @Sendable () async -> Void
    ) {
        let task = Task {
            while !Task.isCancelled {
                await operation()
                do {
                    try await Task.sleep(for: .seconds(seconds))
                } catch {
                    break
                }
            }
        }
        tasks.append(task)
    }

    private func observeWorkspaceNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        workspaceObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.model?.updateWorldState { state in
                    state.system.suspended = true
                    state.system.locked = true
                    state.system.idleState = "locked"
                }
            }
        })

        workspaceObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.model?.updateWorldState { state in
                    state.system.suspended = false
                    state.system.locked = false
                    state.system.idleState = "active"
                }
            }
        })

        workspaceObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.model?.updateWorldState { state in
                    state.system.locked = true
                    state.system.idleState = "locked"
                }
            }
        })

        workspaceObservers.append(notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.model?.updateWorldState { state in
                    state.system.locked = false
                    if !state.system.suspended {
                        state.system.idleState = "active"
                    }
                }
            }
        })
    }

    private func observeFocusModeChanges() {
        guard canReadFocusModeFiles, focusModeChangeSource == nil else {
            return
        }

        let fileDescriptor = open(focusModeAssertionsURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            guard let source else {
                return
            }

            let event = source.data
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                await self.refreshFocus()

                if event.contains(.delete) || event.contains(.rename) {
                    self.stopFocusModeChangeObserver()
                    self.observeFocusModeChanges()
                }
            }
        }
        source.setCancelHandler {
            close(fileDescriptor)
        }
        focusModeChangeSource = source
        source.resume()
    }

    private func stopFocusModeChangeObserver() {
        focusModeChangeSource?.cancel()
        focusModeChangeSource = nil
    }

    private func refreshTimeOfDay() async {
        model?.updateTimeOfDay()
    }

    private func refreshIdleTime() async {
        let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        model?.updateWorldState { state in
            state.idle = idleSeconds
            if state.system.locked {
                state.system.idleState = "locked"
            } else if idleSeconds >= 30 {
                state.system.idleState = "idle"
            } else {
                state.system.idleState = "active"
            }
        }
    }

    private func refreshActivity() async {
        let activity = await activityPoller.poll()
        model?.updateWorldState { state in
            state.activity = activity
        }
    }

    private func refreshPower() async {
        let thermal = mapThermalState(ProcessInfo.processInfo.thermalState)
        let battery = readBatteryState() ?? .default
        let cpu = cpuSampler.sample()

        model?.updateWorldState { state in
            state.thermal = thermal
            state.battery = battery
            if let cpu {
                state.cpu = cpu
            }
        }
    }

    private func refreshWeather() async {
        guard let url = WeatherService.url() else {
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let weatherState = WeatherService.parseCurrentWeather(from: data) else {
                return
            }

            model?.updateWorldState { state in
                state.weather = weatherState
            }
        } catch {
            NSLog("[PetNative] weather refresh failed: \(error.localizedDescription)")
        }
    }

    private func refreshCalendar() async {
        guard isProperlyBundled() else {
            return
        }
        
        do {
            let output = try await runBlockingShell(
                "/usr/bin/osascript",
                arguments: calendarScriptArguments,
                timeout: 10
            )
            let calendarState = CalendarEventParser.parse(output, now: .now)

            model?.updateWorldState { state in
                state.calendar = calendarState
            }
        } catch {
            model?.updateWorldState { state in
                state.calendar = .default
            }
        }
    }

    private func refreshMusic() async {
        guard isProperlyBundled() else {
            return
        }

        do {
            let state = try await queryMusicState()
            model?.updateWorldState { worldState in
                worldState.music = state
            }
        } catch {
            model?.updateWorldState { worldState in
                worldState.music = .default
            }
        }
    }

    private func refreshFocus() async {
        observeFocusModeChanges()

        var authorized = false
        var focusStatusActive = false

        let center = INFocusStatusCenter.default
        if !requestedFocusAuthorization, center.authorizationStatus == .notDetermined {
            requestedFocusAuthorization = true
            
            // Only request authorization if we are properly bundled.
            // In CLI / swift run environments, this can trigger a TCC crash.
            if isProperlyBundled() && !ProcessInfo.processInfo.arguments.contains("--no-prompts") {
                _ = await center.requestAuthorization()
            }
        }
        authorized = center.authorizationStatus == .authorized
        focusStatusActive = authorized && (center.focusStatus.isFocused ?? false)
        focusLog.debug("infocus.status authorized=\(authorized, privacy: .public) is_focused=\(focusStatusActive, privacy: .public)")

        let mode = readCurrentFocusMode() ?? readControlCenterFocusMode()
        let focusModeLookupProtected = !canReadFocusModeFiles
        let active = mode != nil || focusStatusActive
        let source = focusSource(
            mode: mode,
            focusStatusActive: focusStatusActive,
            focusModeLookupProtected: focusModeLookupProtected
        )

        model?.updateWorldState { state in
            state.focus = FocusState(
                active: active,
                authorized: authorized,
                modeIdentifier: mode?.identifier,
                modeName: mode?.name,
                source: source
            )
        }
        focusLog.debug("focus.resolved active=\(active, privacy: .public) mode_id=\(mode?.identifier ?? "", privacy: .public) mode_name=\(mode?.name ?? "", privacy: .public) source=\(source, privacy: .public)")
    }

    private func runBlockingShell(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval? = nil
    ) async throws -> String {
        try await Task.detached(priority: .utility) {
            try ShellCommand.run(executable, arguments: arguments, timeout: timeout)
        }.value
    }

    private func queryMusicState() async throws -> MusicState {
        for player in ["Music", "Spotify"] {
            let isRunning = (try? await runBlockingShell("/usr/bin/pgrep", arguments: ["-x", player], timeout: 1.5)) != nil
            guard isRunning else {
                continue
            }

            let output = try await runBlockingShell(
                "/usr/bin/osascript",
                arguments: musicScriptArguments(for: player),
                timeout: 1.5
            )
            let parsed = MusicStateParser.parse(output, source: player)
            if parsed.playing {
                return parsed
            }
        }

        return .default
    }

    private func mapThermalState(_ state: ProcessInfo.ThermalState) -> ThermalSeverity {
        switch state {
        case .nominal:
            return .nominal
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return .fair
        }
    }

    private func readBatteryState() -> BatteryState? {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
            let source = sources.first,
            let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
        else {
            return nil
        }

        let currentCapacity = description[kIOPSCurrentCapacityKey as String] as? Double
        let maxCapacity = description[kIOPSMaxCapacityKey as String] as? Double
        let charging = (description[kIOPSIsChargingKey as String] as? Bool ?? false) ||
            (description[kIOPSIsChargedKey as String] as? Bool ?? false)
        let powerSourceState = description[kIOPSPowerSourceStateKey as String] as? String
        let onBatteryPower = powerSourceState == kIOPSBatteryPowerValue
        let level = (currentCapacity != nil && maxCapacity != nil && maxCapacity != 0)
            ? currentCapacity! / maxCapacity!
            : nil

        let status: String
        if let isCharged = description[kIOPSIsChargedKey as String] as? Bool, isCharged {
            status = "charged"
        } else if charging {
            status = "charging"
        } else if onBatteryPower {
            status = "discharging"
        } else {
            status = "unknown"
        }

        return BatteryState(
            level: level,
            charging: charging,
            onBatteryPower: onBatteryPower,
            status: status
        )
    }

    private var calendarScriptArguments: [String] {
        [
            "-e", "on padNumber(n)",
            "-e", "if n < 10 then return \"0\" & (n as text)",
            "-e", "return n as text",
            "-e", "end padNumber",
            "-e", "on isoStampForDate(theDate)",
            "-e", "set yyyy to (year of theDate as integer) as text",
            "-e", "set mm to my padNumber(month of theDate as integer)",
            "-e", "set dd to my padNumber(day of theDate as integer)",
            "-e", "set hh to my padNumber(hours of theDate)",
            "-e", "set mi to my padNumber(minutes of theDate)",
            "-e", "set ss to my padNumber(seconds of theDate)",
            "-e", "return yyyy & \"-\" & mm & \"-\" & dd & \"T\" & hh & \":\" & mi & \":\" & ss",
            "-e", "end isoStampForDate",
            "-e", "set nowDate to current date",
            "-e", "set cutoffDate to nowDate + (15 * minutes)",
            "-e", "set bestSummary to \"\"",
            "-e", "set bestDate to missing value",
            "-e", "tell application \"Calendar\"",
            "-e", "repeat with currentCalendar in calendars",
            "-e", "set matchingEvents to (every event of currentCalendar where its start date is greater than or equal to nowDate and its start date is less than or equal to cutoffDate)",
            "-e", "repeat with currentEvent in matchingEvents",
            "-e", "set currentStart to start date of currentEvent",
            "-e", "if bestDate is missing value or currentStart < bestDate then",
            "-e", "set bestDate to currentStart",
            "-e", "set bestSummary to summary of currentEvent",
            "-e", "end if",
            "-e", "end repeat",
            "-e", "end repeat",
            "-e", "end tell",
            "-e", "if bestDate is missing value then return \"\"",
            "-e", "return bestSummary & tab & my isoStampForDate(bestDate)"
        ]
    }

    private func musicScriptArguments(for player: String) -> [String] {
        [
            "-e", "tell application \"\(player)\"",
            "-e", "if player state is playing then",
            "-e", "return (get name of current track) & \"|\" & (get artist of current track) & \"|playing\"",
            "-e", "else",
            "-e", "return \"||\" & (player state as text)",
            "-e", "end if",
            "-e", "end tell"
        ]
    }

    private var focusModeAssertionsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/DoNotDisturb/DB/Assertions.json")
    }

    private var focusModeConfigurationsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/DoNotDisturb/DB/ModeConfigurations.json")
    }

    private func readCurrentFocusMode() -> FocusModeDescriptor? {
        guard canReadFocusModeFiles else {
            return nil
        }

        do {
            let assertionsData = try Data(contentsOf: focusModeAssertionsURL)
            let configurationsData = try Data(contentsOf: focusModeConfigurationsURL)
            let descriptor = FocusModeNameResolver.resolveMode(
                assertionsData: assertionsData,
                configurationsData: configurationsData
            )
            if let descriptor {
                focusLog.debug("assertions.read.ok mode_id=\(descriptor.identifier, privacy: .public) mode_name=\(descriptor.name ?? "", privacy: .public)")
            } else {
                focusLog.debug("assertions.read.ok mode_id= mode_name= (no active mode in assertions)")
            }
            return descriptor
        } catch {
            if isProtectedFocusModeLookupError(error) {
                focusLog.debug("assertions.read.denied")
                canReadFocusModeFiles = false
                stopFocusModeChangeObserver()
            } else if isMissingFocusModeLookupError(error) {
                focusLog.debug("assertions.read.empty (no Assertions.json)")
                return nil
            } else {
                focusLog.debug("assertions.read.error error=\(error.localizedDescription, privacy: .public)")
                NSLog("[PetNative] focus mode lookup failed: \(error.localizedDescription)")
            }
            return nil
        }
    }

    private func readControlCenterFocusMode() -> FocusModeDescriptor? {
        guard accessibilityTrustedForControlCenterLookup() else {
            focusLog.debug("controlcenter.scrape.denied")
            return nil
        }

        guard
            let controlCenterPID = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.controlcenter")
                .first?
                .processIdentifier
        else {
            focusLog.debug("controlcenter.scrape.empty (no controlcenter process)")
            return nil
        }

        let appElement = AXUIElementCreateApplication(controlCenterPID)
        let descriptor = ControlCenterFocusSignalParser.resolveMode(
            from: collectAccessibilityStrings(from: appElement, remainingDepth: 8)
        )
        if let descriptor {
            focusLog.debug("controlcenter.scrape.ok mode_id=\(descriptor.identifier, privacy: .public) mode_name=\(descriptor.name ?? "", privacy: .public)")
        } else {
            focusLog.debug("controlcenter.scrape.empty (no sleep label found)")
        }
        return descriptor
    }

    private func collectAccessibilityStrings(from element: AXUIElement, remainingDepth: Int) -> [String] {
        var elementStrings: [String] = []
        let attributes = [
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXValueAttribute,
            kAXHelpAttribute,
            kAXIdentifierAttribute,
            kAXRoleAttribute,
            kAXSubroleAttribute
        ]

        for attribute in attributes {
            guard let value = copyAccessibilityAttribute(element, attribute: attribute as CFString) else {
                continue
            }

            appendAccessibilityStrings(from: value, to: &elementStrings)
        }

        var strings = elementStrings
        if isAccessibilityElementSelected(element), let selectedSleepLabel = selectedSleepFocusLabel(from: elementStrings) {
            strings.append(selectedSleepLabel)
        }

        guard remainingDepth > 0 else {
            return strings
        }

        guard let childrenValue = copyAccessibilityAttribute(element, attribute: kAXChildrenAttribute as CFString) else {
            return strings
        }

        let children = childrenValue as? [AXUIElement] ?? []
        for child in children {
            strings.append(contentsOf: collectAccessibilityStrings(from: child, remainingDepth: remainingDepth - 1))
        }

        return strings
    }

    private func copyAccessibilityElementAttribute(_ element: AXUIElement, attribute: CFString) -> AXUIElement? {
        guard let value = copyAccessibilityAttribute(element, attribute: attribute) else {
            return nil
        }

        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func copyAccessibilityAttribute(_ element: AXUIElement, attribute: CFString) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }

        return value
    }

    private func isAccessibilityElementSelected(_ element: AXUIElement) -> Bool {
        guard let value = copyAccessibilityAttribute(element, attribute: kAXSelectedAttribute as CFString) else {
            return false
        }

        return (value as? Bool) == true || (value as? NSNumber)?.boolValue == true
    }

    private func selectedSleepFocusLabel(from strings: [String]) -> String? {
        let hasSleepLabel = strings
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .contains { value in
                value == "sleep" || value.contains("sleep focus")
            }

        return hasSleepLabel ? "selected sleep focus" : nil
    }

    private func appendAccessibilityStrings(from value: AnyObject, to strings: inout [String]) {
        if let string = value as? String {
            strings.append(string)
        } else if let number = value as? NSNumber {
            strings.append(number.stringValue)
        } else if let values = value as? [AnyObject] {
            for value in values {
                appendAccessibilityStrings(from: value, to: &strings)
            }
        }
    }

    private func focusSource(
        mode: FocusModeDescriptor?,
        focusStatusActive: Bool,
        focusModeLookupProtected: Bool
    ) -> String {
        if mode != nil {
            return focusModeLookupProtected ? "control-center" : "named-mode"
        }

        if focusModeLookupProtected && focusStatusActive {
            return "protected-mode-status"
        }

        return "status"
    }

    private func isProperlyBundled() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            return false
        }
        
        // If we're running from a .build directory, we're likely in a dev/CLI environment
        // where TCC prompts will crash the process.
        let path = Bundle.main.bundlePath
        if path.contains("/.build/") || path.contains("/DerivedData/") {
            return false
        }
        
        return !bundleID.isEmpty
    }

    private func accessibilityTrustedForControlCenterLookup() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        guard !requestedAccessibilityAuthorization else {
            return false
        }

        requestedAccessibilityAuthorization = true
        
        // In some environments, AXIsProcessTrustedWithOptions with Prompt:true can crash 
        // if the app isn't fully bundled or if TCC is in a weird state.
        if !isProperlyBundled() {
            return false
        }

        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func isProtectedFocusModeLookupError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoPermissionError {
            return true
        }

        let message = error.localizedDescription.lowercased()
        return message.contains("operation not permitted") || message.contains("permission denied")
    }

    private func isMissingFocusModeLookupError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoSuchFileError {
            return true
        }

        return error.localizedDescription.lowercased().contains("no such file")
    }
}

final class NotificationLogMonitor: @unchecked Sendable {
    var onDelivery: ((NotificationDelivery) -> Void)?

    private var process: Process?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var buffer = Data()
    private var disposed = false
    private var restartWorkItem: DispatchWorkItem?
    private var lastPresentedAtByBundleID: [String: Date] = [:]

    func start() {
        disposed = false
        buffer.removeAll(keepingCapacity: true)
        lastPresentedAtByBundleID.removeAll(keepingCapacity: true)
        startStream()
    }

    func stop() {
        disposed = true
        restartWorkItem?.cancel()
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        process?.terminationHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
    }

    private func startStream() {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "stream",
            "--style", "ndjson",
            "--color", "none",
            "--level", "debug",
            "--predicate",
            "process == \"usernoted\" AND (eventMessage CONTAINS[c] \"Presenting <NotificationRecord\" OR eventMessage CONTAINS[c] \"performing delayed database write (delivered)\")"
        ]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        self.process = process
        stdoutHandle = stdoutPipe.fileHandleForReading
        stderrHandle = stderrPipe.fileHandleForReading

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            self?.consume(data)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            let stderr = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !stderr.isEmpty {
                NSLog("[PetNative] notification log stderr: \(stderr)")
            }
        }

        process.terminationHandler = { [weak self] _ in
            self?.scheduleRestart()
        }

        do {
            try process.run()
        } catch {
            NSLog("[PetNative] notification monitor failed to launch: \(error.localizedDescription)")
            scheduleRestart()
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)

        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(...newlineIndex)

            guard
                let line = String(data: lineData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !line.isEmpty,
                let delivery = NotificationLogParser.parseDelivery(from: line)
            else {
                continue
            }

            guard shouldEmit(delivery) else {
                continue
            }

            onDelivery?(delivery)
        }
    }

    private func shouldEmit(_ delivery: NotificationDelivery) -> Bool {
        let bundleID = delivery.bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !bundleID.isEmpty else {
            return false
        }

        prunePresentedDeliveries(now: delivery.timestamp)

        if delivery.deliveryState == "presented" {
            lastPresentedAtByBundleID[bundleID] = delivery.timestamp
            return true
        }

        guard
            delivery.deliveryState == "delivered",
            let presentedAt = lastPresentedAtByBundleID[bundleID]
        else {
            return true
        }

        let elapsed = delivery.timestamp.timeIntervalSince(presentedAt)
        return elapsed < 0 || elapsed > AppConstants.notificationDelayedFallbackDeduplicationWindow
    }

    private func prunePresentedDeliveries(now: Date) {
        lastPresentedAtByBundleID = lastPresentedAtByBundleID.filter { _, presentedAt in
            abs(now.timeIntervalSince(presentedAt)) <= AppConstants.notificationDelayedFallbackDeduplicationWindow
        }
    }

    private func scheduleRestart() {
        guard !disposed else {
            return
        }

        stop()
        disposed = false
        restartWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.disposed else {
                return
            }

            self.startStream()
        }
        restartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + AppConstants.notificationMonitorRestartDelay, execute: workItem)
    }
}
