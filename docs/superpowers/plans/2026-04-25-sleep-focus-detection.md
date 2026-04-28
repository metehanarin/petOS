# Sleep Focus Detection Reliability — Implementation Plan

> **For agentic workers:** REQUIRED: Use `superpowers:subagent-driven-development` (if subagents available) or `superpowers:executing-plans` to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Sleep Focus mode reliably trigger the `.sleeping` animation in both `swift run`-style dev mode and a properly built `.app` bundle, with structured diagnostics so any future regression is visible from `log stream`.

**Architecture:** Bundle the binary via a small shell tooling layer so TCC has a stable identity to grant against; remove the in-app permission gates that silently disabled Focus detection in dev; tighten the mood engine's "unidentified focus" fallback; surface diagnostics through `OSLog` and a Settings "System Access" panel; isolate the focus input pipeline behind a protocol so it can be unit-tested without a real macOS environment.

**Tech Stack:** Swift 6.2, SwiftPM, SwiftUI, Swift Testing (`@Test` / `#expect`), AppKit/AX APIs, `INFocusStatusCenter`, OSLog, `codesign` (ad-hoc), zsh.

**Spec:** [docs/superpowers/specs/2026-04-25-sleep-focus-detection-design.md](../specs/2026-04-25-sleep-focus-detection-design.md)

---

## Preconditions

- macOS 14+ (LSMinimumSystemVersion in `Sources/petOS/Info.plist`).
- `swift --version` reports 6.2 or newer.
- `codesign` available (ships with Xcode Command Line Tools).
- Working directory `/Users/metehanarin/Documents/petOS` is the repo root.

**If the repo is NOT yet a git repo**, initialize it once before starting:

```bash
cd /Users/metehanarin/Documents/petOS
git init
git add Package.swift README.md MIGRATION_NOTES.md SOUNDS_CHECKLIST.md SOUNDS_README.md SOUND_SETUP.md SOUND_DOWNLOAD_LINKS.md setup_sounds.py Sources Tests docs
git commit -m "chore: initialize repo at current state"
```

All later commit steps assume git is available.

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `tools/_bundle.sh` | NEW | Shared bash function `build_bundle` that assembles a `.app` directory and ad-hoc codesigns it. |
| `tools/run.sh` | NEW | Dev runner: builds debug, swaps inner binary into bundle (or full rebuild on `--clean`), execs foreground. |
| `tools/build-release.sh` | NEW | Release builder: builds release, assembles `.app` into `dist/petOS.app`. |
| `tools/test-bundle.sh` | NEW | Smoke test for bundle layout + codesign. |
| `Sources/petOS/Logic/PetMoodEngine.swift` | MODIFY | Add `MoodResolution`, `Reason` enum, new `resolveBaseMoodWithReason`. Generalize `isUnidentifiedFocusAssumedAsSleep` with non-sleep exclusion sets. Keep existing `resolveBaseMood(for:)` as thin wrapper. |
| `Sources/petOS/Services/PetServices.swift` | MODIFY | Drop `isProperlyBundled()` gates and helper. Replace direct file/AX/INFocus calls in `refreshFocus()` with `FocusSourceProvider`. Add `OSLog` calls. |
| `Sources/petOS/Services/FocusSourceProvider.swift` | NEW | Protocol + `LiveFocusSourceProvider` (verbatim wrap of current code paths) for dependency injection. |
| `Sources/petOS/Services/PermissionsInspector.swift` | NEW | Read-only TCC status snapshot + `openSystemSettings` deep-links. |
| `Sources/petOS/PetLaunchPreflight.swift` | NEW | Startup guard: exits `EX_CONFIG` if not running from a `.app` bundle. |
| `Sources/petOS/petOSApp.swift` | MODIFY | Invoke preflight before any other startup work. |
| `Sources/petOS/PetAppModel.swift` | MODIFY | Use `resolveBaseMoodWithReason`, log `mood.resolved` via `OSLog`. |
| `Sources/petOS/UI/SettingsView.swift` | MODIFY | Add "System Access" section bound to `PermissionsInspector.snapshot()` polled every 2s. |
| `Tests/petOSTests/PetMoodEngineTests.swift` | MODIFY | Add 5 new test cases for the tightened fallback. |
| `Tests/petOSTests/FocusPipelineTests.swift` | NEW | Pipeline tests using `FakeFocusSourceProvider`. |
| `Tests/petOSTests/PermissionsInspectorTests.swift` | NEW | Status mapping unit tests. |
| `README.md` | MODIFY | Replace `swift run petOS` with `./tools/run.sh`; add "First run" permissions subsection. |

---

## Chunk 1: Bundling tooling

**Outcome:** `./tools/run.sh` produces a real `.app` bundle, ad-hoc codesigns it, and execs the binary. Same plumbing reused by `./tools/build-release.sh`. Smoke test verifies the layout.

### Task 1.1: Create the shared bundling helper

**Files:**
- Create: `tools/_bundle.sh`

- [ ] **Step 1: Create the file**

```bash
mkdir -p /Users/metehanarin/Documents/petOS/tools
```

- [ ] **Step 2: Write the helper**

`tools/_bundle.sh`:

```bash
#!/usr/bin/env bash
# Shared bundling logic for petOS.
# Source this file from another script, then call:
#   build_bundle <swift-config> <bundle-output-dir> [--inner-only]
#
# - <swift-config>      : "debug" or "release"
# - <bundle-output-dir> : path to the .app directory to produce
# - --inner-only        : if set, skip Info.plist+Resources copy and only
#                         swap the inner binary (used by dev runner for
#                         faster iteration / TCC grant survival).

set -euo pipefail

PETOS_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

build_bundle() {
  local config="$1"
  local bundle_dir="$2"
  local inner_only="${3:-}"

  if [[ "$config" != "debug" && "$config" != "release" ]]; then
    echo "build_bundle: config must be 'debug' or 'release', got '$config'" >&2
    return 2
  fi

  echo "[bundle] swift build -c $config --product petOS"
  (cd "$PETOS_REPO_ROOT" && swift build -c "$config" --product petOS)

  local built_binary
  built_binary="$(cd "$PETOS_REPO_ROOT" && swift build -c "$config" --show-bin-path)/petOS"
  if [[ ! -x "$built_binary" ]]; then
    echo "[bundle] expected binary not found at $built_binary" >&2
    return 1
  fi

  local contents="$bundle_dir/Contents"
  local macos_dir="$contents/MacOS"
  local resources_dir="$contents/Resources"

  mkdir -p "$macos_dir"

  if [[ "$inner_only" != "--inner-only" || ! -f "$contents/Info.plist" ]]; then
    mkdir -p "$resources_dir"
    cp "$PETOS_REPO_ROOT/Sources/petOS/Info.plist" "$contents/Info.plist"

    # Copy SwiftPM-processed resources from the build output
    local pkg_resources
    pkg_resources="$(cd "$PETOS_REPO_ROOT" && swift build -c "$config" --show-bin-path)/petOS_petOS.bundle/Contents/Resources"
    if [[ -d "$pkg_resources" ]]; then
      rm -rf "$resources_dir"
      mkdir -p "$resources_dir"
      cp -R "$pkg_resources/." "$resources_dir/"
    fi
  fi

  cp "$built_binary" "$macos_dir/petOS"
  chmod +x "$macos_dir/petOS"

  echo "[bundle] codesign --force --deep --sign - $bundle_dir"
  codesign --force --deep --sign - "$bundle_dir"

  echo "[bundle] verifying signature"
  codesign --verify --deep --strict "$bundle_dir"

  echo "[bundle] OK -> $bundle_dir"
}
```

