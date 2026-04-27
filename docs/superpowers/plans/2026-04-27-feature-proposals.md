# PetNative — 10 Feature Proposals

**Date:** 2026-04-27  
**Status:** Draft — awaiting review  
**Scope:** PetNative (Sources/PetNative)

---

## Overview

Ten proposed additions to PetNative, ordered by a blend of "cool factor" and feasibility. Each proposal includes a description, technical approach, integration points with the existing codebase, and estimated effort.

---

## 1. 🐾 Screen-Edge Roaming

**The pet walks along the bottom of the screen when idle, occasionally pausing to look around or sit down.**

Instead of sitting frozen in place, the pet drifts along the screen edge during `idle` mood. Movement is slow, organic, and interruptible — clicking the pet or any mood change snaps it back to its home position. The pet respects multi-monitor boundaries and the Dock.

### Technical Approach

- New `PetRoamingEngine` in `Logic/` — a state machine with phases: `resting`, `walking_left`, `walking_right`, `pausing`, `returning`
- Driven by a repeating `Task` in `PetAppModel` that ticks every ~50ms during `idle` mood
- `PetWindowManager.move(by:)` — new method that shifts the window origin by a delta, clamped to `NSScreen.main.visibleFrame`
- New sprite set: `walk-left-01..06`, `walk-right-01..06` (mirrored)
- Roaming pauses when:
  - Mood changes away from `idle`
  - User clicks or drags the pet
  - `alwaysOnTop` is off and the pet is occluded

### Integration Points

| Component | Change |
|---|---|
| `PetAppModel` | New `roamingEnabled` preference, roaming tick task |
| `PetWindowManager` | `move(by:)` method, boundary clamping |
| `PetSpriteView` | New walking sprite configurations |
| `PetPersistence` | New preference field |
| `SettingsView` | Toggle in Care tab |

### Effort: **High** — needs new sprite assets + movement engine + boundary logic

---

## 2. 🎯 Pomodoro Companion

**A built-in focus timer that the pet actively participates in — working hard during focus, celebrating on break, and nudging you when the timer ends.**

The pet becomes a visual Pomodoro clock. During a focus session the pet enters a dedicated `focused` animation (headphones, intense typing). When the timer ends, the pet does a celebration dance and a break countdown begins. The timer state is surfaced in the menu bar extra and via the reaction server API.

### Technical Approach

- New `PetPomodoroTimer` in `Logic/` — `ObservableObject` with states: `idle`, `focus(remaining:)`, `break(remaining:)`, `longBreak(remaining:)`
- Default intervals: 25m focus / 5m break / 15m long break (every 4 cycles)
- Timer publishes to `PetAppModel`, which injects a synthetic `WorldState` override:
  - During focus: forces `working` mood with reason `pomodoro_focus`
  - During break: forces `dancing` mood with reason `pomodoro_break`
  - On transition: enqueues a `pomodoro_complete` reaction (triggers celebration burst)
- Optional system notification at focus/break transitions
- Menu bar extra shows remaining time as a subtitle when active

### Integration Points

| Component | Change |
|---|---|
| `PetAppModel` | Owns `PetPomodoroTimer`, new mood override path |
| `PetMoodEngine` | New `Reason` cases for pomodoro states |
| `PetNativeApp` | Start/stop buttons in menu bar extra |
| `SettingsView` | Pomodoro tab with interval configuration |
| `PetReactionServer` | New `/pomodoro` endpoint to start/stop remotely |

### Effort: **Medium** — timer logic is straightforward; UI integration is the bulk

---

## 3. ✨ Ambient Mood Particles

**Floating particles around the pet that react to weather, mood, and time of day — rain drops, music notes, Zzz bubbles, snowflakes, sparkle dust.**

A particle layer renders above the shadow but behind the sprite. Each mood/weather combination maps to a particle preset. Particles drift naturally with subtle physics (gravity for rain, float for Zzz, bounce for music notes).

### Technical Approach

- New `ParticleEmitterView` in `UI/` — SwiftUI `Canvas` + `TimelineView` based renderer
- Particle types: `raindrop`, `snowflake`, `musicNote`, `zzz`, `sparkle`, `leaf`, `heatWave`
- Mapping table:

  | Condition | Particle | Count | Behavior |
  |---|---|---|---|
  | `weather.rain` | `raindrop` | 8–12 | Fall with slight horizontal drift |
  | `weather.snow` | `snowflake` | 6–10 | Gentle zigzag descent |
  | `mood.sleeping` | `zzz` | 3 | Float upward, fade out |
  | `mood.dancing` | `musicNote` | 4–6 | Bounce and rotate |
  | `mood.sick` + `thermal.serious` | `heatWave` | 3 | Shimmer upward |
  | `sunPhase.dawn/golden` | `sparkle` | 4 | Twinkle in place |

