#!/usr/bin/env bash
# Regenerates every Derived Sample under Library/ from the Sources in Sources/.
# It never downloads media: everything it needs is committed under Sources/.
# The only network access is a one-off clone of the exhale encoder (see below).
#
# Requires: bash, ffmpeg + ffprobe (with libmp3lame, libopus and the native aac
# encoder). If `exhale` is not on PATH, it is cloned from
# https://gitlab.com/ecodis/exhale into tools/ (gitignored) and built there,
# which needs git, make and a C++ compiler.
#
# Usage: scripts/make-samples.sh            # every Derived Sample
#        scripts/make-samples.sh twain      # Tom Sawyer Required Formats only
#        scripts/make-samples.sh doyle      # A Study in Scarlet + Watson’s Casebook
#        scripts/make-samples.sh austen     # Pride and Prejudice
#
# Output is byte-for-byte reproducible on the same ffmpeg/exhale versions
# (bitexact muxing), so re-running it on a clean checkout leaves git clean.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOOKS="$ROOT/Library/Audiobooks"
PODCASTS="$ROOT/Library/Podcasts"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/make-samples.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

EXHALE_REPO="https://gitlab.com/ecodis/exhale.git"
EXHALE_TAG="v1.2.2"

CLIP_START=20   # seconds into each chapter, past the LibriVox intro
CLIP_LEN=40     # seconds per clip
RATE=44100      # every Sample is mono at this sample rate

TWAIN_SRC="$ROOT/Sources/Mark Twain - The Adventures of Tom Sawyer"
TWAIN_EBOOKS="$ROOT/Sources/Mark Twain - The Adventures of Tom Sawyer (ebooks)"
DOYLE_SRC="$ROOT/Sources/Arthur Conan Doyle - A Study in Scarlet"
AUSTEN_SRC="$ROOT/Sources/Jane Austen - Pride and Prejudice"
COVER_SRC="$ROOT/Sources/Hugh Thomson - Pride and Prejudice illustrations"

PDM="Public Domain Mark 1.0"
PDM_URL="https://creativecommons.org/publicdomain/mark/1.0/"

# Deterministic output: no random Ogg serials, no encoder-version tags.
ff() { ffmpeg -hide_banner -loglevel error -nostdin -y "$@"; }
BITEXACT=(-fflags +bitexact -flags:a +bitexact)

# --- helpers -----------------------------------------------------------------

rel() { echo "${1#"$ROOT"/}"; }

fresh_dir() { rm -rf "$1"; mkdir -p "$1"; }

# Path of chapter $2 (1-based) of Source dir $1.
chapter_file() {
  local f
  for f in "$1"/*_"$(printf '%02d' "$2")"_*.mp3; do echo "$f"; return; done
}

# Chapter title from the Source file's own tag, with the "NN - " prefix removed.
chapter_title() {
  ffprobe -v quiet -show_entries format_tags=title -of default=nw=1:nk=1 "$1" |
    sed -E 's/^[0-9]+ *- *//'
}

# Decodes clip $3 (1-based chapter) of Source $1 to $2 as mono PCM WAV.
clip_wav() {
  ff -ss "$CLIP_START" -t "$CLIP_LEN" -i "$(chapter_file "$1" "$3")" -vn -map_metadata -1 \
     -ac 1 -ar "$RATE" -c:a pcm_s16le "$2"
}

# Decodes a whole chapter $3 of Source $1 to $2.
chapter_wav() {
  ff -i "$(chapter_file "$1" "$3")" -vn -map_metadata -1 -ac 1 -ar "$RATE" -c:a pcm_s16le "$2"
}

wav_ms() { # duration of a WAV in whole milliseconds
  ffprobe -v quiet -show_entries format=duration -of default=nw=1:nk=1 "$1" |
    awk '{ printf "%d", $1 * 1000 + 0.5 }'
}

# concat_wavs OUT.wav IN.wav... ; also writes OUT.wav.ffmeta with one chapter
# per input, titled from the matching entry in the TITLES array.
concat_wavs() {
  local out="$1"; shift
  local list="$out.list" meta="$out.ffmeta" t=0 d i=0 f
  : > "$list"
  echo ";FFMETADATA1" > "$meta"
  for f in "$@"; do
    printf "file '%s'\n" "$f" >> "$list"
    d="$(wav_ms "$f")"
    printf '[CHAPTER]\nTIMEBASE=1/1000\nSTART=%d\nEND=%d\ntitle=%s\n' \
      "$t" $((t + d)) "${TITLES[$i]}" >> "$meta"
    t=$((t + d)); i=$((i + 1))
  done
  ff -f concat -safe 0 -i "$list" -c copy "$out"
}

