# audiobookshelf Test Library

A collection of public-domain and freely licensed media for testing [audiobookshelf](https://github.com/advplyr/audiobookshelf). It's a ready-made library covering a wide range of audio encodings, containers, tags and folder layouts. Use it to check the scanner, metadata parsing, chapters and playback without needing your own collection.

## Getting the files

```sh
git clone https://github.com/hskrtich/audiobookshelf-test-library.git
```

Everything is plain git, with no Git LFS. No file is over 40 MB (see [ADR 0001](docs/adr/0001-trimmed-sources-committed-without-lfs.md)).

## Using it with audiobookshelf

Point audiobookshelf library folders at the two directories under `Library/`:

| Folder | Library type |
| --- | --- |
| `Library/Audiobooks` | Books |
| `Library/Podcasts` | Podcasts |

With Docker, mount them read-only so test runs can't change the files:

```sh
docker run -d -p 13378:80 \
  -v "$(pwd)/Library/Audiobooks:/audiobooks:ro" \
  -v "$(pwd)/Library/Podcasts:/podcasts:ro" \
  -v abs-config:/config \
  -v abs-metadata:/metadata \
  ghcr.io/advplyr/audiobookshelf
```

Then open http://localhost:13378, create the libraries, and run a scan. Don't point a library at `Sources/`. That folder holds the raw material the samples are made from, not test items.

## Required formats

The library must always include at least one book in each of these formats. They are all in `Library/Audiobooks/Mark Twain/`, generated from the *Tom Sawyer* Source. Apart from the full-length book and the ebooks, each one is made of four 40-second clips.

| Format | Path |
| --- | --- |
| Single MP3, CBR 64k, ID3v2.3 | `Tom Sawyer Single MP3` |
| Multiple MP3s, ID3v2.3 track numbers | `Tom Sawyer Multi MP3` |
| Single M4B, AAC-LC, 4 chapters | `Tom Sawyer Single M4B AAC` |
| Multiple M4Bs, AAC-LC, 2 chapters each | `Tom Sawyer Multi M4B AAC` |
| Single M4B, xHE-AAC, 4 chapters | `Tom Sawyer Single M4B xHE-AAC` |
| Multiple M4Bs, xHE-AAC, 2 chapters each | `Tom Sawyer Multi M4B xHE-AAC` |
| Single Ogg Opus, 4 chapters | `Tom Sawyer Single Ogg Opus` |
| Multiple Ogg Opus files, 2 chapters each | `Tom Sawyer Multi Ogg Opus` |
| Full-length single M4B, AAC-LC, 5 chapters, about 76 min | `Tom Sawyer Full Length M4B AAC` |
| EPUB only | `Tom Sawyer EPUB` |
| PDF only (1876 scan with a text layer) | `Tom Sawyer PDF` |

## Other cases

| Path | What it tests |
| --- | --- |
| `Audiobooks/Arthur Conan Doyle/Sherlock Holmes/Book 1 - A Study in Scarlet` | Series folder and `Book N -` token; 5 MP3 files; LAME VBR; ID3v2.4 |
| `Audiobooks/Arthur Conan Doyle/A Study in Scarlet - The Reminiscences of John H. Watson` | `Title - Subtitle` token, split only when the "Parse subtitles" scanner setting is on; untagged title so the folder name wins; same author and title as `Book 1 - A Study in Scarlet` on purpose |
| `Audiobooks/Mark Twain/Tom Sawyer Audio ID3v1 Only` | ID3v1.1 tags only: a 128-byte `TAG` trailer and no ID3v2 header |
| `Audiobooks/Arthur Conan Doyle/A Study in Scarlet Single MP3 ID3 Chapters` | A book (not a podcast) as a single MP3 with 4 named ID3v2.3 chapters (CTOC/CHAP) |
| `Audiobooks/Jane Austen/1813 - Pride and Prejudice {Karen Savage}` | Year and narrator tokens; single M4A (not M4B); embedded cover vs. a *different* `cover.jpg`; `desc.txt` and `reader.txt` that disagree with the embedded tags |
| `Audiobooks/Mark Twain/Tom Sawyer Audio With EPUB` | EPUB in the same folder as audio: 4 MP3 files plus an attached EPUB in one book item |
| `Audiobooks/Mark Twain/Tom Sawyer Audio With PDF` | PDF in the same folder as audio: 4 MP3 files plus an attached PDF in one book item |
| `Audiobooks/Jane Austen/Pride and Prejudice Single FLAC` | Single FLAC file; Vorbis comment tags |
| `Audiobooks/Jane Austen/Pride and Prejudice Single WAV` | Single WAV file, PCM 16-bit; tags only in a RIFF LIST/INFO chunk |
| `Audiobooks/Jane Austen/Pride and Prejudice Single WMA` | Single WMA (wmav2) file in ASF; ASF tags |
| `Podcasts/Watson’s Casebook` | Curly apostrophe (U+2019) in the folder name; M4A episodes with podcast MP4 tags (season, episode, release date) |
| `Podcasts/Hacker Public Radio` | One show with mixed codecs (Opus, Ogg Vorbis, MP3); ID3v2.4 + ID3v1; a 192 kHz Vorbis file |
| `Podcasts/Forschergeist` | Embedded chapters and cover in both MP3 (ID3 CHAP/CTOC, UTF-16 ID3v2.3) and Opus (CHAPTERxxx comments) |
| `Podcasts/Libre à vous !` | Non-ASCII and punctuation in the folder name and episode titles; embedded cover |
| `Podcasts/Free as in Freedom` | Completely untagged MP3 and Ogg files from a show that has ended |

Every folder's `SOURCE.txt` lists exactly which cases it covers, along with its licence and origin.

### Wanted

These cases aren't covered yet. Contributions are welcome:

- **Layouts:** multi-disc (`CD1/`, `Disc 1/`)
- **Metadata:** `metadata.opf`, `metadata.json`

## Regenerating the samples

Most book samples, and `Watson’s Casebook`, are *derived* from the Sources in `Sources/` by [`scripts/make-samples.sh`](scripts/make-samples.sh). Their outputs are committed, so you only need to run the script if you change it. It runs on Linux and macOS and needs:

- `ffmpeg` and `ffprobe`, with libmp3lame, libopus and the native AAC encoder
- `git`, `make` and a C++ compiler. If [exhale](https://gitlab.com/ecodis/exhale), the xHE-AAC encoder, isn't on `PATH`, the script clones and builds it into `tools/`. ffmpeg can't encode xHE-AAC.

```sh
sudo apt install ffmpeg git make g++        # Debian/Ubuntu
brew install ffmpeg                         # macOS (plus Xcode command-line tools)

scripts/make-samples.sh                     # everything
scripts/make-samples.sh twain               # or: doyle, austen, id3
```

The output is byte-for-byte reproducible on the same ffmpeg and exhale versions. The other podcasts are *verbatim*: the episodes are exactly as their shows published them.

## Contributing

1. **Only add media you can legally redistribute:** public domain, CC0, CC-BY, CC-BY-SA, or their non-commercial (NC) variants. No-derivatives (ND) material is allowed only if added unmodified. Check the licence against a primary source: the feed, the file's tags, or the archive page. [LibriVox](https://librivox.org/) and the [Internet Archive](https://archive.org/) are good places to look.
2. **No file over 40 MB.** CI rejects anything larger. Prefer short clips unless length itself is the case.
3. **Each addition should cover a new case**, and its `SOURCE.txt` should say which one:

   ```
   Title:
   Author/Creator:
   Licence:
   Licence URL:
   Source URL:
   Derived from:      (generated samples only)
   Cases:
   ```

4. Add a row to the tables above, and remove anything it covers from Wanted.

## License

The scripts and documentation are [MIT-licensed](LICENSE). Each media item keeps the licence of its original source, as recorded in its `SOURCE.txt`.
