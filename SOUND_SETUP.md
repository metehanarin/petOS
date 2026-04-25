# Detailed Sound Setup Guide

The native `PetNative` app supports a dynamic sound system that randomly selects from a pool of 10 meows and 10 purrs. This guide explains how the system works and how to customize it.

## File Naming Convention

The app looks for files with specific names in the resources bundle:

- **Meows**: `meow1.mp3` through `meow10.mp3`
- **Purrs**: `purr1.mp3` through `purr10.mp3`

Supported formats include `.mp3`, `.wav`, and `.m4a`.

## Using the Setup Script

The `setup_sounds.py` script simplifies the process of renaming and moving your files.

1. Place all your downloaded sounds in a single folder.
2. Run `python3 setup_sounds.py`.
3. The script will:
   - Scan for audio files.
   - Try to guess if a file is a meow or a purr based on its filename.
   - Ask you to confirm for ambiguous files.
   - Copy them into `Sources/PetNative/Resources/Sounds/` with the correct names.

## Manual Installation

If you prefer to do it manually:

1. Rename your files to match the convention above.
2. Drag them into `Sources/PetNative/Resources/Sounds/` in Finder.
3. In Xcode, ensure the files are added to the "PetNative" target.
4. Clean and rebuild.

## How it works in Code

The `PetAppModel` manages the sound playback logic. When an event triggers a sound:

1. It checks the user preference for sounds.
2. It picks a random index between 1 and 10.
3. It attempts to load `meow{N}` or `purr{N}` from the main bundle.
4. If the specific numbered file is missing, it falls back to the default `meow.mp3`.

## Troubleshooting

- **No sound?** Check the system volume and the app's internal sound setting.
- **Same sound every time?** Ensure you have multiple files named correctly. If only `meow1.mp3` exists, the other 9 slots will fall back to the default.
- **Resource not found?** Ensure you performed a "Clean Build Folder" in Xcode after adding new assets to the Resources directory.
