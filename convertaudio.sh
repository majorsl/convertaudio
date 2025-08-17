#!/usr/bin/env bash
# Version 1.4.1 - Keeps all eng/en/und tracks
#               - Fixes multiple --audio-tracks bug
#               - Fixes incorrect "removing" log output
#               - Removes global IFS override (cleaner output)

# SET YOUR OPTIONS HERE -------------------------------------------------------------------------
MKVMERGE="/usr/bin/mkvmerge"
JQ="/usr/bin/jq"
LOCKFILE="/tmp/mkv_cleanup.lock"
# -----------------------------------------------------------------------------------------------

# 🔒 Acquire exclusive lock using file descriptor 200
exec 200>"$LOCKFILE"
flock -w 600 200 || {
  echo "⏳ Timeout waiting for lock (10 minutes). Another instance may be stuck. Exiting."
  exit 1
}

# 🔍 Check for required tools
if [ ! -x "$JQ" ]; then
    echo "❌ jq not found at $JQ"
    exit 1
fi
if [ ! -x "$MKVMERGE" ]; then
    echo "❌ mkvmerge not found at $MKVMERGE"
    exit 1
fi

# 🧹 Function to process a single MKV file
process_file() {
    local input_file="$1"
    echo -e "\n📦 Processing: $input_file"

    local json
    json=$("$MKVMERGE" -J "$input_file") || {
        echo "❌ mkvmerge -J failed on: $input_file"
        return 1
    }

    # 🎯 All audio tracks: id:lang
    local all_audio_info
    all_audio_info=$(echo "$json" | "$JQ" -r \
        '.tracks[] | select(.type=="audio") |
         "\(.id):\(.properties.language // "und")"')

    # 🎯 Tracks to keep: ALL eng/en/und (as you wanted)
    mapfile -t wanted_tracks < <(echo "$json" | "$JQ" -r \
        '.tracks[] | select(.type=="audio" and
          (.properties.language=="eng" or .properties.language=="en" or .properties.language=="und")) | .id')

    if [ ${#wanted_tracks[@]} -eq 0 ]; then
        echo "⏭️ Skipping (foreign-only): No matching English/und audio tracks."
        return 0
    fi

    # ✅ Compute tracks to remove using associative array
    declare -A keep_set_map=()
    for id in "${wanted_tracks[@]}"; do keep_set_map["$id"]=1; done

    local remove_info=()
    while IFS= read -r entry; do
        local id="${entry%%:*}"
        local lang="${entry#*:}"
        if [[ -z ${keep_set_map[$id]} ]]; then
            remove_info+=("$id:$lang")
        fi
    done <<< "$all_audio_info"

    # ✅ Log
    echo "🔊 Keeping audio track IDs: ${wanted_tracks[*]}"
    if [ ${#remove_info[@]} -gt 0 ]; then
        echo "🗑️ Removing audio tracks: ${remove_info[*]}"
    else
        echo "👌 No audio tracks to remove. Skipping rewrite."
        return 0
    fi

    # 📦 Build mkvmerge args CORRECTLY (single --audio-tracks with comma list)
    local output_file="${input_file%.mkv}.tmp.mkv"
    local audio_ids
    audio_ids=$(IFS=,; echo "${wanted_tracks[*]}")

    "$MKVMERGE" -o "$output_file" --audio-tracks "$audio_ids" "$input_file" || {
        echo "❌ Error processing file!"
        return 1
    }

    if [ -f "$output_file" ]; then
        mv -f "$output_file" "$input_file"
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
  echo "⚠️ Please provide a directory path as an argument."
  exit 1
fi

if [ ! -d "$dir" ]; then
  echo "❌ Directory doesn't exist: $dir"
  exit 1
fi

# 🔄 Process all MKV files in the directory
while IFS= read -r file; do
    process_file "$file"
done < <(find "$dir" -type f -name "*.mkv")
