# audiobookshelf Test Library

A library of public-domain media laid out so audiobookshelf can scan it, used to exercise specific encoding, container, and layout behaviours in its scanner and player.

## Language

**Case**:
One scanner or player behaviour under test, such as "multi-file M4B with embedded chapters".
_Avoid_: Test, scenario, format (except within Required Format)

**Sample**:
One book or podcast folder under `Library/`, which audiobookshelf sees as a single library item. A Sample may cover several Cases.
_Avoid_: Test file, example, item

**Derived Sample**:
A Sample generated from a Source, typically as short clips re-encoded into the Case's format.

**Verbatim Sample**:
A Sample redistributed exactly as published, with no Source behind it.
_Avoid_: Raw sample, original sample

**Source**:
A trimmed, unmodified excerpt of a redistributable recording or ebook that Derived Samples are made from. A Source is never itself a Sample and lives outside the library.
_Avoid_: Source file, original, master

**Required Format**:
A Case that must always have at least one Sample in the library.
_Avoid_: Mandatory case, core format
