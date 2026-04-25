# Sound System Reference

This document provides a technical overview of the audio implementation in PetNative.

## Architecture

Audio is handled via `NSSound` for simple, low-latency playback of system-like effects.

- **Trigger**: User interactions (clicks, gestures) or world events (notifications, mood changes).
- **Service**: `PetAppModel.playSound(_:)` and `PetAppModel.playPurr()`.
- **Assets**: Scoped within the `Sources/PetNative/Resources/Sounds` directory.

## Asset Specification

| Category | Filename Pattern | Recommended Duration | Usage |
|----------|------------------|----------------------|-------|
| Meow     | `meow1.mp3` - `meow10.mp3` | 0.5s - 2.0s | Clicking the pet, notification alerts |
| Purr     | `purr1.mp3` - `purr10.mp3` | 2.0s - 4.0s | Petting, idle contentment, sleeping |

## Fallback Logic

If the randomized asset search fails (e.g., `meow7` is requested but doesn't exist), the system defaults to:
1. `meow.mp3` (The original base sound)
2. Silence (if even the fallback is missing)

## Development Notes

To add more sounds beyond the 10 slots, update the `PetAppModel` logic:
```swift
// Example: Increasing pool to 20
let randomIndex = Int.random(in: 1...20)
```

## Credits

Sound assets used in development are sourced from Pixabay under their Content License. Users are encouraged to source their own sounds for personal customization.
