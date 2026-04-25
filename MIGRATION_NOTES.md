# Native Migration Notes

## Current Electron Architecture

- `src/main/index.js`: app lifecycle, window creation, watcher startup, IPC registration, context menu wiring
- `src/main/window.js`: transparent always-on-top `BrowserWindow`
- `src/main/worldState.js`: mutable world-state store and reaction/event queue
- `src/main/moodEngine.js`: mood resolution from focus, idle, battery, music, notifications, and calendar state
- `src/main/persistence.js`: app state storage through `electron-store`
- `src/main/watchers/*.js`: polling/system integrations for activity, calendar, focus, idle, music, notifications, power, time of day, weather, and Claude hook
- `src/renderer/*`: HTML/CSS renderer, sprite animation, aura/reaction presentation, and drag-friendly shell

## Native Target Architecture

- `Sources/PetNative/PetNativeApp.swift`: SwiftUI app entry and menu bar companion
- `Sources/PetNative/PetAppModel.swift`: observable app state, persistence coordination, reaction handling, and mood recomputation
- `Sources/PetNative/Models/*`: native world-state/data models matching the Electron state shape
- `Sources/PetNative/Logic/PetMoodEngine.swift`: direct Swift port of the Electron mood rules
- `Sources/PetNative/Persistence/PetPersistence.swift`: JSON-backed native persistence
- `Sources/PetNative/Services/PetServices.swift`: native/polled system integration layer
- `Sources/PetNative/Window/PetWindowManager.swift`: AppKit-only window configuration for the floating pet shell
- `Sources/PetNative/UI/*`: SwiftUI pet shell, sprite animation, aura, reaction burst, settings view

## Electron To Native Mapping

- Electron main process -> `PetNativeApp`, `PetAppModel`, `PetMonitorCoordinator`
- Renderer DOM/CSS -> SwiftUI views in `UI/`
- IPC/preload bridge -> direct observable state updates in `PetAppModel`
- `BrowserWindow` -> SwiftUI scene + narrow AppKit window customization
- `electron-store` -> JSON file persistence in Application Support
- watcher manager -> native coordinator with async polling tasks and workspace notifications

## First Implemented Batch

- native Swift package scaffold
- ported state model and mood engine
- transparent floating pet window
- menu bar extra + native settings surface
- sprite-backed SwiftUI pet renderer using copied PNG mood assets
- persistence for age, position, sound, cached top apps, and reactions
- integrations for time, idle, front app/running apps, battery/thermal/CPU, weather, calendar, music, focus, and notification log alerts
- native localhost reaction hook equivalent to `claudeHook`
- debug mood cycling and structured debug snapshot logging
- Swift package test target covering mood rules, services, persistence, reaction HTTP handling, and sprite resources

## Known Gaps / Next Batch

- replace remaining shell-script-backed integrations with tighter native APIs where practical
- decide whether to keep the app as an accessory/menu-bar companion long-term or promote it to a fuller app bundle with richer settings/onboarding
- evaluate widget/App Group support after the main app behavior is fully validated
