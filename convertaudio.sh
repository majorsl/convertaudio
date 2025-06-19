#!/usr/bin/env bash
# Version 1.2.0 - Adds locking via flock for safe concurrent usage

# SET YOUR OPTIONS HERE -------------------------------------------------------------------------
MKVMERGE="/usr/bin/"
JQ="/usr/bin/"
LOCKFILE="/tmp/mkv_cleanup.lock"
# Modify lines 33, 43 and 57 for the audio languages you want to keep!
# -----------------------------------------------------------------------------------------------

IFS=$'\n'

# Acquire exclusive lock using file descriptor 200
exec 200>"$LOCKFILE"
flock -n 200 || {
  echo "Another instance of this script is running. Exiting."
  exit 1
}

# Check for required tools
if ! command -v "$JQ"jq &> /dev/null; then
    echo "jq could not be found. Please install it."
    exit 1
fi
if ! command -v "$MKVMERGE"mkvmerge &> /dev/null; then
    echo "mkvmerge could not be found. Please install it."
    exit 1
fi

# Function to process a single MKV file
process_file() {
    local input_file="$1"
    
    local json=$("$MKVMERGE"mkvmerge -J "$input_file")

    local tracks_to_remove=($(echo "$json" | "$JQ"jq -r '.tracks[] | select(.type == "audio" and (.properties.language != "eng" and .properties.language != "en" and .properties.language != "und")) | .properties.number'))
    
    echo "Tracks to remove: ${tracks_to_remove[@]}"
    
    if [ ${#tracks_to_remove[@]} -gt 0 ]; then
        local output_file="${input_file%.mkv}.tmp.mkv"

        "$MKVMERGE"mkvmerge -o "$output_file" -a "en,eng,und" "$input_file" || {
            echo "Error processing file: $input_file"
            return 1
        }
        
        if [ -f "$output_file" ]; then
            mv "$output_file" "$input_file"
            echo "Successfully updated file: $input_file"
        else
            echo "Error: New file was not created."
            return 1
        fi
    else
        echo "No non-English audio tracks to remove in: $input_file"
    fi
}

# Check directory argument
if [ -n "$1" ]; then
  dir="$1"
else
  echo "Please call the script with a trailing directory part to process."
  exit 1
fi

if [ ! -d "$dir" ]; then
  echo "Directory doesn't exist, aborting."
  exit 1
fi

# Process all .mkv files
find "$dir" -type f -name "*.mkv" | while read -r file; do
    process_file "$file"
done

unset IFS
