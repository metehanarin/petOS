#!/bin/bash

# Cat Sound Downloader Script
# This script helps you download free cat sounds for the PetNative app

set -e

SOUNDS_DIR="Sources/PetNative/Resources/Sounds"
TEMP_DIR="/tmp/pet_sounds"

echo "🐱 PetNative Cat Sound Downloader"
echo "=================================="
echo ""

# Create directories
mkdir -p "$SOUNDS_DIR"
mkdir -p "$TEMP_DIR"

echo "📁 Sound directory: $SOUNDS_DIR"
echo ""

# Function to download a file
download_file() {
    local url=$1
    local output=$2
    echo "  Downloading: $output"
    curl -L -o "$TEMP_DIR/$output" "$url" 2>/dev/null || wget -O "$TEMP_DIR/$output" "$url" 2>/dev/null
}

echo "🔍 This script will guide you through downloading cat sounds."
echo ""
echo "⚠️  Note: I cannot directly download from most sound libraries due to licensing."
echo "   You'll need to manually download sounds from these recommended sources:"
echo ""
echo "   1. Pixabay (https://pixabay.com/sound-effects/search/cat/)"
echo "   2. Mixkit (https://mixkit.co/free-sound-effects/cat/)"
echo "   3. Freesound (https://freesound.org - requires free account)"
echo ""
echo "📋 Here's what you need:"
echo "   - 10 different cat meow sounds"
echo "   - 10 different cat purr sounds"
echo ""
echo "💡 Recommended search terms:"
echo "   Meows: 'cat meow short', 'kitten meow', 'cat calling'"
echo "   Purrs: 'cat purring', 'cat purr', 'content cat'"
echo ""
echo "---"
echo ""

read -p "Have you already downloaded your sound files? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Great! Where are your downloaded files located?"
    read -p "Enter the directory path: " SOURCE_DIR
    
    if [ ! -d "$SOURCE_DIR" ]; then
        echo "❌ Directory not found: $SOURCE_DIR"
        exit 1
    fi
    
    echo ""
    echo "🔄 Looking for sound files in: $SOURCE_DIR"
    
    # Count files
    SOUND_FILES=$(find "$SOURCE_DIR" -type f \( -name "*.mp3" -o -name "*.wav" -o -name "*.m4a" \) | wc -l)
    echo "   Found $SOUND_FILES sound files"
    
    if [ $SOUND_FILES -lt 20 ]; then
        echo "⚠️  Warning: You need at least 20 files (10 meows + 10 purrs)"
        echo "   You can continue and add more later."
        echo ""
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
    
    echo ""
    echo "📝 Now, let's organize your files:"
    echo ""
    echo "I'll help you rename and copy them to the right location."
    echo "For each file, I'll ask if it's a MEOW or PURR."
    echo ""
    
    MEOW_COUNT=1
    PURR_COUNT=1
    
    find "$SOURCE_DIR" -type f \( -name "*.mp3" -o -name "*.wav" -o -name "*.m4a" \) | while read file; do
        filename=$(basename "$file")
        echo "File: $filename"
        
        if [ $MEOW_COUNT -le 10 ] || [ $PURR_COUNT -le 10 ]; then
            read -p "  Is this a [M]eow, [P]urr, or [S]kip? " -n 1 -r
            echo ""
            
            case $REPLY in
                [Mm])
                    if [ $MEOW_COUNT -le 10 ]; then
                        # Convert to mp3 if needed
                        if [[ $file == *.mp3 ]]; then
                            cp "$file" "$SOUNDS_DIR/meow$MEOW_COUNT.mp3"
                        else
                            echo "    ⚠️  Converting to MP3..."
                            if command -v ffmpeg &> /dev/null; then
                                ffmpeg -i "$file" -b:a 128k "$SOUNDS_DIR/meow$MEOW_COUNT.mp3" -y 2>/dev/null
                            else
                                echo "    ❌ ffmpeg not found. Please convert to MP3 manually."
                                continue
                            fi
                        fi
                        echo "    ✓ Saved as meow$MEOW_COUNT.mp3"
                        MEOW_COUNT=$((MEOW_COUNT + 1))
                    fi
                    ;;
                [Pp])
                    if [ $PURR_COUNT -le 10 ]; then
                        # Convert to mp3 if needed
                        if [[ $file == *.mp3 ]]; then
                            cp "$file" "$SOUNDS_DIR/purr$PURR_COUNT.mp3"
                        else
                            echo "    ⚠️  Converting to MP3..."
                            if command -v ffmpeg &> /dev/null; then
                                ffmpeg -i "$file" -b:a 128k "$SOUNDS_DIR/purr$PURR_COUNT.mp3" -y 2>/dev/null
                            else
                                echo "    ❌ ffmpeg not found. Please convert to MP3 manually."
                                continue
                            fi
                        fi
                        echo "    ✓ Saved as purr$PURR_COUNT.mp3"
                        PURR_COUNT=$((PURR_COUNT + 1))
                    fi
                    ;;
                *)
                    echo "    ⏭  Skipped"
                    ;;
            esac
        fi
    done
    
else
    echo ""
    echo "📥 Manual Download Instructions:"
    echo ""
    echo "1. Visit one of these websites:"
    echo "   • https://pixabay.com/sound-effects/search/cat/"
    echo "   • https://mixkit.co/free-sound-effects/cat/"
    echo "   • https://freesound.org (search for 'cat meow' and 'cat purr')"
    echo ""
    echo "2. Download at least 10 meow sounds and 10 purr sounds"
    echo ""
    echo "3. Save them to a folder on your computer"
    echo ""
    echo "4. Run this script again and answer 'y' when asked"
    echo ""
    echo "💡 Tips:"
    echo "   • Look for short sounds (0.5-3 seconds)"
    echo "   • Choose varied sounds for more personality"
    echo "   • MP3 format is preferred (smaller file size)"
    echo ""
    exit 0
fi

echo ""
echo "✅ Sound Setup Complete!"
echo ""
echo "📊 Summary:"
echo "   Meows added: $((MEOW_COUNT - 1))/10"
echo "   Purrs added: $((PURR_COUNT - 1))/10"
echo ""

if [ $MEOW_COUNT -le 10 ] || [ $PURR_COUNT -le 10 ]; then
    echo "⚠️  You don't have all 20 sounds yet. The app will work, but you can add more later."
    echo "   Just rename files as meow1.mp3-meow10.mp3 and purr1.mp3-purr10.mp3"
    echo "   and copy them to: $SOUNDS_DIR"
fi

echo ""
echo "📝 Next steps:"
echo "   1. Open your project in Xcode"
echo "   2. Clean build folder: Product → Clean Build Folder (⇧⌘K)"
echo "   3. Build: Product → Build (⌘B)"
echo "   4. Run your app and click the cat!"
echo ""
echo "🎵 Check console for: [PetNative] PetAudioService init; meows loaded=X, purrs loaded=Y"
echo ""
