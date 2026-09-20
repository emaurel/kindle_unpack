import 'dart:typed_data';

import 'package:kindle_unpack/kindle_unpack.dart';
import 'package:test/test.dart';

import 'support/indx_builders.dart';

void main() {
  group('IndxData.read', () {
    test('decodes entries with the small-count tag encoding', () {
      // TAGX: tag 1 (vpe=1, mask=0x03), end-marker.
      final tagx = tagxBlock(1, [
        [1, 1, 0x03, 0],
        [0, 0, 0x00, 1],
      ]);
      // Single entry "A": control byte 0x01 (count=1 in mask-0x03 slot),
      // then one var-int value 42.
      final entry = entryIndx(entries: [
        (
          name: 'A',
          controlBytes: [0x01],
          data: vwi(42),
        ),
      ]);
      final pdb = wrapPdb([mainIndx(count: 1, nctoc: 0, tagx: tagx), entry]);
      final indx = IndxData.read(pdb, 0);
      expect(indx.entries, hasLength(1));
      expect(indx.entries[0].tagMap[1], [42]);
    });

    test('decodes multi-value tags with the byte-length encoding', () {
      // mask=0x03, all-bits-set path → next data byte is a var-int
      // BYTE-LENGTH; we then read var-ints until that many bytes
      // consumed.
      final tagx = tagxBlock(1, [
        [6, 2, 0x03, 0],
        [0, 0, 0x00, 1],
      ]);
      // Two var-int values: 100 (1 byte 0xE4) and 200 (2 bytes 0x01 0xC8).
      final dataBytes = [...vwi(100), ...vwi(200)];
      final byteLen = dataBytes.length; // 3
      final entry = entryIndx(entries: [
        (
          name: 'X',
          controlBytes: [0x03],
          data: [...vwi(byteLen), ...dataBytes],
        ),
      ]);
      final pdb = wrapPdb([mainIndx(count: 1, nctoc: 0, tagx: tagx), entry]);
      final indx = IndxData.read(pdb, 0);
      expect(indx.entries[0].tagMap[6], [100, 200]);
    });

    test('decodes CTOC strings into the offset map', () {
      // No actual entries — just a main + entry block + ctoc record.
      final tagx = tagxBlock(1, [
        [0, 0, 0x00, 1],
      ]);
      final main = mainIndx(count: 1, nctoc: 1, tagx: tagx);
      final entry = entryIndx(entries: const []);
      // CTOC: <var-int len><bytes> sequences, terminated by 0.
      const a = 'hello';
      const b = 'world!';
      final ctoc = Uint8List.fromList([
        ...vwi(a.length),
        ...a.codeUnits,
        ...vwi(b.length),
        ...b.codeUnits,
        0,
      ]);
      final pdb = wrapPdb([main, entry, ctoc]);
      final indx = IndxData.read(pdb, 0);
      expect(indx.ctoc, hasLength(2));
      // First string starts at offset 0 of the CTOC record; second
      // follows after the first var-int + payload.
      final firstKey = indx.ctoc.keys.first;
      expect(String.fromCharCodes(indx.ctoc[firstKey]!), a);
    });

    test('throws on missing INDX signature', () {
      final tagx = tagxBlock(1, [
        [0, 0, 0x00, 1],
      ]);
      final main = mainIndx(count: 1, nctoc: 0, tagx: tagx);
      main[0] = 'X'.codeUnitAt(0);
      expect(
        () => IndxData.read(wrapPdb([main]), 0),
        throwsA(isA<HeaderException>()),
      );
    });

    test('throws on missing TAGX signature', () {
      // Build a main INDX whose post-header bytes don't start with TAGX.
      final tagx = tagxBlock(1, [
        [0, 0, 0x00, 1],
      ]);
      final main = mainIndx(count: 1, nctoc: 0, tagx: tagx);
      // Corrupt the TAGX magic.
      main[192] = 'Y'.codeUnitAt(0);
      expect(
        () => IndxData.read(wrapPdb([main]), 0),
        throwsA(isA<HeaderException>()),
      );
    });
  });

  group('IndxData.read — malformed records', () {
    /// A well-formed main INDX with a single end-marker TAGX row, used
    /// as the starting point for the corruption cases below.
    Uint8List goodMain({int count = 0, int nctoc = 0}) => mainIndx(
          count: count,
          nctoc: nctoc,
          tagx: tagxBlock(1, [
            [0, 0, 0x00, 1],
          ]),
        );

    test('throws when the record index is outside the PDB', () {
      final pdb = wrapPdb([goodMain()]);
      expect(
        () => IndxData.read(pdb, 1),
        throwsA(isA<HeaderException>()),
      );
      expect(
        () => IndxData.read(pdb, -1),
        throwsA(isA<HeaderException>()),
      );
    });

    test('throws on a record too short to hold the fixed header', () {
      expect(
        () => IndxData.read(wrapPdb([Uint8List(0x20)]), 0),
        throwsA(isA<HeaderException>()),
      );
    });

    test('throws on ORDT-remapped names', () {
      final main = goodMain();
      // ordt1Count lives at 0xa4 and is only read when the record is
      // long enough to hold it — the 192-byte header is.
      ByteData.sublistView(main).setUint32(0xa4, 1);
      expect(
        () => IndxData.read(wrapPdb([main]), 0),
        throwsA(isA<HeaderException>()),
      );
    });

    test('throws when a declared CTOC record is past the end of the PDB', () {
      // nctoc=1 with no following record: ctocStart lands at index 1,
      // but the PDB only holds the main INDX.
      expect(
        () => IndxData.read(wrapPdb([goodMain(nctoc: 1)]), 0),
        throwsA(isA<HeaderException>()),
      );
    });

    test('throws when the TAGX section starts past the record end', () {
      final main = goodMain();
      // Point headerLength at the very end so start + 12 overruns.
      ByteData.sublistView(main).setUint32(4, main.length);
      expect(
        () => IndxData.read(wrapPdb([main]), 0),
        throwsA(isA<HeaderException>()),
      );
    });

    test('throws when a TAGX row is truncated', () {
      final main = goodMain();
      // firstEntryOffset claims far more rows than the record holds.
      ByteData.sublistView(main).setUint32(192 + 4, 0x400);
      expect(
        () => IndxData.read(wrapPdb([main]), 0),
        throwsA(isA<HeaderException>()),
      );
    });

    test('throws when a CTOC string runs past its record end', () {
      // var-int 0x85 declares a 5-byte string, but only 2 bytes follow.
      final ctoc = Uint8List.fromList([0x85, 0x01, 0x02]);
      expect(
        () => IndxData.read(wrapPdb([goodMain(nctoc: 1), ctoc]), 0),
        throwsA(isA<HeaderException>()),
      );
    });

    test('throws when a var-width int runs off the end of the buffer', () {
      // 0x01 never sets the terminator bit, so the reader walks off the
      // one-byte CTOC record looking for one.
      final ctoc = Uint8List.fromList([0x01]);
      expect(
        () => IndxData.read(wrapPdb([goodMain(nctoc: 1), ctoc]), 0),
        throwsA(isA<HeaderException>()),
      );
    });

    test('throws when IDXT positions extend past the entry record end', () {
      final entry = entryIndx(entries: [
        (name: 'E', controlBytes: const [0x00], data: const <int>[]),
      ]);
      // Push idxtStart beyond the record so the position table overruns.
      ByteData.sublistView(entry).setUint32(20, entry.length);
      expect(
        () => IndxData.read(wrapPdb([goodMain(count: 1), entry]), 0),
        throwsA(isA<HeaderException>()),
      );
    });

    test('throws when an entry name length overflows the entry bounds', () {
      final entry = entryIndx(entries: [
        (name: 'E', controlBytes: const [0x00], data: const <int>[]),
      ]);
      // First entry starts right after the 192-byte header; its name
      // length byte claims far more than the entry can hold.
      entry[192] = 0xC0;
      expect(
        () => IndxData.read(wrapPdb([goodMain(count: 1), entry]), 0),
        throwsA(isA<HeaderException>()),
      );
    });

    test('throws when a tag consumes bytes past the entry end', () {
      // TAGX declares tag 1 with a single-bit mask, so the control byte
      // 0x01 means "one value follows". The entry supplies no value
      // bytes at all, so the reader spills into the IDXT block that
      // follows and ends up past the entry boundary.
      final tagx = tagxBlock(1, [
        [1, 1, 0x01, 0],
        [0, 0, 0x00, 1],
      ]);
      final main = mainIndx(count: 1, nctoc: 0, tagx: tagx);
      final entry = entryIndx(entries: [
        (name: 'E', controlBytes: const [0x01], data: const <int>[]),
      ]);
      expect(
        () => IndxData.read(wrapPdb([main, entry]), 0),
        throwsA(isA<HeaderException>()),
      );
    });
  });
}
