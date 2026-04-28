# petOS

Native macOS migration target for the Electron-based `petOS` app.

## What is included

- SwiftUI pet window with transparent floating presentation
- Native persistence for age, sound, reactions, cached top apps, and window position
- Ported world-state and mood-resolution logic
- Native localhost reaction hook on `127.0.0.1:7893`
- Native/system-backed integrations for:
  - focus status
  - running/frontmost apps with CoreDuet top-app fallback
  - battery + thermal state
  - CPU sampling
  - idle time
  - weather polling
  - calendar polling
  - music polling
  - notification alert watching via unified log stream
- Swift test coverage for mood logic, services, persistence, reaction HTTP handling, and sprite resources
- Menu bar extra and native settings window

## Run

```bash
cd /Users/metehanarin/Documents/petOS
./tools/run.sh
```

This bundles petOS into a real `.app` so macOS TCC can persist Focus, Accessibility, and Full Disk Access grants across rebuilds. Running the binary directly via `swift run` exits with `EX_CONFIG` (78); use `./tools/run.sh` instead.

Pass extra args to petOS after `--`:

```bash
./tools/run.sh -- --debug
```

Force a full bundle rebuild after editing bundle metadata:

```bash
./tools/run.sh --clean
```

Build a distributable bundle:

```bash
./tools/build-release.sh
# Output: dist/petOS.app
```

### First run - system permissions

petOS needs three macOS permissions for full Sleep Focus detection. On first launch, accept the prompts that appear, or grant them manually in System Settings -> Privacy & Security:

| Permission | What it enables | If denied |
|---|---|---|
| Focus | Fast fallback: a boolean "is any focus on" signal, used to put the pet to sleep when the mode name is unavailable. | Pet only detects Sleep via the named-mode sources below. |
| Accessibility | Reads Control Center for the active focus mode label. | Sleep is still detected via Full Disk Access or the Focus boolean fallback. |
| Full Disk Access | Most accurate: reads `~/Library/DoNotDisturb/DB/Assertions.json` directly. | Falls back to Control Center scrape or the Focus boolean fallback. |

The Settings -> System Access section in the app shows live status of all three. Diagnose any "sleeping animation is not triggering" issue with:

```bash
log show --predicate 'subsystem == "com.petos.focus"' --last 30s --info --debug
```

## Cat Sounds Setup

The app loads up to 10 meow and 10 purr sounds that play randomly when you click the cat.

### Quick Setup

1. **Download cat sounds** from free sources:
   - [Pixabay](https://pixabay.com/sound-effects/search/cat/) (Recommended - no account needed)
   - [Mixkit](https://mixkit.co/free-sound-effects/cat/)
   - [Freesound](https://freesound.org) (requires free account)

2. **Run the setup script**:
   ```bash
   python3 setup_sounds.py
   ```
   
3. **Follow the prompts** to organize your files

4. **Rebuild the app bundle**:
   ```bash
   ./tools/run.sh --clean
   ```

### Files Needed

Add these to `Sources/petOS/Resources/Sounds/`:
- `meow1.mp3` through `meow10.mp3`
- `purr1.mp3` through `purr10.mp3` or `.wav`

The repo currently includes 10 numbered meows, 5 numbered purrs, and `meow.mp3` as a fallback. Add the remaining numbered purrs if you want a fuller sound pool.

### More Help

- See `SOUNDS_CHECKLIST.md` for step-by-step checklist
- See `SOUND_SETUP.md` for detailed instructions
- See `SOUNDS_README.md` for complete reference

The app will work with just the original `meow.mp3` as a fallback, but adding the full set gives your cat much more personality!

## Test

Use a scratch build path to avoid stale copied module caches:

```bash
cd /Users/metehanarin/Documents/petOS
swift test --scratch-path /tmp/nativepet-test-build
```

Trigger a local reaction:

```bash
curl -X POST http://127.0.0.1:7893/reaction \
  -H 'Content-Type: application/json' \
  -d '{"type":"sparkle_clap","priority":90}'
```

## Notes

- The original Electron app remains in the repo as the reference implementation.
- The native port is intentionally isolated as its own package so it can be built and iterated independently.