# write_source DIR TITLE CREATOR LICENCE LICENCE_URL SOURCE_URL DERIVED_FROM CASES
write_source() {
  cat > "$1/SOURCE.txt" <<EOF
Title: $2
Author/Creator: $3
Licence: $4
Licence URL: $5
Source URL: $6
Derived from: $7
Cases: $8
EOF
}

# --- exhale (xHE-AAC) --------------------------------------------------------

EXHALE=""
find_exhale() {
  [ -n "$EXHALE" ] && return
  if command -v exhale >/dev/null 2>&1; then EXHALE="$(command -v exhale)"; return; fi
  local dir="$ROOT/tools/exhale"
  if [ ! -x "$dir/bin/exhale" ]; then
    echo "exhale not on PATH; building $EXHALE_TAG in tools/exhale" >&2
    rm -rf "$dir"; mkdir -p "$ROOT/tools"
    git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$EXHALE_TAG" "$EXHALE_REPO" "$dir"
    local jobs; jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
    make -C "$dir" -j"$jobs" release >"$dir/build.log" 2>&1 ||
      { echo "exhale build failed; see tools/exhale/build.log" >&2; exit 1; }
  fi
  EXHALE="$dir/bin/exhale"
}

# exhale_m4b IN.wav OUT.m4b TRACK : encodes with exhale, then remuxes into M4B
# with the chapters from IN.wav.ffmeta and the tags in the TAGS array.
exhale_m4b() {
  find_exhale
  # Preset 1: xHE-AAC (USAC) without eSBR, about 64 kbit/s stereo / 32 kbit/s
  # mono. exhale wants 32 kHz or less for this preset, and won't overwrite.
  rm -f "$WORK/xhe.wav" "$WORK/xhe.m4a"
  ff -i "$1" -ar 32000 -c:a pcm_s16le "$WORK/xhe.wav"
  "$EXHALE" 1 "$WORK/xhe.wav" "$WORK/xhe.m4a" >/dev/null
  ff -i "$WORK/xhe.m4a" -i "$1.ffmeta" -map 0:a -map_metadata 1 -map_chapters 1 \
     -c copy "${TAGS[@]}" -metadata "track=$3" "${BITEXACT[@]}" "$2"
}

# --- Tom Sawyer Required Formats (Library/Audiobooks/Mark Twain/) -----------------

twain_tags() { # $1 = Sample folder name, used as album/title
  TAGS=(-metadata "title=$1" -metadata "album=$1" -metadata "artist=Mark Twain"
        -metadata "album_artist=Mark Twain" -metadata "composer=LibriVox Volunteers"
        -metadata "genre=Audiobook" -metadata "date=1876")
}

twain_source() { # $1 = dir, $2 = cases
  write_source "$1" "The Adventures of Tom Sawyer" \
    "Mark Twain; read by LibriVox volunteers" "$PDM" "$PDM_URL" \
    "https://archive.org/details/adventures_tom_sawyer_3_1903_librivox" \
    "$(rel "$TWAIN_SRC")" "$2"
}

