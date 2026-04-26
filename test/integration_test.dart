import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:kindle_unpack/kindle_unpack.dart';
import 'package:test/test.dart';

/// End-to-end smoke test against a real public-domain MOBI file
/// (Project Gutenberg #1342, *Pride and Prejudice*).
///
/// This test exercises the full pipeline — PDB → PalmDOC + MOBI headers
/// → EXTH → text decompression — on a file produced by a third-party
/// MOBI generator. It's the only check we have that the synthetic-byte
/// unit tests aren't quietly drifting from the real format.
void main() {
  final fixture = File('test/fixtures/pg1342.mobi');
  if (!fixture.existsSync()) {
    // Surface a clearer error than "file not found" if someone runs
    // tests in a partial checkout without LFS / fixture sync.
    throw StateError(
      'fixture missing: ${fixture.path}. Re-fetch with '
      'curl -sSL -o test/fixtures/pg1342.mobi '
      'https://www.gutenberg.org/cache/epub/1342/pg1342.mobi',
    );
  }
  final bytes = fixture.readAsBytesSync();

  group('Pride and Prejudice (Project Gutenberg #1342)', () {
    late PdbFile pdb;
    late Uint8List record0;
    late PalmDocHeader palmDoc;
    late MobiHeader mobi;
    late ExthHeader exth;

    setUpAll(() {
      pdb = PdbFile.parse(bytes);
      record0 = pdb.records[0].data;
      palmDoc = PalmDocHeader.parse(record0);
      mobi = MobiHeader.parse(record0);
      exth = ExthHeader.parse(
        record0,
        offset: mobi.exthOffset,
        textEncoding: mobi.textEncoding,
      );
    });

    test('PDB header identifies a Mobipocket book', () {
      expect(pdb.header.type, 'BOOK');
      expect(pdb.header.creator, 'MOBI');
      expect(pdb.records.length, greaterThan(1));
    });

    test('PalmDOC header reports PalmDOC compression, no encryption', () {
      expect(palmDoc.compression, CompressionType.palmDoc);
      expect(palmDoc.encryption, EncryptionType.none);
      expect(palmDoc.textRecordCount, greaterThan(0));
      expect(palmDoc.maxRecordSize, 4096);
    });

    test('MOBI header is version 6, UTF-8, EXTH present, no DRM', () {
      expect(mobi.fileVersion, 6);
      expect(mobi.textEncoding, 65001);
      expect(mobi.hasExth, isTrue);
      expect(mobi.hasDrm, isFalse);
    });

    test('full title contains "Pride and Prejudice"', () {
      expect(mobi.fullName(record0), contains('Pride and Prejudice'));
    });

    test('EXTH carries author and language metadata', () {
      expect(exth.authors, isNotEmpty);
      expect(exth.authors.first, contains('Austen'));
      expect(exth.language, isNotNull);
    });

    test('decompressed text matches the declared length', () {
      final text = decompressBookText(pdb: pdb, palmDoc: palmDoc, mobi: mobi);
      // The PalmDOC header advertises the uncompressed text length
      // exactly. Real files match within rounding; a hard equality is
      // a useful canary for off-by-one bugs in the trailing-data
      // stripper or back-reference loop.
      expect(text.length, palmDoc.textLength);
    });

    test('decompressed text contains the famous opening line', () {
      final text = decompressBookText(pdb: pdb, palmDoc: palmDoc, mobi: mobi);
      final asString = utf8.decode(text, allowMalformed: true);
      expect(
        asString,
        contains('truth universally acknowledged'),
      );
    });
  });
}
