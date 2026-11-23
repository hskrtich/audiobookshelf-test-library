# Trimmed Sources committed directly, without Git LFS

All media, Sources included, is committed as ordinary git objects, and no file may exceed 40 MB. CI enforces the limit. Each Source is cut down to its first five chapters, kept as the unmodified per-chapter MP3s LibriVox publishes, instead of a full book. Sources live in `Sources/` outside `Library/`, so audiobookshelf never scans them as Samples.

The cap is 40 MB because it fits one full-length Derived Sample (five chapters, single M4B, AAC 64 kbps, about 37 MB) used for duration and seeking Cases, and it stays under GitHub's 50 MB warning threshold. Every other Derived Sample is made of short clips.

## Considered Options

- **Git LFS**: rejected. GitHub's free LFS tier (1 GB storage, 1 GB/month bandwidth) would run out after a few clones of full-length Sources, and LFS adds an install step for every user.
- **Download Sources at generation time, never commit them**: rejected. Generation would depend on outside URLs staying up, and the exact bytes that Samples were made from would not be preserved.
- **Commit full-length Sources**: impossible without LFS. GitHub rejects files over 100 MB, and the history would stay large forever.
- **A 20 MB cap**: rejected. It rules out any realistic-length single-file audiobook at normal bitrates.

## Consequences

Git history is permanent, so every committed Source adds to every clone for good. Add Sources sparingly and keep them small. Before adding another full-length Sample, justify it against what it costs every clone.
