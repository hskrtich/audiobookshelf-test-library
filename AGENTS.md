# AGENTS.md

This file gives coding agents guidance for working in this repository.

## Purpose

A library of **royalty-free / public-domain** media used for basic tests of [audiobookshelf](https://github.com/advplyr/audiobookshelf). There is no code to build, lint, or test here. The repository's value is its *variety*: each item exists to exercise a specific encoding, container, or library-layout case in the audiobookshelf scanner and player.

## Layout

`Library/` is meant to be mounted directly as audiobookshelf library folders:

- `Library/Books/` → a "Books" library
- `Library/Podcasts/` → a "Podcasts" library

The folder structure *is* test data. audiobookshelf derives metadata from paths, so keep its conventions intact:

- Books: `Books/<Author>/[<Series>/]<Title>/<audio files>`. One folder = one book. Multiple audio files in a folder become one multi-track book, ordered by filename/track number.
- Optional folder-name tokens audiobookshelf parses: `Book 1 - Title`, `1999 - Title`, `Title - Subtitle`, `Title {Narrator}`. Multi-disc books use `CD1`/`Disc 1` subfolders inside the title folder.
- Optional sidecar files in a book folder: `cover.jpg`/`cover.png`, `desc.txt`, `reader.txt`, `metadata.opf`, `metadata.json`/`metadata.abs`.
- Podcasts: `Podcasts/<Show>/<episode files>`.

The current title folder names describe the case being tested (e.g. `The Body In The Library Single MP3`, `Example Narration Multipart MP3`). Follow that pattern: name the folder after the configuration it covers, not just the title. Because the name is parsed by the scanner, check that a descriptive suffix doesn't change the parsed title in a way that breaks a test.

## Required formats

The README's "Required formats" table lists the formats that must always be present, with each one's status. [scripts/make-samples.sh](scripts/make-samples.sh) creates the `Tom Sawyer <format>` books in `Library/Books/Mark Twain/` from the public-domain LibriVox M4B already in the repo, plus Gutenberg EPUB/PDF. Change formats through that script rather than by hand, and update the README table to match.

## Adding test files

- **Licensing first.** Only add media that is public domain or explicitly licensed for redistribution (LibriVox, Internet Archive public-domain collections, CC0/CC-BY recordings, or audio generated for this repo). Record the source URL in a text file next to the media. Existing examples are the `New Text Document.txt` files under `Books/Joshua Kane/` and `Books/Mark Twain/`. Prefer naming new ones `SOURCE.txt`.
- **Each addition should cover a new case.** Cases worth covering: codecs/containers (MP3 CBR/VBR, M4B/M4A AAC, Opus, OGG Vorbis, FLAC, WMA, WAV), single-file vs. multi-file vs. multi-disc, embedded chapters vs. none, embedded cover vs. `cover.jpg`, ID3v1/ID3v2.3/ID3v2.4/MP4 tags vs. untagged, series/narrator/year folder tokens, ebooks (EPUB/PDF) alongside or instead of audio, Unicode and punctuation in paths (e.g. the curly apostrophe in `Conan O’Brien Needs A Friend`), and podcasts with an RSS-style episode set.
- **Keep files small.** A short clip proves an encoding case as well as a full book does. Use full-length files only when length itself is what's being tested (long-duration seeking, large-file scanning).

## Git / GitHub

The repo is not yet a git repository or published to GitHub.

- GitHub rejects files over 100 MB, and `AdventuresOfTomSawyer-64kb-Part1.m4b` is about 105 MB. Media should be tracked with Git LFS:
  ```sh
  git init
  git lfs install
  git lfs track "*.mp3" "*.m4b" "*.m4a" "*.flac" "*.ogg" "*.opus" "*.wav" "*.wma" "*.epub" "*.pdf"
  git add .gitattributes
  ```
- Paths contain spaces and non-ASCII characters. On Windows, set `git config core.quotepath false` so `git status` shows the real names, and don't "fix" the names. They are intentional test cases.

## Inspecting media

`ffprobe` (from ffmpeg) is the standard way to check what a file actually contains (codec, bitrate, chapters, tags):

```sh
ffprobe -hide_banner -show_format -show_streams -show_chapters "path/to/file.m4b"
```

ffmpeg is not installed on the current dev machine. Install it (e.g. `winget install Gyan.FFmpeg`) before generating or verifying encodings.

## Agent skills

### Issue tracker

Issues are tracked in this repo's GitHub Issues (hskrtich/audiobookshelf-test-library) via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
