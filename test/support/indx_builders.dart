import 'dart:typed_data';

import 'package:kindle_unpack/kindle_unpack.dart';

/// Byte-level builders for synthetic INDX clusters, shared by the INDX
/// parser tests and the skeleton / fragment table tests that sit on top
/// of them. Kept in one place so the two suites can't drift apart on
/// what a well-formed record looks like.
/// Build a minimal forward variable-width int per the INDX format:
/// each byte holds 7 bits (high to low), the byte with the high bit
/// set marks the end. Mirrors KindleUnpack's `getVariableWidthValue`.
List<int> vwi(int value) {
  if (value < 0) throw ArgumentError('value must be non-negative');
  final out = <int>[];
  out.add((value & 0x7F) | 0x80); // terminator (low 7 bits)
  var v = value >> 7;
  while (v != 0) {
    out.insert(0, v & 0x7F);
    v >>= 7;
  }
  return out;
}

/// Build a minimal "main" INDX record at offset 0:
///   "INDX" + 192-byte header + TAGX block.
/// Caller controls the `count` field (number of entry-INDX records that
/// follow) and `nctoc`. The TAGX block is appended verbatim.
Uint8List mainIndx({
  required int count,
  required int nctoc,
  required Uint8List tagx,
  int codepage = 65001,
}) {
  // Header is 192 bytes; TAGX follows immediately after.
  const headerLen = 192;
  final out = Uint8List(headerLen + tagx.length);
  out[0] = 'I'.codeUnitAt(0);
  out[1] = 'N'.codeUnitAt(0);
  out[2] = 'D'.codeUnitAt(0);
  out[3] = 'X'.codeUnitAt(0);
  final view = ByteData.sublistView(out);
  view.setUint32(4, headerLen);
  view.setUint32(24, count); // index count = number of entry blocks
  view.setUint32(28, codepage);
  view.setUint32(52, nctoc);
  out.setRange(headerLen, headerLen + tagx.length, tagx);
  return out;
}

/// Build a minimal TAGX block: "TAGX" + firstEntryOffset + cbCount +
/// 4-byte (tag, vpe, mask, endFlag) tuples.
Uint8List tagxBlock(int controlByteCount, List<List<int>> rows) {
  final firstEntryOffset = 12 + rows.length * 4;
  final out = Uint8List(firstEntryOffset);
  out[0] = 'T'.codeUnitAt(0);
  out[1] = 'A'.codeUnitAt(0);
  out[2] = 'G'.codeUnitAt(0);
  out[3] = 'X'.codeUnitAt(0);
  final view = ByteData.sublistView(out);
  view.setUint32(4, firstEntryOffset);
  view.setUint32(8, controlByteCount);
  for (var i = 0; i < rows.length; i++) {
    out[12 + i * 4] = rows[i][0];
    out[12 + i * 4 + 1] = rows[i][1];
    out[12 + i * 4 + 2] = rows[i][2];
    out[12 + i * 4 + 3] = rows[i][3];
  }
  return out;
}

/// Build an entry-INDX record (the type-1 INDX) holding one or more
/// entries. Each entry has: 1-byte name length + name + control bytes
/// + variable-width values, ordered to match the supplied TAGX rows.
Uint8List entryIndx({
  required List<({String name, List<int> controlBytes, List<int> data})>
      entries,
}) {
  const headerLen = 192;
  // Build a body that lays the entries out and records start offsets.
  final body = <int>[];
  final positions = <int>[];
  for (final e in entries) {
    positions.add(headerLen + body.length);
    body.add(e.name.length);
    body.addAll(e.name.codeUnits);
    body.addAll(e.controlBytes);
    body.addAll(e.data);
  }
  final idxtStart = headerLen + body.length;
  // IDXT section: "IDXT" + uint16 positions + 2 bytes padding.
  final idxt = <int>[
    'I'.codeUnitAt(0),
    'D'.codeUnitAt(0),
    'X'.codeUnitAt(0),
    'T'.codeUnitAt(0),
  ];
  for (final pos in positions) {
    idxt.add((pos >> 8) & 0xFF);
    idxt.add(pos & 0xFF);
  }
  // Pad to 4-byte alignment.
  while ((idxt.length % 4) != 0) {
    idxt.add(0);
  }

  final total = idxtStart + idxt.length;
  final out = Uint8List(total);
  out[0] = 'I'.codeUnitAt(0);
  out[1] = 'N'.codeUnitAt(0);
  out[2] = 'D'.codeUnitAt(0);
  out[3] = 'X'.codeUnitAt(0);
  final view = ByteData.sublistView(out);
  view.setUint32(4, headerLen);
  view.setUint32(12, 1); // type 1 = entry block
  view.setUint32(20, idxtStart); // IDXT start
  view.setUint32(24, entries.length); // entry count
  out.setRange(headerLen, idxtStart, body);
  out.setRange(idxtStart, total, idxt);
  return out;
}

PdbFile wrapPdb(List<Uint8List> records) => PdbFile(
      header: const PdbHeader(
        name: 'test',
        attributes: 0,
        version: 0,
        creationDate: 0,
        modificationDate: 0,
        lastBackupDate: 0,
        modificationNumber: 0,
        appInfoId: 0,
        sortInfoId: 0,
        type: 'BOOK',
        creator: 'MOBI',
        uniqueIdSeed: 0,
        recordCount: 0,
      ),
      records: records
          .map((r) => PdbRecord(
                offset: 0,
                attributes: 0,
                uniqueId: 0,
                data: r,
              ))
          .toList(growable: false),
    );