make_twain() {
  local author="$BOOKS/Mark Twain" w="$WORK/twain" i d name
  mkdir -p "$w"
  for i in 1 2 3 4; do clip_wav "$TWAIN_SRC" "$w/clip$i.wav" "$i"; done
  TITLES=("Chapter 1" "Chapter 2" "Chapter 3" "Chapter 4")
  concat_wavs "$w/all.wav" "$w"/clip{1,2,3,4}.wav
  concat_wavs "$w/part1.wav" "$w/clip1.wav" "$w/clip2.wav"
  TITLES=("Chapter 3" "Chapter 4")
  concat_wavs "$w/part2.wav" "$w/clip3.wav" "$w/clip4.wav"
  local clipcases="Four ${CLIP_LEN} s clips, from ${CLIP_START} s into chapters 1-4, mono ${RATE} Hz."

  # Single MP3
  name="Tom Sawyer Single MP3"; d="$author/$name"; fresh_dir "$d"; twain_tags "$name"
  ff -i "$w/all.wav" -c:a libmp3lame -b:a 64k -id3v2_version 3 \
     "${TAGS[@]}" -metadata track=1/1 "${BITEXACT[@]}" "$d/$name.mp3"
  twain_source "$d" "Single MP3 file; CBR 64 kbit/s (LAME Info header); ID3v2.3 tags; no chapters. $clipcases"

  # Multi MP3
  name="Tom Sawyer Multi MP3"; d="$author/$name"; fresh_dir "$d"
  for i in 1 2 3 4; do
    twain_tags "$name"
    ff -i "$w/clip$i.wav" -c:a libmp3lame -b:a 64k -id3v2_version 3 \
       "${TAGS[@]}" -metadata "title=Chapter $i" -metadata "track=$i/4" \
       "${BITEXACT[@]}" "$d/0$i - Chapter $i.mp3"
  done
  twain_source "$d" "Multi-file MP3 book, one file per clip; CBR 64 kbit/s; ID3v2.3 tags with track numbers 1/4-4/4; no chapters. $clipcases"

  # Single / Multi M4B AAC
  name="Tom Sawyer Single M4B AAC"; d="$author/$name"; fresh_dir "$d"; twain_tags "$name"
  ff -i "$w/all.wav" -i "$w/all.wav.ffmeta" -map 0:a -map_metadata 1 -map_chapters 1 \
     -c:a aac -b:a 64k "${TAGS[@]}" -metadata track=1/1 "${BITEXACT[@]}" "$d/$name.m4b"
  twain_source "$d" "Single M4B; AAC-LC 64 kbit/s mono; MP4 tags; 4 embedded chapters (Chapter 1-4). $clipcases"

  name="Tom Sawyer Multi M4B AAC"; d="$author/$name"; fresh_dir "$d"
  for i in 1 2; do
    twain_tags "$name"
    ff -i "$w/part$i.wav" -i "$w/part$i.wav.ffmeta" -map 0:a -map_metadata 1 -map_chapters 1 \
       -c:a aac -b:a 64k "${TAGS[@]}" -metadata "track=$i/2" "${BITEXACT[@]}" \
       "$d/$name - Part $i.m4b"
  done
  twain_source "$d" "Multi-file M4B book in 2 parts; AAC-LC 64 kbit/s mono; MP4 track numbers 1/2 and 2/2; 2 embedded chapters per part (Chapter 1-2, Chapter 3-4). $clipcases"

  # Single / Multi M4B xHE-AAC (exhale)
  name="Tom Sawyer Single M4B xHE-AAC"; d="$author/$name"; fresh_dir "$d"; twain_tags "$name"
  exhale_m4b "$w/all.wav" "$d/$name.m4b" 1/1
  twain_source "$d" "Single M4B; xHE-AAC (MPEG-D USAC) encoded by exhale $EXHALE_TAG preset 1 (VBR, no eSBR, 32 kHz), remuxed by ffmpeg; 4 embedded chapters (Chapter 1-4). $clipcases"

  name="Tom Sawyer Multi M4B xHE-AAC"; d="$author/$name"; fresh_dir "$d"
  for i in 1 2; do
    twain_tags "$name"
    exhale_m4b "$w/part$i.wav" "$d/$name - Part $i.m4b" "$i/2"
  done
  twain_source "$d" "Multi-file M4B book in 2 parts; xHE-AAC (MPEG-D USAC) encoded by exhale $EXHALE_TAG preset 1 (VBR, no eSBR); track numbers 1/2 and 2/2; 2 embedded chapters per part. $clipcases"

  # Single / Multi Ogg Opus
  name="Tom Sawyer Single Ogg Opus"; d="$author/$name"; fresh_dir "$d"; twain_tags "$name"
  ff -i "$w/all.wav" -i "$w/all.wav.ffmeta" -map 0:a -map_metadata 1 -map_chapters 1 \
     -c:a libopus -b:a 32k "${TAGS[@]}" -metadata track=1/1 "${BITEXACT[@]}" "$d/$name.opus"
  twain_source "$d" "Single Ogg Opus file (.opus); Opus 32 kbit/s VBR mono; Vorbis comment tags; 4 chapters as CHAPTER000-CHAPTER003 Vorbis comments. $clipcases"

  name="Tom Sawyer Multi Ogg Opus"; d="$author/$name"; fresh_dir "$d"
  for i in 1 2; do
    twain_tags "$name"
    ff -i "$w/part$i.wav" -i "$w/part$i.wav.ffmeta" -map 0:a -map_metadata 1 -map_chapters 1 \
       -c:a libopus -b:a 32k "${TAGS[@]}" -metadata "track=$i/2" "${BITEXACT[@]}" \
       "$d/$name - Part $i.opus"
  done
  twain_source "$d" "Multi-file Ogg Opus book in 2 parts; Opus 32 kbit/s VBR mono; TRACKNUMBER 1/2 and 2/2; 2 chapters per part as CHAPTERxxx Vorbis comments. $clipcases"

  # Full-length M4B: whole chapters 1-5, not clips.
  name="Tom Sawyer Full Length M4B AAC"; d="$author/$name"; fresh_dir "$d"; twain_tags "$name"
  TITLES=()
  for i in 1 2 3 4 5; do
    chapter_wav "$TWAIN_SRC" "$w/full$i.wav" "$i"
    TITLES+=("$(chapter_title "$(chapter_file "$TWAIN_SRC" "$i")")")
  done
  concat_wavs "$w/full.wav" "$w"/full{1,2,3,4,5}.wav
  ff -i "$w/full.wav" -i "$w/full.wav.ffmeta" -map 0:a -map_metadata 1 -map_chapters 1 \
     -c:a aac -b:a 64k "${TAGS[@]}" -metadata track=1/1 "${BITEXACT[@]}" "$d/$name.m4b"
  twain_source "$d" "Full-length single M4B for long-duration seeking and large-file scanning: all of Source chapters 1-5 in full (about 76 min); AAC-LC 64 kbit/s mono; 5 embedded chapters named Chapter 1-5."

  # Ebooks, copied unmodified from the ebooks Source.
  name="Tom Sawyer EPUB"; d="$author/$name"; fresh_dir "$d"
  cp "$TWAIN_EBOOKS/The Adventures of Tom Sawyer.epub" "$d/"
  write_source "$d" "The Adventures of Tom Sawyer" "Mark Twain; Project Gutenberg" \
    "Public domain in the USA" "https://www.gutenberg.org/policy/license.html" \
    "https://www.gutenberg.org/ebooks/74" "$(rel "$TWAIN_EBOOKS")" \
    "EPUB-only book (no audio); Project Gutenberg EPUB3 with images, copied unmodified."

  name="Tom Sawyer PDF"; d="$author/$name"; fresh_dir "$d"
  cp "$TWAIN_EBOOKS/The Adventures of Tom Sawyer.pdf" "$d/"
  write_source "$d" "The Adventures of Tom Sawyer" "Mark Twain; scan by UCLA Library via the Internet Archive" \
    "Public domain (1876; marked NOT_IN_COPYRIGHT by the Internet Archive)" \
    "https://creativecommons.org/publicdomain/mark/1.0/" \
    "https://archive.org/details/adventuresoftoms00twaiiala" "$(rel "$TWAIN_EBOOKS")" \
    "PDF-only book (no audio); scanned 1876 first edition with an OCR text layer, copied unmodified."
}

