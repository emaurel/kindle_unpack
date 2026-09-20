# Changelog

## 0.2.0

**Breaking:** requires `archive` 4.x and Dart SDK 3.8+.

- Migrate to `archive` ^4.0.9. Apps on `archive` 4.x — which is
  effectively all of them now, since `image` 4.x requires it — could not
  depend on kindle_unpack at all while it pinned `archive` ^3.6.1, and
  had to vendor a patched fork instead. The EPUB packager now sets the
  `mimetype` entry's storage via archive 4's `compression` enum rather
  than 3.x's removed `compress` bool, and uses `ZipEncoder.encodeBytes`,
  which returns a non-nullable `Uint8List`. The emitted zip is
  unchanged: `mimetype` is still the first entry and still STORED, as
  OCF requires.
- Raise the SDK floor to ^3.8.0 and move to `lints` ^6.1.0.
- Swap the dev-only `epubx` strict-reader roundtrip test over to
  `epub_plus` ^5.1.0. `epubx` was last published in 2023 and pins
  `archive` ^3.1.6, which is what blocked the upgrade.
- Raise line coverage from 90.1% to 100% (179 → 236 tests). The new
  tests are mostly malformed-input cases for the INDX, HUFF/CDIC, FONT,
  RESC and XHTML-splice parsers, plus the first end-to-end tests of
  `KindleBook.fromBytes` itself: Mobi-7 single-part output, the title
  fallback to the MOBI full name, embedded-font extraction, and the
  graceful degradation path for KF8 files that carry no skeleton or
  fragment tables.
- Make `EpubBuilder`, `ExthType` and `XhtmlSplitter` `abstract final
  class` instead of hiding a private constructor. These have only ever
  held statics, and the modern idiom says so directly. Consumers could
  not construct or subclass them before either, so nothing changes at
  the call site.

## 0.1.1

- Fix `toEpub()` so the OPF declares an EPUB 3 nav document
  (`<item ... properties="nav"/>` pointing at a generated `nav.xhtml`).
  Without it, strict EPUB 3 parsers like `epubx` failed to locate the
  TOC and threw `EPUB parsing error: TOC item, not found in EPUB
  manifest.` The packager still emits the NCX for EPUB 2 reader
  compatibility.

## 0.1.0

First release. Reads MOBI / AZW / AZW3 / KF8 files end-to-end and
re-emits them as EPUB 3.

- **PDB container** — Palm Database header + record list parser.
- **PalmDOC + MOBI headers** — fixed + variable-length headers, with
  the field offsets that real-world files actually use (the
  MobileRead / KindleUnpack layout, not the offsets some other
  references list).
- **EXTH metadata** — typed accessors for title, authors, publisher,
  description, ISBN, subjects, ASIN, language, cover/thumbnail offset,
  KF8 boundary record, etc.
- **PalmDOC decompression** — strict LZ77-style byte-coded interpreter.
- **HUFF/CDIC decompression** — Huffman + dictionary-coded compression
  with recursive expansion of non-precoded entries.
- **Per-record trailing-data stripping** — handles the multibyte-overlap
  indicator and bit-N length-prefixed trailers from MOBI offset 0xF2.
- **Image extraction** — JPEG / PNG / GIF / BMP / SVG with cover and
  thumbnail resolution via EXTH 201/202.
- **KF8 / AZW3 detection** — distinguishes standalone KF8, Mobi-7-only,
  and dual (combo) files via the EXTH 121 boundary plus the BOUNDARY
  sentinel.
- **FDST flow splitting** — slices the rawML into HTML / CSS / SVG /
  auxiliary flows.
- **INDX parser** — main + entry blocks + CTOC strings + the byte-length
  and small-count tag encodings.
- **Skeleton + fragment splicing** — reconstructs individual XHTML files
  from KF8's collapsed primary flow, with the partial-tag boundary
  heuristic for malformed splice points.
- **RESC manifest** — extracts the OPF XML from the RESC record.
- **FONT records** — parses the FONT header, deobfuscates the XOR-mangled
  prefix, decompresses zlib payloads, and sniffs TTF / TTC / OTF.
- **EPUB 3 packaging** — `KindleBook.fromBytes(bytes).toEpub()` produces
  a valid EPUB zip (mimetype-first uncompressed, OPF + NCX + parts +
  images + CSS + fonts).

Real-world fixtures used during development:

- `Pride and Prejudice` (Project Gutenberg #1342) — MOBI v6, PalmDOC.
- A DRM-free AZW3 — KF8 v8, HUFF/CDIC, 70 XHTML parts, 8 images.

Known gaps for follow-up versions:

- The OPF and NCX are synthesised from EXTH metadata, not lifted from
  the file's own RESC manifest / NCX index. Output is valid EPUB but
  doesn't preserve original spine ordering refinements.
- No DRM removal — encrypted files are detected and rejected, never
  decrypted.
- Topaz (`.tpz` / `.azw1`) and Kindle Print Replica (`.kpf`) are out of
  scope.
- Flutter web isn't supported (the HUFF/CDIC decoder uses 64-bit shifts
  and the FONT decoder uses `dart:io`'s `ZLibCodec`).
