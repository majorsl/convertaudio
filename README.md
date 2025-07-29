# convertaudio
 A script that will keep only eng/und audio tracks from MKV files (und are often default eng tracks from poor encodes). Call the script with a trailing directory path and it will process the items in that location.

*Process*
When processing files, the changes are written to a temp file. Upon success, the original file is removed and replaced with the updated version.

*Requirements*

1. ffmpeg
2. jq
