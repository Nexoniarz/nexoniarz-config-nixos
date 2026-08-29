#!/usr/bin/env bash

if [ $# -eq 0 ]; then
    echo "Usage: strip-metadata <file_or_directory>"
    exit 1
fi

TARGET="$1"

echo "[*] Stripping metadata from: $TARGET"

# Remove all embedded metadata while keeping original filenames
if command -v exiftool &> /dev/null; then
    exiftool -all= -overwrite_original -r "$TARGET"
    echo "[+] Exif metadata removed."
else
    echo "[!] Warning: exiftool is not installed."
fi

# Reset timestamps (atime and mtime) to Epoch (1970-01-01 00:00:00)
echo "[*] Resetting timestamps..."
find "$TARGET" -exec touch -t 197001010000.00 {} +

echo "[+] Operation completed successfully."