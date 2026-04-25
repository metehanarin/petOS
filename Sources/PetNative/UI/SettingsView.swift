import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: PetAppModel

    @State private var showingResetConfirmation = false
    @State private var copiedReactionURL = false

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeaderView(model: model)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)

            TabView {
                careTab
                    .tabItem {
                        Label("Care", systemImage: "heart.fill")
                    }

                behaviorTab
                    .tabItem {
                        Label("Behavior", systemImage: "pawprint.fill")
                    }

                signalsTab
                    .tabItem {
                        Label("Signals", systemImage: "waveform.path.ecg")
                    }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 560, height: 520)
        .task {
            model.start()
        }
        .alert("Reset Pet?", isPresented: $showingResetConfirmation) {
            Button("Reset", role: .destructive) {
                model.resetPet()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears age, reactions, saved position, and preferences.")
        }
    }

    private var careTab: some View {
        Form {
            Section("Care") {
                Toggle("Meow sound", isOn: soundBinding)
                Toggle("Swipe down to meow", isOn: swipeMeowBinding)
            }

            Section("Play") {
                HStack(spacing: 8) {
                    reactionButton("Sparkle", systemImage: "sparkles", type: "sparkle_clap")
                    reactionButton("Heart", systemImage: "heart.fill", type: "heart_love")
                    reactionButton("Zap", systemImage: "bolt.fill", type: "zap")
                    reactionButton("Pulse", systemImage: "circle.hexagongrid.fill", type: "pulse")
                }
            }

            Section("Position") {
                HStack {
                    Button {
                        model.recenterWindow()
                    } label: {
                        Label("Recenter", systemImage: "scope")
                    }

                    Spacer()

                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        Label("Reset Pet", systemImage: "arrow.counterclockwise")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var behaviorTab: some View {
        Form {
            Section("Window") {
                Toggle("Always on top", isOn: alwaysOnTopBinding)
            }

            Section("Local hook") {
                Toggle("Reaction server", isOn: reactionServerBinding)

                HStack(spacing: 10) {
                    Text(reactionURL)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        copyReactionURL()
                    } label: {
                        Label(copiedReactionURL ? "Copied" : "Copy", systemImage: copiedReactionURL ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
            }

            Section("Detected top apps") {
                if displayedTopApps.isEmpty {
                    Label("No app data yet", systemImage: "app.dashed")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(displayedTopApps, id: \.self) { appName in
                        Label(
                            appName,
                            systemImage: appName == model.worldState.activity.frontApp ? "arrow.right.circle.fill" : "app.dashed"
                        )
                        .lineLimit(1)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var signalsTab: some View {
        Form {
            Section("Pet") {
                SettingsStatusRow(title: "Mood", value: model.currentMood.displayName, systemImage: "pawprint.fill")
                SettingsStatusRow(title: "Age", value: "\(model.age) days", systemImage: "calendar")
            }

            Section("World") {
                SettingsStatusRow(title: "Focus", value: focusSummary, systemImage: "moon.zzz.fill")
                SettingsStatusRow(title: "Front app", value: frontAppSummary, systemImage: "macwindow")
                SettingsStatusRow(title: "Battery", value: batterySummary, systemImage: "battery.100percent")
                SettingsStatusRow(title: "Weather", value: weatherSummary, systemImage: "cloud.sun.fill")
                SettingsStatusRow(title: "Music", value: musicSummary, systemImage: "music.note")
                SettingsStatusRow(title: "Calendar", value: calendarSummary, systemImage: "calendar.badge.clock")
                SettingsStatusRow(title: "Notifications", value: notificationSummary, systemImage: "bell.badge.fill")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var soundBinding: Binding<Bool> {
        Binding(
            get: { model.soundEnabled },
            set: { model.setSoundEnabled($0) }
        )
    }

    private var swipeMeowBinding: Binding<Bool> {
        Binding(
            get: { model.swipeMeowEnabled },
            set: { model.setSwipeMeowEnabled($0) }
        )
    }

    private var reactionServerBinding: Binding<Bool> {
        Binding(
            get: { model.reactionServerEnabled },
            set: { model.setReactionServerEnabled($0) }
        )
    }

    private var alwaysOnTopBinding: Binding<Bool> {
        Binding(
            get: { model.alwaysOnTop },
            set: { model.setAlwaysOnTop($0) }
        )
    }

    private var reactionURL: String {
        "http://127.0.0.1:\(AppConstants.reactionServerPort)/reaction"
    }

    private var displayedTopApps: [String] {
        Array(model.worldState.activity.topApps.prefix(8))
    }

    private var frontAppSummary: String {
        model.worldState.activity.frontApp.isEmpty ? "None" : model.worldState.activity.frontApp
    }

    private var focusSummary: String {
        let focus = model.worldState.focus
        guard focus.authorized else {
            return "Not authorized"
        }

        guard focus.active else {
            return "Off"
        }

        return focus.modeName ?? "On"
    }

    private var batterySummary: String {
        let battery = model.worldState.battery
        let percentage = Int(((battery.level ?? 0) * 100).rounded())
        return "\(percentage)% - \(battery.status.capitalized)"
    }

    private var weatherSummary: String {
        let weather = model.worldState.weather
        if let tempC = weather.tempC {
            return "\(weather.condition.rawValue.capitalized) - \(Int(tempC.rounded())) C"
        }

        return weather.condition.rawValue.capitalized
    }

    private var musicSummary: String {
        let music = model.worldState.music
        guard music.playing else {
            return music.status.capitalized
        }

        if music.track.isEmpty {
            return music.source ?? "Playing"
        }

        if music.artist.isEmpty {
            return music.track
        }

        return "\(music.track) - \(music.artist)"
    }

    private var calendarSummary: String {
        guard let event = model.worldState.calendar.nextEvent else {
            return "None"
        }

        return "\(event.title) in \(event.minutesAway)m"
    }

    private var notificationSummary: String {
        let notifications = model.worldState.notifications
        guard let bundleID = notifications.lastBundleID else {
            return "None"
        }

        if let alertUntil = notifications.alertUntil, alertUntil > .now {
            return "Alerting - \(bundleID)"
        }

        if let deliveredAt = notifications.lastDeliveredAt {
            return "\(bundleID) at \(deliveredAt.formatted(date: .omitted, time: .shortened))"
        }

        return bundleID
    }

    private func reactionButton(_ title: String, systemImage: String, type: String) -> some View {
        Button {
            model.enqueueReaction(type: type)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
    }

    private func copyReactionURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reactionURL, forType: .string)
        copiedReactionURL = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            copiedReactionURL = false
        }
    }
}

private struct SettingsHeaderView: View {
    @ObservedObject var model: PetAppModel

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.regularMaterial)

                PetStageView(
                    mood: model.currentMood,
                    worldState: model.worldState,
                    reactionVariant: model.reactionVariant,
                    reactionToken: model.reactionToken,
                    notificationToken: model.notificationToken
                )
                .scaleEffect(0.46)
                .frame(width: 116, height: 98)
            }
            .frame(width: 128, height: 98)

            VStack(alignment: .leading, spacing: 8) {
                Label(AppConstants.appName, systemImage: "pawprint.fill")
                    .font(.title3.weight(.semibold))

                Text("\(model.currentMood.displayName) - \(model.age) days old")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    SettingsBadge(title: model.soundEnabled ? "Sound on" : "Sound off", systemImage: "speaker.wave.2.fill")
                    SettingsBadge(title: model.reactionServerEnabled ? "Hook on" : "Hook off", systemImage: "point.3.connected.trianglepath.dotted")
                    SettingsBadge(title: model.alwaysOnTop ? "On top" : "Floating", systemImage: "square.stack.3d.up.fill")
                }
            }

            Spacer()
        }
    }
}

private struct SettingsBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
    }
}

private struct SettingsStatusRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(title)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}

private extension PetMood {
    var displayName: String {
        rawValue.capitalized
    }
}
