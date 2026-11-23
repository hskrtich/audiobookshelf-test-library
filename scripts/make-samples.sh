#!/usr/bin/env bash
# Generates the "Tom Sawyer <format>" sample books under Library/Books/Mark Twain/
# from the public-domain LibriVox recording already in the repo, plus EPUB/PDF
# editions from Project Gutenberg.
#
# Requires: ffmpeg/ffprobe on PATH (libmp3lame, aac, libopus), curl.
# Optional: Microsoft Edge (for the PDF), exhale (for the xHE-AAC samples).
#
# Usage: scripts/make-samples.sh            # everything
#        scripts/make-samples.sh audio       # audio only
#        scripts/make-samples.sh ebooks      # EPUB + PDF only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUTHOR_DIR="$ROOT/Library/Books/Mark Twain"
SRC="$AUTHOR_DIR/Adventures Of Tom Sawyer/AdventuresOfTomSawyer-64kb-Part1.m4b"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

CLIP_LEN=40                                  # seconds per chapter clip
CLIP_STARTS=(0 1598.642 3563.422 5462.221)   # starts of source chapters 1, 3, 5, 7
CHAPTER_NAMES=("Chapter 1" "Chapter 3" "Chapter 5" "Chapter 7")

ff() { ffmpeg -hide_banner -loglevel error -y "$@"; }

# Sets the TAGS array for album/title $1.
tags() {
  TAGS=(-metadata "title=$1" -metadata "album=$1" -metadata "artist=Mark Twain"
        -metadata "album_artist=Mark Twain" -metadata "genre=Audiobook" -metadata "date=1876")
}

# Writes an ffmetadata file with one chapter per clip index given ($2...).
chapters_file() { # $1 = out file, $2.. = clip indices
  local out="$1"; shift
  local t=0
  echo ";FFMETADATA1" > "$out"
  for i in "$@"; do
    printf '[CHAPTER]\nTIMEBASE=1/1000\nSTART=%d\nEND=%d\ntitle=%s\n' \
      $((t * 1000)) $(((t + CLIP_LEN) * 1000)) "${CHAPTER_NAMES[$i]}" >> "$out"
    t=$((t + CLIP_LEN))
  done
}

# Concatenates clips ($2...) into one WAV ($1).
concat_clips() {
  local out="$1"; shift
  : > "$WORK/list.txt"
  for i in "$@"; do echo "file 'clip$i.wav'" >> "$WORK/list.txt"; done
  ff -f concat -safe 0 -i "$WORK/list.txt" -c copy "$out"
}

prepare_clips() {
  for i in "${!CLIP_STARTS[@]}"; do
    ff -ss "${CLIP_STARTS[$i]}" -t "$CLIP_LEN" -i "$SRC" -vn -ac 1 -ar 44100 "$WORK/clip$i.wav"
  done
  concat_clips "$WORK/all.wav" 0 1 2 3
  concat_clips "$WORK/partA.wav" 0 1
  concat_clips "$WORK/partB.wav" 2 3
  chapters_file "$WORK/ch_all.txt" 0 1 2 3
  chapters_file "$WORK/ch_partA.txt" 0 1
  chapters_file "$WORK/ch_partB.txt" 2 3
}

fresh_dir() { rm -rf "$AUTHOR_DIR/$1"; mkdir -p "$AUTHOR_DIR/$1"; echo "$AUTHOR_DIR/$1"; }

write_source() { # $1 = dir, $2 = description
  cat > "$1/SOURCE.txt" <<EOF
$2
Audio: LibriVox recording of "The Adventures of Tom Sawyer" by Mark Twain (public domain).
https://archive.org/details/LibrivoxM4bCollectionAudiobooks4
Clipped and re-encoded by scripts/make-samples.sh.
EOF
}

make_mp3() {
  local name="Tom Sawyer Single MP3" d
  d="$(fresh_dir "$name")"
  tags "$name"
  ff -i "$WORK/all.wav" -c:a libmp3lame -b:a 64k -id3v2_version 3 "${TAGS[@]}" \
     -metadata track=1/1 "$d/$name.mp3"
  write_source "$d" "Single MP3 file, CBR 64 kbps mono, ID3v2.3 tags, no chapters."

  name="Tom Sawyer Multi MP3"
  d="$(fresh_dir "$name")"
  for i in 0 1 2 3; do
    tags "$name"
    ff -i "$WORK/clip$i.wav" -c:a libmp3lame -b:a 64k -id3v2_version 3 "${TAGS[@]}" \
       -metadata "title=${CHAPTER_NAMES[$i]}" -metadata "track=$((i + 1))/4" \
       "$d/$(printf '%02d' $((i + 1))) - ${CHAPTER_NAMES[$i]}.mp3"
  done
  write_source "$d" "Four MP3 files (one per chapter), CBR 64 kbps mono, ID3v2.3 track numbers."
}

# $1 = folder name, $2 = extension, $3.. = encoder args
make_chaptered() {
  local name="$1" ext="$2" d; shift 2
  d="$(fresh_dir "$name")"
  tags "$name"
  ff -i "$WORK/all.wav" -i "$WORK/ch_all.txt" -map 0:a -map_metadata 1 -map_chapters 1 \
     "$@" "${TAGS[@]}" -metadata track=1/1 "$d/$name.$ext"
  echo "$d"
}

