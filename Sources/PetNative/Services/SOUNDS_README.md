# Cat Sounds Quick Reference

## Required Files

Your `Sources/PetNative/Resources/Sounds/` directory should contain:

```
meow1.mp3
meow2.mp3
meow3.mp3
meow4.mp3
meow5.mp3
meow6.mp3
meow7.mp3
meow8.mp3
meow9.mp3
meow10.mp3
purr1.mp3
purr2.mp3
purr3.mp3
purr4.mp3
purr5.mp3
purr6.mp3
purr7.mp3
purr8.mp3
purr9.mp3
purr10.mp3
```

## Quick Setup

### Option 1: Automatic Helper Scripts

Run either script to help organize your sounds:

```bash
# Python (recommended)
python3 setup_sounds.py

# Or Bash
bash download_sounds.sh
```

### Option 2: Manual Setup

1. **Download 20 cat sounds** from free sources:
   - [Pixabay](https://pixabay.com/sound-effects/search/cat/) (Recommended)
   - [Mixkit](https://mixkit.co/free-sound-effects/cat/)
   - [Freesound](https://freesound.org)

2. **Rename files** to match the naming pattern above

3. **Copy to directory**:
   ```bash
   cp *.mp3 Sources/PetNative/Resources/Sounds/
   ```

4. **Build and run** your app

## Free Sound Sources

### ⭐ Pixabay (Best for beginners)
- **URL**: https://pixabay.com/sound-effects/search/cat/
- **License**: Free for commercial use, no attribution
- **Quality**: High
- **Account**: Not required

### Mixkit
- **URL**: https://mixkit.co/free-sound-effects/cat/
- **License**: Free, no attribution
- **Quality**: Professional
- **Account**: Not required

### Freesound
- **URL**: https://freesound.org
- **License**: Varies (filter by CC0 or CC-BY)
- **Quality**: Excellent variety
- **Account**: Free account required
- **Search tips**: "cat meow", "cat purr", filter by duration < 3s

### BBC Sound Effects
- **URL**: https://sound-effects.bbcrewind.co.uk
- **License**: Free for personal/educational
- **Quality**: Professional broadcast quality
- **Account**: Not required
- **Search**: "cat"

### Zapsplat
- **URL**: https://www.zapsplat.com
- **License**: Free (attribution appreciated)
- **Quality**: Professional
- **Account**: Free account recommended

## Recommended Sound Characteristics

### Meows
- **Duration**: 0.5 - 2 seconds
- **Types**: Short meow, chirp, trill, questioning meow, demanding meow
- **Variety**: Mix high and low pitches, different ages (kitten to adult)

### Purrs
- **Duration**: 2 - 4 seconds
- **Types**: Soft purr, loud purr, rumbling purr, content purr
- **Quality**: Look for clean recordings without background noise

### Technical Specs
- **Format**: MP3
- **Bitrate**: 128kbps (good quality/size balance)
- **Sample Rate**: 44.1kHz
- **Channels**: Mono or Stereo (mono recommended for smaller size)
- **File Size**: Aim for < 100KB per file

## Audio Editing Tips

### Free Tools

**Audacity** (Desktop - Recommended)
```
Download: https://www.audacityteam.org/
Use for: Trimming, normalizing, format conversion
```

**Online Audio Converter**
```
URL: https://online-audio-converter.com/
Use for: Quick format conversion, bitrate adjustment
```

**FFmpeg** (Command Line - Advanced)
```bash
# Convert to MP3 at 128kbps
ffmpeg -i input.wav -b:a 128k output.mp3

# Trim to first 2 seconds
ffmpeg -i input.mp3 -t 2 -c copy output.mp3

# Normalize audio (make louder)
ffmpeg -i input.mp3 -filter:a "volume=2.0" output.mp3

# Reduce file size
ffmpeg -i input.mp3 -b:a 96k -ac 1 output.mp3
```

### Editing Workflow

1. **Import** sound into Audacity
2. **Trim** silence from start/end
3. **Normalize** to -3dB (Effect → Normalize)
4. **Export** as MP3, 128kbps

## Troubleshooting

### "Meows loaded=0, purrs loaded=0"

**Problem**: Files aren't being found

**Solutions**:
- Check file location: `Sources/PetNative/Resources/Sounds/`
- Verify filenames exactly match: `meow1.mp3` (lowercase, no spaces)
- Ensure files are `.mp3` format
- Clean build folder in Xcode (⇧⌘K)
- Rebuild project (⌘B)

### "Only plays one sound repeatedly"

**Problem**: Only fallback `meow.mp3` exists

**Solutions**:
- Make sure numbered files exist: `meow1.mp3` - `meow10.mp3`
- Don't rely on the fallback file

### "Sound quality is poor"

**Solutions**:
- Use higher quality source recordings
- Normalize audio in Audacity
- Increase bitrate to 192kbps or 256kbps
- Use lossless source when converting to MP3

### "Files are too large"

**Solutions**:
- Reduce bitrate to 96kbps or 128kbps
- Convert stereo to mono (`ffmpeg -ac 1`)
- Trim silence from start/end
- Use online compressor: https://www.mp3smaller.com/

## Verification

### Check files exist:
```bash
ls -la Sources/PetNative/Resources/Sounds/
```

### Count files:
```bash
ls -1 Sources/PetNative/Resources/Sounds/*.mp3 | wc -l
# Should output: 20
```

### Check file sizes:
```bash
du -h Sources/PetNative/Resources/Sounds/*.mp3
```

### Run test script:
```bash
python3 setup_sounds.py
```

## Sound Behavior

When you click the cat:
- **70% chance**: Plays random meow
- **30% chance**: Plays random purr

The app randomly selects from available sounds, so each click will be different!

## License Compliance

When downloading free sounds:

1. **Check the license** for each sound
2. **Preferred licenses**:
   - CC0 (Public Domain) - No attribution needed
   - CC-BY - Attribution required
   - Pixabay License - Free, no attribution
3. **Keep track** of attribution requirements
4. **Create ATTRIBUTIONS.txt** if needed

Example ATTRIBUTIONS.txt:
```
Sound Credits:
- meow1.mp3: "Cat Meow" by UserName (Freesound) - CC-BY 3.0
- purr1.mp3: "Cat Purring" by UserName (Pixabay License)
```

## Need Help?

- See `SOUND_SETUP.md` for detailed instructions
- Run `python3 setup_sounds.py` for interactive setup
- Check console logs when app starts for diagnostic info
- The app works with just the original `meow.mp3` as fallback

## Contributing Sounds

If you create a great set of cat sounds, consider:
- Sharing on Freesound or Pixabay
- Contributing back to open source projects
- Helping other developers with similar needs

Enjoy your interactive cat! 🐱✨