# --- A Study in Scarlet (Library/Audiobooks/Arthur Conan Doyle/) ------------------

doyle_source_args() {
  DOYLE_ARGS=("Arthur Conan Doyle; read by Ashleighjane for LibriVox" "$PDM" "$PDM_URL"
              "https://archive.org/details/study_scarlet_1203_librivox" "$(rel "$DOYLE_SRC")")
}

make_doyle() {
  local w="$WORK/doyle" i d t
  mkdir -p "$w"; doyle_source_args
  for i in 1 2 3 4 5; do clip_wav "$DOYLE_SRC" "$w/clip$i.wav" "$i"; done

  d="$BOOKS/Arthur Conan Doyle/Sherlock Holmes/Book 1 - A Study in Scarlet"; fresh_dir "$d"
  for i in 1 2 3 4 5; do
    t="$(chapter_title "$(chapter_file "$DOYLE_SRC" "$i")")"
    ff -i "$w/clip$i.wav" -c:a libmp3lame -q:a 6 -id3v2_version 4 \
       -metadata "title=$t" -metadata "album=A Study in Scarlet" \
       -metadata "artist=Arthur Conan Doyle" -metadata "album_artist=Arthur Conan Doyle" \
       -metadata "composer=Ashleighjane" -metadata "genre=Audiobook" -metadata "date=1887" \
       -metadata "track=$i/5" "${BITEXACT[@]}" "$d/0$i - $t.mp3"
  done
  write_source "$d" "A Study in Scarlet" "${DOYLE_ARGS[@]}" \
    "Series folder (Sherlock Holmes) and 'Book N -' sequence token in the folder name; multi-file MP3 book of 5 files; LAME VBR (-q:a 6, Xing header); ID3v2.4 tags with track numbers 1/5-5/5 and chapter titles; no chapters. Five ${CLIP_LEN} s clips from ${CLIP_START} s into chapters 1-5, mono ${RATE} Hz."

  # Watson’s Casebook: a podcast made of clips from chapters 1-3.
  d="$PODCASTS/Watson’s Casebook"; fresh_dir "$d"
  local dates=("2024-01-01" "2024-01-08" "2024-01-15")
  for i in 1 2 3; do
    t="$(chapter_title "$(chapter_file "$DOYLE_SRC" "$i")")"
    ff -i "$w/clip$i.wav" -c:a aac -b:a 64k \
       -metadata "title=Episode $i: $t" -metadata "album=Watson’s Casebook" \
       -metadata "show=Watson’s Casebook" -metadata "artist=Watson’s Casebook" \
       -metadata "album_artist=Watson’s Casebook" -metadata "genre=Podcast" \
       -metadata "date=${dates[$((i - 1))]}" -metadata "track=$i" \
       -metadata "episode_sort=$i" -metadata "episode_id=S01E0$i" -metadata "season_number=1" \
       -metadata "media_type=21" \
       -metadata "description=Watson’s Casebook episode $i: an excerpt from A Study in Scarlet." \
       -metadata "comment=Read by Ashleighjane for LibriVox." \
       "${BITEXACT[@]}" "$d/Episode $i - $t.m4a"
  done
  write_source "$d" "Watson’s Casebook (podcast made from A Study in Scarlet)" "${DOYLE_ARGS[@]}" \
    "Podcast folder name with a curly apostrophe (U+2019); 3 M4A episodes, AAC-LC 64 kbit/s mono; podcast-style MP4 tags: genre Podcast, stik 21 (podcast), show, track 1-3, episode_sort 1-3, episode_id S01E01-S01E03, season 1, release dates 2024-01-01 / 2024-01-08 / 2024-01-15; no chapters; no RSS feed. Three ${CLIP_LEN} s clips from ${CLIP_START} s into chapters 1-3."

  make_doyle_subtitle
}

