#!/usr/bin/env bash
# Version 1.2.4 - Skips foreign-only audio files with no matching tracks

# SET YOUR OPTIONS HERE -------------------------------------------------------------------------
MKVMERGE="/usr/bin/mkvmerge"
JQ="/usr/bin/jq"
LOCKFILE="/tmp/mkv_cleanup.lock"
# Modify line 59 for the audio languages you want to keep!
# -----------------------------------------------------------------------------------------------

IFS=$'\n'

# 🔒 Acquire exclusive lock using file descriptor 200
exec 200>"$LOCKFILE"
flock -w 600 200 || {
  echo "⏳ Timeout waiting for lock (10 minutes). Another instance may be stuck. Exiting."
  exit 1
}

# 🔍 Check for required tools
if ! command -v "$JQ" &> /dev/null; then
    echo "❌ jq could not be found. Please install it."
    exit 1
fi
if ! command -v "$MKVMERGE" &> /dev/null; then
    echo "❌ mkvmerge could not be found. Please install it."
    exit 1
fi

# 🧹 Function to process a single MKV file
process_file() {
    local input_file="$1"
    echo -e "\n📦 Processing: $input_file"
    
    local json=$("$MKVMERGE" -J "$input_file")

    # 🎯 Get IDs of audio tracks with desired languages
    local wanted_tracks=($(echo "$json" | "$JQ" -r '.tracks[] | select(.type == "audio" and (.properties.language == "eng" or .properties.language == "en" or .properties.language == "und")) | .id'))

    if [ ${#wanted_tracks[@]} -eq 0 ]; then
        echo "⏭️  Skipping (foreign-only): No matching English/und audio tracks."
        return 0
    fi

    echo "🔊 Keeping audio track IDs: ${wanted_tracks[@]}"

    local output_file="${input_file%.mkv}.tmp.mkv"
    local args=()
    for id in "${wanted_tracks[@]}"; do
        args+=("--audio-tracks" "$id")
    done

    "$MKVMERGE" -o "$output_file" "${args[@]}" "$input_file" || {
        echo "❌ Error processing file!"
        return 1
    }

    if [ -f "$output_file" ]; then
        mv "$output_file" "$input_file"
        echo "✅ Updated: $input_file"
    else
        echo "❌ Error: Temporary file was not created."
        return 1
    fi
}

# 📁 Check directory argument
if [ -n "$1" ]; then
  dir="$1"
else
  echo "⚠️  Please provide a directory path as an argument."
  exit 1
fi

if [ ! -d "$dir" ]; then
  echo "❌ Directory doesn't exist: $dir"
  exit 1
fi

# 🔄 Process all MKV files in the directory
find "$dir" -type f -name "*.mkv" | while read -r file; do
    process_file "$file"
done

unset IFS
