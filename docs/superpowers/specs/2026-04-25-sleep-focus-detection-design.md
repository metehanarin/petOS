# Sleep Focus Detection Reliability — Design Spec

**Date:** 2026-04-25
**Status:** Approved (user)
**Scope:** petOS (Sources/petOS)

## Problem

When macOS Sleep Focus mode is turned on, the pet does not transition to the `.sleeping` mood/animation. The mood engine itself is correct (covered by `PetMoodEngineTests`); the bug lives in the **input pipeline** that produces `WorldState.focus`. In dev mode (`swift run`) the pipeline is starved of input, and even in a properly bundled app several edge cases leak through (partial focus descriptors, denied permissions, transient AX failures) that today silently resolve to a non-sleep mood.

## Goal

Sleep Focus mode reliably triggers the `.sleeping` animation in **both** modes:

1. Development invocations (today: `swift run petOS`)
2. A properly built `.app` bundle launched normally

Stretch goal: when sleep is *not* detected despite being on, the operator can determine why in seconds via structured logs.

## Non-Goals

- Performance/latency tuning of the focus poll (currently 1s; not in scope)
- New focus-mode-specific moods beyond sleeping
- Replacing the mood engine architecture
- Code-signing with a paid Apple Developer ID (ad-hoc signing only)

## Root Cause Summary

macOS TCC (Transparency, Consent, Control) keys permission grants by `(bundle ID, code-signing requirement)`. A `swift run` binary has no stable identity, so:

- `Sources/petOS/Services/PetServices.swift` lines 317 and 667 contain an `isProperlyBundled()` gate that **skips Focus and Accessibility permission prompts** when the binary lives under `.build/` or `DerivedData/`. This gate exists because invoking `requestAuthorization()` from such a process can hard-crash. Net effect in dev mode: `INFocusStatusCenter` is never authorized, the AX path is never granted, and `~/Library/DoNotDisturb/DB/Assertions.json` is sandbox-protected on macOS 14+ — so all three sources are dead and `focus.active` stays `false`.
- The `isUnidentifiedFocusAssumedAsSleep` fallback at `PetMoodEngine.swift:207-215` only fires when both `modeIdentifier` and `modeName` are empty. Real-world cases where one is populated but the other is `nil` (or near-but-not-equal to "sleep") fall through and resolve to non-sleep moods.

## Approach

A **bundling tooling layer** + **defense-in-depth pipeline hardening**. Both modes converge on the same infrastructure: a generated `.app` bundle with a stable bundle ID. Once the bundle exists, the in-app permission gates can be removed, the engine fallback can be tightened, and structured diagnostics make any future regression visible from `log stream`.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ tools/run.sh                                                │
│   swift build → wrap in .app → ad-hoc codesign → exec       │
│   (dev mode now produces a bundle with stable identity)     │
└──────────────────┬──────────────────────────────────────────┘
                   │ (TCC can grant against this identity)
                   ▼
┌─────────────────────────────────────────────────────────────┐
│ PetServices.refreshFocus()  — input pipeline (HARDENED)     │
│   1. Assertions.json (FDA)                                  │
│   2. Control Center AX scrape                               │
│   3. INFocusStatus boolean ◄── now actually granted         │
│   ★ os_log every branch decision                            │
└──────────────────┬──────────────────────────────────────────┘
                   ▼ FocusState
┌─────────────────────────────────────────────────────────────┐
│ PetMoodEngine — fallback rule TIGHTENED                     │
│   .sleeping if active && not(known-non-sleep mode)          │
│   Returns MoodResolution(mood, reason) for diagnostics      │
└──────────────────┬──────────────────────────────────────────┘
                   ▼
┌─────────────────────────────────────────────────────────────┐
│ SettingsView "System Access" section                        │
│   Read-only TCC status + deep links to System Settings      │
└─────────────────────────────────────────────────────────────┘
```

## Components

### C1. Bundling tooling

**Files:**

- `tools/_bundle.sh` — shared shell function `build_bundle(config, output_dir)`
- `tools/run.sh` — dev runner: builds debug, bundles, ad-hoc codesigns, execs foreground
- `tools/build-release.sh` — release builder: builds release, bundles into `dist/petOS.app`

**Bundle layout produced:**

```
.build/bundle/petOS.app/
└── Contents/
    ├── Info.plist          ← copy of Sources/petOS/Info.plist
    ├── MacOS/
    │   └── petOS       ← swift build product
    └── Resources/
        ├── Sounds/         ← from Sources/petOS/Resources/
        └── *.png           ← sprite assets
