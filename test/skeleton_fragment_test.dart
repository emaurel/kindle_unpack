import 'dart:typed_data';

import 'package:kindle_unpack/kindle_unpack.dart';
import 'package:test/test.dart';

import 'support/indx_builders.dart';

/// A MobiHeader carrying only the two INDX pointers these tables read.
/// Everything else is an innocuous default.
MobiHeader _mobi({int? skeletonIndex, int? fragmentIndex}) => MobiHeader(
      headerLength: 232,
      mobiType: 2,
      textEncoding: 65001,
      uniqueId: 0,
      fileVersion: 8,
      firstNonBookIndex: MobiHeader.unset,
      fullNameOffset: 0,
      fullNameLength: 0,
      locale: 0,
      inputLanguage: 0,
      outputLanguage: 0,
      minVersion: 0,
      firstImageIndex: MobiHeader.unset,
      huffmanRecordOffset: 0,
      huffmanRecordCount: 0,
      huffmanTableOffset: 0,
      huffmanTableLength: 0,
      exthFlags: 0,
      drmOffset: MobiHeader.unset,
      drmCount: MobiHeader.unset,
      drmSize: 0,
      drmFlags: 0,
      fdstRecord: null,
      fdstFlowCount: null,
      fragmentIndex: fragmentIndex,
      skeletonIndex: skeletonIndex,
      extraDataFlags: 0,
    );

/// TAGX for the skeleton table: tag 1 (fragment count, 1 value) and
/// tag 6 (start + length, 2 values), each behind a single mask bit.
Uint8List _skeletonTagx() => tagxBlock(1, [
      [1, 1, 0x01, 0],
      [6, 2, 0x02, 0],
      [0, 0, 0x00, 1],
    ]);

/// TAGX for the fragment table: tags 2 (CTOC offset), 3 (file number),
/// 4 (sequence number) and 6 (start + length).
Uint8List _fragmentTagx() => tagxBlock(1, [
      [2, 1, 0x01, 0],
      [3, 1, 0x02, 0],
      [4, 1, 0x04, 0],
      [6, 2, 0x08, 0],
      [0, 0, 0x00, 1],
    ]);

/// A CTOC record holding a single `<var-int length><bytes>` string at
/// offset 0, terminated by a zero byte.
Uint8List _ctoc(String value) => Uint8List.fromList([
      ...vwi(value.length),
      ...value.codeUnits,
      0,
    ]);

void main() {
  group('SkeletonTable.parse', () {
    test('reads fragment count and byte range from tags 1 and 6', () {
      final pdb = wrapPdb([
        Uint8List(0), // record 0 placeholder — index 0 means "absent"
        mainIndx(count: 1, nctoc: 0, tagx: _skeletonTagx()),
        entryIndx(entries: [
          (
            name: 'SKEL0000',
            controlBytes: const [0x03],
            data: [...vwi(2), ...vwi(0), ...vwi(7)],
          ),
        ]),
      ]);
      final table = SkeletonTable.parse(pdb, _mobi(skeletonIndex: 1));
      expect(table.entries, hasLength(1));
      expect(table.entries.single.name, 'SKEL0000');
      expect(table.entries.single.fragmentCount, 2);
      expect(table.entries.single.start, 0);
      expect(table.entries.single.length, 7);
    });

    test('throws when the MOBI header carries no skeletonIndex', () {
      final pdb = wrapPdb([Uint8List(0)]);
      for (final idx in [null, MobiHeader.unset, 0]) {
        expect(
          () => SkeletonTable.parse(pdb, _mobi(skeletonIndex: idx)),
          throwsA(isA<HeaderException>()),
          reason: 'skeletonIndex $idx should be treated as absent',
        );
      }
    });

    test('throws when an entry is missing the byte-range tag', () {
      // Control byte 0x01 selects tag 1 only, so tag 6 never appears.
      final pdb = wrapPdb([
        Uint8List(0), // record 0 placeholder — index 0 means "absent"
        mainIndx(count: 1, nctoc: 0, tagx: _skeletonTagx()),
        entryIndx(entries: [
          (name: 'SKEL0000', controlBytes: const [0x01], data: vwi(2)),
        ]),
      ]);
      expect(
        () => SkeletonTable.parse(pdb, _mobi(skeletonIndex: 1)),
        throwsA(isA<HeaderException>()),
      );
    });
  });

  group('FragmentTable.parse', () {
    test('resolves the id text through the CTOC map', () {
      final pdb = wrapPdb([
        Uint8List(0), // record 0 placeholder — index 0 means "absent"
        mainIndx(count: 1, nctoc: 1, tagx: _fragmentTagx()),
        entryIndx(entries: [
          (
            name: '3',
            controlBytes: const [0x0F],
            data: [...vwi(0), ...vwi(0), ...vwi(0), ...vwi(7), ...vwi(5)],
          ),
        ]),
        _ctoc("P-//*[@aid='0']"),
      ]);
      final table = FragmentTable.parse(pdb, _mobi(fragmentIndex: 1));
      expect(table.entries, hasLength(1));
      final frag = table.entries.single;
      expect(frag.insertPosition, 3);
      expect(frag.idText, "P-//*[@aid='0']");
      expect(frag.fileNumber, 0);
      expect(frag.sequenceNumber, 0);
      expect(frag.start, 7);
      expect(frag.length, 5);
    });

    test('throws when the MOBI header carries no fragmentIndex', () {
      final pdb = wrapPdb([Uint8List(0)]);
      for (final idx in [null, MobiHeader.unset, 0]) {
        expect(
          () => FragmentTable.parse(pdb, _mobi(fragmentIndex: idx)),
          throwsA(isA<HeaderException>()),
          reason: 'fragmentIndex $idx should be treated as absent',
        );
      }
    });

    test('throws when an entry is missing required tags', () {
      // Control byte 0x03 selects tags 2 and 3 only — the sequence
      // number and byte range are absent.
      final pdb = wrapPdb([
        Uint8List(0), // record 0 placeholder — index 0 means "absent"
        mainIndx(count: 1, nctoc: 1, tagx: _fragmentTagx()),
        entryIndx(entries: [
          (
            name: '3',
            controlBytes: const [0x03],
            data: [...vwi(0), ...vwi(0)],
          ),
        ]),
        _ctoc('x'),
      ]);
      expect(
        () => FragmentTable.parse(pdb, _mobi(fragmentIndex: 1)),
        throwsA(isA<HeaderException>()),
      );
    });

    test('throws when an entry points at a CTOC offset that is absent', () {
      // nctoc 0 means no CTOC records are read at all, so the offset
      // this entry names can never resolve.
      final pdb = wrapPdb([
        Uint8List(0), // record 0 placeholder — index 0 means "absent"
        mainIndx(count: 1, nctoc: 0, tagx: _fragmentTagx()),
        entryIndx(entries: [
          (
            name: '3',
            controlBytes: const [0x0F],
            data: [...vwi(0), ...vwi(0), ...vwi(0), ...vwi(7), ...vwi(5)],
          ),
        ]),
      ]);
      expect(
        () => FragmentTable.parse(pdb, _mobi(fragmentIndex: 1)),
        throwsA(isA<HeaderException>()),
      );
    });
  });
}