make_multi_chaptered() {
  local name="$1" ext="$2" d; shift 2
  d="$(fresh_dir "$name")"
  local n=1
  for p in partA partB; do
    tags "$name"
    ff -i "$WORK/$p.wav" -i "$WORK/ch_$p.txt" -map 0:a -map_metadata 1 -map_chapters 1 \
       "$@" "${TAGS[@]}" -metadata "track=$n/2" "$d/$name - Part $n.$ext"
    n=$((n + 1))
  done
  echo "$d"
}

make_aac() {
  local d
  d="$(make_chaptered "Tom Sawyer Single M4B AAC" m4b -c:a aac -b:a 64k)"
  write_source "$d" "Single M4B, AAC-LC 64 kbps mono, 4 embedded chapters."
  d="$(make_multi_chaptered "Tom Sawyer Multi M4B AAC" m4b -c:a aac -b:a 64k)"
  write_source "$d" "Two M4B parts, AAC-LC 64 kbps mono, 2 embedded chapters per part."
}

make_opus() {
  local d
  d="$(make_chaptered "Tom Sawyer Single Ogg Opus" ogg -c:a libopus -b:a 32k)"
  write_source "$d" "Single Ogg file, Opus 32 kbps mono, 4 chapters as CHAPTERxxx Vorbis comments."
  d="$(make_multi_chaptered "Tom Sawyer Multi Ogg Opus" ogg -c:a libopus -b:a 32k)"
  write_source "$d" "Two Ogg parts, Opus 32 kbps mono, 2 chapters per part as CHAPTERxxx Vorbis comments."
}

# xHE-AAC (USAC): ffmpeg can decode but not encode it, so encode with exhale
# (https://gitlab.com/ecodis/exhale), then remux into M4B with chapters using ffmpeg.
make_xhe() {
  if ! command -v exhale >/dev/null 2>&1; then
    echo "exhale not found on PATH; skipping xHE-AAC samples" >&2
    return
  fi
  local name d n
  exhale_m4b() { # $1 = wav, $2 = chapters, $3 = out, $4 = name, $5 = track
    ff -i "$1" -c:a pcm_s16le "$WORK/x.wav"
    # Preset 1 is exhale's lowest-bitrate VBR mode without eSBR. Run `exhale` with no arguments to see all presets.
    exhale 1 "$WORK/x.wav" "$WORK/x.m4a" >/dev/null
    tags "$4"
    ff -i "$WORK/x.m4a" -i "$2" -map 0:a -map_metadata 1 -map_chapters 1 -c copy \
       "${TAGS[@]}" -metadata "track=$5" "$3"
  }
  name="Tom Sawyer Single M4B xHE-AAC"; d="$(fresh_dir "$name")"
  exhale_m4b "$WORK/all.wav" "$WORK/ch_all.txt" "$d/$name.m4b" "$name" 1/1
  write_source "$d" "Single M4B, xHE-AAC (USAC) encoded with exhale, 4 embedded chapters."
  name="Tom Sawyer Multi M4B xHE-AAC"; d="$(fresh_dir "$name")"; n=1
  for p in partA partB; do
    exhale_m4b "$WORK/$p.wav" "$WORK/ch_$p.txt" "$d/$name - Part $n.m4b" "$name" "$n/2"
    n=$((n + 1))
  done
  write_source "$d" "Two M4B parts, xHE-AAC (USAC) encoded with exhale, 2 embedded chapters per part."
}

make_ebooks() {
  local d
  d="$(fresh_dir "Tom Sawyer EPUB")"
  curl -fsSL -o "$d/The Adventures of Tom Sawyer.epub" https://www.gutenberg.org/ebooks/74.epub3.images
  printf 'EPUB3 edition from Project Gutenberg (public domain in the USA).\nhttps://www.gutenberg.org/ebooks/74\n' > "$d/SOURCE.txt"

  local edge="/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
  if [ ! -x "$edge" ]; then echo "Edge not found; skipping PDF" >&2; return; fi
  d="$(fresh_dir "Tom Sawyer PDF")"
  local out; out="$(cygpath -w "$d/The Adventures of Tom Sawyer.pdf" 2>/dev/null || echo "$d/The Adventures of Tom Sawyer.pdf")"
  "$edge" --headless --disable-gpu --no-pdf-header-footer --print-to-pdf="$out" \
    https://www.gutenberg.org/cache/epub/74/pg74-images.html >/dev/null 2>&1
  printf 'PDF printed (Microsoft Edge, headless) from the Project Gutenberg HTML edition (public domain in the USA).\nhttps://www.gutenberg.org/ebooks/74\n' > "$d/SOURCE.txt"
}

what="${1:-all}"
if [ "$what" = all ] || [ "$what" = audio ]; then
  prepare_clips; make_mp3; make_aac; make_opus; make_xhe
fi
if [ "$what" = all ] || [ "$what" = ebooks ]; then
  make_ebooks
fi
echo "done"
