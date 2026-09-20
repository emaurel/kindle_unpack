import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:epub_plus/epub_plus.dart' as epub;
import 'package:kindle_unpack/kindle_unpack.dart';
import 'package:test/test.dart';

/// Roundtrip: AZW3 -> KindleBook.toEpub() -> EpubReader.readBook.
///
/// epub_plus is a strict pure-Dart EPUB parser (a maintained fork of
/// epubx) standing in for the downstream readers that consume this
/// package. It is the regression canary for the 0.1.1 nav-document
/// bug: the packager used to emit an EPUB that opened in lenient tools
/// but tripped strict readers with
///
///     Exception: EPUB parsing error: TOC item, not found in EPUB manifest.
///
/// Root cause: the OPF declares `<package version="3.0">`, so an EPUB-3
/// parser looks for a nav document — a manifest item with
/// `properties="nav"`. The packager shipped only an NCX
/// (`<item id="ncx" ... media-type="application/x-dtbncx+xml"/>`) and
/// never declared a nav.xhtml, so the manifest lookup returned nothing
/// and parsing failed.
///
/// 0.1.1 fixed this by emitting a real nav.xhtml *and* declaring it
/// with properties="nav", keeping the NCX for EPUB 2 readers. This test
/// fails again if that regresses.
void main() {
  final fixture = File('test/fixtures/Leviathan_Wakes.azw3');
  if (!fixture.existsSync()) {
    test('EPUB roundtrip skipped (fixture missing)', () {
      // ignore: avoid_print
      print(
        'Skipping EPUB roundtrip test: ${fixture.path} not present. '
        'Drop a DRM-free AZW3 there to enable.',
      );
    }, skip: 'AZW3 fixture not present');
    return;
  }

  group('AZW3 -> EPUB -> strict-reader roundtrip', () {
    late Uint8List epubBytes;

    setUpAll(() {
      final azwBytes = fixture.readAsBytesSync();
      epubBytes = KindleBook.fromBytes(azwBytes).toEpub();
    });

    test('produces a non-empty EPUB byte buffer', () {
      expect(epubBytes, isNotEmpty);
    });

    test('OPF and NCX exist in the zip and reference matching files', () {
      // Sanity-only: this test passes today. It's here so when #2 lands
      // and the manifest gains a nav.xhtml entry, regressions in OPF
      // shape get caught alongside the strict-reader assertion below.
      final archive = ZipDecoder().decodeBytes(epubBytes);
      final opf = archive.findFile('OEBPS/content.opf');
      expect(opf, isNotNull, reason: 'content.opf missing from EPUB');
      final ncx = archive.findFile('OEBPS/toc.ncx');
      expect(ncx, isNotNull, reason: 'toc.ncx missing from EPUB');

      final opfStr = utf8.decode(opf!.content as List<int>);
      final ncxStr = utf8.decode(ncx!.content as List<int>);

      // Diagnostic dump on assertion failure: surfaces exactly which
      // <navPoint><content src="..."/> entries have no matching
      // manifest <item href="..."/>. Useful while task #2 is in flight.
      final hrefRe = RegExp(r'<item\s+[^>]*href="([^"]+)"');
      final manifestHrefs =
          hrefRe.allMatches(opfStr).map((m) => m.group(1)!).toSet();
      final navSrcRe = RegExp(r'<content\s+src="([^"#]+)');
      final ncxSrcs =
          navSrcRe.allMatches(ncxStr).map((m) => m.group(1)!).toSet();
      final missing = ncxSrcs.difference(manifestHrefs);
      expect(
        missing,
        isEmpty,
        reason:
            'NCX references not declared in OPF manifest: $missing\n'
            '--- content.opf ---\n$opfStr\n--- toc.ncx ---\n$ncxStr',
      );
    });

    test('parses cleanly with epub_plus (strict EPUB reader)', () async {
      // Canary for the 0.1.1 nav-document bug: before the fix this
      // threw 'EPUB parsing error: TOC item, not found in EPUB
      // manifest.' It must return a book with at least one chapter.
      final book = await epub.EpubReader.readBook(epubBytes);
      expect(book.title, isNotEmpty);
      expect(book.chapters, isNotNull);
      expect(book.chapters.length, greaterThan(0),
          reason: 'strict reader returned a book with no chapters; '
              'TOC/spine wiring is probably still off');
    });
  });
}
