import 'dart:typed_data';

import 'package:kindle_unpack/kindle_unpack.dart';

/// Builders for complete synthetic MOBI / KF8 files — a real PDB byte
/// stream that [KindleBook.fromBytes] can be pointed at end to end.
///
/// The per-structure tests elsewhere feed individual parsers hand-rolled
/// records; these builders exist for the cases where the whole pipeline
/// has to run, including the branches that only a particular *shape* of
/// file reaches (a KF8 without skeleton tables, a book carrying embedded
/// fonts, a title that lives in the MOBI header rather than EXTH).

/// Assemble a PDB container around [records].
Uint8List buildPdb(List<List<int>> records) {
  const headerSize = 78;
  const entrySize = 8;
  const gap = 2;
  final recordListEnd = headerSize + records.length * entrySize;

  final offsets = <int>[];
  var cursor = recordListEnd + gap;
  for (final r in records) {
    offsets.add(cursor);
    cursor += r.length;
  }

  final out = Uint8List(cursor);
  final view = ByteData.sublistView(out);
  const name = 'synthetic';
  out.setRange(0, name.length, name.codeUnits);
  view.setUint16(32, 0);
  view.setUint16(34, 0);
  for (var i = 0; i < 4; i++) {
    out[60 + i] = 'BOOK'.codeUnitAt(i);
    out[64 + i] = 'MOBI'.codeUnitAt(i);
  }
  view.setUint32(68, 0xFF);
  view.setUint16(76, records.length);

  for (var i = 0; i < records.length; i++) {
    final base = headerSize + i * entrySize;
    view.setUint32(base, offsets[i]);
    out[base + 7] = (i + 1) & 0xFF;
    out.setRange(offsets[i], offsets[i] + records[i].length, records[i]);
  }
  return out;
}

/// Build an EXTH block from `(type, data)` pairs.
Uint8List buildExth(List<(int, List<int>)> records) {
  var bodyLen = 0;
  for (final r in records) {
    bodyLen += 8 + r.$2.length;
  }
  final out = Uint8List(12 + bodyLen);
  final view = ByteData.sublistView(out);
  out.setRange(0, 4, 'EXTH'.codeUnits);
  view.setUint32(4, out.length);
  view.setUint32(8, records.length);
  var cursor = 12;
  for (final (type, data) in records) {
    view.setUint32(cursor, type);
    view.setUint32(cursor + 4, 8 + data.length);
    out.setRange(cursor + 8, cursor + 8 + data.length, data);
    cursor += 8 + data.length;
  }
  return out;
}

/// Build record 0: PalmDOC header + MOBI header + optional EXTH +
/// optional full-name string (which the MOBI header points back at).
///
/// [mobiHeaderLength] matters: `skeletonIndex` and `fragmentIndex` live
/// at MOBI-relative 236 and 232, so the default 232-byte header leaves
/// them unreadable — which is exactly the shape a KF8 file without
/// skeleton tables has.
Uint8List buildRecord0({
  required int fileVersion,
  int compression = 1, // 1 = uncompressed
  int textRecordCount = 1,
  int textLength = 0,
  List<(int, List<int>)> exth = const [],
  String fullName = '',
  int firstImageIndex = MobiHeader.unset,
  int? fdstRecord,
  int mobiHeaderLength = 232,
}) {
  final exthBlock = exth.isEmpty ? Uint8List(0) : buildExth(exth);
  final nameBytes = fullName.codeUnits;
  final nameOffset = 16 + mobiHeaderLength + exthBlock.length;

  final out = Uint8List(nameOffset + nameBytes.length);
  final view = ByteData.sublistView(out);

  // PalmDOC header.
  view.setUint16(0, compression);
  view.setUint32(4, textLength);
  view.setUint16(8, textRecordCount);
  view.setUint16(10, 4096);
  view.setUint16(12, 0); // encryption: none

  // MOBI header.
  out.setRange(16, 20, 'MOBI'.codeUnits);
  view.setUint32(20, mobiHeaderLength);

  void writeU32(int relOffset, int value) {
    if (relOffset + 4 > mobiHeaderLength) return;
    view.setUint32(16 + relOffset, value);
  }

  writeU32(8, 2); // mobi type: book
  writeU32(12, 65001); // text encoding: UTF-8
  writeU32(16, 0xABCDEF); // unique id
  writeU32(20, fileVersion);
  writeU32(64, MobiHeader.unset); // firstNonBookIndex
  writeU32(68, nameBytes.isEmpty ? 0 : nameOffset);
  writeU32(72, nameBytes.length);
  writeU32(92, firstImageIndex);
  writeU32(112, exthBlock.isEmpty ? 0 : 0x40); // EXTH present flag
  writeU32(152, MobiHeader.unset); // drmOffset
  writeU32(156, MobiHeader.unset); // drmCount
  if (fdstRecord != null) writeU32(176, fdstRecord);

  if (exthBlock.isNotEmpty) {
    out.setRange(16 + mobiHeaderLength, nameOffset, exthBlock);
  }
  if (nameBytes.isNotEmpty) {
    out.setRange(nameOffset, out.length, nameBytes);
  }
  return out;
}

/// Build an FDST record covering `(start, end)` byte ranges of the
/// decompressed rawML.
Uint8List buildFdst(List<(int, int)> ranges) {
  final out = Uint8List(12 + ranges.length * 8);
  final view = ByteData.sublistView(out);
  out.setRange(0, 4, 'FDST'.codeUnits);
  view.setUint32(4, 12);
  view.setUint32(8, ranges.length);
  for (var i = 0; i < ranges.length; i++) {
    view.setUint32(12 + i * 8, ranges[i].$1);
    view.setUint32(12 + i * 8 + 4, ranges[i].$2);
  }
  return out;
}

/// Build an uncompressed, unobfuscated FONT record wrapping [payload].
Uint8List buildFontRecord(List<int> payload) {
  const dataOffset = 24;
  final out = Uint8List(dataOffset + payload.length);
  final view = ByteData.sublistView(out);
  out.setRange(0, 4, 'FONT'.codeUnits);
  view.setUint32(4, payload.length); // uncompressed size
  view.setUint32(8, 0); // flags: no zlib, no XOR
  view.setUint32(12, dataOffset);
  view.setUint32(16, 0); // xor key length
  view.setUint32(20, dataOffset); // xor key offset (unused)
  out.setRange(dataOffset, out.length, payload);
  return out;
}