- [ ] **Step 3: Make it executable (sourceable shouldn't strictly need +x but harmless)**

```bash
chmod +x /Users/metehanarin/Documents/petOS/tools/_bundle.sh
```

- [ ] **Step 4: Commit**

```bash
git add tools/_bundle.sh
git commit -m "tools: add shared _bundle.sh helper for .app assembly"
```

### Task 1.2: Create the dev runner

**Files:**
- Create: `tools/run.sh`

- [ ] **Step 1: Write the runner**

`tools/run.sh`:

```bash
#!/usr/bin/env bash
# Build petOS and exec it from a generated .app bundle so TCC grants
# (Focus, Accessibility, Full Disk Access) have a stable identity to bind to.
#
# Usage:
#   ./tools/run.sh                # debug build, inner-binary swap if bundle exists
#   ./tools/run.sh --clean        # force full rebuild of the bundle
#   ./tools/run.sh -- --debug     # extra args after `--` are passed to petOS

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_DIR="$REPO_ROOT/.build/bundle/petOS.app"

# shellcheck source=tools/_bundle.sh
source "$REPO_ROOT/tools/_bundle.sh"

clean=0
pass_through=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean) clean=1; shift ;;
    --) shift; pass_through=("$@"); break ;;
    *) pass_through+=("$1"); shift ;;
  esac
done

if [[ "$clean" == "1" ]]; then
  echo "[run.sh] --clean: removing $BUNDLE_DIR"
  rm -rf "$BUNDLE_DIR"
fi

inner_only_flag=""
if [[ -f "$BUNDLE_DIR/Contents/Info.plist" ]]; then
  inner_only_flag="--inner-only"
fi

build_bundle "debug" "$BUNDLE_DIR" "$inner_only_flag"

echo "[run.sh] exec $BUNDLE_DIR/Contents/MacOS/petOS ${pass_through[*]:-}"
exec "$BUNDLE_DIR/Contents/MacOS/petOS" "${pass_through[@]}"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x /Users/metehanarin/Documents/petOS/tools/run.sh
```

- [ ] **Step 3: Verify by running**

```bash
cd /Users/metehanarin/Documents/petOS
./tools/run.sh
```

Expected: Swift builds, bundle is created at `.build/bundle/petOS.app`, codesign verification passes, and the menu bar icon appears (or, if Focus authorization has never been granted to this bundle ID before, a system prompt asks for Focus access — accept it). Hit Ctrl-C to exit.

If the build fails, fix the underlying compile error and re-run; do not proceed with later tasks until `./tools/run.sh` reaches the `[run.sh] exec` line cleanly.

- [ ] **Step 4: Verify codesign identity is stable across rebuilds**

```bash
codesign -dr - /Users/metehanarin/Documents/petOS/.build/bundle/petOS.app 2>&1 | rg "designated"
./tools/run.sh   # second run, inner-only swap
codesign -dr - /Users/metehanarin/Documents/petOS/.build/bundle/petOS.app 2>&1 | rg "designated"
```

Expected: both `designated => identifier "com.petos.petOS"` lines are byte-for-byte identical. If they differ, TCC will demote grants on every rebuild and the whole point of this layer is defeated — investigate before proceeding.

- [ ] **Step 5: Commit**

```bash
git add tools/run.sh
git commit -m "tools: add run.sh dev bundler that preserves TCC identity"
```

### Task 1.3: Create the release builder

**Files:**
- Create: `tools/build-release.sh`

- [ ] **Step 1: Write the script**

`tools/build-release.sh`:

```bash
#!/usr/bin/env bash
# Build petOS.app for distribution. Output: dist/petOS.app

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
BUNDLE_DIR="$DIST_DIR/petOS.app"

# shellcheck source=tools/_bundle.sh
source "$REPO_ROOT/tools/_bundle.sh"

mkdir -p "$DIST_DIR"
rm -rf "$BUNDLE_DIR"

build_bundle "release" "$BUNDLE_DIR"

echo "[build-release.sh] release bundle at $BUNDLE_DIR"
echo "[build-release.sh] copy to /Applications and launch from Finder for first-run permission prompts."
```

- [ ] **Step 2: Make executable**

```bash
chmod +x /Users/metehanarin/Documents/petOS/tools/build-release.sh
```

- [ ] **Step 3: Verify by running**

```bash
./tools/build-release.sh
ls dist/petOS.app/Contents/MacOS/petOS
codesign --verify --deep --strict dist/petOS.app
```

Expected: `dist/petOS.app/Contents/MacOS/petOS` exists; `codesign --verify` exits 0 with no output.

- [ ] **Step 4: Commit**

```bash
git add tools/build-release.sh
git commit -m "tools: add build-release.sh for distribution .app"
```

### Task 1.4: Bundle smoke test

**Files:**
- Create: `tools/test-bundle.sh`

- [ ] **Step 1: Write the test**

`tools/test-bundle.sh`:

```bash
#!/usr/bin/env bash
# Smoke test for the bundling pipeline. Exits non-zero on any failure.
# Run as: ./tools/test-bundle.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_DIR="$REPO_ROOT/.build/bundle/petOS.app"

# shellcheck source=tools/_bundle.sh
source "$REPO_ROOT/tools/_bundle.sh"

rm -rf "$BUNDLE_DIR"
build_bundle "debug" "$BUNDLE_DIR"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "OK: $*"; }

[[ -f "$BUNDLE_DIR/Contents/Info.plist" ]]            || fail "Info.plist missing"
[[ -x "$BUNDLE_DIR/Contents/MacOS/petOS" ]]       || fail "executable missing or not +x"
codesign --verify --deep --strict "$BUNDLE_DIR"       || fail "codesign verify failed"

# Verify bundle ID matches what TCC will key against
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUNDLE_DIR/Contents/Info.plist")"
[[ "$bundle_id" == "com.petos.petOS" ]]       || fail "unexpected bundle id: $bundle_id"

ok "bundle layout"
ok "executable present"
ok "codesign valid"
ok "bundle id = $bundle_id"
echo "PASS"
```

- [ ] **Step 2: Make executable + run**

```bash
chmod +x /Users/metehanarin/Documents/petOS/tools/test-bundle.sh
./tools/test-bundle.sh
```

Expected: ends with a `PASS` line; exit code 0.

- [ ] **Step 3: Commit**

```bash
git add tools/test-bundle.sh
git commit -m "tools: add bundle smoke test"
```

---

## Chunk 2: Diagnostics + MoodResolution

**Outcome:** The mood engine returns a `(mood, reason)` pair the model can log. `OSLog` events emit on every focus poll branch and every mood recompute. Existing tests stay green because the legacy `resolveBaseMood` signature is preserved as a thin wrapper.

### Task 2.1: Add `MoodResolution` + `Reason`, keep legacy signature

**Files:**
- Modify: `Sources/petOS/Logic/PetMoodEngine.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/petOSTests/PetMoodEngineTests.swift` (inside the `PetMoodEngineTests` struct):

```swift
@Test
func resolutionExposesReasonForExplicitSleepFocus() {
    let state = PetTestSupport.makeState {
        $0.hour = 14
        $0.focus.active = true
        $0.focus.modeIdentifier = "com.apple.focus.sleep"
        $0.focus.modeName = "Sleep"
    }

    let resolution = PetMoodEngine.resolveBaseMoodWithReason(for: state)
    #expect(resolution.mood == .sleeping)
    #expect(resolution.reason == .sleepFocusExplicit)
}
```

- [ ] **Step 2: Run the test, confirm it fails**

```bash
swift test --scratch-path /tmp/nativepet-test-build --filter PetMoodEngineTests/resolutionExposesReasonForExplicitSleepFocus
```

Expected: build error — `resolveBaseMoodWithReason` is undefined. That's the failure we want.

- [ ] **Step 3: Implement `MoodResolution`, `Reason`, and `resolveBaseMoodWithReason`**

Edit `Sources/petOS/Logic/PetMoodEngine.swift`. Replace the body of `enum PetMoodEngine` (top of the file, lines 3–52) with the version below. (Identifier-/name-normalization helpers below the function stay unchanged.)

```swift
enum PetMoodEngine {
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

    /// Legacy single-value entry point — preserved so existing callers compile unchanged.
    static func resolveBaseMood(for state: WorldState, now: Date = .now) -> PetMood {
        resolveBaseMoodWithReason(for: state, now: now).mood
    }

    static func resolveBaseMoodWithReason(for state: WorldState, now: Date = .now) -> MoodResolution {
        let topAppFrontmost = isTopAppFrontmost(state.activity)
        let productivityAppFrontmost = isProductivityApp(state.activity.frontApp)
        let sleepFocusActive = isFocusMode(
            state.focus,
            identifier: "com.apple.focus.sleep",
            fallbackNames: ["sleep", "sleeping"]
        )
        let workFocusActive = state.focus.active &&
            isFocusMode(
                state.focus,
                identifier: "com.apple.focus.work",
                fallbackNames: ["work", "working"]
            )
        let sleepModeActive = state.focus.active && sleepFocusActive
        let sleepWindowActive = isSleepWindow(hour: state.hour)
        let unidentifiedSleepFocus = isUnidentifiedFocusAssumedAsSleep(state.focus)

        if sleepModeActive {
            return MoodResolution(mood: .sleeping, reason: .sleepFocusExplicit)
        }
        if sleepWindowActive {
            return MoodResolution(mood: .sleeping, reason: .sleepWindow)
        }
        if unidentifiedSleepFocus {
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

        if workFocusActive {
            return MoodResolution(mood: .working, reason: .workFocus)
        }
        if productivityAppFrontmost {
            return MoodResolution(mood: .working, reason: .productivityApp)
        }
        if state.focus.active && topAppFrontmost {
            return MoodResolution(mood: .working, reason: .focusWithTopApp)
        }

        if state.music.playing {
            return MoodResolution(mood: .dancing, reason: .musicPlaying)
        }

        return MoodResolution(mood: .idle, reason: .idleDefault)
    }

```

After the new `resolveBaseMoodWithReason` function, leave the existing declarations in place and unchanged: `productivityAppNames`, `productivityAppPrefixes`, `reactionVariant`, `isTopAppFrontmost`, `isProductivityApp`, `hasImminentCalendarEvent`, `hasActiveNotificationAlert`, `isSleepWindow`, `isFocusMode`, `normalizeFocusModeIdentifier`, `normalizeFocusModeName`, and `normalizeAppName`.

The `isUnidentifiedFocusAssumedAsSleep` signature changes (drops the `hour` parameter) since it's no longer used. That tighter version is implemented in Chunk 3 — for now, edit the existing function so its declaration becomes:

```swift
private static func isUnidentifiedFocusAssumedAsSleep(_ focus: FocusState) -> Bool {
    guard focus.active else { return false }
    let identifier = normalizeFocusModeIdentifier(focus.modeIdentifier)
    let name = normalizeFocusModeName(focus.modeName)
    return identifier.isEmpty && name.isEmpty
}
```

(Behavior unchanged in this chunk; the rule generalization happens in Chunk 3.)

- [ ] **Step 4: Run the new test, confirm it passes**

```bash
swift test --scratch-path /tmp/nativepet-test-build --filter PetMoodEngineTests/resolutionExposesReasonForExplicitSleepFocus
```

Expected: PASS.

- [ ] **Step 5: Run the full test suite, confirm no regressions**

```bash
swift test --scratch-path /tmp/nativepet-test-build
```

Expected: all pre-existing `PetMoodEngineTests` cases still pass (the legacy `resolveBaseMood` shim returns the same `PetMood` values).

- [ ] **Step 6: Commit**

```bash
git add Sources/petOS/Logic/PetMoodEngine.swift Tests/petOSTests/PetMoodEngineTests.swift
git commit -m "engine: introduce MoodResolution with diagnostic reason"
```

### Task 2.2: Log `mood.resolved` from `PetAppModel`

**Files:**
- Modify: `Sources/petOS/PetAppModel.swift`

- [ ] **Step 1: Add the logger import + property**

Add to imports at top of `Sources/petOS/PetAppModel.swift`:

```swift
import os
```

Inside the `PetAppModel` class, near the other private properties:

```swift
private let moodLog = Logger(subsystem: "com.petos.focus", category: "mood")
```

- [ ] **Step 2: Replace mood-recompute callsites to use `MoodResolution`**

Find every line that calls `PetMoodEngine.resolveBaseMood(for: worldState)` and assigns into `currentMood` (the design-time search found two: line 58 and line 271). Change each from:

```swift
currentMood = PetMoodEngine.resolveBaseMood(for: worldState)
```

to:

```swift
let resolution = PetMoodEngine.resolveBaseMoodWithReason(for: worldState)
currentMood = resolution.mood
moodLog.debug("mood.resolved mood=\(resolution.mood.rawValue, privacy: .public) reason=\(resolution.reason.rawValue, privacy: .public)")
```

For the line with the `debugMoodOverride ?? PetMoodEngine.resolveBaseMood(for: worldState)` (line 271), change to:

```swift
if let override = debugMoodOverride {
    currentMood = override
    moodLog.debug("mood.resolved mood=\(override.rawValue, privacy: .public) reason=debug_override")
} else {
    let resolution = PetMoodEngine.resolveBaseMoodWithReason(for: worldState)
    currentMood = resolution.mood
    moodLog.debug("mood.resolved mood=\(resolution.mood.rawValue, privacy: .public) reason=\(resolution.reason.rawValue, privacy: .public)")
}
```

- [ ] **Step 3: Build**

```bash
swift build
```

Expected: clean build, no warnings about the changed callsites.

- [ ] **Step 4: Run tests**

```bash
swift test --scratch-path /tmp/nativepet-test-build
```

Expected: all pass.

- [ ] **Step 5: Verify logs at runtime**

```bash
./tools/run.sh &
APP_PID=$!
sleep 3
log show --predicate 'subsystem == "com.petos.focus"' --last 10s --info --debug | head -20
kill $APP_PID
```

Expected: at least one line shaped like `mood.resolved mood=idle reason=idle_default`. (`log show` requires no extra config because `Logger.debug` events are persisted briefly when the process emits them.)

- [ ] **Step 6: Commit**

```bash
git add Sources/petOS/PetAppModel.swift
git commit -m "model: log mood.resolved with diagnostic reason via OSLog"
```

### Task 2.3: Add focus-pipeline `OSLog` instrumentation

**Files:**
- Modify: `Sources/petOS/Services/PetServices.swift`

- [ ] **Step 1: Add the logger**

Add to imports of `PetServices.swift`:

```swift
import os
```

Inside `PetMonitorCoordinator`, near other private properties:

```swift
private let focusLog = Logger(subsystem: "com.petos.focus", category: "pipeline")
```

- [ ] **Step 2: Instrument `readCurrentFocusMode()`**

Locate `readCurrentFocusMode()` (currently lines 486–509). After `FocusModeNameResolver.resolveMode(assertionsData:configurationsData:)` returns, log the descriptor branch; in the catch block, log on each error branch:

```swift
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
            focusLog.debug("assertions.read.ok mode_id= mode_name=  (no active mode in assertions)")
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
            NSLog("[petOS] focus mode lookup failed: \(error.localizedDescription)")
        }
        return nil
    }
}
```

- [ ] **Step 3: Instrument `readControlCenterFocusMode()`**

Replace the body (currently lines 511–529) with:

```swift
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
```

- [ ] **Step 4: Instrument `refreshFocus()` for the INFocus + final-resolution events**

Within `refreshFocus()` (currently lines 305–341), after the line `focusStatusActive = authorized && (center.focusStatus.isFocused ?? false)`, insert:

```swift
focusLog.debug("infocus.status authorized=\(authorized, privacy: .public) is_focused=\(focusStatusActive, privacy: .public)")
```

After the `model?.updateWorldState` block that assigns `state.focus`, insert:

```swift
focusLog.debug("focus.resolved active=\(active, privacy: .public) mode_id=\(mode?.identifier ?? "", privacy: .public) mode_name=\(mode?.name ?? "", privacy: .public) source=\(focusSource(mode: mode, focusStatusActive: focusStatusActive, focusModeLookupProtected: focusModeLookupProtected), privacy: .public)")
```

- [ ] **Step 5: Build**

```bash
swift build
```

Expected: clean build.

- [ ] **Step 6: Verify logs**

```bash
./tools/run.sh &
APP_PID=$!
sleep 3
log show --predicate 'subsystem == "com.petos.focus"' --last 10s --info --debug | head -40
kill $APP_PID
```

Expected: at least one `focus.resolved` line and one of `assertions.read.*`, `controlcenter.scrape.*`, or `infocus.status` lines per poll cycle.

- [ ] **Step 7: Commit**

```bash
git add Sources/petOS/Services/PetServices.swift
git commit -m "services: add OSLog instrumentation across focus pipeline"
```

---

## Chunk 3: Pipeline gate removal + preflight + engine fallback

**Outcome:** `isProperlyBundled()` is gone; raw `swift run` exits loudly via preflight; the engine fallback resolves any active focus that isn't an explicitly-known non-sleep mode to `.sleeping`.

### Task 3.1: Add startup preflight

**Files:**
- Create: `Sources/petOS/PetLaunchPreflight.swift`
- Modify: `Sources/petOS/petOSApp.swift`

- [ ] **Step 1: Write the preflight**

`Sources/petOS/PetLaunchPreflight.swift`:

```swift
import Foundation

enum PetLaunchPreflight {
    /// Aborts the process with EX_CONFIG (78) if the binary is being executed
    /// outside an .app bundle. TCC keys grants by code-signing identity, and a
    /// non-bundled binary has none — the focus pipeline silently fails. Make
    /// that failure loud and self-documenting instead.
    static func enforceBundledExecution() {
        let path = Bundle.main.bundlePath
        if path.hasSuffix(".app") {
            return
        }

        fputs(
            """
            [petOS] FATAL: this binary must be launched from an .app bundle.
            Use ./tools/run.sh (dev) or ./tools/build-release.sh (release).
            Detected bundle path: \(path)

            """,
            stderr
        )
        exit(78) // EX_CONFIG
    }
}
```

- [ ] **Step 2: Wire into app entry point**

In `Sources/petOS/petOSApp.swift`, change the stored model property and add an explicit `init` so the preflight runs before `PetAppModel()` is constructed. Replace:

```swift
@StateObject private var model = PetAppModel()
```

with:

```swift
@StateObject private var model: PetAppModel

init() {
    PetLaunchPreflight.enforceBundledExecution()
    _model = StateObject(wrappedValue: PetAppModel())
}
```

Do not move the `@NSApplicationDelegateAdaptor` property or change the `body` scene definitions.

- [ ] **Step 3: Verify the preflight aborts raw swift run**

```bash
swift build
.build/debug/petOS
echo "exit=$?"
```

Expected: stderr message about needing `./tools/run.sh`; `exit=78`.

- [ ] **Step 4: Verify the preflight passes when bundled**

```bash
./tools/run.sh &
APP_PID=$!
sleep 2
ps -p $APP_PID -o pid= 2>/dev/null && echo "running" || echo "exited"
kill $APP_PID 2>/dev/null || true
```

Expected: `running`.

- [ ] **Step 5: Commit**

```bash
git add Sources/petOS/PetLaunchPreflight.swift Sources/petOS/petOSApp.swift
git commit -m "app: enforce bundled execution at startup"
```

### Task 3.2: Drop `isProperlyBundled()` gates

**Files:**
- Modify: `Sources/petOS/Services/PetServices.swift`

- [ ] **Step 1: Remove the gate in `refreshFocus()`**

In `refreshFocus()` (currently around line 317), replace:

```swift
if !requestedFocusAuthorization, center.authorizationStatus == .notDetermined {
    requestedFocusAuthorization = true

    // Only request authorization if we are properly bundled.
    // In CLI / swift run environments, this can trigger a TCC crash.
    if isProperlyBundled() && !ProcessInfo.processInfo.arguments.contains("--no-prompts") {
        _ = await center.requestAuthorization()
    }
}
```

with:

```swift
if !requestedFocusAuthorization, center.authorizationStatus == .notDetermined {
    requestedFocusAuthorization = true
    if !ProcessInfo.processInfo.arguments.contains("--no-prompts") {
        _ = await center.requestAuthorization()
    }
}
```

- [ ] **Step 2: Remove the gate in `accessibilityTrustedForControlCenterLookup()`**

Replace the body of `accessibilityTrustedForControlCenterLookup()` (currently lines 654–675) with:

```swift
private func accessibilityTrustedForControlCenterLookup() -> Bool {
    if AXIsProcessTrusted() {
        return true
    }

    guard !requestedAccessibilityAuthorization else {
        return false
    }

    requestedAccessibilityAuthorization = true

    let options = [
        "AXTrustedCheckOptionPrompt": true
    ] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}
```

- [ ] **Step 3: Delete the `isProperlyBundled()` helper**

Remove the entire `isProperlyBundled()` function (currently lines 639–652) — it has no remaining callers. Verify with:

```bash
rg -n isProperlyBundled Sources/petOS/Services/PetServices.swift
```

Expected: no output.

- [ ] **Step 4: Build**

```bash
swift build
```

Expected: clean build.

- [ ] **Step 5: Run, accept TCC prompts**

```bash
./tools/run.sh
```

Expected: on first run after this change (and if prior grants for this bundle ID are missing), macOS shows a Focus authorization prompt and an Accessibility prompt (the Accessibility one comes asynchronously when Control Center first needs scraping). Accept both. The pet appears.

- [ ] **Step 6: Commit**

```bash
git add Sources/petOS/Services/PetServices.swift
git commit -m "services: drop isProperlyBundled gates now that bundling is mandatory"
```

### Task 3.3: Tighten the engine fallback

**Files:**
- Modify: `Sources/petOS/Logic/PetMoodEngine.swift`
- Modify: `Tests/petOSTests/PetMoodEngineTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `PetMoodEngineTests`:

```swift
@Test
func sleepingResolvesWhenFocusActiveWithSleepNameOnly() {
    let state = PetTestSupport.makeState {
        $0.hour = 14
        $0.focus.active = true
        $0.focus.modeIdentifier = nil
        $0.focus.modeName = "Sleep"
    }

    let resolution = PetMoodEngine.resolveBaseMoodWithReason(for: state)
    #expect(resolution.mood == .sleeping)
    #expect(resolution.reason == .sleepFocusExplicit)
}

@Test
func workingResolvesWhenFocusActiveWithWorkNameOnly() {
    let state = PetTestSupport.makeState {
        $0.hour = 14
        $0.focus.active = true
        $0.focus.modeIdentifier = nil
        $0.focus.modeName = "Work"
    }

    #expect(PetMoodEngine.resolveBaseMood(for: state) == .working)
}

@Test
func sleepingResolvesForCustomNamedFocusOutsideSleepWindow() {
    let state = PetTestSupport.makeState {
        $0.hour = 14
        $0.focus.active = true
        $0.focus.modeIdentifier = "com.example.custom.focus"
        $0.focus.modeName = "Deep Work"
    }

    let resolution = PetMoodEngine.resolveBaseMoodWithReason(for: state)
    #expect(resolution.mood == .sleeping)
    #expect(resolution.reason == .unidentifiedFocusAssumedSleep)
}

@Test
func idleResolvesWhenAllFocusSourcesFailAtMidday() {
    let state = PetTestSupport.makeState {
        $0.hour = 14
        $0.focus.active = false
    }

    #expect(PetMoodEngine.resolveBaseMood(for: state) == .idle)
}

@Test
func drivingFocusDoesNotResolveToSleeping() {
    let state = PetTestSupport.makeState {
        $0.hour = 14
        $0.focus.active = true
        $0.focus.modeIdentifier = "com.apple.donotdisturb.mode.driving"
        $0.focus.modeName = "Driving"
    }

    #expect(PetMoodEngine.resolveBaseMood(for: state) == .idle)
}
```

- [ ] **Step 2: Run new tests, confirm they fail**

```bash
swift test --scratch-path /tmp/nativepet-test-build --filter PetMoodEngineTests/sleepingResolvesWhenFocusActiveWithSleepNameOnly
swift test --scratch-path /tmp/nativepet-test-build --filter PetMoodEngineTests/sleepingResolvesForCustomNamedFocusOutsideSleepWindow
swift test --scratch-path /tmp/nativepet-test-build --filter PetMoodEngineTests/drivingFocusDoesNotResolveToSleeping
```

Expected: `sleepingResolvesWhenFocusActiveWithSleepNameOnly` already passes (current `isFocusMode` matches the name "Sleep"). The "custom named focus" test FAILS (currently resolves to idle because the empty-only fallback doesn't fire). The driving test FAILS (currently active+driving falls through to idle, which happens to be the expected new behavior — verify; if it passes already, that's fine).

- [ ] **Step 3: Implement the tightened fallback**

In `Sources/petOS/Logic/PetMoodEngine.swift`, add these constants near the other `static let` declarations:

```swift
private static let nonSleepFocusIdentifiers: Set<String> = [
    "com.apple.focus.work",
    "com.apple.focus.personal",
    "com.apple.focus.gaming",
    "com.apple.focus.fitness",
    "com.apple.focus.mindfulness",
    "com.apple.focus.driving",
    "com.apple.donotdisturb.mode.driving",
    "com.apple.focus.reading",
    "com.apple.donotdisturb"
]

private static let nonSleepFocusNames: Set<String> = [
    "work", "working",
    "personal",
    "gaming",
    "fitness",
    "mindfulness",
    "driving",
    "reading",
    "do not disturb", "dnd"
]
```

Replace the body of `isUnidentifiedFocusAssumedAsSleep` with:

```swift
private static func isUnidentifiedFocusAssumedAsSleep(_ focus: FocusState) -> Bool {
    guard focus.active else { return false }
    let identifier = normalizeFocusModeIdentifier(focus.modeIdentifier)
    let name = normalizeFocusModeName(focus.modeName)

    if nonSleepFocusIdentifiers.contains(identifier) {
        return false
    }
    if nonSleepFocusNames.contains(name) {
        return false
    }
    return true
}
```

- [ ] **Step 4: Run all tests**

```bash
swift test --scratch-path /tmp/nativepet-test-build
```

Expected: all pre-existing tests still pass; the 5 new tests added in Step 1 all pass.

If `nonSleepFocusDoesNotResolveToSleepingOutsideOvernightWindow` (line 157 of the existing test file) fails, investigate — it's the closest cousin to our new logic. It uses `modeIdentifier="com.apple.focus.work"` and `modeName="Sleep"` and expects NOT-sleeping. The new rule preserves this because the identifier match wins.

- [ ] **Step 5: Verify the bug is gone end-to-end**

```bash
./tools/run.sh &
APP_PID=$!
# Manually turn on Sleep Focus from Control Center.
sleep 5
log show --predicate 'subsystem == "com.petos.focus"' --last 10s --info --debug | rg mood.resolved | tail -3
kill $APP_PID
```

Expected: at least one `mood.resolved mood=sleeping reason=sleep_focus_explicit` (if Assertions.json or Control Center scrape succeeded) or `reason=unidentified_focus_assumed_sleep` (if only INFocus authorized). If `reason=idle_default` shows up while Sleep Focus is on, check the `focus.resolved` lines just above to see why `active=false` — that's the diagnostic this whole layer was built for.

- [ ] **Step 6: Commit**

```bash
git add Sources/petOS/Logic/PetMoodEngine.swift Tests/petOSTests/PetMoodEngineTests.swift
git commit -m "engine: generalize unidentified-focus fallback with non-sleep exclusion sets"
```

---

## Chunk 4: Focus pipeline isolation + permissions UI

**Outcome:** Focus sources sit behind `FocusSourceProvider` so the pipeline is unit-testable. Settings has a "System Access" panel showing live TCC status with deep links.

### Task 4.1: Extract `FocusSourceProvider`

**Files:**
- Create: `Sources/petOS/Services/FocusSourceProvider.swift`
- Modify: `Sources/petOS/Services/PetServices.swift`

- [ ] **Step 1: Write the protocol + live impl**

`Sources/petOS/Services/FocusSourceProvider.swift`:

```swift
import Foundation

@MainActor
protocol FocusSourceProvider: AnyObject {
    /// Returns a descriptor parsed from `~/Library/DoNotDisturb/DB/Assertions.json`,
    /// or `nil` if no active mode / unable to read. May mutate internal state to
    /// remember "permanently denied" so subsequent calls short-circuit.
    func readAssertionsFile() -> FocusModeDescriptor?

    /// Returns a descriptor parsed from Control Center via Accessibility, or `nil`.
    func scrapeControlCenter() -> FocusModeDescriptor?

    /// Returns `(authorized, isFocused)` from `INFocusStatusCenter`. May trigger
    /// the system authorization prompt on first call.
    func queryInFocusStatus() async -> (authorized: Bool, isFocused: Bool)
}
```

- [ ] **Step 2: Move the existing implementations into a `LiveFocusSourceProvider`**

Append to `Sources/petOS/Services/FocusSourceProvider.swift`:

```swift
final class LiveFocusSourceProvider: FocusSourceProvider {
    weak var coordinator: PetMonitorCoordinator?

    init(coordinator: PetMonitorCoordinator? = nil) {
        self.coordinator = coordinator
    }

    func readAssertionsFile() -> FocusModeDescriptor? {
        coordinator?.liveReadAssertionsFile()
    }

    func scrapeControlCenter() -> FocusModeDescriptor? {
        coordinator?.liveScrapeControlCenter()
    }

    func queryInFocusStatus() async -> (authorized: Bool, isFocused: Bool) {
        await coordinator?.liveQueryInFocusStatus() ?? (false, false)
    }
}
```

- [ ] **Step 3: Expose live methods on `PetMonitorCoordinator` and have `refreshFocus()` go through the provider**

In `PetServices.swift`:

a. Add a property and initializer parameter on `PetMonitorCoordinator`:

```swift
private let focusSourceProvider: FocusSourceProvider

init(
    model: PetAppModel,
    persistence: PetPersistence,
    focusSourceProvider: FocusSourceProvider? = nil
) {
    self.model = model
    self.persistence = persistence
    let provider = focusSourceProvider ?? LiveFocusSourceProvider()
    self.focusSourceProvider = provider
    if let live = provider as? LiveFocusSourceProvider {
        live.coordinator = self
    }
}
```

b. Rename the existing `readCurrentFocusMode()` body to `liveReadAssertionsFile()` and `readControlCenterFocusMode()` to `liveScrapeControlCenter()`. Remove the `private` access modifier so `LiveFocusSourceProvider` can call them from `FocusSourceProvider.swift`.

c. Add `liveQueryInFocusStatus()` near the other live focus helpers:

```swift
func liveQueryInFocusStatus() async -> (authorized: Bool, isFocused: Bool) {
    let center = INFocusStatusCenter.default
    if !requestedFocusAuthorization, center.authorizationStatus == .notDetermined {
        requestedFocusAuthorization = true
        if !ProcessInfo.processInfo.arguments.contains("--no-prompts") {
            _ = await center.requestAuthorization()
        }
    }

    let authorized = center.authorizationStatus == .authorized
    let focusStatusActive = authorized && (center.focusStatus.isFocused ?? false)
    return (authorized, focusStatusActive)
}
```

d. Rewrite `refreshFocus()` to call the provider:

```swift
private func refreshFocus() async {
    observeFocusModeChanges()

    let (authorized, focusStatusActive) = await focusSourceProvider.queryInFocusStatus()
    focusLog.debug("infocus.status authorized=\(authorized, privacy: .public) is_focused=\(focusStatusActive, privacy: .public)")

    let mode = focusSourceProvider.readAssertionsFile() ?? focusSourceProvider.scrapeControlCenter()
    let focusModeLookupProtected = !canReadFocusModeFiles
    let active = mode != nil || focusStatusActive

    focusLog.debug("focus.resolved active=\(active, privacy: .public) mode_id=\(mode?.identifier ?? "", privacy: .public) mode_name=\(mode?.name ?? "", privacy: .public) source=\(self.focusSource(mode: mode, focusStatusActive: focusStatusActive, focusModeLookupProtected: focusModeLookupProtected), privacy: .public)")

    model?.updateWorldState { state in
        state.focus = FocusState(
            active: active,
            authorized: authorized,
            modeIdentifier: mode?.identifier,
            modeName: mode?.name,
            source: self.focusSource(
                mode: mode,
                focusStatusActive: focusStatusActive,
                focusModeLookupProtected: focusModeLookupProtected
            )
        )
    }
}
```

- [ ] **Step 4: Build**

```bash
swift build
```

Expected: clean build.

- [ ] **Step 5: Run all existing tests**

```bash
swift test --scratch-path /tmp/nativepet-test-build
```

Expected: all pass (no test currently exercises `refreshFocus` directly, so the refactor is invisible).

- [ ] **Step 6: Commit**

```bash
git add Sources/petOS/Services/FocusSourceProvider.swift Sources/petOS/Services/PetServices.swift
git commit -m "services: extract FocusSourceProvider for pipeline injection"
```

### Task 4.2: Add `FocusPipelineTests` with a fake provider

**Files:**
- Create: `Tests/petOSTests/FocusPipelineTests.swift`
- Modify: `Sources/petOS/Services/PetServices.swift`

- [ ] **Step 1: Write the test file**

`Tests/petOSTests/FocusPipelineTests.swift`:

```swift
import Foundation
import Testing
@testable import petOS

@MainActor
struct FocusPipelineTests {
    @Test
    func allSourcesFailLeavesFocusInactive() async {
        let fake = FakeFocusSourceProvider()
        let (model, coord) = makeModelAndCoordinator(fake: fake)

        await coord.refreshFocusForTest()

        #expect(model.worldState.focus.active == false)
    }

    @Test
    func inFocusActiveWithNoDescriptorResolvesToUnidentifiedSleep() async {
        let fake = FakeFocusSourceProvider()
        fake.inFocusResult = (authorized: true, isFocused: true)
        let (model, coord) = makeModelAndCoordinator(fake: fake)

        await coord.refreshFocusForTest()

        #expect(model.worldState.focus.active == true)
        #expect(model.worldState.focus.modeIdentifier == nil)
        let resolution = PetMoodEngine.resolveBaseMoodWithReason(for: model.worldState)
        #expect(resolution.mood == .sleeping)
        #expect(resolution.reason == .unidentifiedFocusAssumedSleep)
    }

    @Test
    func assertionsSleepDescriptorTakesPriorityOverControlCenter() async {
        let fake = FakeFocusSourceProvider()
        fake.assertionsResult = FocusModeDescriptor(identifier: "com.apple.focus.sleep", name: "Sleep")
        fake.controlCenterResult = FocusModeDescriptor(identifier: "com.apple.focus.work", name: "Work")
        let (model, coord) = makeModelAndCoordinator(fake: fake)

        await coord.refreshFocusForTest()

        #expect(model.worldState.focus.modeIdentifier == "com.apple.focus.sleep")
    }

    @Test
    func controlCenterFallsThroughWhenAssertionsEmpty() async {
        let fake = FakeFocusSourceProvider()
        fake.assertionsResult = nil
        fake.controlCenterResult = FocusModeDescriptor(identifier: "com.apple.focus.sleep", name: "Sleep")
        let (model, coord) = makeModelAndCoordinator(fake: fake)

        await coord.refreshFocusForTest()

        #expect(model.worldState.focus.modeIdentifier == "com.apple.focus.sleep")
    }

    @Test
    func partialDescriptorWithSleepNameOnlyResolvesSleeping() async {
        let fake = FakeFocusSourceProvider()
        fake.assertionsResult = FocusModeDescriptor(identifier: "", name: "Sleep")
        fake.inFocusResult = (authorized: true, isFocused: true)
        let (model, coord) = makeModelAndCoordinator(fake: fake)

        await coord.refreshFocusForTest()

        #expect(PetMoodEngine.resolveBaseMood(for: model.worldState) == .sleeping)
    }

    private func makeModelAndCoordinator(fake: FakeFocusSourceProvider) -> (PetAppModel, PetMonitorCoordinator) {
        let persistence = PetPersistence(fileURL: PetTestSupport.temporaryFileURL())
        let model = PetAppModel(arguments: [], persistence: persistence)
        let coord = PetMonitorCoordinator(
            model: model,
            persistence: persistence,
            focusSourceProvider: fake
        )
        return (model, coord)
    }
}

@MainActor
final class FakeFocusSourceProvider: FocusSourceProvider {
    var assertionsResult: FocusModeDescriptor?
    var controlCenterResult: FocusModeDescriptor?
    var inFocusResult: (authorized: Bool, isFocused: Bool) = (false, false)

    func readAssertionsFile() -> FocusModeDescriptor? { assertionsResult }
    func scrapeControlCenter() -> FocusModeDescriptor? { controlCenterResult }
    func queryInFocusStatus() async -> (authorized: Bool, isFocused: Bool) { inFocusResult }
}
```

- [ ] **Step 2: Add the test-only focus refresh helper**

Add to `Sources/petOS/Services/PetServices.swift`:

```swift
#if DEBUG
extension PetMonitorCoordinator {
    /// Test-only entry point that runs a single focus refresh cycle.
    func refreshFocusForTest() async {
        await refreshFocus()
    }
}
#endif
```

- [ ] **Step 3: Run the new tests**

```bash
swift test --scratch-path /tmp/nativepet-test-build --filter FocusPipelineTests
```

Expected: all 5 pipeline tests pass.

- [ ] **Step 4: Run the full suite**

```bash
swift test --scratch-path /tmp/nativepet-test-build
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Tests/petOSTests/FocusPipelineTests.swift Sources/petOS/Services/PetServices.swift
git commit -m "tests: add FocusPipelineTests covering provider injection paths"
```

### Task 4.3: `PermissionsInspector`

**Files:**
- Create: `Sources/petOS/Services/PermissionsInspector.swift`
- Create: `Tests/petOSTests/PermissionsInspectorTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/petOSTests/PermissionsInspectorTests.swift`:

```swift
import Foundation
import Testing
@testable import petOS

struct PermissionsInspectorTests {
    @Test
    func snapshotProducesAllThreeStatusFields() {
        let snapshot = PermissionsInspector.snapshot()

        // We can't assert specific values (depends on host TCC state) — just
        // verify the snapshot returns plausible enum cases for all three.
        let validStatuses: Set<PermissionsSnapshot.Status> = [.granted, .denied, .notDetermined, .unknown]
        #expect(validStatuses.contains(snapshot.focusStatus))
        #expect(validStatuses.contains(snapshot.accessibility))
        #expect(validStatuses.contains(snapshot.fullDiskAccess))
    }

    @Test
    func paneURLsAreNonNil() {
        #expect(PermissionsInspector.systemSettingsURL(for: .focus) != nil)
        #expect(PermissionsInspector.systemSettingsURL(for: .accessibility) != nil)
        #expect(PermissionsInspector.systemSettingsURL(for: .fullDiskAccess) != nil)
    }
}
```

- [ ] **Step 2: Run the test, confirm it fails**

```bash
swift test --scratch-path /tmp/nativepet-test-build --filter PermissionsInspectorTests
```

Expected: build error — `PermissionsInspector` undefined.

- [ ] **Step 3: Write the inspector**

`Sources/petOS/Services/PermissionsInspector.swift`:

```swift
import AppKit
import Foundation
import Intents
import ApplicationServices

struct PermissionsSnapshot: Equatable {
    enum Status: Equatable {
        case granted
        case denied
        case notDetermined
        case unknown
    }

    let focusStatus: Status
    let accessibility: Status
    let fullDiskAccess: Status
}

enum PermissionsInspector {
    enum Pane {
        case focus
        case accessibility
        case fullDiskAccess
    }

    static func snapshot() -> PermissionsSnapshot {
        PermissionsSnapshot(
            focusStatus: focusStatus(),
            accessibility: accessibilityStatus(),
            fullDiskAccess: fullDiskAccessStatus()
        )
    }

    static func openSystemSettings(for pane: Pane) {
        guard let url = systemSettingsURL(for: pane) else { return }
        NSWorkspace.shared.open(url)
    }

    static func systemSettingsURL(for pane: Pane) -> URL? {
        switch pane {
        case .focus:
            return URL(string: "x-apple.systempreferences:com.apple.preference.notifications?Focus")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .fullDiskAccess:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        }
    }

    private static func focusStatus() -> PermissionsSnapshot.Status {
        switch INFocusStatusCenter.default.authorizationStatus {
        case .authorized:    return .granted
        case .denied:        return .denied
        case .restricted:    return .denied
        case .notDetermined: return .notDetermined
        @unknown default:    return .unknown
        }
    }

    private static func accessibilityStatus() -> PermissionsSnapshot.Status {
        // AXIsProcessTrusted does NOT prompt — safe to call from a status query.
        AXIsProcessTrusted() ? .granted : .denied
    }

    private static func fullDiskAccessStatus() -> PermissionsSnapshot.Status {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/DoNotDisturb/DB/Assertions.json")
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            _ = try handle.read(upToCount: 1)
            return .granted
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoPermissionError {
                return .denied
            }
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoSuchFileError {
                return .unknown
            }
            let message = error.localizedDescription.lowercased()
            if message.contains("operation not permitted") || message.contains("permission denied") {
                return .denied
            }
            return .unknown
        }
    }
}
```

- [ ] **Step 4: Run the tests**

```bash
swift test --scratch-path /tmp/nativepet-test-build --filter PermissionsInspectorTests
```

Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/petOS/Services/PermissionsInspector.swift Tests/petOSTests/PermissionsInspectorTests.swift
git commit -m "services: add PermissionsInspector for read-only TCC status"
```