- Particles are emoji-rendered via `Text` for zero asset overhead, or tiny SF Symbols
- Toggle in Settings → Care → "Ambient particles"

### Integration Points

| Component | Change |
|---|---|
| `PetStageView` | Insert `ParticleEmitterView` layer in ZStack |
| `PetAppModel` | New `particlesEnabled` preference |
| `PetPersistence` | New preference field |
| `SettingsView` | Toggle |

### Effort: **Medium** — Canvas particle system is fun to build, no new assets needed

---

## 4. 🌱 Pet Evolution System

**The pet visually evolves as it ages — from a tiny kitten at day 0, to an adult cat, to a distinguished elder. Each stage unlocks new animations and reactions.**

Three life stages with distinct sprite sets and behaviors:

| Stage | Age Range | Visual | Behavioral Changes |
|---|---|---|---|
| **Kitten** | 0–13 days | Small, big eyes, clumsy | Extra bouncy dancing, falls asleep faster |
| **Adult** | 14–89 days | Current sprites | Standard behavior |
| **Elder** | 90+ days | Slightly larger, dignified | Slower animations, exclusive "wise" idle pose, purrs more than meows |

### Technical Approach

- New `PetLifeStage` enum: `.kitten`, `.adult`, `.elder`
- `PetSpriteCatalog.configuration(for:stage:)` — stage-aware sprite lookup with fallback to current sprites
- Sprite naming convention: `kitten-idle-01.png`, `elder-idle-01.png` (adult uses current names)
- `PetMoodEngine` gets a `stage` parameter that modifies thresholds:
  - Kittens: sleep window extends to 0–7am (they need more sleep)
  - Elders: idle threshold before drowsy drops to 2min
- Age milestone reactions auto-fire at stage transitions (day 14, day 90)

### Integration Points

| Component | Change |
|---|---|
| `PetAppModel` | Computed `lifeStage` property based on `age` |
| `PetSpriteCatalog` | Stage-aware sprite lookup |
| `PetMoodEngine` | Stage-modified thresholds |
| `SettingsView` | Display current life stage in header |
| `PetPersistence` | No change (age already persisted) |

### Effort: **High** — primarily asset creation (3× sprite sets), logic is moderate

---

## 5. 📊 Mood Journal & Timeline

**An automatic diary of the pet's mood throughout the day, viewable as a beautiful color-coded timeline in Settings.**

Every mood transition is timestamped and stored. The Settings view gains a "Journal" tab showing today's mood flow as a horizontal gradient bar, plus a week view with daily summaries. Tapping a segment shows what triggered that mood.

### Technical Approach

- New `MoodJournalEntry` model: `{ mood, reason, startedAt, endedAt }`
- `PetAppModel` records entries on every `recomputeMood` that produces a different mood
- Stored in `PetPersistence` as a rolling 30-day log (capped at ~2000 entries)
- New `JournalView` in `UI/`:
  - **Today strip**: horizontal bar segmented by mood, color-coded (green=idle, blue=working, purple=sleeping, yellow=dancing, orange=alert, red=sick)
  - **Week grid**: 7 rows × 24 columns heatmap
  - **Stats**: "Most productive day", "Average focus hours", "Longest sleep streak"
- Export as JSON via a button in the Journal tab

### Integration Points

| Component | Change |
|---|---|
| `PetAppModel` | Record mood transitions |
| `PetPersistence` | New `moodJournal: [MoodJournalEntry]` field |
| `SettingsView` | New "Journal" tab |
| `UI/JournalView.swift` | New file — timeline + heatmap views |

### Effort: **Medium** — data collection is trivial, the timeline UI is the interesting part

---

## 6. 🛡️ Screen Break Guardian

**After extended continuous use, the pet shows visible concern and gently reminds you to take a break — stretching, yawning, then holding up a tiny "break?" sign.**

Uses the existing `idle` time tracking in reverse: when `idle < 5s` for more than 45 minutes straight, the pet triggers a "concerned" sequence. The reminder is purely visual (no system notifications unless opted in), respecting the pet's non-intrusive spirit.

### Technical Approach

- New `ScreenBreakMonitor` in `Services/`:
  - Tracks `continuousActiveTime` — resets when `idle > 60s`
  - Configurable threshold (default 45min, range 15min–2hr)
  - Fires a `break_reminder` reaction when threshold is hit
  - Cooldown: won't re-fire for 15min after a reminder
- New sprite: `break-reminder-01..03` (pet stretching, yawning, holding sign)
- The reaction triggers a special `ReactionVariant.reminder` with a unique particle effect (gentle pulse)
- Optional: clicking the pet during reminder starts a 5-minute break timer (ties into Pomodoro companion if both are enabled)

