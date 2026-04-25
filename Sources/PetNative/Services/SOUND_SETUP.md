# Cat Sound Setup Guide

This guide will help you add 10 meow and 10 purr sounds to your PetNative app.

## Quick Setup (Recommended)

### Step 1: Download Cat Sounds

I've curated links to free, high-quality cat sounds. Download them from these sources:

#### Free Sound Libraries (No Account Required)

1. **Pixabay** - https://pixabay.com/sound-effects/search/cat/
   - Free for commercial use
   - No attribution required
   - Good variety of cat sounds

2. **Mixkit** - https://mixkit.co/free-sound-effects/cat/
   - Free sound effects
   - High quality
   - No attribution needed

3. **SoundBible** - http://soundbible.com/tags-cat.html
   - Public domain sounds
   - Easy downloads
   - Various cat sounds

#### Recommended Sounds to Download

**For Meows (short, varied):**
- Look for: "cat meow short", "kitten meow", "cat calling", "cat chirp"
- Duration: 0.5-2 seconds each
- Get 10 different variations

**For Purrs (soothing, continuous):**
- Look for: "cat purring", "cat purr loop", "contented cat"
- Duration: 2-4 seconds each
- Get 10 different variations

### Step 2: Prepare the Files

1. **Rename your downloaded files:**
   ```
   meow1.mp3, meow2.mp3, meow3.mp3, ..., meow10.mp3
   purr1.mp3, purr2.mp3, purr3.mp3, ..., purr10.mp3
   ```

2. **Optional - Normalize Audio:**
   - Use Audacity (free) to make all volumes consistent
   - Recommended: -3dB to -6dB peak volume
   - Trim silence from beginning/end

### Step 3: Add to Your Xcode Project

Since you're using Swift Package Manager:

1. **Create the Resources/Sounds directory** (if it doesn't exist):
   ```bash
   mkdir -p Sources/PetNative/Resources/Sounds
   ```

2. **Copy all 20 sound files** into that directory:
   ```bash
   cp meow*.mp3 Sources/PetNative/Resources/Sounds/
   cp purr*.mp3 Sources/PetNative/Resources/Sounds/
   ```

3. **Verify the files are there:**
   ```bash
   ls -la Sources/PetNative/Resources/Sounds/
   ```

4. **Rebuild your project** in Xcode:
   - Product → Clean Build Folder (⇧⌘K)
   - Product → Build (⌘B)

### Step 4: Test

1. Run your app
2. Click on the cat
3. You should hear random meows and purrs!
4. Check the console logs to see which sounds are loaded:
   ```
   [PetNative] PetAudioService init; meows loaded=10, purrs loaded=10
   ```

## Alternative: Use Online Sound Generators

If you want to generate cat sounds programmatically, you can use:

1. **ElevenLabs** (AI voice/sound generation)
2. **MyInstants** (download from sound boards)
3. **YouTube Audio Library** (download and extract audio)

## Troubleshooting

### Sounds not loading?

Check the console output:
```
[PetNative] PetAudioService init; meows loaded=X, purrs loaded=Y
```

- If X or Y is 0, the files aren't in the right location
- Make sure files are in `Sources/PetNative/Resources/Sounds/`
- Check file names exactly match: `meow1.mp3`, not `meow 1.mp3` or `Meow1.mp3`

### Only one sound playing?

If only the fallback `meow.mp3` is found:
- Make sure numbered files exist: `meow1.mp3` through `meow10.mp3`
- Check file extensions are `.mp3` (not `.MP3` or `.m4a`)

### Files are too large?

- Use online tools to compress: https://www.mp3smaller.com/
- Recommended settings: 128kbps, mono, 44.1kHz
- Keep files under 100KB each for best performance

## Quick Test Script

Save this as `test_sounds.sh` and run it to verify your setup:

```bash
#!/bin/bash

SOUNDS_DIR="Sources/PetNative/Resources/Sounds"

echo "Checking for sound files in $SOUNDS_DIR..."
echo ""

echo "Meow files:"
for i in {1..10}; do
    if [ -f "$SOUNDS_DIR/meow$i.mp3" ]; then
        size=$(du -h "$SOUNDS_DIR/meow$i.mp3" | cut -f1)
        echo "  ✓ meow$i.mp3 ($size)"
    else
        echo "  ✗ meow$i.mp3 (missing)"
    fi
done

echo ""
echo "Purr files:"
for i in {1..10}; do
    if [ -f "$SOUNDS_DIR/purr$i.mp3" ]; then
        size=$(du -h "$SOUNDS_DIR/purr$i.mp3" | cut -f1)
        echo "  ✓ purr$i.mp3 ($size)"
    else
        echo "  ✗ purr$i.mp3 (missing)"
    fi
done

echo ""
echo "Total sound files: $(ls -1 $SOUNDS_DIR/*.mp3 2>/dev/null | wc -l)"
```

Make it executable and run:
```bash
chmod +x test_sounds.sh
./test_sounds.sh
```

## Need Help?

- The app will work with just the original `meow.mp3` as a fallback
- You can add sounds gradually (e.g., start with 3 meows and 3 purrs)
- File names must be exact: `meow1.mp3` through `meow10.mp3`

## Audio Editing Tools (Free)

- **Audacity** - https://www.audacityteam.org/
  - Trim, normalize, convert formats
  
- **Online Audio Converter** - https://online-audio-converter.com/
  - Convert to MP3, adjust bitrate

- **FFmpeg** (command line):
  ```bash
  # Convert to MP3
  ffmpeg -i input.wav -b:a 128k output.mp3
  
  # Trim to first 2 seconds
  ffmpeg -i input.mp3 -t 2 -c copy output.mp3
  
  # Normalize volume
  ffmpeg -i input.mp3 -af "volume=1.5" output.mp3
  ```