### Task 4.4: Surface permissions in Settings

**Files:**
- Modify: `Sources/petOS/UI/SettingsView.swift`

- [ ] **Step 1: Add a "System Access" section**

Add to `SettingsView.swift` (location: a new `Section` inside the existing form/list, ideally after any general-preferences section):

```swift
@State private var permissions = PermissionsInspector.snapshot()
@State private var permissionsTimer: Timer?

private var systemAccessSection: some View {
    Section("System Access") {
        permissionRow(
            label: "Focus",
            status: permissions.focusStatus,
            pane: .focus
        )
        permissionRow(
            label: "Accessibility",
            status: permissions.accessibility,
            pane: .accessibility
        )
        permissionRow(
            label: "Full Disk Access",
            status: permissions.fullDiskAccess,
            pane: .fullDiskAccess
        )

        Text("Sleep detection works best when all three are granted. Without Full Disk Access, the app falls back to Control Center, which requires its panel to be visible.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

@ViewBuilder
private func permissionRow(label: String, status: PermissionsSnapshot.Status, pane: PermissionsInspector.Pane) -> some View {
    HStack {
        Circle()
            .fill(color(for: status))
            .frame(width: 10, height: 10)
        Text(label)
        Spacer()
        Text(label(for: status))
            .foregroundStyle(.secondary)
        Button("Open System Settings…") {
            PermissionsInspector.openSystemSettings(for: pane)
        }
        .buttonStyle(.link)
    }
}

private func color(for status: PermissionsSnapshot.Status) -> Color {
    switch status {
    case .granted:        return .green
    case .denied:         return .red
    case .notDetermined:  return .yellow
    case .unknown:        return .gray
    }
}

private func label(for status: PermissionsSnapshot.Status) -> String {
    switch status {
    case .granted:        return "Granted"
    case .denied:         return "Not granted"
    case .notDetermined:  return "Not yet asked"
    case .unknown:        return "Unknown"
    }
}
```

