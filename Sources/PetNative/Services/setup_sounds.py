#!/usr/bin/env python3
"""
PetNative Cat Sound Setup Script
This script helps organize cat sound files for your PetNative app.
"""

import os
import shutil
import sys
from pathlib import Path

SOUNDS_DIR = Path("Sources/PetNative/Resources/Sounds")
REQUIRED_MEOWS = 10
REQUIRED_PURRS = 10

def main():
    print("🐱 PetNative Cat Sound Setup")
    print("=" * 50)
    print()
    
    # Create sounds directory if it doesn't exist
    SOUNDS_DIR.mkdir(parents=True, exist_ok=True)
    print(f"📁 Sound directory: {SOUNDS_DIR}")
    print()
    
    # Check existing files
    existing_meows = list(SOUNDS_DIR.glob("meow*.mp3"))
    existing_purrs = list(SOUNDS_DIR.glob("purr*.mp3"))
    
    if existing_meows or existing_purrs:
        print(f"✓ Found {len(existing_meows)} meow files")
        print(f"✓ Found {len(existing_purrs)} purr files")
        print()
    
    print("📋 Free Cat Sound Sources:")
    print()
    print("1. Pixabay (Recommended)")
    print("   https://pixabay.com/sound-effects/search/cat/")
    print("   • Free for commercial use")
    print("   • No account needed")
    print("   • High quality")
    print()
    print("2. Mixkit")
    print("   https://mixkit.co/free-sound-effects/cat/")
    print("   • Free sound effects")
    print("   • Easy download")
    print()
    print("3. Freesound")
    print("   https://freesound.org")
    print("   • Huge library")
    print("   • Requires free account")
    print("   • Search: 'cat meow' and 'cat purr'")
    print()
    print("4. BBC Sound Effects")
    print("   https://sound-effects.bbcrewind.co.uk")
    print("   • Professional quality")
    print("   • Search for 'cat'")
    print()
    
    print("-" * 50)
    print()
    
    choice = input("Do you have sound files ready to organize? (y/n): ").strip().lower()
    
    if choice == 'y':
        organize_files()
    else:
        show_download_instructions()

def organize_files():
    """Help user organize their downloaded sound files."""
    print()
    source_dir = input("Enter the path to your downloaded sound files: ").strip()
    source_path = Path(source_dir)
    
    if not source_path.exists():
        print(f"❌ Directory not found: {source_dir}")
        return
    
    # Find all audio files
    audio_extensions = ['.mp3', '.wav', '.m4a', '.aac', '.ogg']
    audio_files = []
    for ext in audio_extensions:
        audio_files.extend(source_path.glob(f"*{ext}"))
    
    if not audio_files:
        print("❌ No audio files found in that directory")
        return
    
    print(f"\n✓ Found {len(audio_files)} audio files")
    print()
    
    if len(audio_files) < 20:
        print(f"⚠️  Warning: You have {len(audio_files)} files, but need 20 total")
        print("   (10 meows + 10 purrs)")
        print("   You can continue and add more later.")
        print()
        cont = input("Continue anyway? (y/n): ").strip().lower()
        if cont != 'y':
            return
    
    print("\n📝 File Organization")
    print("-" * 50)
    print("For each file, choose:")
    print("  [M] = Meow")
    print("  [P] = Purr")
    print("  [S] = Skip")
    print("  [Q] = Quit")
    print()
    
    meow_count = 1
    purr_count = 1
    
    for audio_file in audio_files:
        if meow_count > REQUIRED_MEOWS and purr_count > REQUIRED_PURRS:
            print("\n✅ All 20 sounds collected!")
            break
        
        print(f"\nFile: {audio_file.name}")
        
        available_options = []
        if meow_count <= REQUIRED_MEOWS:
            available_options.append("M")
        if purr_count <= REQUIRED_PURRS:
            available_options.append("P")
        
        if not available_options:
            continue
        
        options_str = "/".join(available_options) + "/S/Q"
        choice = input(f"  [{options_str}]: ").strip().upper()
        
        if choice == 'Q':
            break
        elif choice == 'M' and meow_count <= REQUIRED_MEOWS:
            dest = SOUNDS_DIR / f"meow{meow_count}.mp3"
            copy_and_convert(audio_file, dest)
            print(f"  ✓ Saved as meow{meow_count}.mp3")
            meow_count += 1
        elif choice == 'P' and purr_count <= REQUIRED_PURRS:
            dest = SOUNDS_DIR / f"purr{purr_count}.mp3"
            copy_and_convert(audio_file, dest)
            print(f"  ✓ Saved as purr{purr_count}.mp3")
            purr_count += 1
        else:
            print("  ⏭  Skipped")
    
    print()
    print("=" * 50)
    print("📊 Summary:")
    print(f"  Meows: {meow_count - 1}/{REQUIRED_MEOWS}")
    print(f"  Purrs: {purr_count - 1}/{REQUIRED_PURRS}")
    print()
    
    if meow_count > REQUIRED_MEOWS and purr_count > REQUIRED_PURRS:
        print("✅ Setup complete! All 20 sounds ready.")
    else:
        print("⚠️  Not all sounds added yet. You can:")
        print("   • Run this script again with more files")
        print("   • Manually add files named meow1.mp3-meow10.mp3")
        print(f"     and purr1.mp3-purr10.mp3 to: {SOUNDS_DIR}")
    
    print()
    print_next_steps()

