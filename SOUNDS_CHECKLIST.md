# Cat Sounds Checklist

Follow these steps to give your pet its full voice!

- [ ] **Step 1: Collection**
  - [ ] Download 10 short meow/chirp sounds (MP3 or WAV)
  - [ ] Download 10 purr/rumble sounds (MP3 or WAV)
  - *Tip: Use the links in `SOUND_DOWNLOAD_LINKS.md`*

- [ ] **Step 2: Organization**
  - [ ] Open terminal in the `petOS` directory
  - [ ] Run `python3 setup_sounds.py`
  - [ ] Enter the path to your downloads folder when prompted
  - [ ] Categorize any sounds the script doesn't recognize automatically

- [ ] **Step 3: Verification**
  - [ ] Check `Sources/PetNative/Resources/Sounds/`
  - [ ] You should see `meow1.mp3` through `meow10.mp3`
  - [ ] You should see `purr1.mp3` through `purr10.mp3`

- [ ] **Step 4: Integration**
  - [ ] Open the project in Xcode
  - [ ] Perform a "Clean Build Folder" (Shift + Cmd + K)
  - [ ] Run the app (Cmd + R)
  - [ ] Click the cat repeatedly to hear the new variety of sounds!

- [ ] **Step 5: Testing**
  - [ ] Ensure the volume in settings is audible
  - [ ] Verify that purrs play during appropriate moods (like sleeping or idle petting)