In the current `signalsTab` `Form`, insert `systemAccessSection` after the existing `Section("World")` block that contains the Focus, Front app, Battery, Weather, Music, Calendar, and Notifications status rows. Then attach the polling lifecycle to that same `Form` after `.formStyle(.grouped)`:

```swift
.onAppear {
    permissions = PermissionsInspector.snapshot()
    permissionsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
        permissions = PermissionsInspector.snapshot()
    }
}
.onDisappear {
    permissionsTimer?.invalidate()
    permissionsTimer = nil
}
```

The root `SettingsView` already uses tab-specific `Form` containers, so keep this section in the `Signals` tab alongside the existing focus status row.

- [ ] **Step 2: Build**

```bash
swift build
```

Expected: clean build.

- [ ] **Step 3: Verify the panel renders**

```bash
./tools/run.sh
```

Open the menu bar → Settings… → confirm a "System Access" section is present with three rows and live status dots. Click "Open System Settings…" on any row → expect the matching pane to open.

- [ ] **Step 4: Commit**

```bash
git add Sources/petOS/UI/SettingsView.swift
git commit -m "ui: add System Access section to Settings with live TCC status"
```

### Task 4.5: README + final cleanup

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the Run section**

Replace the existing `## Run` section (currently lines 24–37) with:

````markdown
## Run