### Integration Points

| Component | Change |
|---|---|
| `PetMonitorCoordinator` | New repeating task for break monitoring |
| `PetAppModel` | Handle `break_reminder` reaction |
| `PetSpriteView` | Reminder sprite configuration |
| `SettingsView` | Toggle + threshold slider in Care tab |
| `PetPersistence` | New preferences: `breakReminderEnabled`, `breakReminderMinutes` |

### Effort: **Medium** — logic is simple, needs 3 new sprite frames

---

## 7. 🎪 Interactive Tricks

**Keyboard shortcuts and gestures trigger fun one-shot animations — backflip, peek-a-boo, chase a laser dot, or do a little spin.**

Each trick is a scripted animation sequence that temporarily overrides the current mood sprite. Tricks are triggered via global hotkeys, the context menu, or the reaction server API.

### Technical Approach

- New `PetTrickEngine` in `Logic/`:
  - Trick catalog: `backflip`, `spin`, `peekaboo`, `laser_chase`, `wave`, `nap_fake`
  - Each trick is a `[PetSpriteFrame]` sequence with a total duration
  - During a trick, `PetAppModel.activeTrick` overrides `currentMood` for sprite selection
  - Tricks are non-interruptible (finish their sequence before returning to mood)
- Global hotkey registration via `CGEvent.tapCreate` or `NSEvent.addGlobalMonitorForEvents`:
  - `⌘⇧T` — random trick
  - `⌘⇧1..6` — specific tricks
- Reaction server: `POST /reaction` with `type: "trick_backflip"` etc.
- Context menu: "Do a trick" → submenu with all available tricks

### Integration Points

| Component | Change |
|---|---|
| `PetAppModel` | `activeTrick` state, trick execution queue |
| `PetSpriteView` | Trick sprite configurations |
| `PetViews` | Context menu submenu |
| `PetNativeApp` | Command menu entries |
| `PetReactionServer` | Trick types recognized in validator |

### Effort: **High** — needs sprite assets per trick + hotkey system

---

## 8. 🌍 Seasonal & Holiday Themes

**The pet's aura, particles, and idle animations automatically change with real-world seasons and holidays — cherry blossoms in spring, snow in winter, pumpkins on Halloween, fireworks on New Year's.**

A background seasonal engine selects the active theme based on the current date. Themes modify the aura colors, particle presets, and optionally swap the idle sprite for a themed variant.

### Technical Approach

- New `SeasonalThemeEngine` in `Logic/`:
  - Resolves current theme from date: `spring` (Mar–May), `summer` (Jun–Aug), `autumn` (Sep–Nov), `winter` (Dec–Feb)
  - Holiday overrides: `halloween` (Oct 28–31), `newYear` (Dec 31–Jan 1), `valentine` (Feb 14), etc.
  - Returns `SeasonalTheme { auraOverride, particlePreset, idleSpritePrefix? }`
