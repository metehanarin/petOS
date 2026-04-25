import AppKit
import SwiftUI

final class PetAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: false)
    }
}

@main
struct PetNativeApp: App {
    @NSApplicationDelegateAdaptor(PetAppDelegate.self) private var appDelegate
    @StateObject private var model = PetAppModel()

    var body: some Scene {
        WindowGroup(AppConstants.appName) {
            ContentView(model: model)
        }
        .defaultSize(width: AppConstants.windowSize.width, height: AppConstants.windowSize.height)
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("Pet") {
                Button("Recenter", action: model.recenterWindow)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Reset Pet", action: model.resetPet)
                Button("Reload Sprites", action: model.reloadSprites)
                Button(model.soundEnabled ? "Disable Sound" : "Enable Sound", action: model.toggleSound)
            }

            if model.debugEnabled {
                CommandMenu("Debug") {
                    Button("Cycle Mood", action: model.cycleDebugMood)
                        .keyboardShortcut("d", modifiers: [.command, .shift])
                    Button("Clear Mood Override", action: model.clearDebugMoodOverride)
                }
            }
        }

        Settings {
            SettingsView(model: model)
        }

        MenuBarExtra(AppConstants.appName, systemImage: "pawprint.fill") {
            Button("Recenter", action: model.recenterWindow)
            Button("Reset Pet", action: model.resetPet)
            Button("Reload Sprites", action: model.reloadSprites)
            Button(model.soundEnabled ? "Disable Sound" : "Enable Sound", action: model.toggleSound)
            if model.debugEnabled {
                Divider()
                Button("Cycle Mood", action: model.cycleDebugMood)
                Button("Clear Mood Override", action: model.clearDebugMoodOverride)
            }
            Divider()
            SettingsLink {
                Text("Settings")
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