```bash
cd /Users/metehanarin/Documents/petOS
./tools/run.sh
```

This bundles petOS into a real `.app` so macOS TCC can persist Focus / Accessibility / Full Disk Access grants across rebuilds. Running the binary directly via `swift run` will exit with `EX_CONFIG` (78) — use `./tools/run.sh` instead.

Pass extra args to petOS after `--`:

```bash
./tools/run.sh -- --debug
```

Force a full bundle rebuild (e.g. after editing `Info.plist`):

```bash
./tools/run.sh --clean
```

Build a distributable bundle:

```bash
./tools/build-release.sh
# Output: dist/petOS.app
```

### First run — system permissions

petOS needs three macOS permissions for full Sleep Focus detection. On first launch, accept the prompts that appear, or grant them manually in System Settings → Privacy & Security:

| Permission | What it enables | If denied |
|---|---|---|
| Focus | The fastest path: a boolean "is any focus on" signal. | Pet only detects Sleep via Control Center scrape (slower) or the midnight–6am window. |
| Accessibility | Reads Control Center for the active focus mode label. | Sleep is only detected via Focus boolean fallback or the time window. |
| Full Disk Access | Most accurate: reads `~/Library/DoNotDisturb/DB/Assertions.json` directly. | Falls back to Control Center scrape (works when CC panel has been opened). |