- `PetStageView` applies theme-sourced aura colors when no weather override is active
- Composable with ambient particles (proposal #3): seasonal themes provide a default particle set
- User can disable seasonal themes or lock a specific one in Settings

### Integration Points

| Component | Change |
|---|---|
| `PetStageView` | Theme-aware aura color selection |
| `PetAppModel` | `currentTheme` computed property |
| `ParticleEmitterView` | Season-specific particle presets (if #3 is built) |
| `SettingsView` | Theme selector: Auto / Spring / Summer / Autumn / Winter / Off |
| `PetPersistence` | New `themeOverride` preference |

### Effort: **Low–Medium** — logic is simple date math, visual impact depends on particle system

---

## 9. 💬 Thought Bubbles

**The pet occasionally shows a small thought bubble with contextual micro-commentary — "Hmmm, Slack again?", "Nice weather today ☀️", "3 hours focused! 🔥", "Bedtime soon 🌙".**

A curated set of context-aware phrases displayed as a floating pill above the pet. Bubbles appear at mood transitions, notable world-state changes, or randomly during idle. They fade in, linger for 4 seconds, and fade out.

### Technical Approach

- New `ThoughtBubbleEngine` in `Logic/`:
  - Input: `WorldState` diff (previous vs current) + `currentMood` + `age`
  - Output: `Optional<ThoughtBubble>` with text, emoji, and display priority
  - Rules table (examples):

    | Trigger | Bubble Text |
    |---|---|
    | Mood → sleeping | "Goodnight 🌙" / "Zzz..." |
    | Mood → dancing | "Love this song! 🎶" / "♪ ♫ ♬" |
    | Mood → sick (thermal) | "It's getting hot in here 🥵" |
    | Mood → working for >2hr | "In the zone! 🔥" / "Flow state ✨" |
    | Front app → Slack | "Another message? 💬" |
    | Battery < 20% | "We need power! 🔋" |
    | Age milestone (7, 30, 100) | "1 week together! 🎂" |
    | Random idle (1/20 chance per min) | "...", "😺", "*purrs*" |

  - Cooldown: minimum 30s between bubbles
  - Customization: user-defined phrases in a future version

- New `ThoughtBubbleView` in `UI/` — a floating `Text` in a rounded pill with a small triangle pointer, positioned above the pet sprite

### Integration Points

| Component | Change |
|---|---|
| `PetAppModel` | `currentThought` published property, thought generation on mood/world changes |
| `PetStageView` | `ThoughtBubbleView` layer in ZStack |
| `SettingsView` | Toggle: "Thought bubbles" in Care tab |
| `PetPersistence` | New `thoughtBubblesEnabled` preference |

### Effort: **Medium** — mostly content curation + a small SwiftUI overlay

---

## 10. 🔗 Shortcut & Automation Hooks

**Deep integration with macOS Shortcuts app — expose pet actions as Shortcut actions and allow users to build custom automations.**

Expose key PetNative operations as `AppIntent`s so they appear in the Shortcuts app. Users can build automations like "When I arrive home → pet does a happy dance" or "Every day at 9am → show my mood summary".

### Technical Approach

- New `Intents/` directory with `AppIntent` conformances:

  | Intent | Parameters | Effect |
  |---|---|---|
  | `TriggerReaction` | `type: String`, `priority: Int?` | Same as POST /reaction |
  | `GetPetMood` | — | Returns current mood as string |
  | `GetPetAge` | — | Returns age in days |
  | `SetSound` | `enabled: Bool` | Toggle meow sounds |
  | `StartPomodoro` | `minutes: Int?` | Start focus timer (if #2 is built) |
  | `GetMoodSummary` | `date: Date?` | Returns mood breakdown (if #5 is built) |

- Each intent uses `@MainActor` and accesses `PetAppModel.current` (the static weak ref we just added)
- Intents are declared in `Info.plist` via `INIntentsHandledByApplicationContents`
- Zero additional dependencies — `AppIntents` framework ships with macOS 13+

### Integration Points

| Component | Change |
|---|---|
| New `Intents/` directory | 4–6 `AppIntent` structs |
| `PetAppModel` | Already has `static weak var current` |
| `Info.plist` | Intent declarations |
| `Package.swift` | No change (AppIntents is a system framework) |

### Effort: **Low–Medium** — `AppIntent` API is concise; each intent is ~20 lines

---

## Priority Matrix

```
                        ┌─────────────────────────────────┐
                        │         HIGH IMPACT             │
                        │                                 │
              ┌─────────┼──────────┐                      │
              │ #9 Thought Bubbles │  #1 Screen Roaming   │
              │ #3 Particles       │  #4 Pet Evolution    │
              │ #10 Shortcuts      │  #7 Tricks           │
              ├────────────────────┼──────────────────────┤
   LOW EFFORT │ #8 Seasonal Themes │  #2 Pomodoro         │ HIGH EFFORT
              │                    │  #5 Mood Journal     │
              │                    │  #6 Break Guardian   │
              │                    │                      │
              └────────────────────┴──────────────────────┘
                        │         LOW IMPACT              │
                        └─────────────────────────────────┘
```

## Recommended Build Order

| Phase | Features | Rationale |
|---|---|---|
| **Phase 1** — Quick wins | #9 Thought Bubbles, #3 Ambient Particles | Dramatic visual upgrade, zero new assets needed, composable with later features |
| **Phase 2** — Depth | #5 Mood Journal, #10 Shortcuts | Adds lasting value and automation; journal data enables future insights |
| **Phase 3** — Engagement | #2 Pomodoro, #6 Break Guardian | Utility features that make the pet genuinely useful beyond decoration |
| **Phase 4** — Delight | #8 Seasonal Themes, #1 Screen Roaming | Polish layer; themes compose with particles, roaming makes idle state alive |
| **Phase 5** — Ambition | #4 Pet Evolution, #7 Interactive Tricks | Asset-heavy; save for when the sprite pipeline is mature |

---

## Dependencies Between Proposals

- **#3 Particles → #8 Seasonal Themes**: themes provide particle presets
- **#2 Pomodoro → #6 Break Guardian**: break timer can integrate with pomodoro
- **#5 Mood Journal → #10 Shortcuts**: GetMoodSummary intent needs journal data
- **#4 Pet Evolution → #1 Roaming**: stage-specific walk sprites
- **#9, #10, #8**: fully independent — can be built in any order