```

**Codesigning:** `codesign -s - --force --deep <bundle>` — ad-hoc signature derived from bundle ID + content hash. No paid Apple ID required. TCC grants persist across rebuilds as long as Info.plist and entitlements don't change.

**Rebuild strategy (`run.sh`):** inner-binary swap.

- Always run `swift build`.
- Compare new binary signing requirement against the existing bundle's. If unchanged, copy the new `MacOS/petOS` over the existing one and re-sign in place (TCC grant survives). If changed, rebuild the full bundle from scratch.
- `./tools/run.sh --clean` removes `.build/bundle/` before building (use when entitlements or Info.plist change and you want a deterministic rebuild).
- All extra args after `--` pass through to the binary (e.g., `./tools/run.sh -- --debug`).

**Interface guarantees (so other tooling can rely on the bundle layout):**

- After successful run of `tools/run.sh` or `tools/build-release.sh`, the produced `.app` directory contains a valid `Info.plist`, an executable at `Contents/MacOS/petOS`, copied resources, and is ad-hoc codesigned.
- Bundle ID: `com.petos.petOS` (matches existing `Info.plist`).
- Exit code 0 on success; non-zero on any build/sign failure with stderr describing what failed.

### C2. Pipeline gate removal + startup preflight

**Files:** `Sources/petOS/Services/PetServices.swift`, `Sources/petOS/petOSApp.swift`

- Remove the `isProperlyBundled()` gates at lines 317 and 667. The Focus and Accessibility permission prompts will now fire as designed.
- Remove the `isProperlyBundled()` helper itself (no longer called).
- Add a startup preflight in `petOSApp` (or a new `PetLaunchPreflight.swift`) that exits with `EX_CONFIG` (78) if the binary is being executed outside an `.app` bundle. The check: `Bundle.main.bundlePath.hasSuffix(".app")` returns true. (This intentionally subsumes the existing `isProperlyBundled` heuristic which excluded both `/.build/` and `/DerivedData/` — the new check is positive rather than negative, so any future build-output directory is also correctly rejected.) On failure, write a one-line message to stderr pointing the operator at `./tools/run.sh`.

This converts a previously silent failure mode (running raw `swift run` → permissions silently disabled → sleep never detected) into a loud, immediate, self-documenting one.

### C3. Engine fallback generalization

**File:** `Sources/petOS/Logic/PetMoodEngine.swift`

Replace the empty-only check (lines 207-215) with the **balanced rule**:

> `sleeping` IF `focus.active` AND identifier ∉ known-non-sleep identifiers AND name ∉ known-non-sleep names.

**Known-non-sleep identifiers** (`static let`):

```
com.apple.focus.work
com.apple.focus.personal
com.apple.focus.gaming
com.apple.focus.fitness
com.apple.focus.mindfulness
com.apple.focus.driving
com.apple.donotdisturb.mode.driving
com.apple.focus.reading
com.apple.donotdisturb
```

**Known-non-sleep names** (normalized lowercased, `static let`):

```
work, working, personal, gaming, fitness,
mindfulness, driving, reading,
do not disturb, dnd
```

A focus is "non-sleep" if either the normalized identifier is in the identifier set OR the normalized name is in the name set. A focus is treated as sleep if `active && !nonSleep`. Empty identifier + empty name continues to resolve to sleep (this is a strict subset of the new rule, so existing tests stay green).

**Trade-off accepted:** custom user-named focus modes (e.g., "Deep Work") will resolve to sleep unless their name matches an entry in the exclusion set. We document this as expected behavior. The exclusion sets are `static let` constants — extending them is a one-line change.

**Identifier-namespace note:** Apple has historically used both `com.apple.focus.*` and `com.apple.donotdisturb.mode.*` namespaces for built-in focuses (driving in particular has appeared under both). The exclusion set covers both forms where ambiguity exists. A misnamed or new built-in identifier we haven't catalogued falls into the sleep branch — which is the documented safe default.

### C4. Diagnostics layer

**File:** `Sources/petOS/Services/PetServices.swift`, `Sources/petOS/Logic/PetMoodEngine.swift`, `Sources/petOS/PetAppModel.swift`

Single `OSLog` subsystem `com.petos.focus`, category `pipeline`. All events logged at `.debug` level (free in release; user opts in with `log config --mode "level:debug" --subsystem com.petos.focus`).

**Logged events:**

| Event | Fields |
|---|---|
| `assertions.read.ok` | `mode_id`, `mode_name` |
| `assertions.read.denied` | (TCC blocked) |
| `assertions.read.error` | `error` |
| `controlcenter.scrape.ok` | `mode_id`, `mode_name` |
| `controlcenter.scrape.denied` | (no AX permission) |
| `controlcenter.scrape.empty` | (AX worked, no sleep label found) |
| `infocus.status` | `authorized`, `is_focused` |
| `focus.resolved` | `active`, `mode_id`, `mode_name`, `source` |
| `mood.resolved` | `mood`, `reason` |

**Engine signature change** to surface the reason:

```swift
struct MoodResolution: Equatable {
    let mood: PetMood
    let reason: Reason
}