# 'Title - Subtitle' folder token. The MP3 has no title or album tag: those
# would override the folder name in audiobookshelf's audioMetatags step.
make_doyle_subtitle() {
  local w="$WORK/doyle-subtitle" i d
  mkdir -p "$w"; doyle_source_args
  for i in 1 2; do clip_wav "$DOYLE_SRC" "$w/clip$i.wav" "$i"; done
  TITLES=("Chapter 1" "Chapter 2")
  concat_wavs "$w/all.wav" "$w/clip1.wav" "$w/clip2.wav"

  d="$BOOKS/Arthur Conan Doyle/A Study in Scarlet - The Reminiscences of John H. Watson"; fresh_dir "$d"
  ff -i "$w/all.wav" -map_metadata -1 -c:a libmp3lame -b:a 64k -id3v2_version 3 \
     -metadata "artist=Arthur Conan Doyle" -metadata "genre=Audiobook" \
     "${BITEXACT[@]}" "$d/A Study in Scarlet.mp3"
  write_source "$d" "A Study in Scarlet" "${DOYLE_ARGS[@]}" \
    "'Title - Subtitle' token in the folder name, no series folder. audiobookshelf splits it at the first ' - ' only when the server setting Settings > Scanner > 'Parse subtitles' (scannerParseSubtitle, off by default) is on. Expected with it off: title 'A Study in Scarlet - The Reminiscences of John H. Watson', no subtitle. Expected with it on: title 'A Study in Scarlet', subtitle 'The Reminiscences of John H. Watson'. The MP3 has no title, album or subtitle tag, because audio tags override the folder name; only artist and genre are tagged. Deliberate clash: with Parse subtitles on, this book has the same author and title as 'Sherlock Holmes/Book 1 - A Study in Scarlet', so the two must stay separate library items (one in a series, one not), not be merged or deduplicated. Single MP3, CBR 64 kbit/s, ID3v2.3; no chapters. Two ${CLIP_LEN} s clips from ${CLIP_START} s into chapters 1-2, mono ${RATE} Hz, concatenated."
}