def copy_and_convert(source: Path, dest: Path):
    """Copy file, converting to MP3 if needed."""
    if source.suffix.lower() == '.mp3':
        shutil.copy2(source, dest)
    else:
        # If not MP3, check if ffmpeg is available
        if shutil.which('ffmpeg'):
            print(f"  🔄 Converting {source.suffix} to MP3...")
            os.system(f'ffmpeg -i "{source}" -b:a 128k "{dest}" -y 2>/dev/null')
        else:
            print(f"  ⚠️  Warning: ffmpeg not found, copying as-is")
            print(f"     You may need to convert {dest.name} to MP3")
            shutil.copy2(source, dest)

def show_download_instructions():
    """Show detailed instructions for downloading cat sounds."""
    print()
    print("📥 Download Instructions")
    print("=" * 50)
    print()
    print("STEP 1: Choose a sound source")
    print()
    print("  Recommended: Pixabay")
    print("  → https://pixabay.com/sound-effects/search/cat/")
    print()
    print("STEP 2: Download sounds")
    print()
    print("  You need:")
    print("  • 10 different meow sounds")
    print("  • 10 different purr sounds")
    print()
    print("  Search terms to try:")
    print("  • 'cat meow short'")
    print("  • 'kitten meow'")
    print("  • 'cat purr'")
    print("  • 'cat purring'")
    print()
    print("STEP 3: Save to a folder")
    print()
    print("  Create a folder (e.g., ~/Downloads/cat_sounds)")
    print("  Save all downloaded files there")
    print()
    print("STEP 4: Run this script again")
    print()
    print("  python3 setup_sounds.py")
    print("  Then answer 'y' when asked if you have files ready")
    print()
    print("💡 Tips:")
    print("  • Keep sounds short (0.5-3 seconds)")
    print("  • Choose varied sounds for personality")
    print("  • MP3 format preferred (smaller files)")
    print()

def print_next_steps():
    """Print what to do after setup."""
    print("📝 Next Steps:")
    print()
    print("1. Open your project in Xcode")
    print()
    print("2. Clean build folder:")
    print("   Product → Clean Build Folder (⇧⌘K)")
    print()
    print("3. Build the project:")
    print("   Product → Build (⌘B)")
    print()
    print("4. Run your app:")
    print("   Product → Run (⌘R)")
    print()
    print("5. Click the cat and listen!")
    print()
    print("🔍 Check the console for:")
    print("   [PetNative] PetAudioService init; meows loaded=X, purrs loaded=Y")
    print()

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n👋 Cancelled by user")
        sys.exit(0)