enum Reason: String, CaseIterable {
    case sleepFocusExplicit          = "sleep_focus_explicit"
    case sleepWindow                 = "sleep_window"
    case unidentifiedFocusAssumedSleep = "unidentified_focus_assumed_sleep"
    case workFocus                   = "work_focus"
    case productivityApp             = "productivity_app"
    case focusWithTopApp             = "focus_with_top_app"
    case imminentCalendar            = "imminent_calendar"
    case notificationAlert           = "notification_alert"
    case sickCPU                     = "sick_cpu"
    case sickThermal                 = "sick_thermal"
    case sickBattery                 = "sick_battery"
    case musicPlaying                = "music_playing"
    case idleDefault                 = "idle_default"
}
// Swift-conventional case names with explicit snake_case raw values
// preserve grep-friendly log queries.

static func resolveBaseMood(for state: WorldState, now: Date = .now) -> MoodResolution
```

A small extension `var mood: PetMood { resolveBaseMood(for: state).mood }` keeps existing one-liner call sites compact. The model logs `mood.resolved` with the reason on every recompute.

### C5. Permissions surfacing in Settings

**Files:** `Sources/petOS/Services/PermissionsInspector.swift` (new), `Sources/petOS/UI/SettingsView.swift`

**`PermissionsInspector`** — pure read-only. **Does not prompt.**

```swift
enum Pane { case focus, accessibility, fullDiskAccess }

struct PermissionsSnapshot: Equatable {
    enum Status { case granted, denied, notDetermined, unknown }
    let focusStatus: Status        // INFocusStatusCenter.authorizationStatus
    let accessibility: Status      // AXIsProcessTrusted (no prompt)
    let fullDiskAccess: Status     // probe: 1-byte read of Assertions.json
}

enum PermissionsInspector {
    static func snapshot() -> PermissionsSnapshot
    static func openSystemSettings(for pane: Pane)
}
```

FDA probe semantics:

- Read succeeds → `granted`
- `NSFileReadNoPermissionError` / "operation not permitted" → `denied`
- `NSFileReadNoSuchFileError` (no Focus modes ever set up) → `unknown`
- Other I/O error → `unknown`

**Settings UI** — new "System Access" section in `SettingsView`:

```
System Access
─────────────────────────────────────────
Focus              ●  Granted
Accessibility      ●  Granted    [Manage…]
Full Disk Access   ●  Not granted [Open System Settings…]

   Sleep detection works best when all three are granted.
   Without Full Disk Access, the app falls back to reading
   Control Center, which requires the panel to be visible.
