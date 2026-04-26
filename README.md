# kindle_unpack

A pure-Dart library for reading Amazon Kindle ebook files (MOBI / AZW / AZW3 / KF8).
Port of [KindleUnpack](https://github.com/kevinhendricks/KindleUnpack) (Python).

> **Status:** planning. No code yet — see the roadmap below.

## Why

The Dart / Flutter ecosystem has solid EPUB support (`epubx`) and PDF support
(`pdfx`, `pdfium` bindings), but nothing for Kindle's MOBI-derived formats.
Books bought from non-Kindle stores and saved as `.azw3`, classic `.mobi`
files from Project Gutenberg, and stripped-DRM library archives all sit there
unreadable by any Flutter app today. The only way to view them on a Flutter
device right now is to convert them on a desktop with Calibre first.

This library aims to plug that hole: feed it bytes, get back HTML +
metadata + images. A higher-level renderer (or an EPUB-emitting wrapper)
can sit on top.

## Scope

### What this will support
- **MOBI** (PalmDOC-compressed, `.mobi`)
- **AZW** (Mobi-7 with Amazon DRM section *headers* — but only files that
  are not encrypted)
- **AZW3 / KF8** (the modern Kindle format, both standalone and dual MOBI/KF8)
- **HUFF/CDIC** decompression (used in some MOBI files)
- Cover and embedded image extraction
- Metadata via EXTH headers (title, author, publisher, description, ASIN, etc.)
- HTML output preserving structure
- EPUB output as a higher-level wrapper

### What this will NOT support
- **DRM removal.** Files encrypted with Amazon's PID/serial-key DRM stay
  encrypted. There are tools that remove Kindle DRM; this library will not
  be one of them. If a file is encrypted, parsing returns an error.
- **Topaz / .tpz / .azw1.** Topaz is a separate, more obscure format.
  Out of scope for v1.
- **Kindle Print Replica (KPR).** It's just wrapped PDF; use a PDF library.

## Format primer

Kindle files are nested containers. From the outside in:

```
PDB (Palm Database)              ← the file itself; a record-based container
└── PalmDOC header               ← compression type, record count, text length
    └── MOBI header              ← Mobi version, encoding, EXTH offset, image
        │                         indices, etc.
        ├── EXTH header          ← key/value metadata records
        ├── Compressed text      ← HTML, in PalmDOC or HUFF/CDIC compression
        ├── Image records        ← raw JPEG/PNG/GIF
        ├── (KF8 only) FDST      ← record-section table for KF8 portion
        ├── (KF8 only) FONT      ← embedded fonts
        ├── (KF8 only) RESC      ← OPF/manifest description
        └── …
```

AZW3 / KF8 files are often "dual": they contain a legacy MOBI section *and*
a KF8 section in the same PDB, so old Kindles fall back gracefully.
Detecting which sections belong to which version is its own little parsing
problem.

## Roadmap

Each phase is meant to land independently with tests:

- [x] **Phase 1 — PDB container.** Parse the Palm Database header and
      record table. Produces a `List<Uint8List>` of raw records.
- [x] **Phase 2 — PalmDOC + MOBI headers.** Parse the first record's
      headers into a typed struct. Identify Mobi version, encoding,
      record indices.
- [x] **Phase 3 — EXTH metadata.** Parse EXTH key/value records into a
      `Map<int, dynamic>` and expose convenience accessors (`title`,
      `author`, `description`, `asin`, …).
- [x] **Phase 4 — PalmDOC decompression.** LZ77-ish bytecode interpreter.
      Decompress text records into a single HTML string.
- [x] **Phase 5 — Image extraction.** Walk image records, return
      `{name: bytes}`. Handle the cover record specially.
- [x] **Phase 6 — HUFF/CDIC decompression.** Huffman + dictionary-coded
      compression used in some MOBI files. Larger than PalmDOC.
- [x] **Phase 7 — KF8 detection + section extraction.** Identify KF8
      portion in dual-format files via boundary record. Handle FDST table.
- [x] **Phase 8 — KF8 resources.** RESC (OPF manifest), FONT (embedded
      fonts, often obfuscated), embedded raster/vector images.
- [x] **Phase 9 — KF8 HTML reconstruction.** Slice the decompressed
      rawML into FDST-bounded flows (HTML / CSS / SVG / auxiliary).
      Per-XHTML splitting via the skeleton + fragment INDX records is
      deferred to Phase 10, where the EPUB packager decides how many
      `.xhtml` files to emit.
- [x] **Phase 10 — EPUB output.** Walk the skeleton + fragment INDX to
      split the primary flow into individual XHTML parts; package
      everything (parts + CSS + images + OPF manifest) into a proper
      EPUB 3 zip on disk. Integration target for
      [`My_book_reader`](https://github.com/emaurel/My_book_reader).
      One-call entry point: `KindleBook.fromBytes(bytes).toEpub()`.
- [ ] **Phase 11 — Public API + docs.** Stable surface, CHANGELOG,
      pub.dev publish.

Phases 1–5 cover roughly 80% of real-world `.mobi` files. Phases 6–9
are needed for AZW3 from current-gen Kindle exports. Phase 10 is what
turns this into something a reader app can use directly.

## Architecture sketch

```dart
// Public API (target shape — none of this exists yet).

import 'package:kindle_unpack/kindle_unpack.dart';

final book = await KindleBook.fromBytes(bytes);

book.metadata.title;     // String
book.metadata.author;    // String?
book.metadata.asin;      // String?

book.html;               // String — full HTML, links rewritten to images/
book.images;             // Map<String, Uint8List> — name -> bytes
book.cover;              // Uint8List? — convenience for the cover image

// Higher-level: emit an EPUB
final epubBytes = await book.toEpub();
```

Internally the library is a stack of small parsers:

```
lib/
├── kindle_unpack.dart            ← public API
└── src/
    ├── pdb.dart                  ← Palm Database record parser
    ├── headers/
    │   ├── palmdoc_header.dart
    │   ├── mobi_header.dart
    │   └── exth.dart
    ├── decompress/
    │   ├── palmdoc.dart          ← LZ77-ish
    │   └── huff_cdic.dart        ← Huffman + dictionary
    ├── kf8/
    │   ├── boundary.dart         ← detect MOBI/KF8 split
    │   ├── fdst.dart             ← FDST section table
    │   └── resources.dart
    ├── html.dart                 ← link rewriting, normalization
    └── epub.dart                 ← EPUB packaging (Phase 10)
```

## References

The MOBI format isn't officially documented. These are the practical
sources:

- **[KindleUnpack source][1]** — the reference implementation we're
  porting. ~10k LoC of Python, GPL-3.
- **[MobileRead MOBI wiki][2]** — community reverse-engineering of the
  binary layout. Best single-page format reference.
- **[Calibre's MOBI reader][3]** — independent C/Python implementation
  inside Calibre. Useful for cross-checking edge cases.
- **[Wikipedia: PalmDOC][4]** — for the PDB outer container.
- **MobiPerl (archived)** — the original reverse-engineering effort,
  much of which the above tools inherit. Hard to find now.

[1]: https://github.com/kevinhendricks/KindleUnpack
[2]: https://wiki.mobileread.com/wiki/MOBI
[3]: https://github.com/kovidgoyal/calibre/tree/master/src/calibre/ebooks/mobi
[4]: https://en.wikipedia.org/wiki/PalmDOC

## License

**GPL-3.0** — KindleUnpack itself is GPL-3, and a port is a derivative
work, so this repo is required to be GPL-3. If you need a permissive
license you'd have to do a clean-room implementation from the format
specs (refs above) without consulting the KindleUnpack source. That's
genuinely a lot more work and is not what this project does.

## Contributing

This is a personal exploratory project for now. If a phase looks fun
and you want to take it on, open an issue first so we don't duplicate.
