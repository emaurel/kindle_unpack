import 'dart:typed_data';

import 'package:archive/archive.dart' as arch;
import 'package:kindle_unpack/kindle_unpack.dart';
import 'package:test/test.dart';

import 'support/mobi_file.dart';

Uint8List _u8(List<int> b) => Uint8List.fromList(b);

/// Font payloads chosen so [FontFormat] sniffing lands on each branch.
const _ttf = [0x00, 0x01, 0x00, 0x00, 0xAA, 0xBB];
const _ttc = [0x74, 0x74, 0x63, 0x66, 0xAA]; // 'ttcf'
const _otf = [0x4F, 0x54, 0x54, 0x4F, 0xAA]; // 'OTTO'
const _unknownFont = [0xDE, 0xAD, 0xBE, 0xEF];

void main() {
  group('KindleBook.fromBytes — Mobi-7', () {
    const html = '<html><body><p>Hello</p></body></html>';

    test('emits a single monolithic part and exposes the header getters',
        () {
      final bytes = buildPdb([
        buildRecord0(
          fileVersion: 6,
          textLength: html.length,
          exth: [(ExthType.author, 'Ada Lovelace'.codeUnits)],
          fullName: 'Synthetic Book',
        ),
        html.codeUnits,
      ]);

      final book = KindleBook.fromBytes(bytes);
      expect(book.format, KindleFormat.mobi7Only);
      // Mobi-7 has no FDST flows; rawML is one self-contained blob and
      // the splitter is bypassed entirely.
      expect(book.flows, isNull);
      expect(book.parts, hasLength(1));
      expect(book.parts.single.fileNumber, 0);
      expect(String.fromCharCodes(book.parts.single.bytes), html);

      expect(book.palmDoc.textRecordCount, 1);
      expect(book.mobi.fileVersion, 6);
      expect(book.exth?.authors, ['Ada Lovelace']);
    });

    test('falls back to the MOBI full name when EXTH carries no title', () {
      final bytes = buildPdb([
        buildRecord0(
          fileVersion: 6,
          textLength: html.length,
          // EXTH 503 (updated title) deliberately absent.
          exth: [(ExthType.publisher, 'Nobody'.codeUnits)],
          fullName: 'Title From Header',
        ),
        html.codeUnits,
      ]);
      expect(KindleBook.fromBytes(bytes).title, 'Title From Header');
    });

    test('prefers the EXTH title when one is present', () {
      final bytes = buildPdb([
        buildRecord0(
          fileVersion: 6,
          textLength: html.length,
          exth: [(ExthType.updatedTitle, 'Title From EXTH'.codeUnits)],
          fullName: 'Title From Header',
        ),
        html.codeUnits,
      ]);
      expect(KindleBook.fromBytes(bytes).title, 'Title From EXTH');
    });
  });

  group('KindleBook.fromBytes — KF8 without skeleton tables', () {
    test('falls back to one monolithic part instead of throwing', () {
      // A 232-byte MOBI header stops short of the skeleton / fragment
      // index fields, so SkeletonTable.parse throws and the pipeline has
      // to degrade gracefully rather than fail the whole book. Print
      // Replica and some scrambled KF8 files look like this.
      const html = '<html><body><p>KF8 body</p></body></html>';
      final bytes = buildPdb([
        buildRecord0(
          fileVersion: 8,
          textLength: html.length,
          fdstRecord: 2,
          fullName: 'Skeletonless',
        ),
        html.codeUnits,
        buildFdst([(0, html.length)]),
      ]);

      final book = KindleBook.fromBytes(bytes);
      expect(book.format, KindleFormat.kf8Only);
      expect(book.mobi.skeletonIndex, isNull);
      // The FDST split still ran — we lost the per-chapter split, not
      // the flow structure.
      expect(book.flows, isNotNull);
      expect(book.parts, hasLength(1));
      expect(String.fromCharCodes(book.parts.single.bytes), html);
      // And the degraded book still packages.
      expect(book.toEpub(), isNotEmpty);
    });
  });

  group('KindleBook.fromBytes — embedded fonts', () {
    const html = '<html><body>f</body></html>';

    Uint8List bookWithFonts(List<List<int>> fontRecords) => buildPdb([
          buildRecord0(
            fileVersion: 6,
            textLength: html.length,
            firstImageIndex: 2,
            fullName: 'Fonts',
          ),
          html.codeUnits,
          ...fontRecords,
        ]);

    test('extracts every FONT record and sniffs its format', () {
      final book = KindleBook.fromBytes(bookWithFonts([
        buildFontRecord(_ttf),
        buildFontRecord(_ttc),
        buildFontRecord(_otf),
        buildFontRecord(_unknownFont),
      ]));

      expect(
        book.fonts.map((f) => f.format),
        [FontFormat.ttf, FontFormat.ttc, FontFormat.otf, FontFormat.unknown],
      );
      expect(book.fonts.first.payload, _u8(_ttf));
    });

    test('skips FONT-signed records that fail to parse', () {
      // Second record has the signature but is too short to hold the
      // 24-byte header — one corrupt entry must not sink the book.
      final book = KindleBook.fromBytes(bookWithFonts([
        buildFontRecord(_ttf),
        'FONT'.codeUnits,
        buildFontRecord(_otf),
      ]));
      expect(book.fonts, hasLength(2));
      expect(
        book.fonts.map((f) => f.format),
        [FontFormat.ttf, FontFormat.otf],
      );
    });

    test('emits fonts into the EPUB with per-format media types', () {
      final book = KindleBook.fromBytes(bookWithFonts([
        buildFontRecord(_ttf),
        buildFontRecord(_ttc),
        buildFontRecord(_otf),
        buildFontRecord(_unknownFont),
      ]));
      final opf = _opfOf(book.toEpub());

      // ttf and ttc share the sfnt container, otf is OpenType, and an
      // unsniffable payload gets the generic fallback.
      expect(
        opf,
        contains('href="Fonts/font0000.ttf" '
            'media-type="application/font-sfnt"'),
      );
      expect(
        opf,
        contains('href="Fonts/font0001.ttf" '
            'media-type="application/font-sfnt"'),
      );
      expect(
        opf,
        contains('href="Fonts/font0002.otf" '
            'media-type="application/vnd.ms-opentype"'),
      );
      expect(
        opf,
        contains('href="Fonts/font0003.dat" '
            'media-type="application/octet-stream"'),
      );
    });

    test('reports no fonts when firstImageIndex is unset', () {
      final bytes = buildPdb([
        buildRecord0(
          fileVersion: 6,
          textLength: html.length,
          fullName: 'No fonts',
        ),
        html.codeUnits,
        buildFontRecord(_ttf),
      ]);
      expect(KindleBook.fromBytes(bytes).fonts, isEmpty);
    });
  });
}

/// Pull `OEBPS/content.opf` out of a packaged EPUB.
String _opfOf(Uint8List epub) {
  final files = arch.ZipDecoder().decodeBytes(epub).files;
  return String.fromCharCodes(
    files.firstWhere((f) => f.name == 'OEBPS/content.opf').content as List<int>,
  );
}