The Settings → System Access section in the app shows live status of all three. Diagnose any "sleeping animation isn't triggering" issue with:

```bash
log show --predicate 'subsystem == "com.petos.focus"' --last 30s --info --debug
```
````

- [ ] **Step 2: Verify README renders sensibly**

Open `README.md` in any markdown previewer. Confirm the Run section reads cleanly and the table renders.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: replace swift run with ./tools/run.sh; document first-run permissions"
```

### Task 4.6: Final regression sweep

- [ ] **Step 1: Full clean build + tests**

```bash
cd /Users/metehanarin/Documents/petOS
./tools/run.sh --clean &
APP_PID=$!
sleep 5
kill $APP_PID
swift test --scratch-path /tmp/nativepet-test-build
./tools/test-bundle.sh
```

Expected: app launches, tests all pass, smoke test ends in `PASS`.

- [ ] **Step 2: End-to-end manual verification**

1. Turn Sleep Focus OFF.
2. `./tools/run.sh` — confirm pet appears with non-sleeping animation (idle/working/etc per state).
3. Turn Sleep Focus ON via Control Center.
4. Within ~2 seconds, confirm the pet transitions to the sleeping animation (`sleeping-01` … `sleeping-06`).
5. Turn Sleep Focus OFF — confirm transition back.
6. Tail logs in another terminal during steps 3–5:

```bash
log stream --predicate 'subsystem == "com.petos.focus"' --info --debug
```

Expected log progression: `infocus.status authorized=true is_focused=false` → user toggles Sleep ON → `infocus.status authorized=true is_focused=true`, `assertions.read.ok mode_id=com.apple.focus.sleep` (or the unidentified-fallback path), `focus.resolved active=true`, `mood.resolved mood=sleeping reason=sleep_focus_explicit`.

If `mood=sleeping` does NOT appear within ~2 seconds of Sleep Focus turning on, the bug isn't fully gone — the diagnostic logs will tell you which source(s) failed; revisit Chunk 3 Task 3.3 to see whether an exclusion-set entry needs to be removed/added, or Chunk 4 Task 4.1 to see whether a source returned the wrong descriptor.

- [ ] **Step 3: Final commit (if any docs/markdown drift was caught)**

```bash
git status
# If there are uncommitted changes from the regression sweep:
git add <files>
git commit -m "chore: post-implementation cleanup"
```

---

## Done criteria

- `./tools/run.sh` launches, codesign verifies, app appears.
- `./tools/test-bundle.sh` ends in PASS.
- `swift test --scratch-path /tmp/nativepet-test-build` is fully green, including the 5 new fallback tests and the 5 new pipeline tests and the 2 new permissions tests.
- Toggling Sleep Focus on triggers the sleeping animation within one focus poll cycle (≤2s).
- `log stream --predicate 'subsystem == "com.petos.focus"'` shows a coherent narrative for any focus state change.
- README's Run section points at `./tools/run.sh`.
- `rg -n isProperlyBundled Sources/` returns no results.