```

Polled every 2 seconds while the Settings window is visible (driven by SwiftUI `Timer.publish`, cancelled `.onDisappear`). Clicking a button opens the matching System Settings pane via the `x-apple.systempreferences:` URL scheme. No programmatic toggle — macOS doesn't allow it.

### C6. Test infrastructure: focus pipeline isolation

**Files:** `Sources/petOS/Services/FocusSourceProvider.swift` (new protocol), `Tests/petOSTests/FocusPipelineTests.swift` (new)

Today the focus refresh logic in `PetServices` calls concrete file/AX/INFocus APIs directly, which makes it untestable without a real macOS environment. Extract a protocol:

```swift
protocol FocusSourceProvider {
    func readAssertionsFile() throws -> FocusModeDescriptor?
    func scrapeControlCenter() -> FocusModeDescriptor?
    func queryInFocusStatus() -> (authorized: Bool, isFocused: Bool)
}
```

Production keeps existing behavior in a `LiveFocusSourceProvider` that wraps the current code paths verbatim. `FakeFocusSourceProvider` lets tests inject any combination of (success, denied, error, partial-descriptor) for each source.

The protocol extraction is a separate commit from the bug-fix proper so the diff for the behavior change stays small and reviewable.

## Data Flow (after changes)

1. `PetMonitorCoordinator` polling task fires every `AppConstants.focusPollInterval` (1s).
2. `refreshFocus()` calls each source via `FocusSourceProvider`. Each call emits one `os_log` event describing what happened.
3. Source results are merged: first non-nil descriptor wins; `INFocusStatus` boolean fills in `active` if no descriptor came back.
4. `FocusState` is written to `WorldState`, which emits `focus.resolved`.
5. On the next mood recompute (driven by world-state change), `PetMoodEngine.resolveBaseMood` returns `MoodResolution(mood, reason)`.
6. `PetAppModel` stores `currentMood` and emits `mood.resolved`.
7. `PetSpriteView` reacts to `currentMood` change via SwiftUI binding and starts the `sleeping-XX` frame loop.

## Error Handling

- **All three focus sources fail simultaneously** → `focus.active = false`, mood resolves to `idle` (or whatever non-sleep branch matches). Logged as three separate `*.denied`/`*.error` events; user can see the cause in Settings → System Access.
- **`Assertions.json` read intermittently fails** → existing logic flips `canReadFocusModeFiles = false` permanently. Preserved as-is, but the flip is now logged once.
- **AX scrape returns garbage strings** → `ControlCenterFocusSignalParser.resolveMode` already requires explicit "sleep" markers; non-matching strings produce nil. No change needed.
- **`INFocusStatusCenter` returns active=true with both identifier and name nil** → tightened fallback resolves to sleeping with reason `unidentified_focus_assumed_sleep`.
- **Bundle preflight fails** (raw `swift run`) → exit `EX_CONFIG` with stderr message. No partial startup.
- **Bundle script fails** (e.g., `codesign` not available, `swift build` fails) → script exits non-zero, prints actual underlying error.

## Testing

| Layer | Today | After |
|---|---|---|
| Mood engine pure rules | Solid | Extend with `MoodResolution.reason` assertions + 5 new fallback cases |
| Focus pipeline (PetServices) | None | NEW `FocusPipelineTests` with `FakeFocusSourceProvider` |
| Bundle script | N/A | NEW `tools/test-bundle.sh` smoke test (build + verify .app structure + verify codesign) |
| Permissions inspector | N/A | Unit test for status mapping |

**Critical pipeline test cases:**

1. All three sources fail at midday → `focus.active == false`, mood = `idle` (regression check that we didn't accidentally make everything sleep)
2. Only INFocus says `active=true` (everything else denied) → fallback fires, mood = `sleeping` with reason `unidentified_focus_assumed_sleep`
3. Assertions returns `name="Sleep"`, `identifier=nil` → mood = `sleeping` with reason `sleep_focus_explicit`
4. Assertions returns `name="Work"`, `identifier=nil` → mood = `working` (NOT sleeping)
5. INFocus active=true + Assertions returns custom name "Deep Work" → mood = `sleeping` (documented expected behavior — custom focuses fall into the sleep branch unless added to the exclusion set)

## Build & Migration Sequence

The work is intentionally ordered so each step's success is verifiable and the bug-fix slice ships even if the polish steps are deferred:

1. **Bundling tooling first.** `tools/_bundle.sh`, `tools/run.sh`, `tools/build-release.sh`. Verify by hand: `./tools/run.sh` launches the app, menu bar icon appears, `Bundle.main.bundleIdentifier` logs `com.petos.petOS`.
2. **Diagnostics layer.** Add `OSLog`, `MoodResolution` struct, caller shim. Verify: `log stream --predicate 'subsystem == "com.petos.focus"'` shows events on every focus poll.
3. **Drop `isProperlyBundled` gates** + add startup preflight. Verify: raw `swift run` exits with EX_CONFIG; `./tools/run.sh` proceeds; first run prompts for Focus permission.
4. **Manually grant Focus + Accessibility on the bundle.** Verify in logs that `infocus.status` flips to `authorized=true` and that turning Sleep Focus on triggers `mood.resolved reason=sleep_focus_explicit` (or `unidentified_focus_assumed_sleep` if Assertions.json/AX are still blocked).
5. **Tighten engine fallback.** Existing tests stay green. Add the five new test cases.
6. **Extract `FocusSourceProvider` protocol** + add `FocusPipelineTests`. Done as a separate commit so review is bisectable.
7. **Permissions UI** in Settings.
8. **README update** — replace `swift run petOS` with `./tools/run.sh`. Add a "First run" subsection covering the three system permissions and what each enables.

Steps 1–4 alone make the reported bug GONE for most users. Steps 5–8 are the "and stay gone" hardening.

## Open Questions

None at design time. The key trade-off (custom focus names resolving to sleep) is explicitly accepted with a one-line escape hatch (extend the `static let` exclusion set).

## Out of Scope (future work)

- Localized focus names in the exclusion set (today: English-only normalization)
- A widget/App Group story for sleep-state surfacing
- Migrating from polling (`AppConstants.focusPollInterval`) to a Darwin-notification observer for focus-change events
- Replacing AppleScript-backed integrations (calendar, music) with native frameworks
