# PetNative

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
cd /Users/metehanarin/Documents/NativePet
swift run PetNative
```

Run with debug logging and mood-cycling shortcuts enabled:

```bash
cd /Users/metehanarin/Documents/NativePet
swift run PetNative -- --debug
```

## Cat Sounds Setup

The app now supports 10 meow and 10 purr sounds that play randomly when you click the cat!

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

4. **Rebuild** in Xcode (Clean Build Folder, then Build)

### Files Needed

Add these to `Sources/PetNative/Resources/Sounds/`:
- `meow1.mp3` through `meow10.mp3` (10 meow sounds)
- `purr1.mp3` through `purr10.mp3` (10 purr sounds)

### More Help

- See `SOUNDS_CHECKLIST.md` for step-by-step checklist
- See `SOUND_SETUP.md` for detailed instructions
- See `SOUNDS_README.md` for complete reference

The app will work with just the original `meow.mp3` as a fallback, but adding the full set gives your cat much more personality!

## Test

Use a scratch build path to avoid stale copied module caches:

```bash
cd /Users/metehanarin/Documents/NativePet
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
