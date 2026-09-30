#!/bin/sh
# Copies ClanGen's music, ambience and sound effects into KittyClan/Resources/Audio as AAC.
# Usage: tools/add_audio.sh /path/to/clangen
set -eu
CLANGEN="${1:?usage: tools/add_audio.sh /path/to/clangen}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/KittyClan/Resources/Audio"
for kind in music ambiance sounds; do
    mkdir -p "$OUT/$kind"
    case $kind in music) rate=160000 ;; ambiance) rate=96000 ;; *) rate=128000 ;; esac
    find "$CLANGEN/resources/audio/$kind" -type f \( -name '*.mp3' -o -name '*.wav' -o -name '*.ogg' \) | while read -r src; do
        rel="${src#"$CLANGEN/resources/audio/$kind/"}"
        dest="$OUT/$kind/${rel%.*}.m4a"
        mkdir -p "$(dirname "$dest")"
        [ -f "$dest" ] || afconvert -f m4af -d aac -b "$rate" "$src" "$dest"
    done
done
du -sh "$OUT"/music "$OUT"/ambiance "$OUT"/sounds
