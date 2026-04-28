import os
import shutil
import sys

def setup_sounds():
    print("=== PetOS Sound Setup ===")
    print("This script helps you organize your downloaded cat sounds.")
    
    target_dir = "Sources/PetNative/Resources/Sounds"
    if not os.path.exists(target_dir):
        print(f"Error: Target directory {target_dir} not found.")
        print("Please run this script from the project root.")
        return

    source_dir = input("Enter the path to the folder containing your downloaded sounds (e.g., ~/Downloads/cat_sounds): ").strip()
    source_dir = os.path.expanduser(source_dir)

    if not os.path.isdir(source_dir):
        print(f"Error: {source_dir} is not a directory.")
        return

    files = [f for f in os.listdir(source_dir) if f.lower().endswith(('.mp3', '.wav', '.m4a'))]
    if not files:
        print("No audio files found in the source directory.")
        return

    print(f"\nFound {len(files)} audio files.")
    
    meows = []
    purrs = []
    
    for f in files:
        if 'meow' in f.lower() or 'kitten' in f.lower() or 'call' in f.lower():
            meows.append(f)
        elif 'purr' in f.lower():
            purrs.append(f)
        else:
            # Ask user for categorization if ambiguous
            choice = input(f"Is '{f}' a (m)eow or a (p)urr? (Skip with any other key): ").lower()
            if choice == 'm':
                meows.append(f)
            elif choice == 'p':
                purrs.append(f)

    # Process Meows
    for i, f in enumerate(meows, 1):
        ext = os.path.splitext(f)[1]
        new_name = f"meow{i}{ext}"
        print(f"Copying {f} -> {new_name}")
        shutil.copy2(os.path.join(source_dir, f), os.path.join(target_dir, new_name))

    # Process Purrs
    for i, f in enumerate(purrs, 1):
        ext = os.path.splitext(f)[1]
        new_name = f"purr{i}{ext}"
        print(f"Copying {f} -> {new_name}")
        shutil.copy2(os.path.join(source_dir, f), os.path.join(target_dir, new_name))

    print("\nDone! Your sounds have been organized in Sources/PetNative/Resources/Sounds/")
    print("Run ./tools/run.sh --clean to rebuild the app bundle with the new assets.")

if __name__ == "__main__":
    setup_sounds()
