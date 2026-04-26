import 'dart:typed_data';

import '../headers/header_exception.dart';
import '../headers/mobi_header.dart';
import '../headers/palmdoc_header.dart';
import '../pdb.dart';
import 'palmdoc.dart';
import 'trailing_data.dart';

/// Decompress and concatenate every text record in a MOBI book.
///
/// Text records are PDB records 1..[PalmDocHeader.textRecordCount]. Each
/// record is first stripped of its trailing-data entries (per
/// [MobiHeader.extraDataFlags]) and then run through the appropriate
/// decompressor for [PalmDocHeader.compression].
///
/// Returns the raw uncompressed bytes of the book's text. Decoding to a
/// string is the caller's job — the bytes are in [MobiHeader.textEncoding].
///
/// Throws [HeaderException] when the file is encrypted or uses an
/// unsupported compression scheme. HUFF/CDIC support is Phase 6.
Uint8List decompressBookText({
  required PdbFile pdb,
  required PalmDocHeader palmDoc,
  required MobiHeader mobi,
}) {
  if (palmDoc.isEncrypted || mobi.hasDrm) {
    throw HeaderException(
      'cannot decompress encrypted MOBI (encryption=${palmDoc.encryption}, '
      'hasDrm=${mobi.hasDrm})',
    );
  }
  if (palmDoc.compression == CompressionType.huffCdic) {
    throw HeaderException(
      'HUFF/CDIC decompression is not yet implemented (Phase 6)',
    );
  }

  final count = palmDoc.textRecordCount;
  if (count == 0) return Uint8List(0);
  if (1 + count > pdb.records.length) {
    throw HeaderException(
      'PalmDOC header advertises $count text records but PDB only has '
      '${pdb.records.length - 1} records past record 0',
    );
  }

  final flags = mobi.extraDataFlags;
  final out = BytesBuilder(copy: false);
  for (var i = 1; i <= count; i++) {
    final raw = pdb.records[i].data;
    final payload = stripTrailingDataEntries(raw, flags);
    switch (palmDoc.compression) {
      case CompressionType.none:
        out.add(payload);
      case CompressionType.palmDoc:
        out.add(decompressPalmDoc(payload));
      case CompressionType.huffCdic:
        // Already filtered above.
        throw StateError('unreachable');
    }
  }
  return out.toBytes();
}
