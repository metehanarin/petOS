# Cat Sounds Setup Checklist

## Quick Start (5 minutes)

- [ ] **Step 1**: Go to https://pixabay.com/sound-effects/search/cat/
- [ ] **Step 2**: Download 10 meow sounds and 10 purr sounds
- [ ] **Step 3**: Save them to a folder (e.g., `~/Downloads/cat_sounds/`)
- [ ] **Step 4**: Run the setup script:
  ```bash
  python3 setup_sounds.py
  ```
- [ ] **Step 5**: Follow the prompts to organize your files
- [ ] **Step 6**: Clean build in Xcode (Product → Clean Build Folder)
- [ ] **Step 7**: Build and run your app
- [ ] **Step 8**: Click the cat and enjoy! 🎉

## Files You Need

### Meow Sounds (10 files)
- [ ] meow1.mp3
- [ ] meow2.mp3
- [ ] meow3.mp3
- [ ] meow4.mp3
- [ ] meow5.mp3
- [ ] meow6.mp3
- [ ] meow7.mp3
- [ ] meow8.mp3
- [ ] meow9.mp3
- [ ] meow10.mp3

### Purr Sounds (10 files)
- [ ] purr1.mp3
- [ ] purr2.mp3
- [ ] purr3.mp3
- [ ] purr4.mp3
- [ ] purr5.mp3
- [ ] purr6.mp3
- [ ] purr7.mp3
- [ ] purr8.mp3
- [ ] purr9.mp3
- [ ] purr10.mp3

## Verification

After setup, check:

- [ ] Files exist in `Sources/PetNative/Resources/Sounds/`
- [ ] All 20 files are present
- [ ] Files are named correctly (lowercase, no spaces)
- [ ] Files are MP3 format
- [ ] Console shows: `[PetNative] PetAudioService init; meows loaded=10, purrs loaded=10`

## Recommended Download Sources

**Easiest**: Pixabay
- ✅ No account required
- ✅ Free for commercial use
- ✅ No attribution needed
- 🔗 https://pixabay.com/sound-effects/search/cat/

**Most Variety**: Freesound
- ⚠️ Requires free account
- ✅ Huge library
- ⚠️ Check individual licenses
- 🔗 https://freesound.org

**Professional Quality**: Mixkit
- ✅ No account required
- ✅ High quality
- ✅ Free for commercial use
- 🔗 https://mixkit.co/free-sound-effects/cat/

## Tips for Best Results

- [ ] Choose sounds 0.5-3 seconds long
- [ ] Mix different pitches and tones
- [ ] Include both kitten and adult cat sounds
- [ ] Keep purrs softer and more soothing
- [ ] Keep meows more varied and expressive
- [ ] Use Audacity to trim and normalize if needed

## If Something Goes Wrong

**No sounds playing?**
- Check console for: `meows loaded=0`
- Verify files are in correct directory
- Rebuild project in Xcode

**Only one sound playing?**
- Make sure you have numbered files (meow1-10, purr1-10)
- Don't rely on the fallback `meow.mp3`

**Wrong format?**
- Convert to MP3 using Audacity or FFmpeg
- Or use: https://online-audio-converter.com/

## After Setup

Your cat will now:
- ✨ Play random meows when clicked (70% chance)
- ✨ Play random purrs when clicked (30% chance)
- ✨ Have unique personality with varied sounds
- ✨ Never sound repetitive!

---

**Need detailed help?** See `SOUND_SETUP.md` or `SOUNDS_README.md`

**Want interactive setup?** Run `python3 setup_sounds.py`
