# audiobookshelf Test Library

A collection of royalty-free and public-domain media for testing [audiobookshelf](https://github.com/advplyr/audiobookshelf). It is a ready-made library with a wide range of audio encodings and audiobook layouts. Use it to check the scanner, metadata parsing, chapters, and playback without needing your own collection.

## Getting the files

The media files are stored with [Git LFS](https://git-lfs.com/). Install it before cloning, or you'll get small pointer files instead of audio:

```sh
git lfs install
git clone https://github.com/<owner>/audiobookshelf-test-library.git
```

## Using it with audiobookshelf

Point audiobookshelf library folders at the two top-level directories:

| Folder | Library type |
| --- | --- |
| `Library/Books` | Books |
| `Library/Podcasts` | Podcasts |

With Docker, mount them read-only so test runs can't change the files:

```sh
docker run -d -p 13378:80 \
  -v "$(pwd)/Library/Books:/audiobooks:ro" \
  -v "$(pwd)/Library/Podcasts:/podcasts:ro" \
  -v abs-config:/config \
  -v abs-metadata:/metadata \
  ghcr.io/advplyr/audiobookshelf
```

Then open http://localhost:13378, create the libraries, and run a scan.

## Required formats

The library must always include at least one book for each of these formats. Paths are under `Library/Books/Mark Twain/`. [`scripts/make-samples.sh`](scripts/make-samples.sh) creates them from public-domain sources, using 40-second clips.

| Format | Status | Path |
| --- | --- | --- |
| Single MP3 file | ✅ | `Tom Sawyer Single MP3` |
| Multiple MP3 files | ✅ | `Tom Sawyer Multi MP3` |
| Single M4B, AAC, with chapters | ✅ | `Tom Sawyer Single M4B AAC` |
| Multiple M4B, AAC, with chapters | ✅ | `Tom Sawyer Multi M4B AAC` |
| Single M4B, xHE-AAC, with chapters | ❌ needs the [exhale](https://gitlab.com/ecodis/exhale) encoder | `Tom Sawyer Single M4B xHE-AAC` |
| Multiple M4B, xHE-AAC, with chapters | ❌ needs the [exhale](https://gitlab.com/ecodis/exhale) encoder | `Tom Sawyer Multi M4B xHE-AAC` |
| Single Ogg file, Opus, with chapters | ✅ | `Tom Sawyer Single Ogg Opus` |
| Multiple Ogg files, Opus, with chapters | ✅ | `Tom Sawyer Multi Ogg Opus` |
| EPUB | ❌ not yet generated | `Tom Sawyer EPUB` |
| PDF | ❌ not yet generated | `Tom Sawyer PDF` |

To regenerate them, run `scripts/make-samples.sh` (or `make-samples.sh audio` / `make-samples.sh ebooks` for one half). It needs ffmpeg on `PATH`, plus `exhale` for the xHE-AAC samples and Microsoft Edge for the PDF.

## Other cases

Each item is there to test a specific case. Folder names describe the case.

| Path | Case | Source |
| --- | --- | --- |
| `Books/Agatha Christie/The Body In The Library Single MP3` | Single-file MP3 book | — |
| `Books/Joshua Kane/Example Narration Multipart MP3` | Multi-file MP3 book (4 parts) | [joshuakanevo.com](https://joshuakanevo.com/audio-book-narration/) |
| `Books/Mark Twain/Adventures Of Tom Sawyer` | Multi-file M4B book (2 parts, AAC 64 kbps) | [LibriVox via Internet Archive](https://archive.org/details/LibrivoxM4bCollectionAudiobooks4) |
| `Books/Joshua Kane`, `Books/Mark Twain` | `.txt` files next to the audio folders (non-media files the scanner should ignore) | — |
| `Podcasts/Conan O’Brien Needs A Friend` | Non-ASCII character (curly apostrophe) in a path | — |

### Wanted

Contributions that add any of these cases are welcome:

- **Codecs and containers:** MP3 VBR, M4A, OGG Vorbis, FLAC, WAV, WMA
- **Layouts:** multi-disc (`CD1/`, `Disc 1/`), series folders, `Book 1 - Title`, `1999 - Title`, `Title {Narrator}`
- **Metadata:** embedded chapters, embedded cover vs. `cover.jpg`, ID3v1 / ID3v2.3 / ID3v2.4 / MP4 tags, untagged files, `desc.txt`, `reader.txt`, `metadata.opf`
- **Ebooks:** EPUB or PDF in the same folder as audio
- **Podcasts:** a show with several episodes and episode metadata

## Contributing

1. **Only add media you can legally redistribute:** public domain, CC0, CC-BY, or audio you made yourself. [LibriVox](https://librivox.org/) and the [Internet Archive](https://archive.org/) are good sources.
2. Put a `SOURCE.txt` with the original URL and license next to the files.
3. Keep files short unless length is what you're testing. A 30-second clip shows an encoding case as well as a 10-hour book does.
4. Add a row to the table above.

## License

Each item keeps the license of its original source, which is recorded in its `SOURCE.txt`. This repository adds no restrictions.