# --- Pride and Prejudice (Library/Audiobooks/Jane Austen/) ------------------------

make_austen() {
  local w="$WORK/austen" i d
  mkdir -p "$w"
  for i in 1 2 3 4; do clip_wav "$AUSTEN_SRC" "$w/clip$i.wav" "$i"; done
  TITLES=("Chapter 1" "Chapter 2" "Chapter 3" "Chapter 4")
  concat_wavs "$w/all.wav" "$w"/clip{1,2,3,4}.wav

  # Embedded cover and cover.jpg are two different Hugh Thomson illustrations,
  # so a viewer can tell which one audiobookshelf picked.
  ff -i "$COVER_SRC/Thomson-PP01.jpg" -vf scale=600:-2 -q:v 3 "${BITEXACT[@]}" "$w/embedded.jpg"

  d="$BOOKS/Jane Austen/1813 - Pride and Prejudice {Karen Savage}"; fresh_dir "$d"
  ff -i "$w/all.wav" -i "$w/embedded.jpg" -map 0:a -map 1:v -c:a aac -b:a 64k -c:v copy \
     -disposition:v:0 attached_pic \
     -metadata "title=Pride and Prejudice" -metadata "album=Pride and Prejudice" \
     -metadata "artist=Jane Austen" -metadata "album_artist=Jane Austen" \
     -metadata "composer=Karen Savage (embedded tag)" -metadata "genre=Audiobook" \
     -metadata "date=1813" \
     -metadata "description=EMBEDDED TAG description: four clips from the LibriVox recording." \
     -metadata "comment=EMBEDDED TAG comment." \
     "${BITEXACT[@]}" "$d/Pride and Prejudice.m4a"
  ff -i "$COVER_SRC/Houghton Typ 805.94.8320 - superior dancing.jpg" -vf scale=600:-2 -q:v 3 \
     "${BITEXACT[@]}" "$d/cover.jpg"
  printf 'DESC.TXT description: this text comes from the desc.txt sidecar, not the embedded tags.\n' > "$d/desc.txt"
  printf 'Karen Savage (reader.txt)\n' > "$d/reader.txt"

  write_source "$d" "Pride and Prejudice" \
    "Jane Austen; read by Karen Savage for LibriVox; cover illustrations by Hugh Thomson (1894)" \
    "Public Domain (audio); public domain, PD-old (illustrations)" \
    "http://creativecommons.org/licenses/publicdomain/" \
    "https://archive.org/details/pride_prejudice_krs_librivox ; embedded cover https://commons.wikimedia.org/wiki/File:Thomson-PP01.jpg ; cover.jpg https://commons.wikimedia.org/wiki/File:Houghton_Typ_805.94.8320_-_Pride_and_Prejudice,_1894,_Hugh_Thomson_-_superior_dancing.jpg" \
    "$(rel "$AUSTEN_SRC") and $(rel "$COVER_SRC")" \
    "Year token (1813 -) and narrator token ({Karen Savage}) in the folder name; single M4A (not M4B), AAC-LC 64 kbit/s mono, no chapters; embedded cover vs. cover.jpg (different images: embedded is 'Reading Jane's letters', cover.jpg is 'Such very superior dancing'); desc.txt vs. embedded description, and reader.txt (Karen Savage (reader.txt)) vs. embedded composer (Karen Savage (embedded tag)), deliberately different to test which source wins. Four ${CLIP_LEN} s clips from ${CLIP_START} s into chapters 1-4, mono ${RATE} Hz, concatenated."
}

what="${1:-all}"
case "$what" in
  all)    make_twain; make_doyle; make_austen ;;
  twain)  make_twain ;;
  doyle)  make_doyle ;;
  austen) make_austen ;;
  *) echo "usage: $0 [all|twain|doyle|austen]" >&2; exit 2 ;;
esac
echo "done"
